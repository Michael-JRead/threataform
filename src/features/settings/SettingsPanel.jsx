// src/features/settings/SettingsPanel.jsx
// Workspace Settings section: LLM model loader, MCP server, LoRA fine-tuning,
// model metadata editor.

import React, { useState, useRef } from "react";
import {
  Upload, Settings, Loader2, CheckCircle2, XCircle, RefreshCw,
  Plug, Brain, Database, TriangleAlert, Info,
} from "../../icons.jsx";
import { C, SANS, MONO } from "../../constants/styles.js";
import { wllamaManager } from "../../lib/WllamaManager.js";
import { mcpRegistry } from "../../lib/mcp/MCPToolRegistry.js";

/**
 * @param {{
 *   llmStatus: string,       llmProgress: number,
 *   llmStatusText: string,   selectedLlmModel: string,
 *   wllamaModelName: string, wllamaModelSize: number,
 *   onLoadModel: function,
 *   userDocs: Array,
 *   currentModel: object|null,
 *   modelDetails: object,
 *   saveModelDetails: function,
 * }} props
 */
export function SettingsPanel({
  llmStatus,
  llmProgress,
  llmStatusText,
  selectedLlmModel,
  wllamaModelName,
  wllamaModelSize,
  onLoadModel,
  userDocs = [],
  currentModel,
  modelDetails,
  saveModelDetails,
}) {
  // ── MCP state (local — mcpRegistry is a global singleton) ──────────────────
  const [mcpUrl, setMcpUrl]       = useState("ws://localhost:3747");
  const [mcpStatus, setMcpStatus] = useState(null);   // null | 'connecting' | 'connected' | 'failed'
  const [mcpError, setMcpError]   = useState(null);

  // ── LoRA state (local — wllamaManager is a global singleton) ──────────────
  const [isTraining, setIsTraining] = useState(false);
  const [ftProgress, setFtProgress] = useState(0);
  const [loraReady, setLoraReady]   = useState(false);
  const [loraError, setLoraError]   = useState(null);

  const fileInputRef = useRef(null);

  // ── MCP connect ─────────────────────────────────────────────────────────────
  const connectMcp = async () => {
    if (!mcpUrl.trim()) return;
    setMcpStatus("connecting"); setMcpError(null);
    try {
      const ok = await mcpRegistry.tryConnectExternal(mcpUrl.trim());
      setMcpStatus(ok ? "connected" : "failed");
      if (!ok) setMcpError(mcpRegistry.lastConnectError || "Connection failed");
    } catch (err) {
      setMcpStatus("failed");
      setMcpError(err.message || "Connection failed");
    }
  };

  // ── LoRA fine-tune ──────────────────────────────────────────────────────────
  const handleFineTune = async () => {
    if (isTraining || !userDocs?.length) return;
    const texts = userDocs.map(d => d.content).filter(Boolean);
    if (!texts.length) return;
    setIsTraining(true); setFtProgress(0); setLoraReady(false); setLoraError(null);
    try {
      if (typeof wllamaManager.fineTune === "function") {
        const ok = await wllamaManager.fineTune(texts, {
          onProgress: p => setFtProgress(Math.round(p * 100)),
        });
        if (ok) setLoraReady(true);
        else setLoraError("Training did not complete.");
      } else {
        setLoraError("Fine-tuning not available with the loaded model.");
      }
    } catch (err) {
      setLoraError(err.message || "Training failed");
    } finally {
      setIsTraining(false);
    }
  };

  const handleExportLora = async () => {
    if (!loraReady || isTraining) return;
    try {
      let buf;
      if (typeof wllamaManager.saveLoRA === "function") buf = await wllamaManager.saveLoRA();
      if (buf) {
        const blob = new Blob([buf], { type: "application/octet-stream" });
        const a = document.createElement("a"); a.href = URL.createObjectURL(blob);
        a.download = `${(currentModel?.name || "model").replace(/[^a-z0-9]/gi, "_")}.tnlm`;
        a.click(); URL.revokeObjectURL(a.href);
      }
    } catch (err) { console.error("[SettingsPanel] LoRA export:", err); }
  };

  // ── Status colors ──────────────────────────────────────────────────────────
  const statusColor = s => s === "ready" ? C.green : s === "loading" ? C.accent : s === "error" ? C.red : C.textMuted;

  return (
    <div style={{ overflowY: "auto", height: "100%", padding: "28px 32px", maxWidth: 720 }}>

      {/* ═══════════════════════════════════════════════════════════════════ */}
      {/* LLM MODEL                                                           */}
      {/* ═══════════════════════════════════════════════════════════════════ */}
      <section style={{ marginBottom: 32 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
          <Brain size={18} style={{ color: "#7C3AED" }}/>
          <div>
            <div style={{ ...SANS, fontSize: 15, fontWeight: 700, color: C.text }}>AI Language Model</div>
            <div style={{ fontSize: 12, color: C.textMuted }}>
              Load a local .gguf model — runs entirely in your browser via WebAssembly, no internet required
            </div>
          </div>
        </div>

        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 12, padding: "18px 20px" }}>

          {/* Loading progress */}
          {llmStatus === "loading" && (
            <div style={{ marginBottom: 14 }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6 }}>
                <span style={{ fontSize: 13, color: C.text, fontWeight: 600, display: "flex", alignItems: "center", gap: 7 }}>
                  <Loader2 size={13} style={{ animation: "spin 1s linear infinite", color: "#7C3AED" }}/>
                  Loading model into browser…
                </span>
                <span style={{ fontSize: 12, fontWeight: 700, color: "#7C3AED" }}>{llmProgress}%</span>
              </div>
              <div style={{ height: 6, background: C.border, borderRadius: 3, overflow: "hidden", marginBottom: 6 }}>
                <div style={{ height: "100%", borderRadius: 3, width: `${llmProgress}%`,
                  background: "linear-gradient(90deg,#7C3AED,#9F67FA)", transition: "width .3s ease" }}/>
              </div>
              <div style={{ fontSize: 11, color: C.textMuted }}>
                {selectedLlmModel || "model.gguf"}
                {llmStatusText ? ` · ${llmStatusText}` : ""}
              </div>
            </div>
          )}

          {/* Model loaded */}
          {llmStatus === "ready" && wllamaModelName && (
            <div style={{ background: "#7C3AED08", border: "1px solid #7C3AED22", borderRadius: 8,
              padding: "10px 14px", marginBottom: 14, display: "flex", alignItems: "center", gap: 10 }}>
              <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#7C3AED", flexShrink: 0 }}/>
              <div style={{ flex: 1 }}>
                <span style={{ fontSize: 13, fontWeight: 700, color: "#7C3AED" }}>{wllamaModelName}</span>
                {wllamaModelSize > 0 && (
                  <span style={{ fontSize: 11, color: C.textMuted, marginLeft: 8 }}>· {wllamaModelSize} MB</span>
                )}
                <div style={{ fontSize: 11, color: C.textMuted, marginTop: 2 }}>In-browser WASM · Zero internet</div>
              </div>
              <button onClick={() => onLoadModel(null)} style={{
                ...SANS, fontSize: 11, padding: "4px 12px", borderRadius: 6, cursor: "pointer",
                background: "transparent", border: `1px solid ${C.border}`, color: C.textMuted,
              }}>Unload</button>
            </div>
          )}

          {/* Error */}
          {llmStatus === "error" && (
            <div style={{ background: "#200808", border: `1px solid ${C.red}44`, borderRadius: 8,
              padding: "10px 14px", marginBottom: 14, display: "flex", gap: 8, alignItems: "center" }}>
              <TriangleAlert size={14} style={{ color: C.red, flexShrink: 0 }}/>
              <span style={{ fontSize: 12, color: "#FF8A80" }}>
                {llmStatusText || "Failed to load model. Is the file a valid .gguf?"}
              </span>
            </div>
          )}

          {/* Idle / not loaded */}
          {(llmStatus === "idle" || !llmStatus) && (
            <div style={{ fontSize: 12, color: C.textMuted, marginBottom: 14, padding: "8px 12px",
              background: C.bg, borderRadius: 8, border: `1px solid ${C.border}` }}>
              No model loaded. Select a .gguf file below to enable AI-assisted analysis.
            </div>
          )}

          {/* File picker */}
          {llmStatus !== "ready" && llmStatus !== "loading" && (
            <label style={{
              display: "flex", alignItems: "center", gap: 8, cursor: "pointer",
              background: `linear-gradient(135deg,#7C3AED18,#7C3AED08)`,
              border: `1px solid #7C3AED44`, borderRadius: 8,
              padding: "10px 16px", width: "fit-content",
              fontSize: 13, fontWeight: 600, color: "#7C3AED", ...SANS,
            }}>
              <Upload size={14}/> Select .gguf Model File
              <input
                ref={fileInputRef}
                type="file"
                accept=".gguf,.bin"
                style={{ display: "none" }}
                onChange={e => {
                  const file = e.target.files?.[0];
                  if (file) onLoadModel(file);
                  e.target.value = "";
                }}
              />
            </label>
          )}

          {/* Change model when loaded */}
          {llmStatus === "ready" && (
            <label style={{
              display: "inline-flex", alignItems: "center", gap: 6, cursor: "pointer",
              fontSize: 12, color: C.textMuted, ...SANS,
              padding: "5px 12px", borderRadius: 6, border: `1px solid ${C.border}`,
              background: C.surface2,
            }}>
              <Upload size={12}/> Load Different Model
              <input type="file" accept=".gguf,.bin" style={{ display: "none" }}
                onChange={e => { const f = e.target.files?.[0]; if (f) onLoadModel(f); e.target.value = ""; }}/>
            </label>
          )}

          <div style={{ fontSize: 11, color: C.textMuted, marginTop: 10, lineHeight: 1.5 }}>
            Recommended: <span style={{ ...MONO, fontSize: 10 }}>llama-3.2-3b-instruct.Q4_K_M.gguf</span> (~2GB) or any
            instruction-tuned GGUF. Larger models improve analysis quality at the cost of load time.
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════════════════════════ */}
      {/* LORA FINE-TUNING                                                    */}
      {/* ═══════════════════════════════════════════════════════════════════ */}
      <section style={{ marginBottom: 32 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
          <Database size={18} style={{ color: "#2E7D32" }}/>
          <div>
            <div style={{ ...SANS, fontSize: 15, fontWeight: 700, color: C.text }}>LoRA Fine-Tuning</div>
            <div style={{ fontSize: 12, color: C.textMuted }}>
              Adapt the loaded model to your uploaded documents for more accurate domain-specific analysis
            </div>
          </div>
        </div>

        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 12, padding: "18px 20px" }}>
          {llmStatus !== "ready" ? (
            <div style={{ fontSize: 12, color: C.textMuted, display: "flex", gap: 7, alignItems: "center" }}>
              <Info size={13} style={{ opacity: 0.5 }}/>
              Load a .gguf model above to enable LoRA fine-tuning.
            </div>
          ) : !userDocs?.length ? (
            <div style={{ fontSize: 12, color: C.textMuted, display: "flex", gap: 7, alignItems: "center" }}>
              <Info size={13} style={{ opacity: 0.5 }}/>
              Upload supporting documents in Setup to enable fine-tuning on domain content.
            </div>
          ) : (
            <>
              <div style={{ fontSize: 12, color: C.textSub, marginBottom: 14, lineHeight: 1.6 }}>
                Fine-tunes a LoRA adapter on your {userDocs.length} uploaded document{userDocs.length !== 1 ? "s" : ""}.
                The adapter is applied in-memory and can be exported as a <span style={{ ...MONO, fontSize: 11 }}>.tnlm</span> patch file.
              </div>

              {/* Progress bar while training */}
              {isTraining && (
                <div style={{ marginBottom: 14 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 5 }}>
                    <span style={{ fontSize: 12, color: "#2E7D32", fontWeight: 600, display: "flex", gap: 6, alignItems: "center" }}>
                      <Loader2 size={12} style={{ animation: "spin 1s linear infinite" }}/> Training…
                    </span>
                    <span style={{ fontSize: 12, fontWeight: 700, color: "#2E7D32" }}>{ftProgress}%</span>
                  </div>
                  <div style={{ height: 5, background: C.border, borderRadius: 3, overflow: "hidden" }}>
                    <div style={{ height: "100%", borderRadius: 3, width: `${ftProgress}%`,
                      background: "linear-gradient(90deg,#2E7D32,#43A047)", transition: "width .3s ease" }}/>
                  </div>
                </div>
              )}

              {loraReady && !isTraining && (
                <div style={{ background: "#2E7D3208", border: "1px solid #2E7D3222", borderRadius: 8,
                  padding: "8px 12px", marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
                  <CheckCircle2 size={13} style={{ color: "#2E7D32" }}/>
                  <span style={{ fontSize: 12, color: "#2E7D32", fontWeight: 600 }}>LoRA adapter ready</span>
                  <button onClick={handleExportLora} style={{
                    ...SANS, marginLeft: "auto", fontSize: 11, padding: "3px 10px", borderRadius: 5,
                    background: "transparent", border: "1px solid #2E7D3244", color: "#2E7D32", cursor: "pointer",
                    display: "flex", alignItems: "center", gap: 4,
                  }}>Export .tnlm</button>
                </div>
              )}

              {loraError && (
                <div style={{ fontSize: 12, color: C.red, marginBottom: 10, padding: "6px 10px",
                  background: `${C.red}10`, borderRadius: 6, border: `1px solid ${C.red}33` }}>
                  {loraError}
                </div>
              )}

              <button onClick={handleFineTune} disabled={isTraining} style={{
                ...SANS, fontSize: 12, fontWeight: 600, padding: "8px 18px", borderRadius: 7, cursor: isTraining ? "default" : "pointer",
                background: isTraining ? "#2E7D3218" : "linear-gradient(135deg,#2E7D3218,#43A04718)",
                border: `1px solid #2E7D3244`, color: "#2E7D32",
                display: "flex", alignItems: "center", gap: 6, opacity: isTraining ? 0.7 : 1,
              }}>
                {isTraining ? <><Loader2 size={12} style={{ animation: "spin 1s linear infinite" }}/> Training ({ftProgress}%)</> : "Fine-tune on Documents"}
              </button>
            </>
          )}
        </div>
      </section>

      {/* ═══════════════════════════════════════════════════════════════════ */}
      {/* MCP SERVER                                                          */}
      {/* ═══════════════════════════════════════════════════════════════════ */}
      <section style={{ marginBottom: 32 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
          <Plug size={18} style={{ color: C.blue }}/>
          <div>
            <div style={{ ...SANS, fontSize: 15, fontWeight: 700, color: C.text }}>MCP Server</div>
            <div style={{ fontSize: 12, color: C.textMuted }}>
              Connect to a Model Context Protocol server to enable external tools (CVSS scoring, MITRE lookups, etc.)
            </div>
          </div>
        </div>

        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 12, padding: "18px 20px" }}>
          <div style={{ fontSize: 12, color: C.textSub, marginBottom: 14, lineHeight: 1.6 }}>
            MCP tools extend the AI assistant with real-time external data. The server runs locally on your machine.
          </div>

          <div style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 8 }}>
            <input
              value={mcpUrl}
              onChange={e => setMcpUrl(e.target.value)}
              onKeyDown={e => { if (e.key === "Enter") connectMcp(); }}
              placeholder="ws://localhost:3747"
              style={{
                flex: 1, fontSize: 13, padding: "8px 12px", background: C.bg,
                border: `1px solid ${mcpStatus === "connected" ? C.green + "55" : C.border2}`,
                borderRadius: 8, color: C.text, outline: "none", ...MONO,
              }}
              onFocus={e => e.target.style.borderColor = C.accent}
              onBlur={e => e.target.style.borderColor = mcpStatus === "connected" ? C.green + "55" : C.border2}
            />
            <button onClick={connectMcp} disabled={mcpStatus === "connecting"} style={{
              ...SANS, fontSize: 13, fontWeight: 600, padding: "8px 16px", borderRadius: 8, cursor: "pointer",
              background: mcpStatus === "connected" ? `${C.green}18` : `${C.blue}18`,
              border: `1px solid ${mcpStatus === "connected" ? C.green + "55" : C.blue + "44"}`,
              color: mcpStatus === "connected" ? C.green : C.blue,
              display: "flex", alignItems: "center", gap: 6,
              opacity: mcpStatus === "connecting" ? 0.7 : 1,
            }}>
              {mcpStatus === "connecting" ? <><Loader2 size={12} style={{ animation: "spin 1s linear infinite" }}/> Connecting…</> :
               mcpStatus === "connected" ? <><CheckCircle2 size={12}/> Connected</> : "Connect"}
            </button>
          </div>

          {mcpStatus === "connected" && (
            <div style={{ fontSize: 11, color: C.green, display: "flex", alignItems: "center", gap: 5 }}>
              <CheckCircle2 size={11}/>
              {mcpRegistry.toolCount || 0} tools available · LLM can call tools via &lt;tool_call&gt; in responses
            </div>
          )}
          {mcpStatus === "failed" && mcpError && (
            <div style={{ fontSize: 12, color: C.red, padding: "6px 10px", background: `${C.red}10`,
              borderRadius: 6, border: `1px solid ${C.red}33`, display: "flex", gap: 6, alignItems: "center" }}>
              <XCircle size={12}/> {mcpError}
            </div>
          )}

          <div style={{ fontSize: 11, color: C.textMuted, marginTop: 10, lineHeight: 1.5 }}>
            Start your MCP server with: <span style={{ ...MONO, fontSize: 10 }}>npx @threataform/mcp-server</span>
            <br/>The AI assistant will automatically use available tools when answering questions.
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════════════════════════ */}
      {/* MODEL METADATA                                                      */}
      {/* ═══════════════════════════════════════════════════════════════════ */}
      {currentModel && (
        <section style={{ marginBottom: 32 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
            <Settings size={18} style={{ color: C.textMuted }}/>
            <div>
              <div style={{ ...SANS, fontSize: 15, fontWeight: 700, color: C.text }}>Model Settings</div>
              <div style={{ fontSize: 12, color: C.textMuted }}>Edit model name, owner, and description</div>
            </div>
          </div>

          <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 12, padding: "18px 20px" }}>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
              <div>
                <div style={{ fontSize: 11, color: C.textMuted, fontWeight: 600, marginBottom: 6 }}>Model Name</div>
                <input
                  value={modelDetails?.name || currentModel.name || ""}
                  onChange={e => saveModelDetails({ ...modelDetails, name: e.target.value })}
                  style={{ width: "100%", boxSizing: "border-box", background: C.bg, border: `1px solid ${C.border2}`,
                    borderRadius: 8, padding: "8px 12px", color: C.text, fontSize: 13, ...SANS, outline: "none" }}
                />
              </div>
              <div>
                <div style={{ fontSize: 11, color: C.textMuted, fontWeight: 600, marginBottom: 6 }}>Team / Owner</div>
                <input
                  value={modelDetails?.owner || ""}
                  onChange={e => saveModelDetails({ ...modelDetails, owner: e.target.value })}
                  placeholder="e.g. Platform Security Team"
                  style={{ width: "100%", boxSizing: "border-box", background: C.bg, border: `1px solid ${C.border2}`,
                    borderRadius: 8, padding: "8px 12px", color: C.text, fontSize: 13, ...SANS, outline: "none" }}
                />
              </div>
            </div>
            <div>
              <div style={{ fontSize: 11, color: C.textMuted, fontWeight: 600, marginBottom: 6 }}>Description</div>
              <textarea
                value={modelDetails?.description || ""}
                onChange={e => saveModelDetails({ ...modelDetails, description: e.target.value })}
                placeholder="Brief description of this threat model's scope…"
                rows={3}
                style={{ width: "100%", boxSizing: "border-box", background: C.bg, border: `1px solid ${C.border2}`,
                  borderRadius: 8, padding: "8px 12px", color: C.text, fontSize: 12, ...SANS, outline: "none",
                  resize: "vertical", lineHeight: 1.6 }}
                onFocus={e => e.target.style.borderColor = C.accent}
                onBlur={e => e.target.style.borderColor = C.border2}
              />
            </div>
          </div>
        </section>
      )}

      {/* CSS keyframe */}
      <style>{`@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}
