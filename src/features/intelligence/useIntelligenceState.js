// src/features/intelligence/useIntelligenceState.js
// Consolidates all IntelligencePanel state into a single useReducer.
// Replaces 46 individual useState declarations — 14 assistant-related states were removed
// (chat, LoRA, MCP) because they now live in AIChatPanel and SettingsPanel respectively.
//
// Usage in IntelligencePanel:
//   const { state, set } = useIntelligenceState();
//   // Read:  state.postureNarrative
//   // Write: set('postureNarrative')(newValue)
//   // Write: set('postureNarrative')('') to clear

import { useReducer, useCallback } from 'react';

// ── Initial state ────────────────────────────────────────────────────────────

const INITIAL_STATE = {
  // ── Tab routing ─────────────────────────────────────────────────────────
  iTab: 'posture-controls',   // default; 'assistant' removed (now in right pane)

  // ── Cross-tab navigation ─────────────────────────────────────────────────
  attackFilter:       null,
  resourceSearch:     '',
  resourceTypeFilter: '',
  resourcePage:       0,
  expandedControl:    null,
  expandedCwe:        null,
  expandedFinding:    null,

  // ── Query (hybrid search) ────────────────────────────────────────────────
  query:             '',
  results:           null,    // null = not searched yet
  queryLoading:      false,
  synthesisingQuery: false,
  synthesisText:     '',

  // ── Security Posture & Controls ──────────────────────────────────────────
  postureNarrative:   '',
  postureNarrLoading: false,
  gapAnalysis:        '',
  gapAnalysisLoading: false,
  remediationPlan:    '',
  remediationLoading: false,
  controlSearch:      '',

  // ── Scope Analysis ───────────────────────────────────────────────────────
  threatScenarios:        '',
  threatScenariosLoading: false,
  inferredScope:          '',
  inferredScopeLoading:   false,

  // ── Resource Intel ───────────────────────────────────────────────────────
  resourceSummaries: {},
  hybridHits:        {},

  // ── Threat Intelligence ──────────────────────────────────────────────────
  techPassages:      {},
  attackNarrative:   '',
  attackNarrLoading: false,

  // ── Cross-Doc ────────────────────────────────────────────────────────────
  contradictionNarrative: '',
  contraNarrLoading:      false,

  // ── Misconfigs ───────────────────────────────────────────────────────────
  findingGuidance: {},
};

// ── Reducer ──────────────────────────────────────────────────────────────────

function intelligenceReducer(state, action) {
  switch (action.type) {
    case 'SET':
      return { ...state, [action.key]: action.value };
    case 'PATCH':
      return { ...state, ...action.patch };
    case 'RESET':
      return INITIAL_STATE;
    default:
      return state;
  }
}

// ── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Returns `state` (all intelligence panel values) and `set` (a curried setter factory).
 *
 * `set(key)` returns a stable setter function `(value) => dispatch(SET key value)`.
 * This means you can use it as a drop-in replacement for useState setters:
 *
 *   const setPostureNarrative = set('postureNarrative');
 *   setPostureNarrative('Loading…');   // works exactly like the old useState setter
 *
 * Or inline in an onClick / callback:
 *   onChange={e => set('controlSearch')(e.target.value)}
 */
export function useIntelligenceState() {
  const [state, dispatch] = useReducer(intelligenceReducer, INITIAL_STATE);

  // Curried setter: set('key') returns (value) => dispatch(SET)
  // useCallback with empty deps — dispatch is stable so this never re-creates.
  const set = useCallback(
    (key) => (value) => dispatch({ type: 'SET', key, value }),
    [],
  );

  // Patch multiple keys at once
  const patch = useCallback(
    (patchObj) => dispatch({ type: 'PATCH', patch: patchObj }),
    [],
  );

  // Reset all state to INITIAL_STATE
  const reset = useCallback(() => dispatch({ type: 'RESET' }), []);

  return { state, set, patch, reset, dispatch };
}
