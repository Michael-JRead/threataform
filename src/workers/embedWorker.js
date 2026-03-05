/**
 * Threataform Embed Worker
 * Generates dense vector embeddings using Transformers.js (Xenova/all-MiniLM-L6-v2)
 * Runs entirely in a Web Worker — zero UI blocking, 100% client-side.
 *
 * Based on local-rag patterns (MIT license) adapted for Threataform threat modeling.
 * Model: Xenova/all-MiniLM-L6-v2 (~22MB, cached in browser after first load)
 */

import { pipeline, env } from "@huggingface/transformers";

// Cache model in browser (IndexedDB via transformers.js default)
env.allowRemoteModels = true;
env.useBrowserCache = true;

let embedder = null;
let modelId = "Xenova/all-MiniLM-L6-v2";

async function getEmbedder() {
  if (!embedder) {
    embedder = await pipeline("feature-extraction", modelId, {
      progress_callback: (progress) => {
        self.postMessage({ type: "progress", progress });
      },
    });
  }
  return embedder;
}

// Cosine similarity between two vectors
function cosineSimilarity(a, b) {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (!normA || !normB) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

// L2-normalize a vector
function l2normalize(vec) {
  let norm = Math.sqrt(vec.reduce((s, v) => s + v * v, 0));
  if (!norm) return vec;
  return vec.map(v => v / norm);
}

self.onmessage = async ({ data }) => {
  const { type, id } = data;

  if (type === "init") {
    try {
      await getEmbedder();
      self.postMessage({ type: "ready", modelId });
    } catch (err) {
      self.postMessage({ type: "error", error: err.message });
    }
  }

  else if (type === "embed") {
    // Embed a batch of texts: { texts: string[], batchId: string }
    try {
      const emb = await getEmbedder();
      const results = [];
      for (let i = 0; i < data.texts.length; i++) {
        const text = data.texts[i];
        if (!text?.trim()) { results.push(null); continue; }
        const output = await emb(text, { pooling: "mean", normalize: true });
        const vec = l2normalize(Array.from(output.data));
        results.push(vec);
        // Report per-item progress for large batches
        if (data.texts.length > 5) {
          self.postMessage({ type: "embed_progress", done: i + 1, total: data.texts.length, batchId: data.batchId });
        }
      }
      self.postMessage({ type: "embeddings", id, batchId: data.batchId, vectors: results });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }

  else if (type === "embed_query") {
    // Embed a single query string: { query: string }
    try {
      const emb = await getEmbedder();
      const output = await emb(data.query, { pooling: "mean", normalize: true });
      const vec = l2normalize(Array.from(output.data));
      self.postMessage({ type: "query_embedding", id, vector: vec });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }

  else if (type === "similarity_search") {
    // Dense-only search over provided store: { query: string, store: [{text, vector, ...meta}], topK: number, threshold: number }
    try {
      const emb = await getEmbedder();
      const output = await emb(data.query, { pooling: "mean", normalize: true });
      const qVec = l2normalize(Array.from(output.data));
      const scored = (data.store || [])
        .map((item, idx) => ({ idx, sim: item.vector ? cosineSimilarity(qVec, item.vector) : 0 }))
        .filter(r => r.sim >= (data.threshold ?? 0.25))
        .sort((a, b) => b.sim - a.sim)
        .slice(0, data.topK || 8);
      self.postMessage({ type: "search_results", id, results: scored });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }
};
