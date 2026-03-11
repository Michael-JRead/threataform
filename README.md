# Threataform

**Enterprise Terraform Threat Intelligence Platform**

A fully client-side, browser-native security analysis platform for enterprise infrastructure-as-code. Upload Terraform files, enrich the model with supporting documents, run automated threat modeling, generate exportable Data Flow Diagrams, and query a custom-built LLM + RAG stack — all within your browser. Zero data leaves your machine.

---

## Table of Contents

- [What Is Threataform?](#what-is-threataform)
- [Quick Start](#quick-start)
- [Application Workflow](#application-workflow)
- [Navigation Architecture](#navigation-architecture)
- [Features In Depth](#features-in-depth)
  - [Overview](#overview-section)
  - [Setup](#setup-section)
  - [Threats](#threats-section)
  - [Intelligence Panel](#intelligence-panel)
  - [AI Chat (Right Panel)](#ai-chat-right-panel)
  - [Diagram](#diagram-section)
  - [Settings](#settings-section)
- [LLM Engine — WllamaManager (Active)](#llm-engine--wllamamanager-active)
- [LLM Engine — ThreataformEngine (Next-Gen)](#llm-engine--threataformengine-next-gen)
- [ThreataformLM-200M Architecture](#threataformlm-200m-architecture)
- [RAG Pipeline](#rag-pipeline)
- [NLP Pipeline](#nlp-pipeline)
- [File Ingestion](#file-ingestion)
- [IaC Parsing](#iac-parsing)
- [Security Analysis](#security-analysis)
- [DFD Output](#dfd-output)
- [MCP Tool Server](#mcp-tool-server)
- [TFE-Pave Pattern Support](#tfe-pave-pattern-support)
- [Training Pipeline](#training-pipeline)
- [.tnlm Format Reference](#tnlm-format-reference)
- [State Management](#state-management)
- [Project Structure](#project-structure)
- [Security & Privacy](#security--privacy)
- [Tech Stack](#tech-stack)
- [Supported Frameworks](#supported-frameworks)
- [Acknowledgments](#acknowledgments)

---

## What Is Threataform?

Threataform is an enterprise security tool for teams that use Terraform (or CloudFormation) to manage cloud infrastructure. It answers the question: **"What are the security risks in my infrastructure code, and how do I fix them?"**

It works entirely in the browser with no backend, no cloud API, and no data transmission. You upload your `.tf` files directly, and the platform analyzes them locally using:

- A **custom IaC parser** that understands cross-file Terraform dependencies, module hierarchies, and enterprise PAVE layers
- A **Security Analyzer** that performs 30+ automated misconfiguration checks mapped to STRIDE threats, MITRE ATT&CK techniques, and CWE weaknesses
- A **DFD Generator** that produces Data Flow Diagrams in draw.io / Lucidchart XML format
- A **Retrieval-Augmented Generation (RAG) engine** that indexes your uploaded documents and lets you query your architecture knowledge base
- A **local LLM** (either user-supplied `.gguf` via llama.cpp WASM, or the custom ThreataformLM-200M engine) for AI-assisted threat analysis

---

## Quick Start

```bash
npm install
npm run dev          # http://127.0.0.1:5173
npm run build        # production build → dist/
```

> **COOP/COEP headers are required.** The dev server sets these automatically. For production, configure your static file server to send:
> ```
> Cross-Origin-Opener-Policy: same-origin
> Cross-Origin-Embedder-Policy: require-corp
> ```
> These are required for `SharedArrayBuffer` (multi-threaded llama.cpp WASM).

**Generate smoke-test model before using the custom engine:**

```bash
python scripts/create_dummy_model.py
# Writes public/model.tnlm (~300KB, random weights)
# Replace with real trained weights after running the training pipeline
```

### Enterprise / Restricted npm Registry

If `npm install` fails or Vite is not found after install (common with corporate Artifactory proxies that intercept `devDependencies`):

```bash
rm -rf node_modules package-lock.json
npm install
npm install vite --save-dev
npm run dev
```

The `rm -rf` ensures a clean state; reinstalling `vite` separately works around Artifactory virtual repos that may not resolve dev dependencies in a single pass. Any `npm audit` 404 errors logged by Artifactory are harmless — the install itself succeeds.

If your environment blocks the public npm registry entirely:

```bash
npm install --omit=optional   # skip native binary optionals
npm run dev
```

### CDN Fallbacks for Document Extractors

All document extractors automatically fall back to **esm.sh CDN** if their npm packages are unavailable:

| Format | npm package | CDN fallback |
|---|---|---|
| PDF | pdfjs-dist | esm.sh/pdfjs-dist@3.11.174 |
| DOCX | mammoth | esm.sh/mammoth@1.6.0 |
| XLSX/XLS | xlsx (SheetJS) | esm.sh/xlsx@0.18.5 |
| PPTX | jszip | esm.sh/jszip@3.10.1 |
| PNG/JPG | tesseract.js | esm.sh/tesseract.js@5.0.4 |
| CSV | pure JS | — |

---

## Application Workflow

Threataform is organized as a five-step workflow. Each step corresponds to a section in the left navigation rail:

```
Step 1 — Overview
  See your threat model summary, security grade, and key findings.
  ↓
Step 2 — Setup
  Name your threat model, upload Terraform + supporting docs,
  set application details (environment, team, data classification).
  ↓
Step 3 — Threats
  STRIDE breakdown · IaC misconfiguration checks · ATT&CK mapping
  · trust boundary analysis · architecture narrative
  ↓
Step 4 — Intelligence
  Security Posture · Control Inventory · Misconfig Checks ·
  Cross-Doc Links · Threat Intelligence · Scope · Resource Intel ·
  Architecture Layers
  ↓
Step 5 — Diagram
  Exportable DFD (.xml for draw.io / Lucidchart) ·
  architecture image · stats ·
  import instructions
```

All state persists per-model in browser `localStorage`. You can switch between models without losing context. Each model has its own documents, chat history, and settings.

---

## Navigation Architecture

The workspace is built around a **persistent split-pane layout** (`WorkspaceShell`) with three zones:

```
┌────────────────────────────────────────────────────────────┐
│ Header: ‹ Home | Threataform logo | Model name + grade     │
│         ──────────────────────────────────── ⌘K  AI       │
├──────┬──────────────────────────────┬────────────────────  │
│      │                              │                       │
│  Nav │       Center Pane            │   Right Panel         │
│  Rail│  (changes with navSection)   │   (AI Chat)           │
│      │                              │   toggle with ⌘K      │
│  48px│      flex: 1                 │   default 320px       │
└──────┴──────────────────────────────┴───────────────────── ┘
```

### NavRail Sections

| Section ID | Label | Icon | Tooltip |
|---|---|---|---|
| `overview` | Overview | Home | Model summary, health grade, and recent findings |
| `setup` | Setup | Upload | Upload files and configure application details |
| `diagram` | Diagram | Layers | Data flow diagram and export |
| `threats` | Threats | ShieldAlert | STRIDE, ATT&CK, and misconfigurations |
| `intelligence` | Intelligence | Brain | Posture, scope, resource, and architecture analysis |
| `settings` | Settings | Settings | LLM model, MCP server, and model settings |

The active NavRail section highlights with a left accent bar. Hovering any icon shows the full descriptive tooltip. Keyboard shortcut **⌘K** (Ctrl+K on Windows/Linux) toggles the AI Chat right panel from anywhere in the workspace.

---

## Features In Depth

### Overview Section

The **Overview** tab (navSection: `overview`) displays a read-only summary of the current threat model's security posture. It includes:

- **Health grade** (A–F) computed from weighted security findings
- **Top findings** by severity
- **Architecture summary** auto-populated from Terraform analysis
- **Document count** and **TF file count** indicators
- A **rebuild intelligence** banner (`RebuildBanner`) when documents change and the index needs updating

---

### Setup Section

The **Setup** tab (navSection: `setup`) is where models are populated. It consists of two sub-panels rendered side-by-side:

#### Left: `UserDocsPanel`

Handles all document ingestion. Users can:
- Drag-and-drop or browse to upload any supported file format (see [File Ingestion](#file-ingestion))
- See each document's filename, type, and extraction status
- Remove documents (also purges that document's IndexedDB embedding cache)
- Upload Terraform / HCL / Sentinel files (these are parsed for resources, not just indexed as docs)

#### Right: Application Details Form

Fields that describe the threat model context:
- **Application Name** — the product or service name (e.g., "Kinesis Data Analytics")
- **Environment** — Production / Staging / Development / DR
- **Team / Owner** — security contact
- **Data Classification** — Confidential / Internal / Public / Restricted
- **Architecture Description** — auto-populated from Terraform + uploaded docs, freely editable
- **Key Features / Compliance Frameworks / Product Modules** — chip input fields

These fields produce **synthetic context documents** that are indexed alongside user docs, so queries like "What frameworks do we target?" can be answered from the intelligence engine.

---

### Threats Section

The **Threats** tab (navSection: `threats`, legacy mainTab: `analysis`) renders `AnalysisPanel` with a full security report:

- **Executive Summary** — risk score, finding breakdown, STRIDE distribution
- **Security Findings** — sorted by severity (CRITICAL → LOW); each finding shows:
  - Resource ID and type
  - Severity badge
  - Short description and long-form remediation guidance
  - Linked MITRE ATT&CK technique (e.g., T1530, T1552.005)
  - Linked CWE weakness (e.g., CWE-311, CWE-798)
- **STRIDE Threat Map** — per tier (org, security, network, compute, storage)
- **Trust Boundaries** — identified network, IAM, storage, compute, and org boundaries
- **ATT&CK Coverage Grid** — which tactics and techniques are relevant to your architecture
- **Architecture Narrative** — a text description of the key security properties of the infrastructure

If no Terraform files have been uploaded, the Threats section shows an empty state with a "No threats analyzed yet" message and a button to navigate to Setup.

---

### Intelligence Panel

The **Intelligence** tab (navSection: `intelligence`) renders `IntelligencePanel` with **7 analysis sub-tabs** organized into 3 groups. This is the deep-analysis hub of the platform.

#### Tab Groups

```
Analysis group:
  ├── Security Posture & Controls   (PostureControlsTab)
  └── Misconfig Checks              (MisconfigsTab)

Threat Intel group:
  ├── Threat Intelligence           (ThreatIntelTab)
  └── Cross-Doc Links               (CrossDocTab)

Architecture group:
  ├── Scope Analysis                (ScopeTab)
  ├── Resource Intel                (ResourceIntelTab)
  └── Architecture Layers           (ArchLayersTab)
```

The default tab is **Security Posture & Controls**. Each tab button uses `role="tab"` and `aria-selected` for accessibility.

#### State Management

All intelligence panel state is consolidated into a **single `useReducer` hook** (`useIntelligenceState`). This eliminates the previous 46 individual `useState` declarations and makes the state predictable and debuggable. The reducer supports three action types:

- `SET` — update a single state key
- `PATCH` — update multiple keys at once
- `RESET` — restore all state to defaults

The hook exports a curried setter `set(key)` that returns `(value) => dispatch(...)` — a direct drop-in for `useState` setters in child components.

#### Sub-Tab Descriptions

| Sub-tab | Component | Description |
|---|---|---|
| Security Posture & Controls | `PostureControlsTab` | Aggregated security score, defense-in-depth layer coverage, present/absent controls with document evidence, compliance gap summary |
| Misconfig Checks | `MisconfigsTab` | 30+ automated IaC checks across all uploaded resources, filterable by severity |
| Threat Intelligence | `ThreatIntelTab` | Per-resource threat details with CVSS estimates, MITRE ATT&CK technique mappings, and remediation guidance |
| Cross-Doc Links | `CrossDocTab` | Contradictions, gaps, and alignment across multiple uploaded documents |
| Scope Analysis | `ScopeTab` | In-scope / out-of-scope declarations extracted from documents and Terraform attributes |
| Resource Intel | `ResourceIntelTab` | BM25 + vector hybrid search for any resource; summarizes relevant doc passages per resource |
| Architecture Layers | `ArchLayersTab` | PAVE layer analysis (L0–L4), factory patterns, module hierarchies, architecture narrative |

#### Context Object Pattern

`IntelligencePanel` builds a `ctx` object from all state fields and passes it to each tab via `{...ctx}`. Child tab components receive a consistent, flat API — they do not know or care about the parent's state management implementation.

---

### AI Chat (Right Panel)

The **AI Chat** is a **persistent right panel** (`AIChatPanel`) rendered in the `SplitPane` right slot. It is visible in the workspace header as a **⌘K** toggle button and is available regardless of which nav section is active.

The chat panel is separate from the Intelligence Panel tabs — it provides free-form conversational access to the RAG-indexed documents, while the Intelligence tabs provide structured, pre-computed views.

#### Chat Architecture

```
User sends message
  ↓
Build context from intelligence engine (BM25 search)
  + hybrid vector search (if LLM loaded)
  ↓
Construct prompt with retrieved passages
  ↓
Stream tokens from LLM (if loaded) OR return BM25 summary
  ↓
Append to chat history (persisted to localStorage)
```

- **Without LLM**: Returns the top BM25-ranked passages verbatim. Fast and always available.
- **With LLM**: Streams generated tokens with RAG context injected.
- **Chat history** persists per-model in `localStorage` key `tf-model-{id}-chat`.
- **Quick prompts** appear when the chat is empty and the intelligence index is ready.

#### LLM Not Loaded State

When no LLM is loaded, the panel shows a notice: _"AI chat unavailable — load a model in Settings to enable"_ with a button linking to the Settings section. BM25 fallback is always active.

---

### Diagram Section

The **Diagram** tab (navSection: `diagram`, legacy mainTab: `dfd`) has four sub-tabs:

| Sub-tab | Content |
|---|---|
| Architecture | View / upload an architecture image (Lucidchart export screenshot) |
| Stats | Resource count, connection count, module count, tier distribution |
| XML | Syntax-highlighted mxGraphModel XML (copy or download) |
| Import Guide | Step-by-step instructions for importing into draw.io and Lucidchart |

The DFD is auto-generated whenever Terraform files are uploaded or changed. Export options in the header:

- **Export .xml** — mxGraphModel XML for draw.io or Lucidchart
- **Copy XML** — clipboard copy
- **.lucid** — Lucid Standard Import bundle (`.lucid` format, a ZIP containing JSON + XML)
- **Report .txt** — plain text architecture report
- **Report .md** — Markdown architecture report

---

### Settings Section

The **Settings** tab (navSection: `settings`) renders `SettingsPanel` with four sections:

#### 1. AI Language Model

Configure the active LLM for AI chat:
- Browse and load a `.gguf` model from local disk (via `WllamaManager` / `ThreataformEngine`)
- Loading progress bar
- Current model name and size display
- Status: idle / loading / ready / error

#### 2. LoRA Fine-Tuning

In-browser fine-tuning of the ThreataformLM model on your uploaded documents:
- Start / stop fine-tuning on current documents
- Training progress indicator
- Status: idle / training / complete / error
- Save LoRA adapter to browser storage
- Load previously saved adapter

#### 3. MCP Server

Connect to an external MCP (Model Context Protocol) tool server:
- Enter WebSocket URL (e.g., `ws://localhost:3000`)
- Connect / disconnect
- Status display (connected / error / disconnected)
- Error message if connection fails

#### 4. Model Settings

- Model-level metadata editing (same fields as the Setup panel, cross-linked)
- Save model details

---

## LLM Engine — WllamaManager (Active)

`src/lib/WllamaManager.js` is currently a **thin compatibility shim** that re-exports `ThreataformEngine`:

```js
export { threataformEngine as wllamaManager } from './ThreataformEngine.js';
```

This means all existing code that imports `wllamaManager` gets the `ThreataformEngine` singleton automatically. The shim exists to preserve import compatibility while the engine migration completes.

### Historical Context

Originally, `WllamaManager` wrapped `@wllama/wllama` v2.3.7 (the llama.cpp WASM library) and provided:
- User-selectable `.gguf` file loading via the browser File API
- Multi-threaded WASM inference with `SharedArrayBuffer`
- Single-thread fallback when `SharedArrayBuffer` was unavailable

The shim approach means the transition from wllama to `ThreataformEngine` is zero-breaking-change.

---

## LLM Engine — ThreataformEngine (Next-Gen)

`src/lib/ThreataformEngine.js` (482 lines) is the main LLM + RAG engine.

### Design Goals

- **Auto-loads** `/public/model.tnlm` via `autoLoad()` — no user file picker required
- **Web Worker delegation** — all inference and ingestion run in background workers, never blocking the UI
- **Same public API** as the original WllamaManager — drop-in compatible
- **Full RAG stack** built-in: BM25, dense vectors, ColBERT, HyDE, SELF-RAG
- **In-browser LoRA fine-tuning** on uploaded documents

### Public API

```js
// Singleton
import { threataformEngine } from './ThreataformEngine.js';

threataformEngine.isLoaded          // boolean
threataformEngine.onStatus          // callback: (msg: string) => void
threataformEngine.onProgress        // callback: (pct: number) => void
threataformEngine.onLoadProgress    // callback: (loaded: number, total: number) => void

// Loading
await threataformEngine.loadFromFile(file)  // user-selected File object
await threataformEngine.loadFromUrl(url)    // URL string (e.g., '/model.tnlm')

// Generation (streaming async generator)
for await (const token of threataformEngine.generate(messages)) {
  process.stdout.write(token);
}

// Embeddings
const vec = await threataformEngine.embed(text)         // Float32Array[dim]
const vecs = await threataformEngine.embedBatch(texts)  // Float32Array[]
const qVec = await threataformEngine.embedQuery(text)   // Float32Array[dim]

// Ingestion + RAG
await threataformEngine.ingestFile(file)     // extract + chunk + embed
const results = await threataformEngine.search(query, topK)

// Fine-tuning
await threataformEngine.fineTune(options)    // LoRA training on ingested data
await threataformEngine.saveLoRA()           // persist adapter to IDB
await threataformEngine.loadLoRA()           // load previously saved adapter
await threataformEngine.unload()             // release memory
```

### Worker Architecture

```
ThreataformEngine (main thread)
  ├─ engineWorker.js  ← model forward pass, generate, embed, train
  └─ ingestWorker.js  ← file parsing, chunking, embedding, BM25 indexing
```

Both workers communicate via `postMessage` / `onmessage`. The engine uses promise-based message routing with unique IDs for each request.

### Chat Flow (ThreataformEngine Path)

```
User query
  → HyDE query expansion
       (generate hypothetical answer at temp=0.3, embed it)
  → Hybrid retrieval
       BM25 keyword recall
       + Dense vector HNSW search
       + ColBERT multi-vector MaxSim
  → Reciprocal Rank Fusion (k=60)
  → Cross-encoder reranking (if cross-encoder available)
  → SELF-RAG [IsRel] filtering
  → Generation with surviving passages as context
  → Streaming tokens to UI
```

---

## ThreataformLM-200M Architecture

The custom causal transformer built from scratch in pure JavaScript for `ThreataformEngine`. No WASM, no WebGPU, no external inference libraries — pure `Float32Array` math.

### Hyperparameters

| Parameter | Value |
|---|---|
| Total parameters | ~200M |
| vocab_size | 32,000 (full BPE, security-domain weighted) |
| context_len | 4,096 (extendable to ~32K via YaRN) |
| dim | 1,024 |
| n_layers | 24 |
| n_heads | 16 (head_dim = 64) |
| n_kv_heads | 4 (GQA: each KV head serves 4 Q-heads) |
| ffn_hidden | 4,096 (SwiGLU gate × up → down) |
| normalization | RMSNorm (eps=1e-5), pre-norm |
| position encoding | RoPE (theta=10000) + YaRN context scaling |
| initialization | muP (Maximal Update Parametrization) |
| tied embeddings | true (lm_head shares tok_embedding weights, saves ~128MB F32) |
| quantization | Mixed Q4/Q8 → ~50MB at full scale |

**Inference speed target:** 2–5 tok/s (200M Q4, pure JS Web Worker)

**Current model state:** `public/model.tnlm` is a 300KB smoke-test model with random weights. Produces garbage output by design. Replace with trained weights from `scripts/quantize.py` for real inference.

### Math Primitives — `src/lib/llm/Ops.js`

Every operation implemented from scratch over `Float32Array` / `Uint8Array`. No external math library.

| Function | Description |
|---|---|
| `matmul(out, W, x, rows, cols)` | Dense matrix-vector multiply (hot path — called every layer) |
| `matmulAccum(out, W, x, rows, cols)` | Accumulate mv-mul into existing buffer (LoRA delta application) |
| `matmulQ4(out, W_raw, x, rows, cols)` | Q4 row-dequant during multiply — avoids 4× memory expansion |
| `matmulQ8(out, W_raw, x, rows, cols)` | Q8 row-dequant during multiply |
| `rmsnorm(out, x, w, n, eps)` | LLaMA-style RMSNorm — no mean subtraction, scale by 1/RMS(x) |
| `softmax(arr, offset, n)` | Numerically stable — subtract max before exp |
| `silu(x)` | SwiGLU gate activation: x × sigmoid(x) |
| `buildRoPETable(headDim, maxSeq, theta, yarnScale)` | Pre-compute RoPE sin/cos frequency tables (once on model load) |
| `applyRoPE(q_or_k, vecOffset, headDim, pos, freqReal, freqImag)` | In-place rotary position encoding |
| `vecAdd(a, b, n)` | In-place residual addition |
| `cosineSim(a, b)` | Cosine similarity (retrieval scoring) |
| `dotProduct(a, b, n)` | Late-interaction dot product (ColBERT MaxSim) |
| `l2Normalize(v, n)` | L2-normalize embedding vector |
| `greedySample(logits)` | Argmax decoding (temp=0) |
| `sampleTopP(logits, temp, topP)` | Nucleus (top-p) sampling |
| `sampleTopK(logits, temp, topK)` | Top-K sampling |
| `f16ToF32(h)` | IEEE 754 half→float (pure bit manipulation) |
| `f32ToF16(f)` | IEEE 754 float→half |
| `dequantQ4Block(raw, blockIdx)` | 18-byte Q4 block → 32 floats |
| `dequantQ8Block(raw, blockIdx)` | 34-byte Q8 block → 32 floats |

### BPE Tokenizer — `src/lib/llm/Tokenizer.js`

Full byte-pair encoding (Sennrich et al. 2016) in pure JavaScript.

- **Unicode-aware pre-tokenization** — splits on whitespace + punctuation boundaries preserving word integrity
- **Byte fallback** — every Unicode character maps to UTF-8 byte tokens — guaranteed full coverage, no UNK tokens
- **32K merge rules** embedded as compressed JS object
- **NFC normalization**, BOM stripping, Windows line-ending normalization
- **LLaMA-3-compatible instruct chat template** via `encodeChat(messages)`

**Special tokens:**

| Token | ID | Purpose |
|---|---|---|
| `<\|pad\|>` | 0 | Padding |
| `<\|bos\|>` | 1 | Beginning of sequence |
| `<\|eos\|>` | 2 | End of sequence |
| `<\|retrieve\|>` | 3 | SELF-RAG: trigger retrieval |
| `<\|isrel\|>` | 4 | SELF-RAG: passage relevance judgment |
| `<\|issup\|>` | 5 | SELF-RAG: response supported by evidence |
| `<\|isuse\|>` | 6 | SELF-RAG: usefulness score (1–5) |

### Forward Pass — `src/lib/llm/Model.js`

```
ThreataformLM(config, weights)
  ├── forward(tokenId, pos, kvCache)     → Float32Array[vocab_size] — raw logits
  ├── generate(promptTokens, opts)       → async generator of token IDs
  ├── embed(tokenIds)                    → Float32Array[dim] — pooled vector
  ├── embedMulti(tokenIds)               → Float32Array[][dim] — per-token ColBERT vectors
  ├── predictTokenProb(prompt, tokenId)  → float — used by SELF-RAG
  ├── allocateKVCache(maxSeqLen)         → KVCache — pre-allocated Float32Arrays per layer
  └── clearKVCache()
```

**Per-token forward pass (per layer):**
1. `attention_norm` — RMSNorm(x, w_norm)
2. Q/K/V projections (matmulQ4) → apply RoPE to Q and K
3. GQA attention: causal mask, softmax, KV-cache read/write, O projection (matmulQ8)
4. Residual add
5. `ffn_norm` — RMSNorm
6. SwiGLU FFN: `silu(W_gate @ x) * (W_up @ x)` → `W_down`
7. Residual add

### Weight Loading — `src/lib/llm/WeightsLoader.js`

- Parses `.tnlm` binary format
- **IndexedDB cache** (`threataform-model-v1`): stores raw `ArrayBuffer`; second load is always from IDB (<2s)
- Streaming load with per-tensor progress callbacks
- `autoLoad()` — lazy-fetches `/model.tnlm` on first `generate()` or `embed()` call

### In-Browser Fine-Tuning — `src/lib/llm/LoRA.js`

Low-Rank Adaptation on all 7 projections per layer (Q, K, V, O, gate, up, down) × 24 layers = **168 adapter pairs**.

| Config | Default | Notes |
|---|---|---|
| rank r | 8 | r=8 → ~50MB adapter; r=16 → ~100MB |
| alpha | 16 | delta = (alpha/r) × B @ (A @ x) |
| Optimizer | AdamW | lr=3e-4, β1=0.9, β2=0.999, wd=0.01 |
| Loss | cross-entropy | Next-token prediction on document chunks |
| Batch | 4 sequences | Micro-batching in Web Worker |

- A matrices: Kaiming normal init; B matrices: zero init (delta = 0 at start)
- Manual backprop: `dL/dA = Bᵀ @ grad_out @ xᵀ`, `dL/dB = grad_out @ (A @ x)ᵀ`
- Adapter serialized to `ArrayBuffer`, cached in IndexedDB, reloaded automatically

### Inference Web Worker — `src/workers/engineWorker.js`

Runs `ThreataformLM` in a dedicated Web Worker (no UI blocking).

| Message type | Direction | Description |
|---|---|---|
| `load` | → worker | Fetch + parse `model.tnlm`, report progress |
| `generate` | → worker | Start streaming token generation |
| `token` | ← worker | Single generated token (one per forward pass) |
| `embed` | → worker | Single-vector embedding for a text string |
| `embedMulti` | → worker | Per-token ColBERT embeddings |
| `train` | → worker | LoRA training loop with progress updates |
| `progress` | ← worker | Training progress update |
| `ready` | ← worker | Sent on successful model load |

---

## RAG Pipeline

### Chunking — `src/lib/rag/Chunker.js`

#### RecursiveTextSplitter

Deterministic, zero dependencies. Separator hierarchy (most structural → least):

1. Markdown headings (`## `, `### `)
2. Paragraph breaks (`\n\n`)
3. Single newlines (`\n`)
4. Sentence endings (`[.!?]`)
5. Clause endings (`[,;:]`)
6. Word boundaries (spaces)
7. Character-level (last resort)

Default: `minChunk=100`, `maxChunk=800`, `overlap=50` characters.

#### SemanticChunker (in `NLP.js`, re-exported from `Chunker.js`)

Embeds sequential sentence windows, detects cosine-similarity dips as semantic boundaries. Requires async `embedFn: string → Float32Array`.

#### HierarchicalChunker — Two-Pass (Recommended for Production)

- Pass 1: RecursiveTextSplitter (fast structural split)
- Pass 2: SemanticChunker refines chunks still above `maxChunk`

```js
import { makeChunker } from './rag/Chunker.js';
const chunker = makeChunker('balanced'); // 'fast' | 'balanced' | 'precise'
const chunks = await chunker.chunk(text, embedFn);
```

| Preset | minChunk | maxChunk | overlap | semanticThreshold |
|---|---|---|---|---|
| fast | 80 | 600 | 30 | 0.70 |
| balanced | 100 | 900 | 50 | 0.65 |
| precise | 120 | 1200 | 80 | 0.58 |

---

### BM25 Index — `src/lib/rag/BM25Index.js`

Classic Okapi BM25: `k1=1.5`, `b=0.75`. Stop-word filtered. Primary retrieval stage and fallback when no LLM is loaded. Indexes document text, metadata, and extracted entities.

---

### Vector Store — `src/lib/rag/VectorStore.js`

#### SingleVectorStore

- One embedding vector per chunk
- Cosine similarity ranking
- HNSW for O(log N) approximate nearest-neighbour search at scale

#### ColBERTVectorStore

- One embedding vector **per token** (late interaction)
- Stores `Float32Array[]` (T × dim) per document
- **MaxSim scoring**: `score(Q, D) = Σᵢ max_j (qᵢ · dⱼ)` — highly expressive, captures fine-grained token-level matches

#### HNSW — Hierarchical Navigable Small World

- Parameters: M=16 connections/node, efC=200 (construction), efS=50 (search)
- O(log N) approximate nearest-neighbour; brute-force fallback below 50 vectors

---

### Hybrid Retrieval — `src/lib/rag/HybridRetriever.js`

Four-stage pipeline with Reciprocal Rank Fusion:

**Stage 1 — Broad recall (top-40 pool per source)**

| Source | Method |
|---|---|
| BM25 | Keyword TF-IDF recall |
| Dense | Single-vector cosine similarity via HNSW |
| ColBERT | Multi-vector MaxSim late interaction |

**Stage 2 — Reciprocal Rank Fusion**

`score(d) = Σᵣ 1/(60 + rankᵣ(d))` (Cormack et al. 2009, k=60)

Combines the three ranked lists into a single fused ranking without requiring score normalization.

**Stage 3 — Cross-encoder reranking**

Uses `ThreataformLM` as a binary relevance classifier. Skipped when model is not loaded.

**Stage 4 — SELF-RAG filtering**

Per-passage `[IsRel]` probability filters irrelevant passages before generation.

---

### HyDE — Hypothetical Document Embeddings (`src/lib/rag/HyDE.js`)

Based on Gao et al. 2022.

```
query
  → generate short hypothetical answer (maxNew=200, temp=0.3, no retrieval)
  → embed hypothetical answer
  → embed original query
  → average both embeddings
  → retrieve with combined signal
```

Falls back to direct query embedding when model not loaded.

---

### SELF-RAG — `src/lib/rag/SelfRAG.js`

Self-Reflective RAG (Asai et al. 2023). Uses special control tokens predicted by the model to decide when to retrieve, which passages are relevant, and whether the generated answer is actually supported.

| Special token | Threshold | Decision |
|---|---|---|
| `[Retrieve]` | P > 0.40 | Should we even retrieve for this query? |
| `[IsRel]` | P > 0.50 | Is this retrieved passage relevant? |
| `[IsSup]` | P > 0.40 | Does the response cite this passage as evidence? |
| `[IsUse]` | score ≥ 3 | Is the final response useful (1–5 scale)? |

**Generation loop:**
1. Predict `[Retrieve]` — skip retrieval if query is self-contained
2. Retrieve candidates via `HybridRetriever`
3. Filter by `[IsRel]` per passage — discard irrelevant
4. Generate with each surviving passage independently
5. Score each output by `[IsSup]` + `[IsUse]`
6. Return the highest-scoring response

---

### Intelligence Engine — `src/lib/intelligence/ThreatModelIntelligence.js`

A **simpler, always-available** BM25 + entity extraction engine. This is what powers most of the Intelligence Panel tabs without requiring an LLM. It operates entirely synchronously (after index build) and has no external dependencies.

#### Index Sources

| Source | Content |
|---|---|
| Terraform resources | Resource type, name, ATT&CK techniques, misconfig check descriptions |
| User documents | Full extracted text chunked at ~400 tokens with 50-token overlap |
| Arch context doc | Synthetic doc: product name, environment, frameworks, key features |
| Model details doc | Architecture description, data classifications, team fields |

#### Entity Patterns Extracted

STRIDE threats, MITRE ATT&CK T-numbers, compliance framework names, 100+ AWS service patterns, security control keywords, scope declarations (in-scope / out-of-scope language), CVE IDs, IP addresses, domain names.

#### Key Methods

| Method | Description |
|---|---|
| `build(userDocs, resources, modules)` | Index all sources, extract features |
| `query(text, topK)` | BM25 search, returns verbatim chunks with scores |
| `analyzeResource(type, name)` | Relevant doc passages for a specific resource |
| `getArchitectureSummary(resources)` | Auto-fills the architecture description field |
| `_docHasControl(ctrlName)` | Cross-references control against uploaded docs |

The engine rebuilds automatically on every file upload, document change, or architecture override.

#### Query Expansion

Domain keywords map to synonyms for richer recall:

```
iam  → ['identity access management', 'permissions', 'policy', 'role', ...]
mfa  → ['multi-factor', '2fa', 'second factor', ...]
s3   → ['object storage', 'bucket', 'simple storage service']
... 40+ domains with aliases
```

---

## NLP Pipeline

`src/lib/llm/NLP.js`

| Class / Function | Description |
|---|---|
| `SecurityNER` | Recognizes: CVE IDs, MITRE T-numbers, AWS resource types, CIS control refs, IPs/ports, Terraform resource names, compliance framework names |
| `SemanticChunker` | Embedding-based sentence-boundary detection |
| `CoreferenceResolver` | Pronoun → antecedent linking ("it", "the system" → actual entity) |
| `RelationExtractor` | Subject-predicate-object triples, e.g. `{S3 bucket, exposes, public internet}` |
| `detectLanguage(text)` | Trigram frequency model, 50 languages |
| `segmentSentences(text)` | Handles code blocks, URLs, abbreviations |

---

## File Ingestion

`src/lib/ingestion/FileRouter.js` routes by MIME type + extension. All extractors are **lazy-loaded** — only the needed parser is fetched/initialized.

| Format | Primary Library | CDN Fallback | Output |
|---|---|---|---|
| PDF | pdfjs-dist | esm.sh/pdfjs-dist@3.11.174 | Text + table detection |
| DOCX/DOC | mammoth | esm.sh/mammoth@1.6.0 | Heading hierarchy, tables, metadata |
| XLSX/XLS | SheetJS (xlsx) | esm.sh/xlsx@0.18.5 | "ColHeader: CellValue" row format |
| CSV | pure JS | — | First row as headers, labelled sentences |
| PPTX | jszip | esm.sh/jszip@3.10.1 | Slide titles + body + speaker notes |
| PNG/JPG/TIFF | Tesseract.js | esm.sh/tesseract.js@5.0.4 | OCR text + layout analysis |
| MP3/WAV/MP4 | Whisper.js | — | Audio transcription (lazy-loaded) |
| JSON/YAML | built-in | — | Flattened `key.subkey.leaf: value` |
| HCL/Terraform | custom parser | — | Resource blocks with all attributes |
| HTML | DOMParser | — | Text nodes + tag context |
| Markdown | built-in | — | Stripped syntax + code blocks |
| TOML | built-in | — | Parsed + flattened |

All extractors return a standardized object:

```js
{
  text: string,
  metadata: { filename, type, pages?, sheets?, slides? },
  tables: [{ headers: string[], rows: string[][] }],
  codeBlocks: [{ lang: string, code: string }],
  entities: []   // populated by SecurityNER post-extraction
}
```

---

## IaC Parsing

### Terraform / HCL — `src/lib/iac/TerraformParser.js`

Entry point: `parseTFMultiFile(files)` → returns a comprehensive parse result object.

#### What It Parses

- **Resource blocks** — `aws_*`, `azurerm_*`, `google_*`, and custom providers
- **Module calls** — with Terraform Registry source inference (registry / local / git / remote_state)
- **Output and variable dependencies** — cross-file reference resolution
- **Cross-file connections** — security groups → EC2, IAM roles → Lambda, VPC → subnets
- **Sentinel policy files** — `.sentinel` enforcement rules
- **`.tfvars` files** — value injection into variable resolution
- **Remote state data sources** — `terraform_remote_state` reference tracking
- **PAVE layer detection** — infers L0–L4 from file path conventions

#### Parse Result Shape

```js
{
  resources: [{
    id: "aws_s3_bucket.my-bucket",
    type: "aws_s3_bucket",
    name: "my-bucket",
    label: "my-bucket-name",      // friendly display label
    body: "...",                   // raw HCL text
    attrs: { ... },                // parsed attributes dict
    inputRefs: ["aws_kms_key.main.arn", ...],  // cross-resource references
    multi: "for_each" | "count" | null,
    file: "modules/storage/main.tf",
    paveLayer: "L3" | null
  }],

  modules: [{
    id: "module.vpc",
    name: "vpc",
    source: "terraform-aws-modules/vpc/aws",
    shortSrc: "vpc/aws",
    version: "3.0.0",
    srcType: "registry" | "local" | "git" | "remote_state" | "data",
    pinned: "exact" | "constrained" | "unpinned",
    body: "...",
    file: "network/main.tf",
    paveLayer: "L2" | null
  }],

  connections: [{
    from: "aws_s3_bucket.data",
    to: "aws_lambda.processor",
    kind: "implicit" | "explicit" | "module-output" | "module-input" | "data-ref" | "attachment",
    file: "main.tf"
  }],

  outputs: [{ name, value, sensitive, file }],
  variables: [{ name, type, hasDefault, defaultVal, sensitive, file }],
  remoteStates: [{ name, key, bucket }]
}
```

### CloudFormation — `src/lib/iac/CFNParser.js`

Parses CloudFormation JSON/YAML stacks: Resources, Parameters, Outputs, Conditions.

---

## Security Analysis

### `src/lib/iac/SecurityAnalyzer.js`

The security analyzer consumes the `parseTFMultiFile` result and produces a structured security report.

#### Check Categories

| Category | Example Checks |
|---|---|
| Network exposure | Security groups with `0.0.0.0/0` ingress on sensitive ports |
| Encryption at rest | S3 without SSE, RDS without `storage_encrypted`, EBS without `encrypted` |
| Encryption in transit | ALB without HTTPS, MSK without TLS |
| Access control | IAM policies with `*` actions/resources, missing MFA enforcement |
| Logging / audit | CloudTrail disabled, S3 access logging off, VPC flow logs absent |
| Public access | Public S3 ACLs, unrestricted Lambda URLs, public EKS API endpoints |
| Versioning / backup | S3 versioning disabled, DynamoDB PITR off, RDS backup window missing |
| Key management | KMS key rotation disabled, short deletion window |
| Monitoring | CloudWatch alarms missing, GuardDuty not enabled |

Each finding includes:

```js
{
  sev: "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",
  code: "TF-S3-001",               // unique check code
  id: "aws_s3_bucket.uploads",     // offending resource
  msg: "S3 bucket allows public access",
  detail: "...",                    // remediation guidance
  technique: "T1530",              // MITRE ATT&CK technique
  cwe: "CWE-284"                   // CWE weakness
}
```

#### Additional Analysis Functions

| Function | Output |
|---|---|
| `identifyTrustBoundaries()` | Network, IAM, compute, storage, and org trust boundaries |
| `buildArchitectureNarrative()` | Human-readable architecture description from resources |
| `buildStrideLMByTier()` | STRIDE threat list per architectural tier |
| `getSecurityPosture()` | Security grade (A–F) + weighted score |

---

## DFD Output

`src/lib/diagram/DFDGenerator.js` produces mxGraphModel XML for draw.io / Lucidchart.

### Layout

Left-to-right tiers. Resources grouped by service type into tier columns. Maximum 5 nodes per sub-column (controlled by `MAXROWS=5`). Legend in top-left corner at `(CPAD, CPAD)`.

**Tier order (left → right):** xsphere → org → security → cicd → network → compute → storage

### XML Format

> ⚠️ **The XML format is locked.** Lucidchart import has been verified and depends on this exact structure. Do not change node styles, edge styles, or attribute naming.

- All nodes: `html=1;whiteSpace=wrap;`
- All edges: `edgeStyle=orthogonalEdgeStyle;...endArrow=blockThin;`
- Newlines in cell values: `&#xa;` (pre-escaped via `xeXml()`)
- File wrapper: `<mxfile host="app.diagrams.net" version="21.0.0" type="device">`
- Indentation: mxGraphModel content is indented 4 spaces inside `<diagram>`
- Cell nesting: `<mxCell...>\n      <mxGeometry.../>\n    </mxCell>` (6sp geometry, 4sp cell close)

### Edge Types

| Edge Style | Meaning |
|---|---|
| Grey solid | Implicit Terraform reference (resource attribute reference) |
| Red dashed | Explicit `depends_on` declaration |
| Green | Module input/output connection |

Resources with STRIDE findings get a `⚠ stride1,stride2` label appended to their node.

### Exports

`src/lib/diagram/ExportUtils.js` provides:

- `makeZipOneFile(xml, filename)` — wraps XML in a `.lucid` ZIP bundle (Lucid Standard Import format)
- `generateTXTReport(archAnalysis, opts)` — plain text security report
- `generateMarkdownReport(archAnalysis, opts)` — Markdown security report

### Importing into Lucidchart

1. Lucidchart → **File** → **Import** → **Diagram** → select `.xml`

### Importing into draw.io

1. draw.io → **Extras** → **Edit Diagram** → paste XML
2. Or: draw.io → **File** → **Import From** → **Device** → select `.xml`

---

## MCP Tool Server

`src/lib/mcp/MCPToolRegistry.js` implements a Model Context Protocol tool registry. Built-in tools are always available. External tools are discovered from an MCP server via WebSocket.

### Built-in Tools

| Tool ID | Description | Input | Output |
|---|---|---|---|
| `score_cvss` | CVSS v3.1 base score calculator | `vector: string` (e.g., "AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H") | `{ score, severity, metrics }` |
| `lookup_mitre` | MITRE ATT&CK technique lookup | `techniqueId: string` or `keyword: string` | `{ id, name, tactics, description, mitigations }` |
| `check_compliance` | Compliance gap check | `{ framework, resourceType, attrs }` | `{ gaps, controls, status }` |

Supported compliance frameworks for `check_compliance`: HIPAA, FedRAMP Moderate, FedRAMP High, PCI DSS v4, SOC 2 Type II, GDPR, CMMC Level 2.

### External MCP Client — `src/lib/mcp/MCPClient.js`

Connects to an external MCP server via WebSocket and exposes its tools through the same registry interface.

```js
// Connection
mcpClient.connect('ws://localhost:3000');

// Tool discovery (called after connect)
const tools = await mcpClient.listTools();  // [{name, description, inputSchema}]

// Tool invocation
const result = await mcpClient.callTool('my_tool', { param: 'value' });
```

The external tools are merged into the registry and appear identically to built-in tools from the AI assistant's perspective.

---

## TFE-Pave Pattern Support

Threataform understands enterprise hierarchical IAM layers used in large Terraform Enterprise deployments:

| Layer | Name | Description |
|---|---|---|
| L0 | Org / Management | SCPs, OU structure, Control Tower, Landing Zone |
| L1 | Account Vending | AFT (Account Factory for Terraform), account bootstrapping |
| L2 | Account Pave | CloudTrail, GuardDuty, Config, permission boundaries |
| L3 | Product Pave | Platform VPC, TGW, shared SGs, ProductTeamDeployer role |
| L4 | Service | Application workloads, service-specific roles |

Layer detection is based on file path patterns. For example:
- `layers/l0-org/main.tf` → L0
- `pave/account/modules/security.tf` → L2
- `services/kinesis/main.tf` → L4

**Context-aware IAM analysis example:** A `kinesis:*` IAM policy scoped to `team-prefix-*` resources with a permission boundary applied = **LOW severity** (standard pave pattern). Without a permission boundary = **HIGH severity**.

---

## Training Pipeline

The full training pipeline for ThreataformLM-200M runs offline with Python scripts.

### Corpus Sources

| Source | Content | Approx. Size |
|---|---|---|
| MITRE ATT&CK STIX | Technique descriptions + examples | ~50MB |
| NVD CVE database (2010–present) | Structured vulnerability descriptions | ~2GB |
| AWS security documentation | Service security sections | ~500MB |
| Terraform provider docs | Resource attribute descriptions | ~200MB |
| CIS Controls v7/v8 | Control text | ~10MB |
| NIST SP 800-53 r5 | Security control catalog | ~20MB |
| OWASP Top 10 + ASVS | Vulnerability descriptions | ~5MB |
| Synthetic Q&A (GPT-4o, one-time) | 100K threat modeling pairs | ~200MB |
| General web text (OpenWebText) | Language quality | 1B tokens |

### Pipeline Scripts

```bash
# 1. Build vocabulary (CPU, ~1 hour)
python scripts/build_vocab.py
#    → vocab.json + merges.txt (32K BPE, security-weighted 60% / general 40%)

# 2. Download + preprocess corpus (CPU, multi-hour, ~50GB disk)
python scripts/build_corpus.py

# 3. Generate synthetic Q&A (requires OPENAI_API_KEY, run once)
python scripts/generate_synth_data.py

# 4. Pre-training (1× A100 ~3 days, 4× RTX 4090 ~5 days)
python scripts/train_base.py

# 5. Supervised fine-tuning (few hours)
python scripts/train_instruct.py

# 6. DPO alignment (few hours)
python scripts/train_dpo.py

# 7. Quantize + export to .tnlm
python scripts/quantize.py --input checkpoints/final.pt --out public/model.tnlm

# 8. Export updated vocabulary to JS
python scripts/export_vocab.py

# 9. Evaluate
python scripts/eval.py --model public/model.tnlm --all --save-report report.json
```

### Evaluation Benchmarks

| Benchmark | Metric | What it tests |
|---|---|---|
| STRIDE classification | Accuracy | Terraform resource → correct threat categories |
| MITRE ATT&CK recall | Recall@10 | Attack scenario → correct T-numbers |
| CIS control recommendation | Precision@5 | Misconfiguration → correct CIS controls |
| Perplexity | PPL | Held-out security text perplexity |
| RAG retrieval | MRR, NDCG, Hit@5 | Retrieval quality |
| Threat Q&A | BLEU-4, ROUGE-L | Full answer quality vs reference answers |

---

## .tnlm Format Reference

Binary model format used by `WeightsLoader.js`.

```
Header:
  [4B]  magic = "TNLM"
  [4B]  version = 2  (little-endian uint32)
  [4B]  config_json_length
  [N B] config JSON (utf-8)

Tensors (repeated until EOF):
  [4B]       name_length
  [N B]      name (utf-8)
  [4B]       dtype  (0=F32, 1=Q4, 2=Q8)
  [4B]       ndim
  [4B × ndim] shape dimensions (little-endian uint32)
  [data]     see dtype encoding below

F32: 4 bytes per element (IEEE 754 LE float)

Q4: ceil(n/32) × 18 bytes
  Per 32-weight block:
    [2B]  f16 scale = max_abs / 7
    [16B] nibbles
      byte[i]: low  nibble = weight[i]       → ((byte & 0x0F) - 8) × scale
               high nibble = weight[i + 16]  → ((byte >> 4)   - 8) × scale

Q8: ceil(n/32) × 34 bytes
  Per 32-weight block:
    [2B]  f16 scale = max_abs / 127
    [32B] int8 values → int8 × scale
```

Q8 is used for output projections (`attention.wo`, `feed_forward.w2`) where precision loss has the most impact on output quality.

### Weight Naming Convention

```
tok_embeddings                    [vocab_size, dim]          F32
norm                              [dim]                      F32
layers.{l}.attention_norm         [dim]                      F32
layers.{l}.attention.wq           [n_heads×head_dim, dim]    Q4
layers.{l}.attention.wk           [n_kv_heads×head_dim, dim] Q4
layers.{l}.attention.wv           [n_kv_heads×head_dim, dim] Q4
layers.{l}.attention.wo           [dim, dim]                 Q8
layers.{l}.ffn_norm               [dim]                      F32
layers.{l}.feed_forward.w1        [ffn_hidden, dim]          Q4
layers.{l}.feed_forward.w3        [ffn_hidden, dim]          Q4
layers.{l}.feed_forward.w2        [dim, ffn_hidden]          Q8
```

---

## State Management

React hooks only — no external state library (no Redux, no Zustand, no MobX).

### Global App State (terraform-enterprise-intelligence.jsx)

| State | Hook | Storage |
|---|---|---|
| `files` | `useParseResult` | Memory |
| `parseResult` | `useParseResult` | Memory |
| `xml` | `useParseResult` | Memory |
| `userDocs` | `useUserDocs` | localStorage `tf-model-{id}-docs` |
| `currentModel` | `useModelManager` | localStorage `tf-models` |
| `llmStatus` | `useLLM` | Memory |
| `llmProgress` | `useLLM` | Memory |
| `llmStatusText` | `useLLM` | Memory |
| `wllamaModelName` | `useLLM` | localStorage `tf-last-llm-model` |
| `wllamaModelSize` | `useLLM` | Memory |
| `intelligenceRef` | `useRef` | Memory (singleton) |
| `intelligenceVersion` | `useState` | Memory (increment counter) |
| `vectorStoreRef` | `useVectorStore` | IndexedDB `threataform-vectors` v2 |

### Intelligence Panel State (useIntelligenceState.js)

All state for `IntelligencePanel` is managed by a single `useReducer` hook with 29 fields:

```js
const INITIAL_STATE = {
  iTab: 'posture-controls',     // active sub-tab
  attackFilter: null,           // ATT&CK tactic filter
  resourceSearch: '',           // resource search query
  resourceTypeFilter: '',       // resource type dropdown
  resourcePage: 0,              // pagination
  expandedControl: null,        // expanded control item
  expandedCwe: null,            // expanded CWE item
  expandedFinding: null,        // expanded finding item
  query: '',                    // intelligence query text
  results: null,                // query results
  queryLoading: false,          // query in-flight
  synthesisingQuery: false,     // LLM synthesis running
  synthesisText: '',            // streaming synthesis output
  postureNarrative: '',         // AI-generated posture summary
  postureNarrLoading: false,
  gapAnalysis: '',              // compliance gap narrative
  gapAnalysisLoading: false,
  remediationPlan: '',          // AI remediation plan
  remediationLoading: false,
  controlSearch: '',            // control search filter
  threatScenarios: '',          // threat scenario narrative
  threatScenariosLoading: false,
  inferredScope: '',            // scope inference text
  inferredScopeLoading: false,
  resourceSummaries: {},        // { resourceId: summary }
  hybridHits: {},               // { resourceId: hits[] }
  techPassages: {},             // { techniqueId: passages[] }
  attackNarrative: '',          // ATT&CK narrative
  attackNarrLoading: false,
  contradictionNarrative: '',   // cross-doc contradiction narrative
  contraNarrLoading: false,
  findingGuidance: {},          // { findingCode: guidance }
};
```

The hook exports:
- `state` — current state object
- `set(key)` — curried setter `(value) => dispatch(...)`, drop-in for useState setters
- `patch(obj)` — batch update multiple keys
- `reset()` — restore all state to defaults
- `dispatch` — raw dispatch for custom actions

### Persistence

| Data | Storage | Key |
|---|---|---|
| Models list | localStorage | `tf-models` |
| Documents per model | localStorage | `tf-model-{id}-docs` |
| Chat history per model | localStorage | `tf-model-{id}-chat` |
| Last-used LLM model name | localStorage | `tf-last-llm-model` |
| Dense embedding vectors | IndexedDB | `threataform-vectors` (v2) |
| Model weights cache | IndexedDB | `threataform-model-v1` |
| LoRA adapter | IndexedDB | `threataform-lora-v1` |
| Architecture image | modelMeta IDB | `diagram-image` (per model) |

### Known Bug Pattern: TDZ in `useCallback` Deps

If callback A (declared earlier in the component body) lists callback B (declared later) in its dependency array, JavaScript throws a Temporal Dead Zone error at module evaluation time:

```
Cannot access 'B' before initialization
```

**Fix pattern:** Declare `const bRef = useRef(null)` before callback A, then assign `bRef.current = B` after B is defined. Inside A, call `bRef.current?.()` instead of `B()` directly.

---

## Project Structure

```
threataform/
│
├── index.html                                       # React DOM mount point
├── package.json                                     # Dependencies + scripts
├── vite.config.js                                   # Build config (WASM, COEP/COOP, PWA)
│
├── terraform-enterprise-intelligence.jsx            # Main App component (~2848 lines)
│   # Orchestrates: file parsing, DFD gen, RAG rebuild, navigation,
│   # model CRUD, LLM loading, export, stepper, all workspace render logic.
│
├── src/
│   │
│   ├── main.jsx                                     # Entry: ReactDOM.createRoot().render(<App/>)
│   ├── icons.jsx                                    # Re-exports lucide-react icons + KB_DOMAIN_ICONS
│   │
│   ├── constants/
│   │   ├── layout.js        # DFD diagram constants
│   │   │                    #   NW=84 (node width), NH=60 (node height)
│   │   │                    #   LH=32 (lane header), VGAP=12, HGAP=18
│   │   │                    #   TPAD=18, TVPAD=22, HDRH=40, TGAP=60
│   │   │                    #   CPAD=28, LEGEND_W=252
│   │   │
│   │   ├── styles.js        # Design system
│   │   │                    #   C — dark-mode color palette (bg, surface, text, accent, etc.)
│   │   │                    #   MONO / SANS — typography
│   │   │                    #   SEV_COLOR / SEV_BG — severity colors
│   │   │                    #   card() / sectionBar() — style factories
│   │   │                    #   hlXml() — XML syntax highlighter
│   │   │
│   │   └── tiers.js         # Architectural tier definitions
│   │                        #   TIERS map: id → { label, bg color, text color }
│   │                        #   Tier IDs: xsphere, org, security, cicd, network, compute, storage
│   │                        #   detectPaveLayer(filePath) → "L0" | "L1" | ... | null
│   │
│   ├── data/
│   │   ├── kb-domains.js           # Built-in knowledge base (8 domains)
│   │   │                           #   Each domain: title, color, icon, sections[]
│   │   │                           #   Domains: xSphere, AWS Orgs, IAM, Terraform/IaC,
│   │   │                           #            Kubernetes, Networking, Databases, Compliance
│   │   │
│   │   ├── resource-types.js       # Terraform type → DFD metadata
│   │   │                           #   100+ resource types
│   │   │                           #   { l: label, t: tier, i: icon-emoji, c: hex-color }
│   │   │
│   │   ├── attack-data.js          # MITRE ATT&CK data
│   │   │                           #   ATTACK_TECHNIQUES — technique definitions
│   │   │                           #   TF_ATTACK_MAP — resource type → technique IDs
│   │   │                           #   CWE_DETAILS — weakness descriptions
│   │   │                           #   STRIDE_PER_ELEMENT — STRIDE applicability
│   │   │                           #   getElementType() — type → element category
│   │   │
│   │   ├── entity-patterns.js      # Regex patterns for NER
│   │   │                           #   PII, credentials, IPs, domains, ARNs, IOCs
│   │   │                           #   STOP_WORDS — English stopwords
│   │   │
│   │   ├── control-detection.js    # Compliance control mapping
│   │   │                           #   CONTROL_DETECTION_MAP, DID_LAYERS, ZT_PILLARS
│   │   │                           #   NIST_CSF_CHECKS, mkEvidence()
│   │   │
│   │   ├── misconfig-checks.js     # Security check rules by resource type
│   │   │                           #   30+ checks: RDS, S3, Lambda, KMS, SGs, IAM, etc.
│   │   │
│   │   └── architecture-layers.js  # Enterprise PAVE layer definitions
│   │                               #   L0 Org → L1 Vending → L2 Pave → L3 Product → L4 Service
│   │
│   ├── hooks/
│   │   ├── useLLM.js              # LLM status + progress state
│   │   │                          #   llmStatus, llmProgress, llmStatusText
│   │   │                          #   embedStatus, embedProgress
│   │   │                          #   selectedLlmModel, wllamaModelName, wllamaModelSize
│   │   │
│   │   ├── useModelManager.js     # Threat model CRUD + persistence
│   │   │                          #   currentModel, modelDetails, saveModelDetails
│   │   │                          #   createModel, openModel, deleteModel
│   │   │                          #   localStorage: 'tf-models'
│   │   │
│   │   ├── useUserDocs.js         # User document state + IDB cache purge on remove
│   │   │                          #   userDocs, addDocs, removeDoc
│   │   │                          #   localStorage: 'tf-model-{id}-docs'
│   │   │
│   │   ├── useParseResult.js      # files / parseResult / xml state
│   │   │                          #   Updated after every file upload or re-parse
│   │   │
│   │   └── useVectorStore.js      # VectorStore + ColBERTVectorStore refs
│   │                              #   rebuildVectorStore() — re-embeds all docs
│   │                              #   IndexedDB: 'threataform-vectors' v2
│   │
│   ├── components/
│   │   ├── KBPanel.jsx             # Knowledge base accordion viewer
│   │   │                           #   Renders 8 kb-domains.js domains
│   │   │                           #   Collapsible sections, copy-to-query button
│   │   │
│   │   ├── UserDocsPanel.jsx       # Document uploader + management panel
│   │   │                           #   Drag-and-drop + file picker
│   │   │                           #   Per-doc status, remove button
│   │   │
│   │   ├── ScopeSelector.jsx       # In-scope / out-of-scope tag selector
│   │   │                           #   Filters which files/resources are analyzed
│   │   │
│   │   ├── ChipInput.jsx           # Multi-value chip input (tags)
│   │   │                           #   Used for frameworks, features, product modules
│   │   │
│   │   ├── GradeBadge.jsx          # Security grade badge (A–F)
│   │   │                           #   Props: grade, size ("sm" | "md" | "lg"), color
│   │   │                           #   Used in LandingPage model cards + WorkspaceShell header
│   │   │
│   │   ├── NavRail.jsx             # 48px-wide vertical icon navigation rail
│   │   │                           #   Props: items[], active, onChange
│   │   │                           #   item.title used as tooltip (falls back to item.label)
│   │   │                           #   aria-current="page" on active item
│   │   │
│   │   ├── RebuildBanner.jsx       # "Intelligence index needs rebuild" notification
│   │   │                           #   Props: active, text
│   │   │                           #   Collapses when active=false
│   │   │
│   │   └── SplitPane.jsx           # Resizable center + right pane layout
│   │                               #   Props: center, right, rightWidth, rightOpen
│   │                               #   Drag handle to resize right pane
│   │
│   ├── features/
│   │   │
│   │   ├── intelligence/
│   │   │   ├── IntelligencePanel.jsx         # 7-tab intelligence hub
│   │   │   │   # 3 tab groups: Analysis, Threat Intel, Architecture
│   │   │   │   # Default tab: posture-controls
│   │   │   │   # Builds ctx object from all state, spreads into tab components
│   │   │   │   # noData guard: shows empty state when intelligence not built
│   │   │   │
│   │   │   ├── AIChatPanel.jsx               # Persistent AI chat right panel
│   │   │   │   # Multi-turn chat with RAG context
│   │   │   │   # BM25 fallback (no LLM needed)
│   │   │   │   # Chat history: localStorage 'tf-model-{id}-chat'
│   │   │   │   # Quick prompts when empty + intelligence ready
│   │   │   │
│   │   │   ├── useIntelligenceState.js       # Consolidated useReducer hook
│   │   │   │   # 29 state fields, SET/PATCH/RESET actions
│   │   │   │   # set(key) returns curried setter
│   │   │   │
│   │   │   ├── panelHelpers.jsx              # Shared UI helpers
│   │   │   │   # SEV_COLOR, renderMarkdown, chunkCard, scoreBar, etc.
│   │   │   │
│   │   │   └── tabs/
│   │   │       ├── PostureControlsTab.jsx    # Security posture + control inventory
│   │   │       ├── MisconfigsTab.jsx         # Misconfiguration checklist
│   │   │       ├── ThreatIntelTab.jsx        # STRIDE + ATT&CK per resource
│   │   │       ├── CrossDocTab.jsx           # Multi-document contradiction + gap analysis
│   │   │       ├── ScopeTab.jsx              # Scope extraction from docs
│   │   │       ├── ResourceIntelTab.jsx      # Per-resource BM25 + vector hits
│   │   │       └── ArchLayersTab.jsx         # PAVE layer architecture analysis
│   │   │
│   │   ├── analysis/
│   │   │   ├── AnalysisPanel.jsx             # Full STRIDE threat analysis report
│   │   │   │   # Consumes parseResult → generateAnalysis()
│   │   │   │   # Findings sorted by severity, collapsible sections
│   │   │   │   # Trust boundaries, STRIDE map, ATT&CK grid
│   │   │   │
│   │   │   └── AnalysisErrorBoundary.jsx     # React error boundary for AnalysisPanel
│   │   │
│   │   ├── setup/
│   │   │   └── SetupPanel.jsx                # Upload + configure
│   │   │       # Left: UserDocsPanel (document ingestion)
│   │   │       # Right: Application details form
│   │   │       # ChipInput for frameworks, features, product modules
│   │   │
│   │   ├── settings/
│   │   │   └── SettingsPanel.jsx             # Platform settings
│   │   │       # Section 1: AI Language Model (LLM load + status)
│   │   │       # Section 2: LoRA Fine-Tuning (in-browser training)
│   │   │       # Section 3: MCP Server (WebSocket external tools)
│   │   │       # Section 4: Model Settings (metadata)
│   │   │
│   │   ├── pages/
│   │   │   ├── LandingPage.jsx               # Model selection / creation screen
│   │   │   │   # "Start New Threat Model" card with name input
│   │   │   │   # Quick example chips (Kinesis, EKS, API Gateway, etc.)
│   │   │   │   # Existing models grid with GradeBadge, file counts, dates
│   │   │   │   # Delete button per model card
│   │   │   │
│   │   │   └── DocumentsPage.jsx             # Document management page
│   │   │
│   │   └── workspace/
│   │       └── WorkspaceShell.jsx            # Persistent workspace layout
│   │           # 48px header with: Home button, brand, model name + grade, ⌘K AI toggle
│   │           # NavRail (left) + SplitPane (center + AI chat right)
│   │           # RebuildBanner below header
│   │           # ⌘K keyboard shortcut toggles AI chat panel
│   │           # Exports: NAV_SECTION_IDS constant
│   │
│   ├── lib/
│   │   │
│   │   ├── WllamaManager.js          # Compatibility shim → re-exports ThreataformEngine
│   │   │
│   │   ├── ThreataformEngine.js      # Main LLM + RAG engine (482 lines)
│   │   │   # loadFromFile(), loadFromUrl(), generate(), embed(), embedQuery()
│   │   │   # ingestFile(), fineTune(), saveLoRA(), loadLoRA(), search(), unload()
│   │   │   # Delegates to engineWorker.js + ingestWorker.js
│   │   │
│   │   ├── ThrataformRAG.js          # Core RAG primitives (no external ML deps)
│   │   │   # RecursiveTextSplitter — semantic chunking
│   │   │   # BM25Index — Okapi BM25 (k1=1.5, b=0.75)
│   │   │   # VectorStore — cosine similarity + HNSW ANN
│   │   │   # hybridSearch() — BM25 + vector RRF fusion (k=60)
│   │   │   # rerank() — optional cross-encoder
│   │   │   # ContextPacker — token-budget-aware context assembly
│   │   │
│   │   ├── observability.js          # Logging and instrumentation
│   │   │   # LOG(level, msg, data) — structured logger
│   │   │   # ThreataformError — typed error class
│   │   │   # createInferenceTracker() — latency + token tracking
│   │   │   # logHybridSearch() — retrieval telemetry
│   │   │
│   │   ├── rag/
│   │   │   ├── BM25Index.js          # Standalone BM25 implementation
│   │   │   ├── VectorStore.js        # SingleVectorStore + ColBERTVectorStore + HNSW
│   │   │   ├── Chunker.js            # RecursiveTextSplitter, SemanticChunker, makeChunker
│   │   │   ├── HybridRetriever.js    # 4-stage: BM25 + dense + ColBERT + rerank
│   │   │   ├── HyDE.js               # Hypothetical Document Embeddings
│   │   │   └── SelfRAG.js            # SELF-RAG control-token generation loop
│   │   │
│   │   ├── iac/
│   │   │   ├── TerraformParser.js    # parseTFMultiFile() + PAVE detection
│   │   │   ├── SecurityAnalyzer.js   # runSecurityChecks() + STRIDE + ATT&CK + posture
│   │   │   ├── CFNParser.js          # CloudFormation JSON/YAML parser
│   │   │   ├── PolicyEvaluator.js    # AWS IAM / SCP policy simulation
│   │   │   └── OrgTreeBuilder.js     # AWS Organizations hierarchy reconstruction
│   │   │
│   │   ├── diagram/
│   │   │   ├── DFDGenerator.js       # generateDFDXml() → mxGraphModel XML
│   │   │   ├── LegendBuilder.js      # buildLegendCells() + xe() / xeXml() XML escaping
│   │   │   └── ExportUtils.js        # .lucid ZIP + TXT/Markdown report generation
│   │   │
│   │   ├── intelligence/
│   │   │   ├── ThreatModelIntelligence.js    # BM25-lite knowledge index
│   │   │   │   # build(), query(), analyzeResource(), getArchitectureSummary()
│   │   │   │
│   │   │   └── ArchitectureAnalyzer.js       # PAVE layer analysis + factory detection
│   │   │
│   │   ├── llm/
│   │   │   ├── Model.js              # ThreataformLM forward pass + generate + embed
│   │   │   ├── Tokenizer.js          # 32K BPE tokenizer + chat template
│   │   │   ├── WeightsLoader.js      # .tnlm parser + IndexedDB cache + autoLoad
│   │   │   ├── Ops.js                # All math primitives (Float32Array)
│   │   │   ├── NLP.js                # SecurityNER, SemanticChunker, detectLanguage
│   │   │   └── LoRA.js               # In-browser fine-tuning, AdamW, 168 adapter pairs
│   │   │
│   │   ├── mcp/
│   │   │   ├── MCPToolRegistry.js    # Built-in + external tool registry
│   │   │   ├── MCPClient.js          # JSON-RPC WebSocket MCP client
│   │   │   └── tools/
│   │   │       ├── CVSSScorer.js     # CVSS v3.1 base score calculator
│   │   │       ├── ThreatDBTool.js   # MITRE ATT&CK lookup
│   │   │       └── ComplianceChecker.js  # HIPAA/PCI/SOC2/FedRAMP gap analysis
│   │   │
│   │   └── ingestion/
│   │       ├── FileRouter.js         # Multi-format extractor dispatcher
│   │       ├── PDFExtractor.js       # pdfjs-dist PDF text extraction
│   │       ├── DocxExtractor.js      # mammoth DOCX parsing
│   │       ├── SpreadsheetExtractor.js  # SheetJS Excel/CSV
│   │       ├── PresentationExtractor.js # jszip PPTX
│   │       ├── ImageExtractor.js     # Tesseract.js OCR
│   │       ├── AudioExtractor.js     # Web Audio API / Whisper.js transcription
│   │       ├── MarkupExtractor.js    # HTML / Markdown / RST
│   │       └── StructuredExtractor.js   # JSON / YAML / HCL / TOML / XML
│   │
│   └── workers/
│       ├── engineWorker.js           # ThreataformLM inference + LoRA training
│       │   # Messages: load, generate, token, embed, embedMulti, train, progress, ready
│       │
│       ├── ingestWorker.js           # File chunking + embedding pipeline
│       │   # Messages: ingest, chunk, embed, done, progress
│       │
│       ├── llmWorker.js              # wllama generation worker (legacy / active)
│       └── embedWorker.js            # wllama embedding worker (legacy / active)
│
├── public/
│   ├── model.tnlm                   # ThreataformLM weights
│   │                                #   Smoke-test: 300KB random weights (garbage output)
│   │                                #   Production: ~50MB Q4/Q8 quantized weights
│   ├── manifest.webmanifest         # PWA manifest
│   └── README.md                    # Deployment reference
│
├── scripts/                         # Python offline training pipeline
│   ├── build_vocab.py               # BPE vocabulary construction
│   ├── build_corpus.py              # Corpus download + preprocessing
│   ├── generate_synth_data.py       # Synthetic Q&A generation (GPT-4o, one-time)
│   ├── train_base.py                # Pre-training
│   ├── train_instruct.py            # Supervised fine-tuning
│   ├── train_dpo.py                 # DPO alignment
│   ├── quantize.py                  # Mixed Q4/Q8 quantization + .tnlm export
│   ├── export_vocab.py              # Vocabulary export to JS
│   ├── eval.py                      # Evaluation suite
│   └── create_dummy_model.py        # Creates 300KB smoke-test model.tnlm
│
└── dist/                            # Production build output (git-ignored)
```

---

## Security & Privacy

- **100% client-side.** Terraform code and documents never leave your browser at any point.
- **No telemetry.** No analytics, no crash reporting, no external API calls from the application itself.
- **Files never uploaded.** All file processing uses the browser File API and Web Workers, entirely locally.
- **Air-gap compatible.** PWA service worker caches the app shell for offline-first loading. GGUF models loaded from disk work without any network connection.
- **IndexedDB only.** Embedding vectors and model weights are cached in the browser's local IndexedDB — not sent anywhere.
- **CDN fallbacks only for parsers.** If optional document extraction libraries (PDF, DOCX, etc.) are missing from node_modules, the app falls back to loading them from `esm.sh`. In a fully air-gapped environment, pre-install all packages or disable CDN fallback in `FileRouter.js`.
- **MCP external tools are opt-in.** The MCP WebSocket connection is only established when the user manually provides a server URL and clicks Connect in Settings.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI Framework | React 18 |
| Icons | Lucide React |
| Styling | Inline CSS (no CSS-in-JS library, no Tailwind) |
| Build Tool | Vite 5.4 + vite-plugin-pwa |
| Active LLM Engine | ThreataformEngine.js (auto-loads model.tnlm) |
| Legacy LLM Shim | @wllama/wllama 2.3.7 (llama.cpp WASM, now wrapped by ThreataformEngine) |
| Custom LLM | ThreataformLM-200M (pure JS, engineWorker.js) |
| RAG | ThrataformRAG.js (BM25 + HNSW + hybrid search, pure JS) |
| File: PDF | pdfjs-dist 4.10 |
| File: DOCX | mammoth 1.8 |
| File: XLSX | SheetJS 0.18 |
| File: PPTX/ZIP | jszip 3.10 |
| File: OCR | Tesseract.js |
| Optional: Reranker | @huggingface/transformers 3.0.2 (cross-encoder, optional) |
| Diagrams | draw.io / Lucidchart mxGraph XML |
| Persistence | localStorage (model state + docs + chat) + IndexedDB (vectors + model cache) |
| PWA | vite-plugin-pwa — offline-first service worker + app manifest |

---

## Supported Frameworks

### Compliance / Industry

HIPAA, FedRAMP Moderate, FedRAMP High, PCI DSS v4, GDPR, SOC 2 Type II, CMMC Level 2, NIST 800-53 r5, NIST CSF 2.0, CIS Controls v8, ISO 27001, NIST SP 800-207 (Zero Trust Architecture)

### Threat Modeling Methodologies

STRIDE, STRIDE-LM, PASTA, VAST, LINDDUN, OCTAVE, RTMP, OWASP Top 10, OWASP Top 10 Cloud, MITRE ATT&CK Enterprise v18.1, DREAD, TRIKE

---

## Acknowledgments

- [MITRE ATT&CK®](https://attack.mitre.org/) Enterprise v18.1
- [HashiCorp Terraform](https://developer.hashicorp.com/terraform)
- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) — Microsoft
- [SELF-RAG](https://arxiv.org/abs/2310.11511) — Asai et al. 2023
- [HyDE](https://arxiv.org/abs/2212.10496) — Gao et al. 2022
- [ColBERT](https://arxiv.org/abs/2004.12832) — Khattab & Zaharia 2020
- [RRF](https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf) — Cormack et al. 2009
- [BPE Tokenization](https://arxiv.org/abs/1508.07909) — Sennrich et al. 2016
- [LoRA](https://arxiv.org/abs/2106.09685) — Hu et al. 2021
- [RoPE](https://arxiv.org/abs/2104.09864) — Su et al. 2021
- [YaRN](https://arxiv.org/abs/2309.00071) — Peng et al. 2023
- [GQA](https://arxiv.org/abs/2305.13245) — Ainslie et al. 2023
- [muP](https://arxiv.org/abs/2203.03466) — Yang et al. 2022
