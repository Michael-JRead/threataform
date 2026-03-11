// src/components/SplitPane.jsx
// Horizontal split-pane layout: center pane (flex:1) + optional collapsible right panel.

import React from "react";
import { C } from "../constants/styles.js";

/**
 * @param {{
 *   center: React.ReactNode,
 *   right: React.ReactNode,
 *   rightWidth?: number,
 *   rightOpen?: boolean,
 *   style?: React.CSSProperties,
 * }} props
 */
export function SplitPane({ center, right, rightWidth = 320, rightOpen = true, style }) {
  return (
    <div
      style={{
        display: "flex",
        flex: 1,
        minHeight: 0,
        overflow: "hidden",
        ...style,
      }}
    >
      {/* Center pane — fills remaining width */}
      <div
        style={{
          flex: 1,
          minWidth: 0,
          overflow: "hidden",
          display: "flex",
          flexDirection: "column",
        }}
      >
        {center}
      </div>

      {/* Right panel — collapsible */}
      {right && (
        <div
          style={{
            width: rightOpen ? rightWidth : 0,
            minWidth: 0,
            overflow: "hidden",
            flexShrink: 0,
            transition: "width 0.22s cubic-bezier(0.4, 0, 0.2, 1)",
            borderLeft: rightOpen ? `1px solid ${C.border}` : "none",
            background: C.surface,
            display: "flex",
            flexDirection: "column",
          }}
        >
          {/* Inner wrapper prevents content from shifting while animating */}
          <div
            style={{
              width: rightWidth,
              height: "100%",
              display: "flex",
              flexDirection: "column",
              overflow: "hidden",
            }}
          >
            {right}
          </div>
        </div>
      )}
    </div>
  );
}
