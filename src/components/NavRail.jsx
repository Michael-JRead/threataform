// src/components/NavRail.jsx
// 48px-wide vertical icon navigation rail for the Workspace shell.
// Each item shows its icon; tooltip text is provided via title attribute.

import React from "react";
import { C } from "../constants/styles.js";

const RAIL_W = 48;

/**
 * @param {{ items: Array<{id:string, icon:React.ReactNode, label:string, title?:string}>,
 *           active: string,
 *           onChange: (id:string)=>void }} props
 *
 * Each item may include an optional `title` field for a more descriptive tooltip.
 * If omitted, the `label` is used as the tooltip text.
 */
export function NavRail({ items = [], active, onChange }) {
  return (
    <div
      style={{
        width: RAIL_W,
        minWidth: RAIL_W,
        height: "100%",
        background: C.surface,
        borderRight: `1px solid ${C.border}`,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        paddingTop: 8,
        paddingBottom: 8,
        gap: 2,
        flexShrink: 0,
      }}
    >
      {items.map((item) => {
        const isActive = item.id === active;
        const tooltip = item.title || item.label;
        return (
          <button
            key={item.id}
            title={tooltip}
            aria-label={item.label}
            aria-current={isActive ? "page" : undefined}
            onClick={() => onChange(item.id)}
            style={{
              width: 40,
              height: 40,
              borderRadius: 8,
              border: "none",
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: isActive ? C.surface2 : "transparent",
              color: isActive ? C.accent : C.textSub,
              boxShadow: isActive
                ? `inset 3px 0 0 ${C.accent}`
                : undefined,
              transition: "background 0.15s, color 0.15s",
              padding: 0,
              marginLeft: isActive ? -3 : 0,    // shift to show left border without layout shift
              flexShrink: 0,
            }}
            onMouseEnter={(e) => {
              if (!isActive) {
                e.currentTarget.style.background = C.surface2;
                e.currentTarget.style.color = C.text;
              }
            }}
            onMouseLeave={(e) => {
              if (!isActive) {
                e.currentTarget.style.background = "transparent";
                e.currentTarget.style.color = C.textSub;
              }
            }}
          >
            {item.icon}
          </button>
        );
      })}
    </div>
  );
}
