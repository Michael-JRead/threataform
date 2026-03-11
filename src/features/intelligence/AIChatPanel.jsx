// src/features/intelligence/AIChatPanel.jsx
// Persistent AI chat right panel — always mounted in WorkspaceShell.
// Owns its own chat state (independent of IntelligencePanel's AI Assistant tab).
// Chat history is persisted to localStorage keyed by currentModelId.
//
// Props:
//   intelligence      ThreatModelIntelligence instance (for offline BM25 search)
//   llmStatus         "idle"|"loading"|"ready"
//   onHybridSearch    (query, topK) => Promise<chunks[]>
//   onGenerateLLM     (messages, onToken) => Promise<void>
//   parseResult       parsed Terraform resources/modules/connections
//   userDocs          uploaded documents array
//   modelDetails      model metadata (owner, environment, etc.)
//   archLayerAnalysis 7-layer architecture analysis result
//   archAnalysis      architecture narrative
//   archOverrides     manual architecture section overrides
//   wllamaModelName   display name of loaded GGUF model
//   llmProgress       0-100 loading progress
//   llmStatusText     status text during loading
//   selectedLlmModel  selected model filename
//   currentModelId    model id for localStorage chat persistence
//   onOpenSettings    () => void — navigate to Settings section

import React, { useState, useRef, useEffect, useCallback } from "react";
import { Bot, Send, Loader2, RotateCcw, FileText, Users } from "../../icons.jsx";
import { C, SANS } from "../../constants/styles.js";
import { wllamaManager } from "../../lib/WllamaManager.js";
import { mcpRegistry } from "../../lib/mcp/MCPToolRegistry.js";
import { createInferenceTracker } from "../../lib/observability.js";
import { renderMarkdown } from "./panelHelpers.jsx";

const QUICK_PROMPTS = [
  "What are the top STRIDE threats in this architecture?",
  "Identify security gaps and missing controls",
  "Map findings to MITRE ATT&CK techniques",
  "Summarize trust boundary violations",
  "Generate an executive security summary",
  "What compliance gaps exist for our frameworks?",
  "List the highest-risk Terraform misconfigurations",
  "What data flows cross trust boundaries?",
];

export function AIChatPanel({
  intelligence,
  llmStatus,
  onHybridSearch,
  onGenerateLLM,
  parseResult,
  userDocs,
  modelDetails,
  archLayerAnalysis,
  archAnalysis,
  archOverrides,
  wllamaModelName,
  llmProgress = 0,
  llmStatusText = "",
  selectedLlmModel,
  currentModelId,
  onOpenSettings,
}) {
  // ── Chat state (own — independent of IntelligencePanel) ────────────
  const chatKey = currentModelId ? `tf-model-${currentModelId}-rightchat` : null;
  const [chatMessages, setChatMessages] = useState(() => {
    if (!chatKey) return [];
    try { return JSON.parse(localStorage.getItem(chatKey) || "[]"); } catch { return []; }
  });
  const [chatInput, setChatInput] = useState("");
  const [chatGenerating, setChatGenerating] = useState(false);
  const chatBottomRef = useRef(null);

  // ── Persist chat to localStorage ────────────────────────────────────
  useEffect(() => {
    if (!chatKey) return;
    try { localStorage.setItem(chatKey, JSON.stringify(chatMessages.slice(-60))); } catch {}
  }, [chatMessages, chatKey]);

  // ── Scroll to bottom on new messages ────────────────────────────────
  useEffect(() => {
    chatBottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chatMessages]);

  // ── Reset chat when model switches ──────────────────────────────────
  useEffect(() => {
    if (!chatKey) { setChatMessages([]); return; }
    try { setChatMessages(JSON.parse(localStorage.getItem(chatKey) || "[]")); } catch { setChatMessages([]); }
  }, [chatKey]);

  // ── Build RAG context ────────────────────────────────────────────────
  const buildContext = useCallback(async (userText) => {
    const chunks = onHybridSearch ? await onHybridSearch(userText, 16) : [];
    const retrievedCtx = chunks.length
      ? chunks.map((c, i) =>
          `[DOC-${i + 1}] File: ${c.source || c.docId || "doc"} | Category: ${c.category || "general"}\n${c.text}`
        ).join("\n\n")
      : "No indexed documents available yet.";

    const md = modelDetails || {};
    const metaLines = [
      md.productName ? `Product: ${md.productName}` : null,
      md.environment ? `Environment: ${md.environment}` : null,
      md.dataClassification?.length ? `Data Classification: ${md.dataClassification.join(", ")}` : null,
      md.frameworks?.length ? `Compliance Frameworks: ${md.frameworks.join(", ")}` : null,
      md.owner ? `Owner: ${md.owner}` : null,
    ].filter(Boolean);

    const resources = parseResult?.resources || [];
    const resCtx = resources.length
      ? `IaC resources (${resources.length}): ${[...new Set(resources.map((r) => r.type))].slice(0, 12).join(", ")}`
      : null;

    const archLayerCtx = archLayerAnalysis
      ? `Architecture layers: ${archLayerAnalysis.architectureGrade || "?"} grade, ${
          Object.entries(archLayerAnalysis.layers || {}).filter(([, l]) => l.completeness > 0).length
        }/7 present`
      : null;

    const archCtx = archAnalysis?.summary || archOverrides?.narrative?.description
      ? `Architecture: ${(archAnalysis?.summary || archOverrides?.narrative?.description || "").substring(0, 300)}`
      : null;

    const sections = [
      metaLines.length ? `=== MODEL CONTEXT ===\n${metaLines.join("\n")}` : null,
      archLayerCtx ? `=== ARCHITECTURE LAYERS ===\n${archLayerCtx}` : null,
      archCtx ? `=== ARCHITECTURE ===\n${archCtx}` : null,
      resCtx ? `=== IaC RESOURCES ===\n${resCtx}` : null,
      `=== RETRIEVED CONTEXT ===\n${retrievedCtx}`,
    ].filter(Boolean).join("\n\n");

    return { sections, contextChunks: chunks };
  }, [onHybridSearch, modelDetails, parseResult, archLayerAnalysis, archAnalysis, archOverrides]);

  // ── Offline smart response (no LLM) ─────────────────────────────────
  const generateSmartResponse = useCallback((userText) => {
    if (!intelligence?._built) {
      return "Upload Terraform files or documents to enable AI analysis. Once files are indexed, I can answer questions about your architecture.";
    }
    const results = intelligence.query(userText, 8);
    if (!results.length) {
      return "No relevant content found for this query. Try uploading more context documents or rephrasing your question.";
    }
    const lines = ["Here are the most relevant passages from your uploaded documents:\n"];
    results.slice(0, 5).forEach((r, i) => {
      const src = r.source || r.docId || r.category || "doc";
      lines.push(`**[${i + 1}] ${src}**\n${r.text.substring(0, 300).trim()}…`);
    });
    return lines.join("\n\n");
  }, [intelligence]);

  // ── Send message ─────────────────────────────────────────────────────
  const sendChat = useCallback(async (userText) => {
    if (!userText?.trim() || chatGenerating) return;
    setChatInput("");
    setChatGenerating(true);
    setChatMessages((prev) => [...prev, { role: "user", content: userText }]);
    setChatMessages((prev) => [...prev, { role: "assistant", content: "", streaming: true, sources: [] }]);

    try {
      const { sections, contextChunks } = await buildContext(userText);

      if (onGenerateLLM && llmStatus === "ready") {
        // ── LLM inference ─────────────────────────────────────────────
        const systemPrompt = `You are Threataform, expert threat modeler and cloud security architect.
Provide complete, exhaustive responses. Use headers, bullets, and code blocks. Cite specific resource IDs and finding codes.
Never hallucinate resource names or CVE IDs. If uncertain, say so.

Context:\n${sections}`;

        const historyMsgs = chatMessages
          .filter((m) => !m.streaming)
          .slice(-12)
          .map((m) => ({ role: m.role, content: m.content.slice(0, 800) }));

        const messages = [
          { role: "system", content: systemPrompt },
          ...historyMsgs,
          { role: "user", content: userText },
        ];

        const retrieval = contextChunks.length
          ? {
              count: contextChunks.length,
              bm25: contextChunks.filter((c) => c.searchType === "bm25").length,
              dense: contextChunks.filter((c) => c.searchType === "dense").length,
              avgScore: Math.round(
                (contextChunks.reduce((s, c) => s + (c.score ?? 0.5), 0) / contextChunks.length) * 100
              ),
            }
          : null;

        setChatMessages((prev) => {
          const last = prev[prev.length - 1];
          if (last?.streaming)
            return [
              ...prev.slice(0, -1),
              {
                ...last,
                sources: contextChunks
                  .slice(0, 5)
                  .map((c) => ({ file: c.source || c.docId || "doc", cat: c.category || "", type: c.searchType || "bm25" })),
                retrieval,
              },
            ];
          return prev;
        });

        let fullResponse = "";
        const tracker = createInferenceTracker(wllamaModelName || "wllama");
        tracker.start();
        await onGenerateLLM(messages, (token) => {
          fullResponse += token;
          setChatMessages((prev) => {
            const last = prev[prev.length - 1];
            if (last?.streaming)
              return [...prev.slice(0, -1), { ...last, content: last.content + token }];
            return prev;
          });
        });
        tracker.end(fullResponse.split(/\s+/).length);

        // Execute tool_call blocks
        if (fullResponse.includes("<tool_call>")) {
          const withResults = await mcpRegistry.executeToolCalls(fullResponse);
          if (withResults !== fullResponse) {
            setChatMessages((prev) => {
              const last = prev[prev.length - 1];
              if (!last?.streaming)
                return [...prev.slice(0, -1), { ...last, content: withResults }];
              return prev;
            });
          }
        }
      } else {
        // ── Offline fallback ──────────────────────────────────────────
        const response = generateSmartResponse(userText);
        setChatMessages((prev) => {
          const last = prev[prev.length - 1];
          if (last?.streaming)
            return [...prev.slice(0, -1), { ...last, content: response }];
          return prev;
        });
      }
    } catch (err) {
      setChatMessages((prev) => {
        const last = prev[prev.length - 1];
        if (last?.streaming)
          return [...prev.slice(0, -1), { ...last, content: `Error: ${err.message}`, streaming: false }];
        return prev;
      });
    }

    setChatMessages((prev) =>
      prev.map((m, i) => (i === prev.length - 1 ? { ...m, streaming: false } : m))
    );
    setChatGenerating(false);
  }, [chatGenerating, chatMessages, buildContext, onGenerateLLM, llmStatus, wllamaModelName, generateSmartResponse]);

  const intelligenceReady = !!intelligence?._built;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        overflow: "hidden",
        ...SANS,
      }}
    >
      {/* ── Panel header ─────────────────────────────────────────────── */}
      <div
        style={{
          padding: "12px 14px 10px",
          borderBottom: `1px solid ${C.border}`,
          flexShrink: 0,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
          <Bot size={16} style={{ color: "#7C3AED" }} />
          <span style={{ fontSize: 13, fontWeight: 700, color: C.text }}>AI Assistant</span>
          <span
            style={{
              fontSize: 10,
              background: intelligenceReady ? "#43A04718" : C.surface2,
              border: `1px solid ${intelligenceReady ? "#43A04744" : C.border}`,
              borderRadius: 9,
              padding: "2px 8px",
              fontWeight: 600,
              color: intelligenceReady ? "#43A047" : C.textMuted,
            }}
          >
            {intelligenceReady ? "Ready" : "Upload files"}
          </span>
          {llmStatus === "ready" && (
            <span
              style={{
                fontSize: 10,
                color: "#7C3AED",
                background: "#7C3AED15",
                border: "1px solid #7C3AED33",
                borderRadius: 9,
                padding: "2px 8px",
                fontWeight: 600,
              }}
            >
              + Local AI
            </span>
          )}
          {chatMessages.length > 0 && (
            <button
              onClick={() => setChatMessages([])}
              title="Clear chat history"
              style={{
                marginLeft: "auto",
                background: "none",
                border: `1px solid ${C.border}`,
                borderRadius: 6,
                padding: "3px 8px",
                color: C.textMuted,
                cursor: "pointer",
                fontSize: 10,
                display: "flex",
                alignItems: "center",
                gap: 4,
              }}
            >
              <RotateCcw size={10} /> Clear
            </button>
          )}
        </div>
        <div style={{ fontSize: 10, color: C.textMuted }}>
          Fully offline · No internet required
          {llmStatus === "ready" && wllamaModelName && (
            <span style={{ color: "#7C3AED", marginLeft: 6 }}>· {wllamaModelName}</span>
          )}
        </div>
      </div>

      {/* ── LLM loading indicator ─────────────────────────────────────── */}
      {llmStatus === "loading" && (
        <div
          style={{
            margin: "10px 12px",
            background: C.surface,
            border: "1px solid #7C3AED33",
            borderRadius: 8,
            padding: "10px 14px",
            flexShrink: 0,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
            <div
              style={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                background: "#7C3AED",
                animation: "pulse 1.2s ease-in-out infinite",
              }}
            />
            <span style={{ fontSize: 12, color: C.text, fontWeight: 600 }}>
              Loading model…
            </span>
          </div>
          <div
            style={{
              height: 4,
              background: C.border,
              borderRadius: 2,
              overflow: "hidden",
              marginBottom: 4,
            }}
          >
            <div
              style={{
                height: "100%",
                borderRadius: 2,
                width: `${llmProgress}%`,
                background: "linear-gradient(90deg,#7C3AED,#9F67FA)",
                transition: "width .3s ease",
              }}
            />
          </div>
          <div style={{ fontSize: 10, color: C.textMuted }}>
            {llmProgress}%{llmStatusText ? ` · ${llmStatusText}` : ""}
          </div>
        </div>
      )}

      {/* ── Load model nudge ──────────────────────────────────────────── */}
      {llmStatus === "idle" && (
        <div
          style={{
            margin: "10px 12px",
            background: "#7C3AED08",
            border: "1px solid #7C3AED22",
            borderRadius: 8,
            padding: "10px 14px",
            flexShrink: 0,
          }}
        >
          <div style={{ fontSize: 12, color: C.text, fontWeight: 600, marginBottom: 4 }}>
            AI chat unavailable — load a model in Settings to enable
          </div>
          <div style={{ fontSize: 11, color: C.textMuted, marginBottom: 8, lineHeight: 1.5 }}>
            Load a .gguf model in Settings to enable AI-assisted threat modeling.
          </div>
          {onOpenSettings && (
            <button
              onClick={onOpenSettings}
              style={{
                background: "#7C3AED15",
                border: "1px solid #7C3AED44",
                borderRadius: 6,
                padding: "5px 12px",
                color: "#7C3AED",
                fontSize: 11,
                cursor: "pointer",
                fontWeight: 600,
              }}
            >
              Load model in Settings →
            </button>
          )}
        </div>
      )}

      {/* ── Quick prompts ─────────────────────────────────────────────── */}
      {chatMessages.length === 0 && intelligenceReady && (
        <div
          style={{
            padding: "10px 12px",
            flexShrink: 0,
            borderBottom: `1px solid ${C.border}`,
          }}
        >
          <div
            style={{
              fontSize: 10,
              color: C.textMuted,
              fontWeight: 600,
              textTransform: "uppercase",
              letterSpacing: ".08em",
              marginBottom: 6,
            }}
          >
            Quick Prompts
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
            {QUICK_PROMPTS.slice(0, 6).map((p, i) => (
              <button
                key={i}
                onClick={() => sendChat(p)}
                style={{
                  background: C.surface,
                  border: `1px solid ${C.border}`,
                  borderRadius: 12,
                  padding: "4px 10px",
                  color: C.textSub,
                  fontSize: 11,
                  cursor: "pointer",
                  ...SANS,
                }}
              >
                {p}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ── Chat messages ─────────────────────────────────────────────── */}
      <div
        style={{
          flex: 1,
          overflowY: "auto",
          display: "flex",
          flexDirection: "column",
          gap: 10,
          padding: "10px 12px",
        }}
      >
        {chatMessages.length === 0 && !intelligenceReady && (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              height: "100%",
              gap: 10,
              opacity: 0.4,
              textAlign: "center",
            }}
          >
            <Bot size={32} style={{ color: "#7C3AED" }} />
            <div style={{ fontSize: 13, color: C.text, fontWeight: 600 }}>
              Upload files to start
            </div>
            <div style={{ fontSize: 12, color: C.textMuted }}>
              Drop .tf files in Setup to enable AI analysis
            </div>
          </div>
        )}

        {chatMessages.map((msg, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              flexDirection: msg.role === "user" ? "row-reverse" : "row",
              gap: 7,
              alignItems: "flex-start",
            }}
          >
            <div
              style={{
                width: 26,
                height: 26,
                borderRadius: "50%",
                flexShrink: 0,
                background: msg.role === "user" ? C.accent : "#7C3AED",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {msg.role === "user"
                ? <Users size={12} style={{ color: "#fff" }} />
                : <Bot size={12} style={{ color: "#fff" }} />}
            </div>

            <div
              style={{
                maxWidth: "80%",
                background: msg.role === "user" ? `${C.accent}15` : C.surface,
                border: `1px solid ${msg.role === "user" ? C.accent + "33" : C.border}`,
                borderRadius: 10,
                padding: "8px 12px",
              }}
            >
              <div
                style={{
                  fontSize: 12,
                  color: C.text,
                  lineHeight: 1.65,
                  whiteSpace: msg.role === "assistant" ? undefined : "pre-wrap",
                }}
              >
                {msg.role === "assistant" ? renderMarkdown(msg.content) : msg.content}
                {msg.streaming && (
                  <span
                    style={{
                      display: "inline-block",
                      width: 7,
                      height: 13,
                      background: C.accent,
                      marginLeft: 2,
                      animation: "pulse 1s ease-in-out infinite",
                      verticalAlign: "text-bottom",
                      borderRadius: 2,
                    }}
                  />
                )}
              </div>

              {/* Source chips */}
              {msg.role === "assistant" && msg.sources?.length > 0 && !msg.streaming && (
                <div
                  style={{
                    display: "flex",
                    flexWrap: "wrap",
                    gap: 4,
                    marginTop: 6,
                    paddingTop: 6,
                    borderTop: `1px solid ${C.border}`,
                  }}
                >
                  {msg.sources.map((s, si) => (
                    <span
                      key={si}
                      title={s.file}
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: 3,
                        background: s.type === "dense" ? "#7C3AED12" : C.bg,
                        border: `1px solid ${s.type === "dense" ? "#7C3AED33" : C.border}`,
                        borderRadius: 9,
                        padding: "2px 7px",
                        fontSize: 10,
                        color: C.textSub,
                      }}
                    >
                      <FileText size={8} style={{ flexShrink: 0, opacity: 0.7 }} />
                      <span
                        style={{
                          maxWidth: 100,
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {s.file.split("/").pop().split("\\").pop()}
                      </span>
                      {s.cat && <span style={{ opacity: 0.6 }}>· {s.cat}</span>}
                    </span>
                  ))}
                </div>
              )}

              {/* Retrieval stats */}
              {msg.role === "assistant" && msg.retrieval && !msg.streaming && (
                <div
                  style={{
                    display: "flex",
                    gap: 6,
                    flexWrap: "wrap",
                    marginTop: 3,
                    fontSize: 9,
                    color: C.textMuted,
                  }}
                >
                  <span>{msg.retrieval.count} chunks</span>
                  {msg.retrieval.bm25 > 0 && <span>BM25: {msg.retrieval.bm25}</span>}
                  {msg.retrieval.dense > 0 && <span>dense: {msg.retrieval.dense}</span>}
                  <span>avg: {msg.retrieval.avgScore}%</span>
                </div>
              )}

              {/* Copy button */}
              {msg.role === "assistant" && !msg.streaming && (
                <button
                  onClick={() => navigator.clipboard.writeText(msg.content).catch(() => {})}
                  title="Copy response"
                  style={{
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    color: C.textMuted,
                    fontSize: 10,
                    padding: "2px 4px",
                    marginTop: 3,
                    opacity: 0.7,
                    display: "flex",
                    alignItems: "center",
                    gap: 3,
                  }}
                >
                  ⎘ Copy
                </button>
              )}
            </div>
          </div>
        ))}
        <div ref={chatBottomRef} />
      </div>

      {/* ── Input area ───────────────────────────────────────────────── */}
      <div
        style={{
          padding: "10px 12px",
          borderTop: `1px solid ${C.border}`,
          flexShrink: 0,
          display: "flex",
          gap: 7,
        }}
      >
        <input
          value={chatInput}
          onChange={(e) => setChatInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              sendChat(chatInput);
            }
          }}
          placeholder={
            !intelligenceReady
              ? "Upload files to enable chat…"
              : chatGenerating
              ? "Generating…"
              : "Ask about your architecture…"
          }
          disabled={chatGenerating || !intelligenceReady}
          style={{
            flex: 1,
            background: C.surface,
            border: `1px solid ${chatGenerating ? C.border : "#7C3AED44"}`,
            borderRadius: 8,
            padding: "9px 12px",
            color: C.text,
            fontSize: 12,
            outline: "none",
            ...SANS,
            opacity: chatGenerating || !intelligenceReady ? 0.6 : 1,
          }}
        />
        <button
          onClick={() => sendChat(chatInput)}
          disabled={chatGenerating || !chatInput.trim() || !intelligenceReady}
          style={{
            background: "linear-gradient(135deg,#7C3AED,#6D28D9)",
            border: "none",
            borderRadius: 8,
            padding: "9px 14px",
            color: "#fff",
            fontSize: 12,
            cursor: "pointer",
            fontWeight: 600,
            ...SANS,
            opacity: chatGenerating || !chatInput.trim() || !intelligenceReady ? 0.5 : 1,
            display: "flex",
            alignItems: "center",
            gap: 5,
            flexShrink: 0,
          }}
        >
          {chatGenerating
            ? <Loader2 size={13} style={{ animation: "spin 1s linear infinite" }} />
            : <Send size={13} />}
        </button>
      </div>
    </div>
  );
}
