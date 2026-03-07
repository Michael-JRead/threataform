/**
 * src/lib/iac/CFNParser.js
 * Parses CloudFormation JSON templates into a unified resource structure
 * compatible with parseTFMultiFile output (isCFN: true resources).
 *
 * Usage:
 *   import { extractCFNResources } from './CFNParser.js';
 *   const { resources, gaps } = extractCFNResources(jsonText, filePath);
 */

// ── detectPaveLayer replicated inline (cannot import from JSX) ───────────────
function detectPaveLayer(filePath) {
  const p = (filePath || '').toLowerCase();
  if (/\bl0[_/-]|org[_/-]mgmt|management[_/-]|control[_/-]tower/.test(p)) return 'L0';
  if (/\bl1[_/-]|vend|aft[_/-]|account[_/-]vend/.test(p)) return 'L1';
  if (/\bl2[_/-]|account[_/-]pave|pave[_/-]account|baseline/.test(p)) return 'L2';
  if (/\bl3[_/-]|product[_/-]pave|platform[_/-]|shared[_/-]/.test(p)) return 'L3';
  if (/\bl4[_/-]|service[_/-]|workload[_/-]|app[_/-]/.test(p)) return 'L4';
  return null;
}

// ── Resource types we extract ─────────────────────────────────────────────────
const SUPPORTED_TYPES = new Set([
  'AWS::IAM::Role',
  'AWS::IAM::Policy',
  'AWS::IAM::ManagedPolicy',
  'AWS::IAM::Group',
  'AWS::IAM::User',
  'AWS::IAM::InstanceProfile',
  'AWS::Organizations::Policy',
  'AWS::Organizations::PolicyAttachment',
  'AWS::Organizations::Account',
  'AWS::Organizations::OrganizationalUnit',
  'AWS::S3::Bucket',
  'AWS::S3::BucketPolicy',
  'AWS::KMS::Key',
  'AWS::KMS::Alias',
  'AWS::CloudFormation::Stack',
  'AWS::RDS::DBInstance',
  'AWS::RDS::DBCluster',
  'AWS::EC2::SecurityGroup',
  'AWS::EC2::VPC',
  'AWS::EC2::Subnet',
  'AWS::EC2::Instance',
  'AWS::Lambda::Function',
  'AWS::Lambda::Permission',
  'AWS::ApiGateway::RestApi',
  'AWS::ApiGatewayV2::Api',
  'AWS::DynamoDB::Table',
  'AWS::ElastiCache::ReplicationGroup',
  'AWS::SecretsManager::Secret',
  'AWS::SSM::Parameter',
  'AWS::SNS::Topic',
  'AWS::SQS::Queue',
  'AWS::CloudTrail::Trail',
  'AWS::Config::ConfigRule',
  'AWS::GuardDuty::Detector',
  'AWS::SecurityHub::Hub',
  'AWS::WAFv2::WebACL',
  'AWS::Shield::Protection',
  'AWS::StepFunctions::StateMachine',
  'AWS::Events::Rule',
  'AWS::Bedrock::Agent',
  'AWS::SageMaker::NotebookInstance',
]);

// ── Intrinsic function keys ───────────────────────────────────────────────────
const INTRINSIC_KEYS = new Set([
  'Ref', 'Fn::Sub', 'Fn::GetAtt', 'Fn::If', 'Fn::Select',
  'Fn::Join', 'Fn::Split', 'Fn::Base64', 'Fn::FindInMap',
  'Fn::ImportValue', 'Fn::Transform', 'Condition',
]);

/**
 * Recursively replace intrinsic functions with "__INTRINSIC__" string,
 * recording which top-level property keys were replaced.
 *
 * @param {*}        value          - Value to process
 * @param {string}   propKey        - Top-level property name (for tracking)
 * @param {string[]} unknownFields  - Accumulator for replaced field names
 * @returns {*} Processed value
 */
function resolveIntrinsics(value, propKey, unknownFields) {
  if (value === null || value === undefined) return value;

  if (typeof value !== 'object') return value;

  if (Array.isArray(value)) {
    return value.map(item => resolveIntrinsics(item, propKey, unknownFields));
  }

  // Check if this object IS an intrinsic function
  const keys = Object.keys(value);
  if (keys.length === 1 && INTRINSIC_KEYS.has(keys[0])) {
    if (propKey && !unknownFields.includes(propKey)) {
      unknownFields.push(propKey);
    }
    return '__INTRINSIC__';
  }

  // Recurse into object properties
  const out = {};
  for (const [k, v] of Object.entries(value)) {
    out[k] = resolveIntrinsics(v, k, unknownFields);
  }
  return out;
}

/**
 * Derive a human-readable name from CFN resource logical ID + properties.
 * @param {string} logicalId
 * @param {object} props
 * @param {string} type
 * @returns {string}
 */
function deriveName(logicalId, props, type) {
  // Prefer explicit name properties
  const nameProp = props.RoleName || props.PolicyName || props.BucketName ||
    props.FunctionName || props.TableName || props.KeyAlias ||
    props.Name || props.ClusterIdentifier || props.DBInstanceIdentifier ||
    props.StateMachineName || props.TopicName || props.QueueName;
  if (nameProp && nameProp !== '__INTRINSIC__') return String(nameProp);
  return logicalId;
}

/**
 * Check if a JSON string (or parsed object) looks like a CloudFormation template.
 * @param {string} text
 * @returns {boolean}
 */
export function isCFNTemplate(text) {
  if (typeof text !== 'string') return false;
  const peek = text.slice(0, 4096);
  return (
    /"AWSTemplateFormatVersion"/.test(peek) ||
    (/"Resources"\s*:\s*\{/.test(peek) && /"AWS::/.test(peek))
  );
}

/**
 * Extract resources from a CloudFormation JSON template.
 *
 * @param {string} content   - Raw JSON string of the CFN template
 * @param {string} filePath  - Source file path (used for paveLayer detection)
 * @returns {{ resources: object[], gaps: string[] }}
 */
export function extractCFNResources(content, filePath = '') {
  const resources = [];
  const gaps = [];
  const paveLayer = detectPaveLayer(filePath);

  let template;
  try {
    template = JSON.parse(content);
  } catch (err) {
    gaps.push(`[CFNParser] JSON parse error in ${filePath}: ${err.message}`);
    return { resources, gaps };
  }

  if (!template || typeof template !== 'object') {
    gaps.push(`[CFNParser] Template is not an object: ${filePath}`);
    return { resources, gaps };
  }

  const cfnResources = template.Resources;
  if (!cfnResources || typeof cfnResources !== 'object') {
    // Could be a parameter file or outputs file — skip silently
    return { resources, gaps };
  }

  const parameters = template.Parameters || {};
  const conditions = template.Conditions || {};

  for (const [logicalId, resourceDef] of Object.entries(cfnResources)) {
    if (!resourceDef || typeof resourceDef !== 'object') continue;

    const type = resourceDef.Type;
    if (!type || typeof type !== 'string') continue;

    // Extract even unsupported types if they have AWS:: prefix (for ATT&CK coverage)
    if (!type.startsWith('AWS::')) continue;

    const rawProps = resourceDef.Properties || {};
    const unknownFields = [];

    // Resolve intrinsic functions
    const props = resolveIntrinsics(rawProps, null, unknownFields);

    const name = deriveName(logicalId, props, type);

    // Build unified resource object matching parseTFMultiFile shape
    const resource = {
      id:            `${type}::${logicalId}`,
      type,
      name,
      label:         name,
      body:          JSON.stringify(props),
      cfnProps:      props,
      paveLayer,
      file:          filePath,
      isCFN:         true,
      logicalId,
      unknownFields,
      // Metadata for IntelligencePanel display
      metadata: {
        type:    'cloudformation',
        cfnType: type,
        file:    filePath,
        paveLayer,
      },
    };

    resources.push(resource);

    // Track gaps for intrinsic-heavy resources
    if (unknownFields.length > 3) {
      gaps.push(
        `[CFNParser] ${type} "${logicalId}" in ${filePath}: ${unknownFields.length} fields use intrinsic functions — analysis may be incomplete`
      );
    }
  }

  // Track unsupported types
  const allTypes = Object.values(cfnResources).map(r => r?.Type).filter(Boolean);
  const unsupported = [...new Set(allTypes.filter(t => t.startsWith('AWS::') && !SUPPORTED_TYPES.has(t)))];
  if (unsupported.length > 0) {
    gaps.push(
      `[CFNParser] ${filePath}: ${unsupported.length} resource types extracted without dedicated check rules: ${unsupported.slice(0, 5).join(', ')}${unsupported.length > 5 ? '...' : ''}`
    );
  }

  return { resources, gaps };
}
