# Threataform

**Enterprise Terraform Threat Intelligence Platform**

A browser-based, fully client-side security analysis platform for enterprise infrastructure-as-code. Upload Terraform, enrich with supporting documents, run automated threat modeling, and generate exportable Data Flow Diagrams — zero data leaves your browser.

---

## Table of Contents

- [Workflow Overview](#workflow-overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Intelligence Engine](#intelligence-engine)
- [Architecture Analysis](#architecture-analysis)
- [DFD Output](#dfd-output)
- [Knowledge Base](#knowledge-base)
- [TFE-Pave Pattern Support](#tfe-pave-pattern-support)
- [Supported File Types](#supported-file-types)
- [Security & Privacy](#security--privacy)
- [Project Structure](#project-structure)
- [Contributing](#contributing)

---

## Workflow Overview

Threataform follows a structured 3-step workflow per threat model:

```
Step 1 — Create Model
  Name your threat model (e.g. "Kinesis Data Analytics", "EKS Platform")
  ↓
Step 2 — Supporting Documents
  Upload categorized enterprise context documents
  Select industry & threat modeling frameworks in scope
  Describe key product features
  ↓
Step 3 — Workspace
  Upload & parse Terraform files
  Run Architecture Analysis (auto-populated from TF + docs)
  Query the Intelligence engine
  Run Threataform security analysis
  Export DFD to Lucidchart
```

All state is persisted per-model in browser `localStorage`. Switch between models without losing context.

---

## Features

### Step 2 — Supporting Documents

A dedicated intake screen for enriching the intelligence engine before analysis begins:

**Document Categories (with PDF/image extraction)**
| Category | Purpose |
|----------|---------|
| Enterprise Architecture | Platform type, AWS Org/OU/SCP docs, ADRs, SDLC processes |
| Application / Product Details | HLDD, engineer docs, vendor documentation |
| Enterprise Security Controls | Security control matrix, control baseline, known risks |
| CSPM / Cloud Configuration | Wiz reports, cloud configuration rules, posture findings |
| Customer Compliance Guide | CSP compliance guides cross-referenced with control matrix |
| Trust on Cloud Documentation | Enterprise cloud trust framework documentation |

**Framework Selection (chip selectors)**
- *Industry & Compliance:* NIST 800-53 r5, NIST CSF 2.0, CIS Controls v8, PCI DSS v4, HIPAA, FedRAMP Moderate, FedRAMP High, GDPR, ISO 27001, CMMC Level 2, SOC 2 Type II, NIST SP 800-207 (Zero Trust)
- *Threat Modeling:* STRIDE, PASTA, VAST, LINDDUN, OCTAVE, RTMP, OWASP Top 10, OWASP Top 10 Cloud, MITRE ATT&CK, DREAD, TRIKE

**Key Features textarea** — describe product capabilities; this feeds the intelligence context doc so queries about scope, auth, and data handling return meaningful results.

### Document Extraction (PDF.js + Tesseract.js)

All uploaded files are fully extracted at intake — no placeholder text:

| File Type | Extraction Method |
|-----------|------------------|
| Text-based PDF | PDF.js text layer extraction |
| Scanned / image-based PDF | PDF.js canvas render → Tesseract.js OCR per page |
| Mixed PDF | Text pages extracted directly; image pages OCR'd |
| PNG / JPG / WebP / BMP | Tesseract.js OCR with structural filename wrapper |
| TXT, MD, JSON, YAML, CSV, XML, HCL, TF | FileReader.readAsText() |

Both libraries are lazy-loaded from CDN on first use (PDF.js 3.11.174, Tesseract.js 4.x). Nothing is bundled.

---

### Step 3 — Workspace

#### Upload & Analyze

- Drag-and-drop or folder-select `.tf`, `.hcl`, `.sentinel`, and `.tfvars` files
- Multi-file parsing with cross-file reference detection (remote state, module inputs, `depends_on`, implicit refs)
- Non-TF files dropped here are automatically routed to the intelligence context index
- Scope selector — restrict threat model to specific files/folders within a large codebase
- Live file list with per-file size display and individual remove controls

#### Architecture Analysis Tab

Auto-populated from Terraform resources and indexed documents. Two-column layout:

**Narrative Findings (9 free-text fields, editable)**
- Entry Points · Data Flow · Security Boundaries · Public & Private Resources
- Security Controls · Fault Tolerance · Authentication & AuthZ
- External Dependencies · Storage & Data Security

Each field shows an **AI** badge when auto-generated and an **edited** badge after user modification. User edits are stored as overrides on top of the AI base — re-analyzing doesn't wipe manual changes.

**Structured Attributes (chip selection, 4 groups)**
- *Application Profile:* Application/Solution Type, Entry Points, Developed By, Users/Consumers
- *Data & Integration:* Inbound Source/Flow, Outbound Flow/Destination, Integrations
- *Deployment & Infrastructure:* Exposure, Facility Type, Compute Type
- *Security:* Authentication Methods

AI-inferred chips show a `✦` indicator. All overrides persist per-model in `localStorage`.

**Confidence score** — based on resource count + indexed doc chunks. Re-analyze button refreshes from current TF + documents.

#### Intelligence Tab

BM25-lite search engine with entity boosting, built entirely in-browser with no external dependencies:

| Sub-tab | Description |
|---------|-------------|
| Query | Free-text semantic search across all indexed documents and Terraform resources |
| Security Posture | NIST CSF 2.0 (40%) + Defense-in-Depth (35%) + Zero Trust (25%) composite score, A–F grade |
| Control Inventory | Present/absent controls per defense-in-depth layer |
| Cross-Doc Correlation | Identifies conflicts and confirmations across multiple uploaded documents |
| Misconfig Checks | 30+ automated checks (Checkov/tfsec-style) across all resources |
| ATT&CK Mapping | MITRE ATT&CK v18.1 technique coverage from parsed resource types |
| Doc Threat Findings | STRIDE threat signals extracted from uploaded documents |
| Scope Analysis | In-scope / out-of-scope declarations found across all indexed content |
| Resource Intelligence | Per-resource BM25 query against all indexed documents and KB |

The intelligence engine automatically rebuilds on every TF file change, document upload, model detail change, or framework selection — keeping results current without manual refresh.

#### Threataform Analysis Tab

- Executive summary with risk score and severity breakdown
- Per-finding detail: resource ID, severity (CRITICAL / HIGH / MEDIUM / LOW), remediation guidance
- CWE mapping and MITRE ATT&CK technique reference per finding
- STRIDE-LM threat mapping per architectural tier
- Trust boundary identification (network, compute, storage, IAM, org)
- Full ATT&CK coverage heatmap

**Pave-layer-aware IAM analysis** distinguishes genuinely dangerous wildcard policies from standard hierarchical pave patterns bounded by SCPs and permission boundaries. See [TFE-Pave Pattern Support](#tfe-pave-pattern-support).

#### DFD Output Tab

| Sub-tab | Description |
|---------|-------------|
| Architecture | Upload Lucidchart diagram image exported from the XML |
| Stats | Resource counts, module list, connection graph summary |
| XML Output | Full mxGraphModel XML — copy or download for Lucidchart import |
| Import Guide | Step-by-step Lucidchart import instructions with screenshots |
| Legend | Color-coded tier legend for the generated diagram |
| Analysis | DFD-level threat analysis |

The generated XML uses orthogonal edge routing with left-to-right tier layout. Import directly into [Lucidchart](https://lucid.app): *File → Import → Diagram* (XML).

#### Knowledge Base Tab

Searchable reference documentation for 11 enterprise domains:

| Domain | Coverage |
|--------|---------|
| xSphere Cloud | xSphere Terraform provider, Direct Connect, cross-provider hybrid patterns, FedRAMP/HIPAA compliance |
| Spinnaker.io | Full microservice pipeline architecture, Terraspin integration, Jenkins→Spinnaker→AWS |
| IAM · Org · OUs · SCPs | 7-layer policy evaluation, SCPs, RCPs, AFT, IAM Identity Center, RVM pattern |
| Jenkins / Jules | Terraform pipeline patterns, OIDC auth, Vault dynamic secrets, ephemeral agents |
| Enterprise DFD | Multi-repo topologies, cross-state coupling, Terragrunt dependency patterns |
| Wiz CSPM | Cloud Security Posture Management, CCRs, CNAPP findings, graph-based risk correlation |
| MITRE ATT&CK® | Enterprise v18.1 technique taxonomy mapped to Terraform resource types |
| MITRE CWE | Common Weakness Enumeration mapped to security findings |
| STRIDE-LM | STRIDE + Lateral Movement methodology, trust boundary analysis |
| TFE-Pave / Hier. IAM | L0–L4 hierarchical IAM, permission boundaries, workspace scoping, state file security |
| My Documents | All user-uploaded context documents indexed for intelligence queries |

---

## Quick Start

### Prerequisites

- Node.js 18+ and npm

### Run Locally

```bash
git clone https://github.com/YOUR_ORG/threataform.git
cd threataform
npm install
npm run dev
```

Open `http://localhost:5173` in your browser.

### Build for Production

```bash
npm run build
# Output in dist/ — serve with any static file server
```

### Deploy (Static Hosting)

Threataform is a fully static SPA. No server required.

```bash
# Netlify
netlify deploy --prod --dir=dist

# Vercel
vercel --prod

# AWS S3 + CloudFront
aws s3 sync dist/ s3://your-bucket --delete
aws cloudfront create-invalidation --distribution-id XXXX --paths "/*"
```

---

## Usage Guide

### 1. Create a Threat Model

From the landing page, enter your product/service name and click **Create →**. Use a descriptive name that reflects the service being modeled (e.g., "Kinesis Data Analytics Platform", "EKS Multi-Tenant Cluster"). This name seeds the intelligence engine.

### 2. Upload Supporting Documents (Step 2)

On the Documents page:

1. **Enterprise Architecture** — upload AWS Org structure JSON, architecture decision records, SCP policy files
2. **Application / Product Details** — upload HLDD, vendor documentation, integration specs
3. **Key Features** — fill in the textarea describing the product's capabilities (real-time streaming, multi-tenant, PII storage, etc.)
4. **Security & Compliance** — upload your security control baseline, Wiz CSPM exports, compliance guides
5. **Analysis Frameworks** — select all industry and threat modeling frameworks in scope

Click **Continue →** when ready. Documents are extracted and indexed immediately.

### 3. Upload Terraform Files

In the workspace **Upload & Analyze** tab:
- Drag-and-drop a folder or click **Select Folder** to upload an entire Terraform repository
- Supports entire directory trees with cross-file reference detection
- Drop additional context files (architecture diagrams, runbooks) to enrich intelligence

### 4. Review Architecture Analysis

Navigate to **Architecture Analysis** tab — fields auto-populate from your Terraform resources and uploaded documents:
- Edit any narrative field to override the AI inference
- Toggle structured attribute chips to refine the model
- Click **Re-analyze** to refresh from current state

### 5. Query Intelligence

Use the **Intelligence** tab to query across all indexed content:
- Free-text queries: *"what authentication methods are used"*, *"what data classification applies"*, *"NIST CSF 2.0 coverage"*
- Framework-aware: selected frameworks appear automatically in scope queries
- Security Posture grade reflects actual Terraform resource configuration

### 6. Review Security Findings

The **Threataform Analysis** tab shows automated findings, STRIDE threats, ATT&CK coverage, and trust boundary analysis. Use the scope selector to focus on specific parts of a large codebase.

### 7. Export DFD to Lucidchart

1. Go to **DFD Output → XML Output**
2. Click **Export .xml** to download `enterprise-tf-dfd.xml`
3. Open [Lucidchart](https://lucid.app) → File → Import → Diagram → select the XML
4. Export the diagram as PNG/JPG/SVG from Lucidchart
5. Upload the image in **DFD Output → Architecture** tab

---

## Intelligence Engine

The `ThreatModelIntelligence` class implements a BM25-lite retrieval engine with entity boosting — no external search library, no server, no embeddings API.

### Index Sources

Every rebuild indexes three source types simultaneously:

| Source | Content |
|--------|---------|
| Terraform resources | Resource type, name, ATT&CK techniques, misconfig check descriptions |
| User documents | Full extracted text chunked at ~400 tokens with 50-token overlap |
| Model context doc | Synthetic document: product name, environment, frameworks, key features, compliance scope |

### Entity Patterns

Extracted from every chunk at index time for entity-boosted retrieval:

- **STRIDE threats** — spoofing, tampering, repudiation, information disclosure, DoS, elevation
- **MITRE ATT&CK** — technique IDs (T1xxx) and tactic names
- **Compliance** — HIPAA, FedRAMP, SOC 2, PCI DSS, GDPR, CMMC, NIST
- **AWS services** — 100+ service name patterns
- **Security controls** — encryption, MFA, WAF, GuardDuty, CloudTrail, KMS, etc.
- **Scope declarations** — in-scope / out-of-scope / excluded / included language

### `analyzeArchitecture()` Method

Derives structured architecture fields from TF resources (no hallucination) combined with BM25 doc queries:

**Resource-Based Inference**
- `aws_lambda_function` + `aws_api_gateway_*` without ECS/EC2 → **Serverless**
- `aws_ecs_cluster` + `aws_lb` → **Container-Based (ECS)**
- `aws_cloudfront_distribution` + `aws_s3_bucket` without compute → **Static Web Application**
- `aws_cognito_user_pool` → **OAuth 2.0 / Cognito** auth method
- `aws_wafv2_web_acl` present → Security Controls narrative
- etc.

**Doc-Based Narrative** — 9 targeted BM25 queries fill the narrative fields from uploaded documentation.

---

## DFD Output

Generated XML conforms to `mxGraphModel` (draw.io / Lucidchart standard):

- **Layout:** Left-to-right, tiers as columns, nodes flow top-to-bottom within each column
- **Edge style:** `edgeStyle=orthogonalEdgeStyle` with `endArrow=blockThin`
- **Connection types:**
  - Grey — implicit Terraform references (e.g., `aws_iam_role.this.arn`)
  - Red dashed — explicit `depends_on`
  - Green — module input/output
- **Threat annotations:** Resources with STRIDE findings get a `⚠ stride1,stride2` third label line
- **Legend:** Top-left tier color legend auto-generated with every diagram

Import into Lucidchart: **File → Import → Diagram** → select the `.xml` file.

---

## Knowledge Base

The built-in KB contains structured reference documentation for enterprise Terraform and cloud security patterns. Access via the **Knowledge Base** tab — select a domain from the sidebar to read structured content with expandable sections.

All KB content is also indexed into the intelligence engine automatically, so queries like *"how does hierarchical IAM work"* or *"what is the Spinnaker bake stage"* return relevant passages even without uploading documents.

---

## TFE-Pave Pattern Support

Threataform understands enterprise **pave-layer hierarchies**:

| Layer | Name | Description |
|-------|------|-------------|
| L0 | Org / Management | SCPs, OU structure, Control Tower |
| L1 | Account Vending | AFT, account bootstrapping, enrollment |
| L2 | Account Pave | CloudTrail, GuardDuty, Config, permission boundaries |
| L3 | Product Pave | Platform VPC, TGW, shared SGs, ProductTeamDeployer role |
| L4 | Service | Application workloads, service-specific roles |

**Context-aware wildcard IAM analysis:**

| Pattern | Context | Severity |
|---------|---------|---------|
| `iam:*` at any layer | — | CRITICAL — permission hierarchy escape |
| `sts:AssumeRole` on `*` | — | CRITICAL — cross-account pivot |
| `kinesis:*` on `arn:.../stream/team-prefix-*` | permission boundary present | LOW — standard pave pattern |
| `s3:*` on `*` | — | HIGH — state file exfiltration risk |
| OIDC sub-claim `*` | — | CRITICAL — any repo can assume role |
| `sts:AssumeRoleWithWebIdentity` | bounded OIDC subject claim | LOW — safe OIDC trust |

---

## Supported File Types

**Terraform (parsed for resources, connections, modules)**

| Extension | Description |
|-----------|-------------|
| `.tf` | Terraform HCL resource definitions |
| `.hcl` | HCL configuration files |
| `.sentinel` | HashiCorp Sentinel policy files |
| `.tfvars` | Terraform variable definition files |

**Context Documents (indexed for intelligence)**

| Type | Extraction |
|------|-----------|
| `.pdf` | PDF.js text extraction + Tesseract.js OCR for scanned pages |
| `.png` `.jpg` `.jpeg` `.webp` `.bmp` | Tesseract.js OCR |
| `.docx` `.xlsx` `.csv` `.json` `.yaml` `.xml` | FileReader text |
| `.txt` `.md` `.log` | FileReader text |
| Max file size | 50 MB per file |

---

## Security & Privacy

- **100% client-side** — Terraform code and documents never leave your browser
- All parsing, OCR, intelligence indexing, and analysis runs in the browser's JavaScript engine
- No telemetry, no analytics, no external API calls (CDN script loads for PDF.js/Tesseract are lazy and on-demand)
- `localStorage` keys: `tf-threat-models`, `tf-model-{id}-docs`, `tf-model-{id}-details`, `tf-model-{id}-files`, `tf-model-{id}-arch-analysis`, `tf-model-{id}-diagram-image`
- Safe to use with sensitive internal infrastructure code

---

## Project Structure

```
threataform/
├── terraform-enterprise-intelligence.jsx  # Full application (~8600 lines)
├── dfd-generator.jsx                      # Standalone DFD XML generator
├── kb-module.jsx                          # Knowledge base module (standalone)
├── src/
│   └── main.jsx                           # Vite entry point
├── index.html                             # HTML shell
├── package.json                           # React 18 + Vite 6 + lucide-react
├── vite.config.js                         # Vite configuration
└── dist/                                  # Production build output
```

**Stack:**
- React 18 (functional components, hooks only)
- Vite 6 (build tool / dev server)
- lucide-react (SVG icon system, tree-shaken)
- PDF.js 3.11.174 (CDN, lazy-loaded on first PDF upload)
- Tesseract.js 4.x (CDN, lazy-loaded on first image/scanned-PDF upload)
- Inter + JetBrains Mono via Google Fonts CDN
- Zero other external UI dependencies — all styling is inline CSS

**Key internals in `terraform-enterprise-intelligence.jsx`:**

| Symbol | Description |
|--------|-------------|
| `ThreatModelIntelligence` | BM25-lite retrieval engine with entity extraction and boosting |
| `extractTextFromFile()` | PDF.js + Tesseract.js async file extraction utility |
| `parseTFMultiFile()` | Multi-file HCL parser with cross-file reference graph |
| `generateDFDXml()` | mxGraphModel XML generator (L→R tier layout, orthogonal edges) |
| `DocumentsPage` | Step 2 full-screen document intake UI |
| `LandingPage` | Model management: create, open, delete threat models |
| `IntelligencePanel` | 9-tab BM25 query interface |
| `AnalysisPanel` | Security findings, STRIDE analysis, ATT&CK mapping |
| `ArchitectureImageViewer` | Lucidchart diagram image upload and display |
| `KBPanel` | Knowledge base reader with expandable sections |
| `TF_MISCONFIG_CHECKS` | 30+ per-resource security rules (pave-layer-aware IAM) |
| `TF_ATTACK_MAP` | Resource type → MITRE ATT&CK technique mappings |
| `KB` | Structured knowledge base content for 10 enterprise domains |
| `RT` | 100+ AWS + xSphere resource type metadata (tier, color, label) |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-enhancement`
3. Make changes to `terraform-enterprise-intelligence.jsx`
4. Test locally with `npm run dev`
5. Open a pull request

### Adding Security Rules

Security checks live in `TF_MISCONFIG_CHECKS` (per-resource rules) and `runSecurityChecks()` (architecture-level gap detection). Each per-resource rule uses:

```js
TF_MISCONFIG_CHECKS["aws_resource_type"] = [
  {
    id: "TF-XXX",
    title: "Human-readable finding title",
    severity: "HIGH",          // CRITICAL | HIGH | MEDIUM | LOW
    check: (r) => !r.config?.some_attribute,
    detail: "Remediation guidance...",
    cwe: "CWE-XXX",
    attack: "T1XXX",
  }
];
```

### Adding Knowledge Base Entries

The `KB` object maps domain IDs to structured content:

```js
KB["my-domain"] = {
  title: "My Domain",
  color: "#1A73E8",
  sections: [
    { heading: "Overview", body: "..." },
    { heading: "Key Concepts", items: ["item 1", "item 2"] },
  ]
};
```

Add a corresponding entry to `KB_DOMAINS` (for the sidebar) and `KB_DOMAIN_ICONS` (for the Lucide icon).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [MITRE ATT&CK®](https://attack.mitre.org/) Enterprise v18.1 — threat technique taxonomy
- [HashiCorp Terraform](https://developer.hashicorp.com/terraform) documentation
- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html) (SRA)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) threat modeling methodology (Microsoft)
- [PDF.js](https://mozilla.github.io/pdf.js/) — Mozilla PDF rendering library
- [Tesseract.js](https://tesseract.projectnaptha.com/) — pure JavaScript OCR engine
- [lucide-react](https://lucide.dev/) — SVG icon library
