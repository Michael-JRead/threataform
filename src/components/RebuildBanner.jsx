// src/components/RebuildBanner.jsx
// Thin animated status stripe shown during index/analysis rebuilds.
// Collapses to zero height when inactive.

import React from "react";
import { C } from "../constants/styles.js";

/**
 * @param {{ active: boolean, text?: string }} props
 */
export function RebuildBanner({ active, text = "Processing…" }) {
  return (
    <div
      aria-live="polite"
      aria-atomic="true"
      style={{
        height: active ? 28 : 0,
        overflow: "hidden",
        transition: "height 0.2s ease",
        background: C.surface,
        borderBottom: active ? `1px solid ${C.border}` : "none",
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: active ? "0 16px" : "0",
        flexShrink: 0,
      }}
    >
      {active && (
        <>
          {/* Spinner via CSS keyframe */}
          <style>{`@keyframes _rb_spin { to { transform: rotate(360deg); } }`}</style>
          <div
            style={{
              width: 10,
              height: 10,
              border: `2px solid ${C.border2}`,
              borderTop: `2px solid ${C.accent}`,
              borderRadius: "50%",
              animation: "_rb_spin 0.9s linear infinite",
              flexShrink: 0,
            }}
          />
          <span
            style={{
              fontSize: 11,
              color: C.textMuted,
              fontFamily: "'Inter','DM Sans','system-ui',sans-serif",
              whiteSpace: "nowrap",
            }}
          >
            {text}
          </span>
        </>
      )}
    </div>
  );
}
