/**
 * src/lib/iac/PolicyEvaluator.js
 * Deterministic IAM policy evaluation following the AWS canonical evaluation order.
 * Handles explicit Deny, SCP intersection, and permission boundary constraints.
 *
 * Limitations (Phase 2 scope):
 *  - No condition key evaluation (→ UNKNOWN if conditions present)
 *  - Wildcard action matching: "iam:*" matches any "iam:" action
 *  - Resource-level matching: "*" matches all; exact string match only otherwise
 *
 * Usage:
 *   import { evaluateRequest, computeSCPCeilings } from './PolicyEvaluator.js';
 *   const { decision, evidence } = evaluateRequest(principal, action, resource, layers);
 *   const ceilings = computeSCPCeilings(resources, orgTree);
 */

// ── Decision codes ────────────────────────────────────────────────────────────
export const DECISION = {
  ALLOW:            'ALLOW',
  DENY_EXPLICIT:    'DENY_EXPLICIT',
  DENY_IMPLICIT:    'DENY_IMPLICIT',
  DENY_BY_SCP:      'DENY_BY_SCP',
  DENY_BY_BOUNDARY: 'DENY_BY_BOUNDARY',
  UNKNOWN:          'UNKNOWN',
};

// ── Action wildcard matching ──────────────────────────────────────────────────
/**
 * Test whether a policy action pattern matches a specific action.
 * Supports:  "*"  →  matches everything
 *            "iam:*"  →  matches any iam: action
 *            "iam:CreateRole"  →  exact match
 * @param {string} pattern  - Pattern from policy (may contain "*")
 * @param {string} action   - Specific action to test
 * @returns {boolean}
 */
function actionMatches(pattern, action) {
  if (pattern === '*') return true;
  if (pattern === action) return true;
  if (pattern.endsWith(':*')) {
    const service = pattern.slice(0, -2);  // e.g. "iam"
    return action.startsWith(service + ':');
  }
  // Simple glob: replace * with .* for regex
  try {
    const regex = new RegExp('^' + pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$', 'i');
    return regex.test(action);
  } catch {
    return false;
  }
}

/**
 * Test whether a resource pattern matches a specific resource ARN.
 * @param {string} pattern
 * @param {string} resource
 * @returns {boolean}
 */
function resourceMatches(pattern, resource) {
  if (pattern === '*') return true;
  if (pattern === resource) return true;
  try {
    const regex = new RegExp('^' + pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
    return regex.test(resource);
  } catch {
    return false;
  }
}

/**
 * Check whether a single policy statement applies to a given action + resource.
 * Returns: 'ALLOW' | 'DENY' | 'NO_MATCH' | 'UNKNOWN' (conditions present)
 * @param {object} statement
 * @param {string} action
 * @param {string} resource
 * @returns {string}
 */
function evaluateStatement(statement, action, resource) {
  if (!statement || typeof statement !== 'object') return 'NO_MATCH';

  // Conditions → UNKNOWN
  if (statement.Condition && Object.keys(statement.Condition).length > 0) {
    return 'UNKNOWN';
  }

  const effect = statement.Effect;
  if (effect !== 'Allow' && effect !== 'Deny') return 'NO_MATCH';

  // Action check
  const actions = Array.isArray(statement.Action)
    ? statement.Action
    : (statement.Action ? [statement.Action] : []);
  if (!actions.some(a => actionMatches(a, action))) return 'NO_MATCH';

  // Resource check
  const resources = Array.isArray(statement.Resource)
    ? statement.Resource
    : (statement.Resource ? [statement.Resource] : ['*']);
  if (!resources.some(r => resourceMatches(r, resource))) return 'NO_MATCH';

  return effect === 'Deny' ? 'DENY' : 'ALLOW';
}

/**
 * Evaluate a single IAM policy document against an action + resource.
 * @param {object|string} policyDoc
 * @param {string} action
 * @param {string} resource
 * @returns {{ result: 'ALLOW'|'DENY'|'NEUTRAL'|'UNKNOWN', statements: object[] }}
 */
function evaluatePolicy(policyDoc, action, resource) {
  let doc;
  try {
    doc = typeof policyDoc === 'string' ? JSON.parse(policyDoc) : policyDoc;
  } catch {
    return { result: 'UNKNOWN', statements: [] };
  }
  if (!doc || !doc.Statement) return { result: 'NEUTRAL', statements: [] };

  const stmts = Array.isArray(doc.Statement) ? doc.Statement : [doc.Statement];
  let hasAllow  = false;
  let hasDeny   = false;
  let hasUnknown = false;

  for (const stmt of stmts) {
    const r = evaluateStatement(stmt, action, resource);
    if (r === 'DENY')    { hasDeny = true; break; }
    if (r === 'ALLOW')   hasAllow = true;
    if (r === 'UNKNOWN') hasUnknown = true;
  }

  if (hasDeny)    return { result: 'DENY', statements: stmts };
  if (hasUnknown) return { result: 'UNKNOWN', statements: stmts };
  if (hasAllow)   return { result: 'ALLOW', statements: stmts };
  return { result: 'NEUTRAL', statements: stmts };
}

/**
 * Evaluate an IAM authorization request following AWS canonical evaluation order.
 *
 * Canonical order:
 *  1. Explicit Deny anywhere → DENY_EXPLICIT
 *  2. No identity Allow → DENY_IMPLICIT
 *  3. SCP doesn't allow → DENY_BY_SCP
 *  4. Boundary doesn't allow → DENY_BY_BOUNDARY
 *  5. All conditions met → ALLOW
 *  6. Any UNKNOWN (conditions) → UNKNOWN
 *
 * @param {string}   principal  - Principal ARN or ID (informational only)
 * @param {string}   action     - IAM action e.g. "s3:GetObject"
 * @param {string}   resource   - Resource ARN or "*"
 * @param {object}   layers
 * @param {object[]} layers.identityPolicies     - Identity-based policy documents
 * @param {object[]} layers.scpChain             - SCP policy documents (must all allow)
 * @param {object[]} layers.permissionBoundaries - Permission boundary policy documents
 * @param {object[]} [layers.resourcePolicies]   - Resource-based policy documents (not evaluated in Phase 2)
 * @returns {{ decision: string, evidence: string[] }}
 */
export function evaluateRequest(principal, action, resource, layers = {}) {
  const {
    identityPolicies     = [],
    scpChain             = [],
    permissionBoundaries = [],
  } = layers;

  const evidence = [];
  let hasUnknown = false;

  // ── Step 1: Check for explicit Deny in any policy layer ──────────────────
  const allPolicies = [...identityPolicies, ...scpChain, ...permissionBoundaries];
  for (const policy of allPolicies) {
    const { result } = evaluatePolicy(policy, action, resource);
    if (result === 'DENY') {
      evidence.push(`Explicit Deny found in policy`);
      return { decision: DECISION.DENY_EXPLICIT, evidence };
    }
    if (result === 'UNKNOWN') hasUnknown = true;
  }

  // ── Step 2: Check identity policies for Allow ────────────────────────────
  let identityAllow = false;
  for (const policy of identityPolicies) {
    const { result } = evaluatePolicy(policy, action, resource);
    if (result === 'ALLOW') { identityAllow = true; break; }
    if (result === 'UNKNOWN') hasUnknown = true;
  }
  if (!identityAllow && identityPolicies.length > 0) {
    evidence.push(`No identity policy allows ${action}`);
    if (hasUnknown) {
      evidence.push('Note: some policies have conditions that could not be evaluated');
      return { decision: DECISION.UNKNOWN, evidence };
    }
    return { decision: DECISION.DENY_IMPLICIT, evidence };
  }

  // ── Step 3: SCP chain must allow ─────────────────────────────────────────
  for (const scp of scpChain) {
    const { result } = evaluatePolicy(scp, action, resource);
    if (result === 'NEUTRAL' || result === 'DENY') {
      evidence.push(`SCP does not allow ${action}`);
      return { decision: DECISION.DENY_BY_SCP, evidence };
    }
    if (result === 'UNKNOWN') hasUnknown = true;
  }

  // ── Step 4: Permission boundaries must allow ─────────────────────────────
  for (const boundary of permissionBoundaries) {
    const { result } = evaluatePolicy(boundary, action, resource);
    if (result === 'NEUTRAL' || result === 'DENY') {
      evidence.push(`Permission boundary does not allow ${action}`);
      return { decision: DECISION.DENY_BY_BOUNDARY, evidence };
    }
    if (result === 'UNKNOWN') hasUnknown = true;
  }

  // ── Step 5: All checks passed ────────────────────────────────────────────
  if (hasUnknown) {
    evidence.push('Authorization likely but conditions present — could not fully evaluate');
    return { decision: DECISION.UNKNOWN, evidence };
  }
  evidence.push(`${action} is allowed by identity policy`);
  return { decision: DECISION.ALLOW, evidence };
}

// ── High-risk actions we track for SCP ceiling analysis ──────────────────────
const HIGH_RISK_ACTIONS = [
  'iam:CreateRole', 'iam:AttachRolePolicy', 'iam:PutRolePolicy',
  'iam:CreateUser', 'iam:AttachUserPolicy',
  'iam:CreatePolicy', 'iam:CreatePolicyVersion',
  's3:DeleteBucket', 's3:PutBucketAcl', 's3:PutBucketPolicy',
  'ec2:AuthorizeSecurityGroupIngress', 'ec2:CreateVpc',
  'cloudtrail:DeleteTrail', 'cloudtrail:StopLogging', 'cloudtrail:UpdateTrail',
  'kms:DisableKey', 'kms:ScheduleKeyDeletion',
  'organizations:LeaveOrganization', 'organizations:DeleteOrganization',
  'sts:AssumeRole',
  'lambda:InvokeFunction',
  'rds:DeleteDBInstance', 'rds:ModifyDBInstance',
  'ec2:TerminateInstances',
  'secretsmanager:DeleteSecret', 'secretsmanager:GetSecretValue',
];

/**
 * Compute SCP ceilings — which high-risk actions are explicitly denied
 * by SCPs for each account in the org tree.
 *
 * @param {object[]} resources  - Combined HCL + CFN resources
 * @param {object}   orgTree    - Output of buildOrgTree()
 * @returns {Object.<string, string[]>}  accountId → array of denied action patterns
 */
export function computeSCPCeilings(resources, orgTree) {
  const ceilings = {};
  if (!orgTree) return ceilings;

  const { accounts = [], scpPolicies = [], ous = [] } = orgTree;

  // Build a map of policy id → content
  const policyContent = new Map();
  for (const p of scpPolicies) {
    if (p.content) policyContent.set(p.id, p.content);
  }

  // Also collect SCP content from inline resources
  for (const r of resources) {
    if (r.type === 'aws_organizations_policy' || r.type === 'AWS::Organizations::Policy') {
      const props = r.cfnProps || {};
      const body  = r.body || '';
      let content = null;
      if (props.Content && props.Content !== '__INTRINSIC__') {
        try { content = typeof props.Content === 'string' ? JSON.parse(props.Content) : props.Content; } catch {}
      } else {
        const m = body.match(/content\s*=\s*jsonencode\((.+?)\)\s*$/ms)
          || body.match(/content\s*=\s*"([^"]+)"/);
        if (m) { try { content = JSON.parse(m[1]); } catch { content = m[1]; } }
      }
      if (content) policyContent.set(r.id || r.logicalId, content);
    }
  }

  // Build OU → SCP list map for inheritance
  const ouScps = new Map();
  for (const ou of ous) {
    ouScps.set(ou.id, ou.scps || []);
  }

  // For each account, collect all applicable SCPs (from root + parent OU chain + direct)
  for (const acc of accounts) {
    const applicableScpIds = [
      ...(orgTree.root?.scps || []),
      ...collectOUScps(acc.parentOU, ous),
      ...(acc.scps || []),
    ];

    const deniedActions = [];
    const unknownActions = [];

    for (const scpId of applicableScpIds) {
      const content = policyContent.get(scpId);
      if (!content) continue;

      const doc = typeof content === 'string' ? (() => { try { return JSON.parse(content); } catch { return null; } })() : content;
      if (!doc?.Statement) continue;

      const stmts = Array.isArray(doc.Statement) ? doc.Statement : [doc.Statement];
      for (const stmt of stmts) {
        if (stmt.Effect === 'Deny') {
          const actions = Array.isArray(stmt.Action) ? stmt.Action : (stmt.Action ? [stmt.Action] : []);
          for (const a of actions) {
            if (a !== '__INTRINSIC__' && !deniedActions.includes(a)) deniedActions.push(a);
            if (a === '__INTRINSIC__') unknownActions.push('__INTRINSIC__');
          }
        }
      }
    }

    if (deniedActions.length > 0 || unknownActions.length > 0) {
      ceilings[acc.id] = [
        ...deniedActions,
        ...(unknownActions.length ? ['UNKNOWN'] : []),
      ];
    }
  }

  // ── Fallback: when attachments couldn't be resolved (all intrinsic refs),
  //    collect Deny actions from ALL SCP policy documents and store under
  //    the special key '__global__' so the misconfig badge still works.
  if (Object.keys(ceilings).length === 0 && policyContent.size > 0) {
    const globalDenied = [];
    let hasUnknown = false;
    for (const [, content] of policyContent) {
      const doc = typeof content === 'string'
        ? (() => { try { return JSON.parse(content); } catch { return null; } })()
        : content;
      if (!doc?.Statement) continue;
      const stmts = Array.isArray(doc.Statement) ? doc.Statement : [doc.Statement];
      for (const stmt of stmts) {
        if (stmt.Effect === 'Deny') {
          // Skip NotAction patterns — too complex for static analysis
          if (stmt.NotAction) continue;
          const hasCondition = stmt.Condition && Object.keys(stmt.Condition).length > 0;
          const actions = Array.isArray(stmt.Action) ? stmt.Action
            : (stmt.Action ? [stmt.Action] : []);
          for (const a of actions) {
            if (a === '__INTRINSIC__') { hasUnknown = true; continue; }
            // Wildcard '*' with a condition is too uncertain — mark unknown, skip
            if (a === '*' && hasCondition) { hasUnknown = true; continue; }
            // Specific actions from conditioned Deny still represent real coverage
            // (they block most principals); mark UNKNOWN to indicate partial eval
            if (hasCondition) hasUnknown = true;
            if (!globalDenied.includes(a)) globalDenied.push(a);
          }
        }
      }
    }
    if (globalDenied.length > 0 || hasUnknown) {
      ceilings['__global__'] = [
        ...globalDenied,
        ...(hasUnknown ? ['UNKNOWN'] : []),
      ];
    }
  }

  return ceilings;
}

/**
 * Walk up the OU tree and collect all SCP IDs from ancestor OUs.
 * @param {string}   ouId
 * @param {object[]} ous
 * @returns {string[]}
 */
function collectOUScps(ouId, ous) {
  const result = [];
  const visited = new Set();
  let current = ouId;
  while (current && current !== 'ROOT' && !visited.has(current)) {
    visited.add(current);
    const ou = ous.find(o => o.id === current);
    if (!ou) break;
    result.push(...(ou.scps || []));
    current = ou.parentId;
  }
  return result;
}

/**
 * Check if a specific high-risk action is denied by any SCP for a given account.
 * @param {string}  accountId
 * @param {string}  action
 * @param {Object}  scpCeilings  Output of computeSCPCeilings
 * @returns {'DENIED'|'ALLOWED'|'UNKNOWN'}
 */
export function isActionDeniedBySCP(accountId, action, scpCeilings) {
  const denied = scpCeilings[accountId];
  if (!denied) return 'ALLOWED';
  if (denied.includes('UNKNOWN')) return 'UNKNOWN';
  for (const pattern of denied) {
    if (actionMatches(pattern, action)) return 'DENIED';
  }
  return 'ALLOWED';
}
