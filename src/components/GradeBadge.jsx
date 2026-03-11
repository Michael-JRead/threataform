// src/components/GradeBadge.jsx
// Reusable security posture grade badge (A / B / C / D / F).
// Color is supplemental — the letter is always the primary signal.

import React from "react";

const DEFAULT_COLORS = {
  A: "#4CAF50",
  B: "#8BC34A",
  C: "#FFA726",
  D: "#FF7043",
  F: "#EF5350",
};

const SIZE_STYLES = {
  sm: { fontSize: 11, width: 22, height: 22, borderRadius: 5, fontWeight: 700 },
  md: { fontSize: 13, width: 28, height: 28, borderRadius: 6, fontWeight: 700 },
  lg: { fontSize: 18, width: 40, height: 40, borderRadius: 8, fontWeight: 800 },
};

/**
 * @param {{
 *   grade: string,          // 'A'|'B'|'C'|'D'|'F'|'?'
 *   color?: string,         // override the default grade color
 *   size?: 'sm'|'md'|'lg',
 *   style?: React.CSSProperties,
 * }} props
 */
export function GradeBadge({ grade = "?", color, size = "md", style }) {
  const s = SIZE_STYLES[size] || SIZE_STYLES.md;
  const letterKey = (grade || "?").toUpperCase().trim()[0] || "?";
  const resolvedColor = color || DEFAULT_COLORS[letterKey] || "#9090A8";

  return (
    <span
      aria-label={`Grade ${letterKey}`}
      title={`Security posture grade: ${letterKey}`}
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        width: s.width,
        height: s.height,
        borderRadius: s.borderRadius,
        fontSize: s.fontSize,
        fontWeight: s.fontWeight,
        fontFamily: "'Inter','DM Sans','system-ui',sans-serif",
        background: resolvedColor + "22",
        border: `1.5px solid ${resolvedColor}55`,
        color: resolvedColor,
        letterSpacing: 0,
        flexShrink: 0,
        userSelect: "none",
        ...style,
      }}
    >
      {letterKey}
    </span>
  );
}
