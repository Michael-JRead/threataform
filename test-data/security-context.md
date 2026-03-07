# Security Architecture Context — Application Platform

## Scope Declaration

**In Scope:**
- AWS VPC, subnets, and network ACLs
- EC2 Auto Scaling Group and Application Load Balancer
- RDS PostgreSQL primary database
- S3 data and logs buckets
- IAM roles, permission boundaries, and SCPs
- Lambda data processor function
- CloudWatch logging and alarms
- AWS Organizations OUs and accounts
- KMS encryption keys and aliases
- Secrets Manager secrets

**Out of Scope:**
- On-premises infrastructure
- Third-party SaaS integrations
- Client-side browser security
- Physical data center security

## Compliance Requirements

This deployment is subject to:
- **SOC 2 Type II** — Controls for CC6 (Logical Access), CC7 (System Operations), CC8 (Change Management)
- **HIPAA** — PHI handled in the RDS database must be encrypted at rest and in transit
- **FedRAMP Moderate** — GovCloud region deployment planned for Q2
- **PCI DSS v4.0** — Payment card data processed through the app tier; SAQ-A scope

## Architecture Notes

The platform uses a pave-layer model (L0–L4):
- **L0**: AWS Organizations root with SCPs enforcing baseline controls
- **L1**: Account vending machine and permission boundary enforcement
- **L2**: Shared services (logging, monitoring, security tooling)
- **L3**: Platform services (EKS, RDS, ElastiCache)
- **L4**: Workload accounts (app servers, Lambda, S3)

## Security Controls Present

### Identity and Access Management
- All IAM roles use permission boundaries (`platform-permission-boundary`) to prevent privilege escalation
- SCPs at the OU level deny root account actions, CloudTrail deletion, and unauthorized region usage
- SCP `deny-privilege-escalation` blocks `iam:CreateRole`, `iam:AttachRolePolicy`, and `iam:CreateUser` in workload OUs unless originating from management account
- MFA enforced for all console access via IAM Identity Center (AWS SSO)
- Cross-account access uses external ID conditions on AssumeRole

### Data Protection
- All S3 buckets: KMS-SSE encryption, versioning enabled, public access blocked, access logging enabled
- RDS: encrypted at rest with customer-managed KMS key, encrypted in transit (SSL enforced)
- Secrets Manager: all database credentials stored; no plaintext secrets in environment variables
- KMS key rotation: enabled on all platform keys; 30-day deletion window

### Network Security
- All EC2 in private subnets; no direct internet access
- ALB in public subnets with TLS 1.3 only, invalid header fields dropped
- Security groups use least-privilege: app-sg allows 443/80 from internet, db-sg allows 5432 from app-sg only
- VPC Flow Logs enabled to S3 logs bucket

### Logging and Monitoring
- CloudTrail: enabled organization-wide, logs to centralized S3 bucket in Security OU
- CloudWatch Logs: all EC2, Lambda, RDS logs with 90-day retention and KMS encryption
- GuardDuty: enabled organization-wide
- Security Hub: aggregated findings from GuardDuty, Inspector, and Macie
- ALB access logs: enabled to logs bucket

### Incident Response
- CloudWatch alarms for 5xx error rate, CPU spikes, unauthorized API calls
- SNS topic for alert delivery to on-call rotation
- AWS Config rules: 47 managed rules enabled, including CIS AWS Foundations Benchmark

## Known Gaps and Risks

1. **OverprivilegedAdminRole**: Legacy role (`OverprivilegedAdminRole`) in the CFN template has no permission boundary and allows `*` actions with broad principal (`Principal: "*"`). This was flagged in the last penetration test.
2. **Legacy RDS instance** (`legacy-database`): Not encrypted, publicly accessible, deletion protection disabled. Scheduled for decommission in Q3.
3. **UnrotatedKMSKey**: Legacy key with `EnableKeyRotation: false`. Used by a deprecated service. Rotation blocked due to key usage in older encrypted data.
4. **PublicAssetsBucket**: S3 bucket with no encryption, versioning, or public access block configured. Used for static web assets only — no sensitive data.
5. **SCP conditions with intrinsic refs**: SCP for privilege escalation uses `Fn::Sub` for management account ARN, creating an `__INTRINSIC__` sentinel — full evaluation not possible without account ID resolution.

## Threat Model Notes

### High-Priority Threats
- **T1078.004 (Cloud Account Compromise)**: Mitigated by SCPs (deny-root-actions, deny-privilege-escalation), MFA enforcement, permission boundaries
- **T1530 (Data from Cloud Storage)**: Mitigated by S3 public access block, KMS encryption, bucket policies. RISK: PublicAssetsBucket has no controls.
- **T1190 (Exploit Public-Facing Application)**: ALB in public subnets; WAF not yet deployed — FLAGGED as gap
- **T1552.005 (Cloud Instance Metadata API)**: EC2 instances use IMDSv2 (http_tokens = "required")
- **T1485 (Data Destruction)**: RDS and S3 versioning + deletion protection on primary resources
- **T1548 (Abuse Elevation Control Mechanism)**: SCPs block `iam:CreateRole`, `iam:AttachRolePolicy` in workload OU

### Defense-in-Depth Layers
1. Preventive: SCPs, permission boundaries, security groups, KMS
2. Detective: CloudTrail, GuardDuty, Security Hub, Config
3. Corrective: Incident response playbooks, automated remediation via Config rules
4. Recovery: RDS automated backups (30-day), S3 versioning, multi-AZ deployment

## Data Flow

1. Client → Internet → ALB (TLS 1.3) → App Server (EC2)
2. App Server → RDS (PostgreSQL, SSL) [credentials via Secrets Manager]
3. App Server → S3 Data Bucket (KMS-SSE) [via IAM role]
4. App Server → Lambda Processor (invocation) [via IAM role]
5. Lambda → S3 Data Bucket [process and write results]
6. All components → CloudWatch Logs [log aggregation]
7. CloudTrail → S3 Logs Bucket [audit trail]
