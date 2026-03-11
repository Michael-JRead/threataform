// src/features/workspace/WorkspaceShell.jsx
// Persistent split-pane workspace layout.
// Renders: sticky header + NavRail (48px left) + SplitPane (center | right AI panel)
//
// Usage:
//   <WorkspaceShell
//     navSection="setup"
//     setNavSection={setNavSection}
//     rightPanel={<AIChatPanel .../>}
//     rightPanelOpen={rightPanelOpen}
//     setRightPanelOpen={setRightPanelOpen}
//     rebuildActive={false}
//     rebuildStatusText=""
//     currentModel={model}
//     grade="A"
//     gradeColor="#4CAF50"
//     onHome={() => setAppMode("landing")}
//   >
//     {/* Center pane content — changes per navSection */}
//     <MyPanel />
//   </WorkspaceShell>

import React, { useEffect, useCallback } from "react";
import { NavRail } from "../../components/NavRail.jsx";
import { SplitPane } from "../../components/SplitPane.jsx";
import { RebuildBanner } from "../../components/RebuildBanner.jsx";
import { GradeBadge } from "../../components/GradeBadge.jsx";
import { C, SANS } from "../../constants/styles.js";

// ── Icons (inline SVG wrappers to avoid adding new icon imports) ──────────────
// We reuse the existing icon set from the app — WorkspaceShell accepts icon nodes
// as part of NAV_SECTIONS defined at the call site. Fallback text icons here.

/** All 6 nav sections */
export const NAV_SECTION_IDS = ["overview", "setup", "diagram", "threats", "intelligence", "settings"];

const HEADER_H = 48;

/**
 * @param {{
 *   navSection: string,
 *   setNavSection: (id: string) => void,
 *   navItems: Array<{id:string, icon:React.ReactNode, label:string}>,
 *   children: React.ReactNode,
 *   rightPanel?: React.ReactNode,
 *   rightPanelOpen?: boolean,
 *   setRightPanelOpen?: (v: boolean) => void,
 *   rightPanelWidth?: number,
 *   rebuildActive?: boolean,
 *   rebuildStatusText?: string,
 *   currentModel?: { id: string, name: string },
 *   grade?: string,
 *   gradeColor?: string,
 *   onHome: () => void,
 *   headerRight?: React.ReactNode,   // e.g. export buttons
 * }} props
 */
export function WorkspaceShell({
  navSection,
  setNavSection,
  navItems = [],
  children,
  rightPanel,
  rightPanelOpen = false,
  setRightPanelOpen,
  rightPanelWidth = 320,
  rebuildActive = false,
  rebuildStatusText = "Processing…",
  currentModel,
  grade,
  gradeColor,
  onHome,
  headerRight,
}) {
  // ── ⌘K keyboard shortcut toggles right panel ─────────────────────────────
  const handleKeyDown = useCallback(
    (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setRightPanelOpen?.(!rightPanelOpen);
      }
    },
    [rightPanelOpen, setRightPanelOpen]
  );

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  return (
    <div
      style={{
        ...SANS,
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        overflow: "hidden",
        background: C.bg,
        color: C.text,
      }}
    >
      {/* ── HEADER (48px) ─────────────────────────────────────────────────── */}
      <div
        style={{
          height: HEADER_H,
          minHeight: HEADER_H,
          background: C.surface,
          borderBottom: `1px solid ${C.border}`,
          display: "flex",
          alignItems: "center",
          padding: "0 12px 0 8px",
          gap: 10,
          zIndex: 200,
          flexShrink: 0,
        }}
      >
        {/* Home button */}
        <button
          onClick={onHome}
          title="All threat models"
          aria-label="Go to all threat models"
          style={{
            background: "transparent",
            border: `1px solid ${C.border}`,
            borderRadius: 6,
            padding: "4px 10px",
            color: C.textMuted,
            cursor: "pointer",
            fontSize: 11,
            display: "flex",
            alignItems: "center",
            gap: 4,
            flexShrink: 0,
          }}
        >
          ‹ Home
        </button>

        {/* Brand */}
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
          <div
            style={{
              width: 26,
              height: 26,
              borderRadius: 6,
              background: "linear-gradient(135deg,#FF6B35,#FF9900)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              boxShadow: "0 2px 6px #FF990030",
              flexShrink: 0,
            }}
          >
            <span style={{ color: "#fff", fontSize: 13, fontWeight: 800, lineHeight: 1 }}>T</span>
          </div>
          <span style={{ fontSize: 13, fontWeight: 700, color: C.text, letterSpacing: "-.01em" }}>
            Threataform
          </span>
        </div>

        {/* Model name + grade */}
        {currentModel && (
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              padding: "3px 10px",
              borderRadius: 6,
              background: C.surface2,
              border: `1px solid ${C.border}`,
              maxWidth: 240,
              flexShrink: 1,
              minWidth: 0,
            }}
          >
            {grade && <GradeBadge grade={grade} color={gradeColor} size="sm" />}
            <span
              style={{
                fontSize: 12,
                fontWeight: 600,
                color: C.text,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {currentModel.name}
            </span>
          </div>
        )}

        {/* Spacer */}
        <div style={{ flex: 1 }} />

        {/* Right header content (export buttons etc.) */}
        {headerRight}

        {/* AI Chat toggle button */}
        {rightPanel && (
          <button
            onClick={() => setRightPanelOpen?.(!rightPanelOpen)}
            title={rightPanelOpen ? "Close AI assistant (⌘K)" : "Open AI assistant (⌘K)"}
            aria-label={rightPanelOpen ? "Close AI assistant" : "Open AI assistant"}
            aria-pressed={rightPanelOpen}
            style={{
              background: rightPanelOpen ? `${C.accent}18` : "transparent",
              border: `1px solid ${rightPanelOpen ? C.accent + "55" : C.border}`,
              borderRadius: 6,
              padding: "5px 12px",
              color: rightPanelOpen ? C.accent : C.textMuted,
              cursor: "pointer",
              fontSize: 12,
              fontWeight: 600,
              display: "flex",
              alignItems: "center",
              gap: 6,
              flexShrink: 0,
              transition: "all .15s",
            }}
          >
            <span style={{ fontSize: 14 }}>⌘K</span>
            <span>AI</span>
          </button>
        )}
      </div>

      {/* ── REBUILD BANNER ────────────────────────────────────────────────── */}
      <RebuildBanner active={rebuildActive} text={rebuildStatusText} />

      {/* ── BODY: NavRail + SplitPane ─────────────────────────────────────── */}
      <div
        style={{
          flex: 1,
          display: "flex",
          minHeight: 0,
          overflow: "hidden",
        }}
      >
        {/* Nav rail */}
        <NavRail items={navItems} active={navSection} onChange={setNavSection} />

        {/* Main content area */}
        <SplitPane
          center={
            <div
              style={{
                flex: 1,
                display: "flex",
                flexDirection: "column",
                overflow: "hidden",
                minHeight: 0,
              }}
            >
              {children}
            </div>
          }
          right={rightPanel}
          rightWidth={rightPanelWidth}
          rightOpen={rightPanelOpen}
        />
      </div>
    </div>
  );
}
