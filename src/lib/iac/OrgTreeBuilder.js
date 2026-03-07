/**
 * src/lib/iac/OrgTreeBuilder.js
 * Builds an AWS Organizations hierarchy from a mixed HCL + CFN resource array.
 * Works with resources from parseTFMultiFile (isCFN: false) and
 * extractCFNResources (isCFN: true).
 *
 * Usage:
 *   import { buildOrgTree } from './OrgTreeBuilder.js';
 *   const tree = buildOrgTree(parseResult.resources);
 */

// ── HCL resource type identifiers ────────────────────────────────────────────
const HCL_ORG          = 'aws_organizations_organization';
const HCL_OU           = 'aws_organizations_organizational_unit';
const HCL_ACCOUNT      = 'aws_organizations_account';
const HCL_POLICY       = 'aws_organizations_policy';
const HCL_ATTACHMENT   = 'aws_organizations_policy_attachment';

// ── CFN resource type identifiers ─────────────────────────────────────────────
const CFN_OU           = 'AWS::Organizations::OrganizationalUnit';
const CFN_ACCOUNT      = 'AWS::Organizations::Account';
const CFN_POLICY       = 'AWS::Organizations::Policy';
const CFN_ATTACHMENT   = 'AWS::Organizations::PolicyAttachment';

/**
 * Extract a string attribute from an HCL resource body (regex-based).
 * @param {string} body
 * @param {string} key
 * @returns {string|null}
 */
function hclAttr(body, key) {
  if (!body) return null;
  const m = body.match(new RegExp(`${key}\\s*=\\s*"([^"]+)"`));
  return m ? m[1] : null;
}

/**
 * Build the organization tree.
 * @param {object[]} resources  Combined HCL + CFN resources array
 * @returns {{
 *   root:        { id: string, name: string, scps: string[] } | null,
 *   ous:         Array<{ id, name, paveLayer, parentId, scps, accounts, children }>,
 *   accounts:    Array<{ id, name, paveLayer, parentOU, scps, permissionBoundaries }>,
 *   scpPolicies: Array<{ id, name, type, content, attachedTo }>,
 *   gaps:        string[],
 * }}
 */
export function buildOrgTree(resources) {
  const gaps = [];
  const root = { id: 'ROOT', name: 'Root', scps: [] };
  const ous = [];
  const accounts = [];
  const scpPolicies = [];

  // ── Index helpers ─────────────────────────────────────────────────────────
  const ouById   = new Map();   // id → ou
  const accById  = new Map();   // id → account
  const policyById = new Map(); // id → policy

  // ── Process HCL resources ─────────────────────────────────────────────────
  for (const r of resources) {
    if (r.isCFN) continue;
    const body = r.body || '';

    if (r.type === HCL_OU) {
      const ou = {
        id:         r.id || r.name,
        name:       r.name || hclAttr(body, 'name') || r.id,
        paveLayer:  r.paveLayer || null,
        parentId:   hclAttr(body, 'parent_id') || 'ROOT',
        scps:       [],
        accounts:   [],
        children:   [],
        source:     'hcl',
      };
      ous.push(ou);
      ouById.set(ou.id, ou);
    }

    if (r.type === HCL_ACCOUNT) {
      const acc = {
        id:                   r.id || r.name,
        name:                 r.name || hclAttr(body, 'name') || r.id,
        paveLayer:            r.paveLayer || null,
        parentOU:             hclAttr(body, 'parent_id') || 'ROOT',
        email:                hclAttr(body, 'email') || null,
        scps:                 [],
        permissionBoundaries: [],
        source:               'hcl',
      };
      accounts.push(acc);
      accById.set(acc.id, acc);
    }

    if (r.type === HCL_POLICY) {
      const policyType = hclAttr(body, 'type') || 'SERVICE_CONTROL_POLICY';
      let content = null;
      const contentMatch = body.match(/content\s*=\s*jsonencode\((.+?)\)\s*$/ms)
        || body.match(/content\s*=\s*"([^"]+)"/);
      if (contentMatch) {
        try { content = JSON.parse(contentMatch[1]); } catch { content = contentMatch[1]; }
      }
      const policy = {
        id:         r.id || r.name,
        name:       r.name || hclAttr(body, 'name') || r.id,
        type:       policyType,
        content,
        attachedTo: [],
        source:     'hcl',
      };
      scpPolicies.push(policy);
      policyById.set(policy.id, policy);
    }

    if (r.type === HCL_ATTACHMENT) {
      const policyId    = hclAttr(body, 'policy_id');
      const targetId    = hclAttr(body, 'target_id');
      if (policyId && targetId) {
        const policy = policyById.get(policyId);
        if (policy) policy.attachedTo.push(targetId);
        // Attach to OU or account
        const ou  = ouById.get(targetId);
        const acc = accById.get(targetId);
        if (ou)  ou.scps.push(policyId);
        if (acc) acc.scps.push(policyId);
        if (!ou && !acc && targetId !== 'ROOT') {
          gaps.push(`[OrgTreeBuilder] Policy ${policyId} attached to unknown target ${targetId} (may be intrinsic Ref)`);
        }
        if (targetId === 'ROOT') root.scps.push(policyId);
      }
    }
  }

  // ── Process CFN resources ─────────────────────────────────────────────────
  for (const r of resources) {
    if (!r.isCFN) continue;
    const props = r.cfnProps || {};

    if (r.type === CFN_OU) {
      const ouId = props.Id && props.Id !== '__INTRINSIC__' ? props.Id : r.logicalId;
      const ou = {
        id:         ouId,
        name:       props.Name && props.Name !== '__INTRINSIC__' ? props.Name : r.name,
        paveLayer:  r.paveLayer || null,
        parentId:   (props.ParentId && props.ParentId !== '__INTRINSIC__') ? props.ParentId : 'ROOT',
        scps:       [],
        accounts:   [],
        children:   [],
        source:     'cfn',
        logicalId:  r.logicalId,
      };
      // Avoid duplicates
      if (!ouById.has(ou.id)) {
        ous.push(ou);
        ouById.set(ou.id, ou);
      }
      if (props.ParentId === '__INTRINSIC__') {
        gaps.push(`[OrgTreeBuilder] OU "${ou.name}" parent is an intrinsic Ref — cannot resolve hierarchy`);
      }
    }

    if (r.type === CFN_ACCOUNT) {
      const accId = props.AccountId && props.AccountId !== '__INTRINSIC__' ? props.AccountId : r.logicalId;
      const acc = {
        id:                   accId,
        name:                 r.name,
        paveLayer:            r.paveLayer || null,
        parentOU:             (props.ParentId && props.ParentId !== '__INTRINSIC__') ? props.ParentId : 'ROOT',
        email:                (props.Email && props.Email !== '__INTRINSIC__') ? props.Email : null,
        scps:                 [],
        permissionBoundaries: [],
        source:               'cfn',
        logicalId:            r.logicalId,
      };
      if (!accById.has(acc.id)) {
        accounts.push(acc);
        accById.set(acc.id, acc);
      }
      if (props.AccountId === '__INTRINSIC__') {
        gaps.push(`[OrgTreeBuilder] Account "${acc.name}" ID is an intrinsic Ref — analysis gaps possible`);
      }
    }

    if (r.type === CFN_POLICY) {
      let content = null;
      if (props.Content && props.Content !== '__INTRINSIC__') {
        try {
          content = typeof props.Content === 'string' ? JSON.parse(props.Content) : props.Content;
        } catch { content = props.Content; }
      }
      const policy = {
        id:         r.logicalId,
        name:       (props.Name && props.Name !== '__INTRINSIC__') ? props.Name : r.name,
        type:       (props.Type && props.Type !== '__INTRINSIC__') ? props.Type : 'SERVICE_CONTROL_POLICY',
        content,
        attachedTo: [],
        source:     'cfn',
        logicalId:  r.logicalId,
      };
      if (!policyById.has(policy.id)) {
        scpPolicies.push(policy);
        policyById.set(policy.id, policy);
      }
    }

    if (r.type === CFN_ATTACHMENT) {
      const policyId  = props.PolicyId  !== '__INTRINSIC__' ? props.PolicyId  : null;
      const targetId  = props.TargetId  !== '__INTRINSIC__' ? props.TargetId  : null;
      if (policyId && targetId) {
        const policy = policyById.get(policyId);
        if (policy && !policy.attachedTo.includes(targetId)) policy.attachedTo.push(targetId);
        const ou  = ouById.get(targetId);
        const acc = accById.get(targetId);
        if (ou  && !ou.scps.includes(policyId))  ou.scps.push(policyId);
        if (acc && !acc.scps.includes(policyId)) acc.scps.push(policyId);
        if (targetId === 'ROOT' && !root.scps.includes(policyId)) root.scps.push(policyId);
      } else {
        gaps.push(`[OrgTreeBuilder] PolicyAttachment ${r.logicalId} has intrinsic PolicyId or TargetId — cannot wire SCP`);
      }
    }
  }

  // ── Build parent-child OU tree ────────────────────────────────────────────
  for (const ou of ous) {
    const parent = ouById.get(ou.parentId);
    if (parent) {
      parent.children.push(ou.id);
    }
    // Wire accounts to their OU
    for (const acc of accounts) {
      if (acc.parentOU === ou.id) {
        if (!ou.accounts.includes(acc.id)) ou.accounts.push(acc.id);
      }
    }
  }

  // ── Summary gaps ─────────────────────────────────────────────────────────
  const unknownParentAccounts = accounts.filter(a => a.parentOU !== 'ROOT' && !ouById.has(a.parentOU));
  if (unknownParentAccounts.length > 0) {
    gaps.push(
      `[OrgTreeBuilder] ${unknownParentAccounts.length} account(s) reference unknown parent OU IDs (intrinsic Refs): ${unknownParentAccounts.slice(0, 3).map(a => a.name).join(', ')}`
    );
  }

  return { root, ous, accounts, scpPolicies, gaps };
}
