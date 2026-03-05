/**
 * Threataform LLM Worker
 * Powers the "Threataform Assistant" using WebLLM (100% client-side inference).
 * Model: Phi-3.5-mini-instruct (~2.4GB quantized, cached in browser after first load)
 *
 * OpenAI-compatible API via @mlc-ai/web-llm.
 * WebGPU-accelerated with automatic WASM CPU fallback.
 */

import { CreateMLCEngine } from "@mlc-ai/web-llm";

let engine = null;
let currentModelId = null;

self.onmessage = async ({ data }) => {
  const { type, id } = data;

  if (type === "init") {
    const modelId = data.modelId || "Phi-3.5-mini-instruct-q4f32_1-MLC";
    try {
      if (engine && currentModelId === modelId) {
        self.postMessage({ type: "ready", modelId });
        return;
      }
      engine = await CreateMLCEngine(modelId, {
        initProgressCallback: (p) => {
          self.postMessage({
            type: "progress",
            progress: Math.round((p.progress || 0) * 100),
            text: p.text || "",
            timeElapsed: p.time_elapsed,
          });
        },
      });
      currentModelId = modelId;
      self.postMessage({ type: "ready", modelId });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }

  else if (type === "generate") {
    // Streaming generation: { messages: ChatMessage[], id: string }
    if (!engine) {
      self.postMessage({ type: "error", id, error: "LLM engine not initialized. Call init first." });
      return;
    }
    try {
      const stream = await engine.chat.completions.create({
        messages: data.messages,
        stream: true,
        temperature: data.temperature ?? 0.3,
        max_tokens: data.maxTokens ?? 2048,
      });
      let fullText = "";
      for await (const chunk of stream) {
        const token = chunk.choices[0]?.delta?.content;
        if (token) {
          fullText += token;
          self.postMessage({ type: "token", id, token });
        }
      }
      self.postMessage({ type: "done", id, fullText });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }

  else if (type === "reset") {
    try {
      if (engine) await engine.resetChat();
      self.postMessage({ type: "reset_done", id });
    } catch (err) {
      self.postMessage({ type: "error", id, error: err.message });
    }
  }

  else if (type === "abort") {
    try {
      if (engine) engine.interruptGenerate?.();
      self.postMessage({ type: "aborted", id });
    } catch {}
  }
};
