// src/components/ChipInput.jsx
// Reusable chip/tag input component.
// Comma or Enter commits the current value as one or more chips.
// On blur, any uncommitted text is also committed.

import React, { useState } from "react";
import { C } from "../constants/styles.js";

/**
 * @param {{
 *   value: string[],
 *   onAdd: (names: string[]) => void,
 *   onRemove: (index: number) => void,
 *   placeholder?: string,
 *   chipColor?: string,
 *   chipBg?: string,
 *   chipBorder?: string,
 *   style?: React.CSSProperties,
 * }} props
 */
export function ChipInput({
  value = [],
  onAdd,
  onRemove,
  placeholder = "Type and press Enter…",
  chipColor = "#9C6FFF",
  chipBg = "#7C4DFF20",
  chipBorder = "#7C4DFF44",
  style,
}) {
  const [inputVal, setInputVal] = useState("");

  const commit = (raw) => {
    const names = raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (names.length) {
      onAdd(names);
      setInputVal("");
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, ...style }}>
      {/* Chips */}
      {value.length > 0 && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
          {value.map((name, i) => (
            <span
              key={i}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 4,
                fontSize: 11,
                padding: "3px 8px",
                borderRadius: 12,
                background: chipBg,
                border: `1px solid ${chipBorder}`,
                color: chipColor,
                fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',monospace",
              }}
            >
              {name}
              <button
                aria-label={`Remove ${name}`}
                onClick={() => onRemove(i)}
                style={{
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                  color: chipColor,
                  padding: 0,
                  lineHeight: 1,
                  fontSize: 14,
                  opacity: 0.7,
                }}
                onMouseEnter={(e) => (e.currentTarget.style.opacity = "1")}
                onMouseLeave={(e) => (e.currentTarget.style.opacity = "0.7")}
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}

      {/* Input */}
      <input
        type="text"
        placeholder={placeholder}
        value={inputVal}
        onChange={(e) => setInputVal(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === ",") {
            e.preventDefault();
            commit(inputVal);
          } else if (e.key === "Backspace" && !inputVal && value.length > 0) {
            onRemove(value.length - 1);
          }
        }}
        onBlur={() => {
          if (inputVal.trim()) commit(inputVal);
        }}
        style={{
          width: "100%",
          boxSizing: "border-box",
          padding: "7px 10px",
          fontSize: 12,
          borderRadius: 6,
          border: `1px solid ${C.border2}`,
          background: C.bg,
          color: C.text,
          outline: "none",
          fontFamily: "'Inter','DM Sans','system-ui',sans-serif",
        }}
        onFocus={(e) => (e.target.style.borderColor = C.accent)}
        onBlurCapture={(e) => (e.target.style.borderColor = C.border2)}
      />
    </div>
  );
}
