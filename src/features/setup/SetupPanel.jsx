// src/features/setup/SetupPanel.jsx
// Workspace Setup section — 3 tabs: Files | Application Details | Product Layers
// Replaces the inline mainTab==="build" block in the workspace.

import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  Upload, FolderOpen, Download, FileText, X, CheckCircle2, TriangleAlert,
  BarChart2, Package, Building2, ArrowLeftRight, Lock, Globe, Shield,
  Database, RefreshCw, KeyRound, LinkIcon, DoorOpen, Loader2,
  RotateCcw, ClipboardList, SquareStack, Zap, Sparkles, Layers,
} from "../../icons.jsx";
import { C, SANS, MONO, card, sectionBar } from "../../constants/styles.js";
import { ChipInput } from "../../components/ChipInput.jsx";

// ── Architecture context constants ─────────────────────────────────────────────
const NARRATIVE_FIELDS = [
  { key: "entryPoints",            label: "Entry Points",               Icon: DoorOpen },
  { key: "dataFlow",               label: "Data Flow",                  Icon: ArrowLeftRight },
  { key: "securityBoundaries",     label: "Security Boundaries",        Icon: Lock },
  { key: "publicPrivateResources", label: "Public & Private Resources", Icon: Globe },
  { key: "securityControls",       label: "Security Controls",          Icon: Shield },
  { key: "faultTolerance",         label: "Fault Tolerance",            Icon: RefreshCw },
  { key: "authAndAuthz",           label: "Authentication & AuthZ",     Icon: KeyRound },
  { key: "externalDependencies",   label: "External Dependencies",      Icon: LinkIcon },
  { key: "storageAndDataSecurity", label: "Storage & Data Security",    Icon: Database },
];

const ATTR_CHIPS = {
  applicationType:        ["Web App","REST API","Serverless","Microservices","Container-Based","VM-Based","Static Site","Data Pipeline","Streaming","ML/AI"],
  entryPointTypes:        ["HTTPS","REST API","GraphQL","gRPC","CLI","SDK","Webhook","Event Stream","File Transfer","Web UI"],
  developedBy:            ["Vendor (AWS)","Vendor (Azure)","Vendor (GCP)","Vendor (3rd Party)","Internal","Hybrid"],
  users:                  ["Internal Employees","Internal Apps/Services","External End Users","3rd Party Systems","Business Partners"],
  inboundDataSource:      ["Internal Corporate Network","External 3rd Party","External Public","Trusted Partner","IoT/Edge"],
  inboundDataFlow:        ["API Request","Event/Message","Network Traffic","User Input","Data Streaming","File Upload","DB Replication"],
  outboundDataFlow:       ["API Response","Event/Message","Network Traffic","Data Streaming","File Export","DB Write"],
  outboundDataDestination:["Internal Corporate Network","External 3rd Party","External Public","Trusted Partner","Data Warehouse"],
  integrations:           ["REST API","GraphQL","SDK","Webhook","File Transfer","Message Queue (SQS/SNS)","Event Stream (Kinesis/Kafka)","Middleware","DB Replication"],
  exposure:               ["Public Internet","Intranet Only","VPN Required","Trusted Partner Network","Air-Gapped"],
  facilityType:           ["AWS Cloud","Azure Cloud","GCP Cloud","Enterprise Data Center","3rd Party DC","Mobile","Desktop"],
  computeType:            ["Cloud Managed Service","Serverless","Container (ECS/EKS)","VM (EC2)","On-Premises","Hybrid"],
  authMethods:            ["OAuth 2.0","SSO/SAML","PKI/mTLS","ADFS/LDAP","API Key","MFA","AWS IAM","Certificate","Passwordless"],
  dataSensitivity:        ["PII","PHI","PCI Data","Confidential","Internal","Public","Export Controlled","Trade Secret"],
  complianceFramework:    ["HIPAA","PCI-DSS","SOC 2","GDPR","FedRAMP","ISO 27001","NIST 800-53","CIS AWS","CCPA","CMMC"],
  environment:            ["Production","Staging","Development","DR / Backup","Lab / Sandbox","Multi-Tenant","Single-Tenant"],
};

const ATTR_GROUPS = [
  { label: "Application Profile",        keys: ["applicationType","entryPointTypes","developedBy","users"] },
  { label: "Data & Integration",          keys: ["inboundDataSource","inboundDataFlow","outboundDataFlow","outboundDataDestination","integrations"] },
  { label: "Deployment & Infrastructure", keys: ["exposure","facilityType","computeType"] },
  { label: "Security & Compliance",       keys: ["authMethods","dataSensitivity","complianceFramework"] },
  { label: "Context",                     keys: ["environment"] },
];

const ATTR_LABELS = {
  applicationType:"Application / Solution Type", entryPointTypes:"Entry Points",
  developedBy:"Developed By", users:"Users / Consumers",
  inboundDataSource:"Inbound Data Source", inboundDataFlow:"Inbound Data Flow",
  outboundDataFlow:"Outbound Data Flow", outboundDataDestination:"Outbound Destination",
  integrations:"Integrations", exposure:"Exposure", facilityType:"Facility Type",
  computeType:"Compute Type", authMethods:"Authentication Methods",
  dataSensitivity:"Data Sensitivity", complianceFramework:"Compliance Frameworks",
  environment:"Environment / Deployment Stage",
};

const SINGLE_SELECT = ["developedBy","environment"];

const INDUSTRY_FRAMEWORKS = [
  "NIST 800-53 r5","NIST CSF 2.0","CIS Controls v8","PCI DSS v4","HIPAA",
  "FedRAMP Moderate","FedRAMP High","GDPR","ISO 27001","CMMC Level 2","SOC 2 Type II","NIST SP 800-207 (Zero Trust)",
];
const THREAT_FRAMEWORKS = [
  "STRIDE","PASTA","VAST","LINDDUN","OCTAVE","RTMP",
  "OWASP Top 10","OWASP Top 10 Cloud","MITRE ATT&CK","DREAD","TRIKE",
];

// ── Tab IDs ────────────────────────────────────────────────────────────────────
const TABS = [
  { id: "files",   label: "Files",               icon: Upload },
  { id: "details", label: "Application Details", icon: Building2 },
  { id: "layers",  label: "Product Layers",       icon: Layers },
];

/**
 * @param {{
 *   files: Array,           parseResult: object|null,
 *   ingestState: object|null, error: string,
 *   handleDrop: function,   readFiles: function,
 *   readDirectory: function, removeFile: function,
 *   clearFiles: function,
 *   currentModel: object|null,
 *   modelDetails: object,
 *   saveModelDetails: function,
 *   archAnalysis: object|null, archOverrides: object,
 *   archAnalyzing: boolean,
 *   setArchOverrides: function, setArchAnalyzing: function,
 *   setIntelligenceVersion: function,
 *   modelMetaPut: function,
 *   intelligence: object|null, intelligenceVersion: number,
 *   userDocs: Array,
 *   productModuleNames: string[],
 *   onAddProductModules: function, onRemoveProductModule: function,
 *   onNavToThreats: function, onNavToDiagram: function,
 * }} props
 */
export function SetupPanel({
  files = [],
  parseResult,
  ingestState,
  error,
  handleDrop,
  readFiles,
  readDirectory,
  removeFile,
  clearFiles,
  currentModel,
  modelDetails,
  saveModelDetails,
  archAnalysis,
  archOverrides,
  archAnalyzing,
  setArchOverrides,
  setArchAnalyzing,
  setIntelligenceVersion,
  modelMetaPut,
  intelligence,
  intelligenceVersion,
  userDocs = [],
  productModuleNames = [],
  onAddProductModules,
  onRemoveProductModule,
  onNavToThreats,
  onNavToDiagram,
}) {
  const [activeTab, setActiveTab] = useState("files");
  const [dragging, setDragging] = useState(false);
  const [keyFeaturesText, setKeyFeaturesText] = useState(modelDetails?.keyFeatures || "");
  const [kfGenerating, setKfGenerating] = useState(false);
  const kfRef = useRef(null);

  // ── Key features textarea auto-resize ──────────────────────────────────────
  useEffect(() => {
    if (kfRef.current) {
      kfRef.current.style.height = "auto";
      kfRef.current.style.height = kfRef.current.scrollHeight + "px";
    }
  }, [keyFeaturesText]);

  // ── Auto-populate key features when intelligence rebuilds ──────────────────
  useEffect(() => {
    if (!intelligence?._built) return;
    const entDocs = (userDocs || []).filter(d => d.docCategory === "enterprise-arch" || d.docCategory === "app-details").length;
    if (!entDocs) return;
    if (keyFeaturesText && !keyFeaturesText.startsWith("- ")) return;
    setKfGenerating(true);
    setTimeout(() => {
      const bullets = intelligence.extractKeyFeatures?.() || [];
      if (bullets.length) {
        const text = bullets.join("\n");
        setKeyFeaturesText(text);
        saveModelDetails({ ...modelDetails, keyFeatures: text });
      }
      setKfGenerating(false);
    }, 0);
  }, [intelligenceVersion]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Sync keyFeaturesText when modelDetails changes externally ──────────────
  useEffect(() => {
    setKeyFeaturesText(modelDetails?.keyFeatures || "");
  }, [currentModel?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const saveKeyFeatures = useCallback(() => {
    saveModelDetails({ ...modelDetails, keyFeatures: keyFeaturesText });
  }, [modelDetails, keyFeaturesText, saveModelDetails]);

  const toggleFramework = useCallback((fw, isIndustry) => {
    const key = isIndustry ? "frameworks" : "threatFrameworks";
    const current = modelDetails?.[key] || [];
    const updated = current.includes(fw) ? current.filter(f => f !== fw) : [...current, fw];
    saveModelDetails({ ...modelDetails, [key]: updated });
  }, [modelDetails, saveModelDetails]);

  // ── Architecture analysis helpers ──────────────────────────────────────────
  const ovNarrative = archOverrides?.narrative || {};
  const ovAttrs     = archOverrides?.attributes || {};
  const narrative   = { ...(archAnalysis?.narrative || {}), ...ovNarrative };
  const attrs       = { ...(archAnalysis?.attributes || {}), ...ovAttrs };

  const saveNarrativeField = useCallback((key, value) => {
    const updated = { ...archOverrides, narrative: { ...ovNarrative, [key]: value } };
    setArchOverrides(updated);
    setIntelligenceVersion(v => v + 1);
    if (currentModel) modelMetaPut(currentModel.id, "arch-analysis", { base: archAnalysis, overrides: updated });
  }, [archOverrides, ovNarrative, archAnalysis, currentModel, modelMetaPut, setArchOverrides, setIntelligenceVersion]);

  const toggleAttrChip = useCallback((attrKey, chip) => {
    const single = SINGLE_SELECT.includes(attrKey);
    const current = attrs[attrKey];
    let updated;
    if (single) {
      updated = current === chip ? "" : chip;
    } else {
      const arr = Array.isArray(current) ? current : [];
      updated = arr.includes(chip) ? arr.filter(c => c !== chip) : [...arr, chip];
    }
    const newAttrs = { ...ovAttrs, [attrKey]: updated };
    const newOverrides = { ...archOverrides, attributes: newAttrs };
    setArchOverrides(newOverrides);
    setIntelligenceVersion(v => v + 1);
    if (currentModel) modelMetaPut(currentModel.id, "arch-analysis", { base: archAnalysis, overrides: newOverrides });
  }, [attrs, ovAttrs, archOverrides, archAnalysis, currentModel, modelMetaPut, setArchOverrides, setIntelligenceVersion]);

  const reanalyze = useCallback(() => {
    setArchAnalyzing(true);
    setTimeout(() => {
      try {
        const result = intelligence?.analyzeArchitecture?.(parseResult?.resources || [], userDocs, modelDetails);
        if (result) {
          if (currentModel) modelMetaPut(currentModel.id, "arch-analysis", { base: result, overrides: archOverrides });
        }
      } finally { setArchAnalyzing(false); }
    }, 0);
  }, [intelligence, parseResult, userDocs, modelDetails, archOverrides, currentModel, modelMetaPut, setArchAnalyzing]);

  const resetOverrides = useCallback(() => {
    setArchOverrides({});
    if (currentModel) modelMetaPut(currentModel.id, "arch-analysis", { base: archAnalysis, overrides: {} });
  }, [archAnalysis, currentModel, modelMetaPut, setArchOverrides]);

  // ── Helpers ────────────────────────────────────────────────────────────────
  const extColorTF = e => ({ tf:"#FF6B35",hcl:"#FF9900",sentinel:"#E91E63",tfvars:"#9C27B0" }[e] || C.textMuted);
  const ext = f => (f.path || f.name || "").split(".").pop().toLowerCase();

  const renderFrameworkChips = (items, selected, onToggle, accent) => (
    <div style={{ display:"flex", flexWrap:"wrap", gap:6 }}>
      {items.map(item => {
        const active = (selected || []).includes(item);
        return (
          <button key={item} onClick={() => onToggle(item)} style={{
            background: active ? `${accent}22` : "transparent",
            border: `1px solid ${active ? accent : C.border2}`,
            borderRadius: 20, padding: "4px 12px",
            fontSize: 11, color: active ? accent : C.textMuted, cursor: "pointer", ...SANS,
            transition: "all .15s",
          }}>{item}</button>
        );
      })}
    </div>
  );

  // ── Tabs ───────────────────────────────────────────────────────────────────
  return (
    <div style={{ display:"flex", flexDirection:"column", height:"100%", overflow:"hidden" }}>

      {/* Tab bar */}
      <div style={{
        display:"flex", gap:2, padding:"10px 28px 0",
        background:C.surface, borderBottom:`1px solid ${C.border}`,
        flexShrink:0,
      }}>
        {TABS.map(({ id, label, icon: Icon }) => {
          const active = activeTab === id;
          // Badge counts
          const badge =
            id === "files"   ? files.length || null :
            id === "layers"  ? productModuleNames.length || null :
            null;
          return (
            <button
              key={id}
              onClick={() => setActiveTab(id)}
              role="tab"
              aria-selected={active}
              style={{
                display:"flex", alignItems:"center", gap:6,
                padding:"8px 16px", borderRadius:"6px 6px 0 0",
                border:`1px solid ${active ? C.border : "transparent"}`,
                borderBottom: active ? `1px solid ${C.surface}` : "none",
                marginBottom: active ? -1 : 0,
                background: active ? C.surface : "transparent",
                color: active ? C.text : C.textMuted,
                fontSize:13, fontWeight: active ? 700 : 400, cursor:"pointer", ...SANS,
                transition:"color .15s",
              }}
            >
              <Icon size={14} style={{ color: active ? C.accent : C.textMuted }}/>
              {label}
              {badge != null && (
                <span style={{
                  fontSize:10, fontWeight:700, padding:"1px 6px", borderRadius:9,
                  background: active ? `${C.accent}22` : C.surface2,
                  color: active ? C.accent : C.textMuted,
                  border:`1px solid ${active ? C.accent+"44" : C.border}`,
                }}>{badge}</span>
              )}
            </button>
          );
        })}
      </div>

      {/* Tab content */}
      <div style={{ flex:1, overflowY:"auto", minHeight:0 }}>

        {/* ═══════════════════════════════════════════════════════════════════ */}
        {/* FILES TAB                                                           */}
        {/* ═══════════════════════════════════════════════════════════════════ */}
        {activeTab === "files" && (
          <div style={{ padding:"28px 32px", maxWidth:900 }}>

            {/* Ingestion progress bar */}
            {ingestState && (
              <div style={{ background:C.surface, border:`1px solid ${C.border}`, borderRadius:8,
                padding:"10px 16px", marginBottom:20 }}>
                <div style={{ display:"flex", alignItems:"center", justifyContent:"space-between", marginBottom:5 }}>
                  <span style={{ fontSize:12, color:C.textSub, fontWeight:500 }}>
                    Analyzing {ingestState.done} / {ingestState.total} files
                    {ingestState.current ? ` · ${ingestState.current}` : ""}
                  </span>
                  <span style={{ fontSize:12, fontWeight:700, color:C.accent }}>
                    {Math.round((ingestState.done / Math.max(ingestState.total, 1)) * 100)}%
                  </span>
                </div>
                <div style={{ height:4, background:C.border, borderRadius:2, overflow:"hidden" }}>
                  <div style={{
                    height:"100%", borderRadius:2,
                    background:`linear-gradient(90deg,${C.accent},${C.accent}aa)`,
                    width:`${Math.round((ingestState.done / Math.max(ingestState.total, 1)) * 100)}%`,
                    transition:"width .3s ease",
                  }}/>
                </div>
              </div>
            )}

            {/* Drop zone */}
            <div
              onDrop={e => { handleDrop(e); setDragging(false); }}
              onDragOver={e => { e.preventDefault(); setDragging(true); }}
              onDragLeave={() => setDragging(false)}
              style={{
                border:`2px dashed ${dragging ? C.accent : C.border2}`,
                borderRadius:12, padding: files.length ? "24px 32px" : "48px 32px",
                textAlign:"center", background: dragging ? `${C.accent}08` : C.surface,
                transition:"all .2s", marginBottom:16,
                boxShadow: dragging ? `0 0 24px ${C.accent}20` : "none",
              }}
            >
              <div style={{ marginBottom:8, opacity:dragging?1:0.6, display:"flex", justifyContent:"center" }}>
                {dragging ? <Download size={files.length?28:40}/> : <FolderOpen size={files.length?28:40}/>}
              </div>
              <div style={{ ...SANS, color:C.textSub, fontSize:14, marginBottom:4, fontWeight:500 }}>
                {dragging ? "Drop to add files" : files.length ? "Drop more files to add them" : "Drag & drop files or a folder here"}
              </div>
              <div style={{ fontSize:12, color:C.textMuted, marginBottom:18 }}>
                All file types accepted · .tf .hcl .sentinel .tfvars → parsed · everything else → context docs
              </div>
              <div style={{ display:"flex", gap:10, justifyContent:"center", flexWrap:"wrap" }}>
                {"showDirectoryPicker" in window && (
                  <button onClick={async () => {
                    try {
                      const dirHandle = await window.showDirectoryPicker({ mode: "read" });
                      readDirectory(dirHandle);
                    } catch (err) {
                      if (err?.name !== "AbortError") console.warn("[SetupPanel] showDirectoryPicker failed:", err);
                    }
                  }} style={{
                    background:`${C.blue}18`, border:`1px solid ${C.blue}55`,
                    borderRadius:8, padding:"9px 20px", color:C.blue,
                    fontSize:13, cursor:"pointer", ...SANS, display:"flex", alignItems:"center", gap:7, fontWeight:600,
                  }}>
                    🗂 Open Folder (1GB+)
                  </button>
                )}
                <label style={{
                  background:C.surface2, border:`1px solid ${C.border2}`,
                  borderRadius:8, padding:"9px 20px", color:C.textSub,
                  fontSize:13, cursor:"pointer", ...SANS, display:"flex", alignItems:"center", gap:7, fontWeight:500,
                }}>
                  <FileText size={14}/> {files.length ? "Add Files" : "Select Files"}
                  <input type="file" multiple
                    onChange={e => { if (e.target.files?.length) readFiles(e.target.files, files.length > 0); e.target.value = ""; }}
                    style={{ display:"none" }}/>
                </label>
                <label style={{
                  background:`linear-gradient(135deg,${C.accent}18,${C.accent}08)`,
                  border:`1px solid ${C.accent}55`,
                  borderRadius:8, padding:"9px 20px", color:C.accent,
                  fontSize:13, cursor:"pointer", ...SANS, display:"flex", alignItems:"center", gap:7, fontWeight:600,
                }}>
                  <span>📂</span> {files.length ? "Add Folder" : "Select Folder"}
                  <input type="file" webkitdirectory=""
                    onChange={e => { if (e.target.files?.length) readFiles(e.target.files, files.length > 0); e.target.value = ""; }}
                    style={{ display:"none" }}/>
                </label>
              </div>
            </div>

            {/* Error message */}
            {error && (
              <div style={{
                padding:"12px 16px", background:"#200808",
                border:`1px solid ${C.red}44`, borderRadius:8,
                color:"#FF8A80", fontSize:13, marginBottom:16,
                display:"flex", gap:10, alignItems:"flex-start",
              }}>
                <TriangleAlert size={16} style={{ flexShrink:0 }}/>
                <span>{error}</span>
              </div>
            )}

            {/* File list */}
            {files.length > 0 && (() => {
              const grouped = {};
              files.forEach(f => {
                const parts = (f.path || f.name).split("/");
                const folder = parts.length > 1 ? parts.slice(0,-1).join("/") : "";
                if (!grouped[folder]) grouped[folder] = [];
                grouped[folder].push(f);
              });
              return (
                <div style={{ ...card(C.green+"33"), marginBottom:16 }}>
                  <div style={{ ...sectionBar(C.green), justifyContent:"space-between" }}>
                    <div style={{ display:"flex", alignItems:"center", gap:8 }}>
                      <CheckCircle2 size={14}/>
                      <span>{files.length} file{files.length!==1?"s":""} loaded</span>
                      {parseResult && (
                        <span style={{ fontSize:11, color:C.textMuted }}>
                          · {parseResult.resources.length} resources · {parseResult.connections.length} connections
                        </span>
                      )}
                    </div>
                    <button onClick={clearFiles} style={{
                      background:"transparent", border:`1px solid ${C.red}44`,
                      borderRadius:6, padding:"3px 10px", color:C.red,
                      fontSize:11, cursor:"pointer", ...SANS,
                    }}>Clear All</button>
                  </div>
                  <div style={{ padding:"10px 14px", maxHeight:280, overflowY:"auto" }}>
                    {Object.entries(grouped).map(([folder, fls]) => (
                      <div key={folder} style={{ marginBottom: folder ? 10 : 0 }}>
                        {folder && (
                          <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:4, paddingLeft:2,
                            textTransform:"uppercase", letterSpacing:".06em", display:"flex", alignItems:"center", gap:5 }}>
                            <FolderOpen size={11}/> {folder}
                          </div>
                        )}
                        {fls.map(f => (
                          <div key={f.path || f.name} style={{
                            display:"flex", gap:8, alignItems:"center", padding:"4px 6px",
                            borderRadius:5, marginBottom:2, background:"transparent",
                          }}
                            onMouseEnter={e => e.currentTarget.style.background = C.surface2}
                            onMouseLeave={e => e.currentTarget.style.background = "transparent"}
                          >
                            <span style={{
                              fontSize:9, fontWeight:700, padding:"2px 5px", borderRadius:3,
                              background:`${extColorTF(ext(f))}20`, color:extColorTF(ext(f)),
                              border:`1px solid ${extColorTF(ext(f))}44`, flexShrink:0, minWidth:28, textAlign:"center",
                            }}>{ext(f).toUpperCase().slice(0,6)}</span>
                            <span style={{ ...MONO, fontSize:12, color:C.textSub, flex:1, overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>
                              {folder ? (f.path || f.name).split("/").pop() : (f.path || f.name)}
                            </span>
                            {f.size && <span style={{ fontSize:11, color:C.textMuted, flexShrink:0 }}>
                              {f.size < 1024 ? f.size+"B" : Math.round(f.size/1024)+"K"}
                            </span>}
                            <button onClick={() => removeFile(f.path || f.name)} aria-label={`Remove ${f.name}`} style={{
                              background:"transparent", border:"none", color:C.textMuted,
                              cursor:"pointer", fontSize:14, padding:"0 4px", lineHeight:1, borderRadius:4, flexShrink:0,
                            }}
                              onMouseEnter={e => { e.currentTarget.style.color = C.red; e.currentTarget.style.background = C.red+"15"; }}
                              onMouseLeave={e => { e.currentTarget.style.color = C.textMuted; e.currentTarget.style.background = "transparent"; }}
                            ><X size={12}/></button>
                          </div>
                        ))}
                      </div>
                    ))}
                  </div>
                </div>
              );
            })()}

            {/* Parse results */}
            {parseResult && (
              <div style={{ ...card(), marginBottom:20 }}>
                <div style={{ ...sectionBar(C.accent) }}>
                  <BarChart2 size={14}/>
                  <span>Parse Results</span>
                </div>
                <div style={{ padding:"20px 18px" }}>
                  <div style={{ display:"grid", gridTemplateColumns:"repeat(3,1fr)", gap:12, marginBottom:20 }}>
                    {[
                      { label:"Resources",    val:parseResult.resources.length,          c:C.green },
                      { label:"Modules",      val:parseResult.modules.length,            c:C.accent },
                      { label:"Connections",  val:parseResult.connections.length,        c:C.blue },
                      { label:"Outputs",      val:parseResult.outputs.length,            c:"#9C27B0" },
                      { label:"Variables",    val:parseResult.variables.length,          c:"#00BCD4" },
                      { label:"Remote States",val:parseResult.remoteStates?.length||0,   c:"#E91E63" },
                    ].map(s => (
                      <div key={s.label} style={{ background:C.bg, borderRadius:8, padding:"14px 16px", border:`1px solid ${s.c}30` }}>
                        <div style={{ fontSize:26, fontWeight:700, color:s.c, lineHeight:1 }}>{s.val}</div>
                        <div style={{ fontSize:12, color:C.textMuted, marginTop:5 }}>{s.label}</div>
                      </div>
                    ))}
                  </div>
                  <div style={{ display:"flex", gap:10 }}>
                    <button onClick={onNavToThreats} style={{
                      background:"linear-gradient(135deg,#FF6B35,#FF9900)",
                      border:"none", borderRadius:8, padding:"10px 24px",
                      color:"#000", fontWeight:700, fontSize:13, cursor:"pointer", ...SANS,
                      display:"flex", alignItems:"center", gap:8,
                    }}>🔬 View Analysis →</button>
                    <button onClick={onNavToDiagram} style={{
                      background:C.surface2, border:`1px solid ${C.accent}44`,
                      borderRadius:8, padding:"10px 24px",
                      color:C.accent, fontWeight:600, fontSize:13, cursor:"pointer", ...SANS,
                      display:"flex", alignItems:"center", gap:8,
                    }}>🗺 View DFD →</button>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {/* ═══════════════════════════════════════════════════════════════════ */}
        {/* APPLICATION DETAILS TAB                                            */}
        {/* ═══════════════════════════════════════════════════════════════════ */}
        {activeTab === "details" && (
          <div style={{ padding:"28px 32px", maxWidth:900 }}>

            {/* Basic fields */}
            {currentModel && (
              <div style={{ background:C.surface, border:`1px solid ${C.border}`, borderRadius:14,
                padding:"20px 24px", marginBottom:24 }}>
                <div style={{ fontSize:14, fontWeight:700, color:C.text, marginBottom:16, display:"flex", alignItems:"center", gap:8 }}>
                  <span>Application Details</span>
                  <span style={{ fontSize:10, color:C.textMuted, fontWeight:400 }}>— enriches intelligence context</span>
                </div>
                <div style={{ display:"grid", gridTemplateColumns:"1fr 1fr", gap:16, marginBottom:14 }}>
                  <div>
                    <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:6 }}>Environment</div>
                    <select
                      value={modelDetails?.environment || ""}
                      onChange={e => saveModelDetails({ ...modelDetails, environment:e.target.value })}
                      style={{ width:"100%", background:C.bg, border:`1px solid ${C.border2}`, borderRadius:8,
                        padding:"8px 12px", color:modelDetails?.environment?C.text:C.textMuted, fontSize:13, ...SANS, outline:"none" }}
                    >
                      <option value="">Select environment...</option>
                      {["Production","Staging","Development","DR / Disaster Recovery","Sandbox"].map(o => (
                        <option key={o} value={o}>{o}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:6 }}>Team / Owner</div>
                    <input
                      value={modelDetails?.owner || ""}
                      onChange={e => saveModelDetails({ ...modelDetails, owner:e.target.value })}
                      placeholder="e.g. Platform Security Team"
                      style={{ width:"100%", boxSizing:"border-box", background:C.bg, border:`1px solid ${C.border2}`,
                        borderRadius:8, padding:"8px 12px", color:C.text, fontSize:13, ...SANS, outline:"none" }}
                    />
                  </div>
                </div>
                <div style={{ marginBottom:14 }}>
                  <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:8 }}>Data Classification</div>
                  <div style={{ display:"flex", flexWrap:"wrap", gap:6 }}>
                    {["PII (Personal Data)","PHI (Health Data)","PCI (Payment Data)","Financial Data","Internal","Public"].map(cls => {
                      const on = (modelDetails?.dataClassification || []).includes(cls);
                      return (
                        <button key={cls} onClick={() => {
                          const arr = modelDetails?.dataClassification || [];
                          const updated = arr.includes(cls) ? arr.filter(x => x !== cls) : [...arr, cls];
                          saveModelDetails({ ...modelDetails, dataClassification:updated });
                        }} style={{
                          background:on?"#0277BD20":"transparent", border:`1px solid ${on?"#0277BD":C.border2}`,
                          borderRadius:20, padding:"4px 12px", fontSize:11,
                          color:on?"#4FC3F7":C.textMuted, cursor:"pointer", ...SANS,
                        }}>{cls}</button>
                      );
                    })}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:6, display:"flex", alignItems:"center", gap:8 }}>
                    Architecture Description
                    {!modelDetails?.description && intelligence?._built && (
                      <span style={{ fontSize:10, color:C.accent, fontWeight:400 }}>auto-populated from docs</span>
                    )}
                  </div>
                  <textarea
                    value={modelDetails?.description || ""}
                    onChange={e => saveModelDetails({ ...modelDetails, description:e.target.value })}
                    placeholder="Auto-populated from uploaded documents and Terraform analysis. Edit freely."
                    rows={3}
                    style={{ width:"100%", boxSizing:"border-box", background:C.bg, border:`1px solid ${C.border2}`,
                      borderRadius:8, padding:"8px 12px", color:C.text, fontSize:12, ...SANS, outline:"none",
                      resize:"vertical", lineHeight:1.6, ...MONO }}
                  />
                </div>
              </div>
            )}

            {/* Key Features */}
            <div style={{ background:C.surface, border:`1px solid ${keyFeaturesText?C.accent+"66":C.border}`,
              borderRadius:12, padding:"18px 20px", marginBottom:24 }}>
              <div style={{ display:"flex", alignItems:"center", gap:10, marginBottom:12 }}>
                <Sparkles size={18} style={{ color:keyFeaturesText?C.accent:C.textMuted }}/>
                <div style={{ flex:1 }}>
                  <div style={{ ...SANS, fontSize:13, fontWeight:700, color:C.text }}>Key Features</div>
                  <div style={{ fontSize:11, color:C.textMuted }}>Auto-extracted from Enterprise Context docs — edit freely</div>
                </div>
                {kfGenerating && (
                  <span style={{ display:"flex", alignItems:"center", gap:5, fontSize:11, color:C.accent }}>
                    <Loader2 size={12} style={{ animation:"spin 1s linear infinite" }}/> Extracting...
                  </span>
                )}
                {intelligence?._built && !kfGenerating && (
                  <button onClick={() => {
                    setKfGenerating(true);
                    setTimeout(() => {
                      const bullets = intelligence.extractKeyFeatures?.() || [];
                      if (bullets.length) {
                        const text = bullets.join("\n");
                        setKeyFeaturesText(text);
                        saveModelDetails({ ...modelDetails, keyFeatures:text });
                      }
                      setKfGenerating(false);
                    }, 0);
                  }} style={{
                    display:"flex", alignItems:"center", gap:5, fontSize:11, fontWeight:600,
                    background:`${C.accent}15`, border:`1px solid ${C.accent}44`, borderRadius:6,
                    padding:"4px 10px", color:C.accent, cursor:"pointer", ...SANS,
                  }}>
                    <RefreshCw size={11}/> Regenerate
                  </button>
                )}
              </div>
              <textarea
                ref={kfRef}
                value={keyFeaturesText}
                onChange={e => setKeyFeaturesText(e.target.value)}
                onBlur={saveKeyFeatures}
                placeholder="Upload Enterprise Context docs — key features will be auto-extracted. Or type manually."
                style={{ width:"100%", boxSizing:"border-box", minHeight:90, resize:"none", overflow:"hidden",
                  background:C.bg, border:`1px solid ${C.border}`, borderRadius:8,
                  color:C.text, fontSize:12, padding:"10px 12px", lineHeight:1.6, outline:"none", ...SANS }}
                onFocus={e => e.target.style.borderColor = C.accent}
                onBlurCapture={e => e.target.style.borderColor = C.border}
              />
            </div>

            {/* Analysis Frameworks */}
            <div style={{ marginBottom:24 }}>
              <div style={{ display:"flex", alignItems:"center", gap:10, marginBottom:16 }}>
                <SquareStack size={18} style={{ color:"#7B1FA2" }}/>
                <div>
                  <div style={{ ...SANS, fontSize:15, fontWeight:700, color:C.text }}>Analysis Frameworks</div>
                  <div style={{ fontSize:12, color:C.textMuted }}>Select frameworks in scope — informs intelligence queries and threat model generation</div>
                </div>
              </div>
              <div style={{ display:"flex", flexDirection:"column", gap:14 }}>
                <div style={{ background:C.surface, border:`1px solid ${C.border}`, borderRadius:12, padding:"18px 20px" }}>
                  <div style={{ display:"flex", alignItems:"center", gap:8, marginBottom:14 }}>
                    <ClipboardList size={16} style={{ color:"#7B1FA2" }}/>
                    <span style={{ ...SANS, fontSize:13, fontWeight:700, color:C.text }}>Industry & Compliance Frameworks</span>
                    {(modelDetails?.frameworks?.length > 0) && (
                      <span style={{ fontSize:11, color:"#7B1FA2", background:"#7B1FA210", border:"1px solid #7B1FA244",
                        borderRadius:9, padding:"1px 7px", marginLeft:"auto" }}>
                        {modelDetails.frameworks.length} selected
                      </span>
                    )}
                  </div>
                  {renderFrameworkChips(INDUSTRY_FRAMEWORKS, modelDetails?.frameworks, fw => toggleFramework(fw, true), "#7B1FA2")}
                </div>
                <div style={{ background:C.surface, border:`1px solid ${C.border}`, borderRadius:12, padding:"18px 20px" }}>
                  <div style={{ display:"flex", alignItems:"center", gap:8, marginBottom:14 }}>
                    <Zap size={16} style={{ color:"#E65100" }}/>
                    <span style={{ ...SANS, fontSize:13, fontWeight:700, color:C.text }}>Threat Modeling Frameworks</span>
                    {(modelDetails?.threatFrameworks?.length > 0) && (
                      <span style={{ fontSize:11, color:"#E65100", background:"#E6510010", border:"1px solid #E6510044",
                        borderRadius:9, padding:"1px 7px", marginLeft:"auto" }}>
                        {modelDetails.threatFrameworks.length} selected
                      </span>
                    )}
                  </div>
                  {renderFrameworkChips(THREAT_FRAMEWORKS, modelDetails?.threatFrameworks, fw => toggleFramework(fw, false), "#E65100")}
                </div>
              </div>
            </div>

            {/* Architecture Context */}
            <details style={{ marginTop:8, marginBottom:32 }}>
              <summary style={{
                fontSize:14, fontWeight:700, color:C.text, cursor:"pointer",
                padding:"12px 0", borderTop:`1px solid ${C.border}`,
                listStyle:"none", display:"flex", alignItems:"center", gap:8, userSelect:"none",
              }}>Architecture Context (optional)</summary>

              {/* Narrative sub-section */}
              <div style={{ marginTop:16 }}>
                <div style={{ fontSize:12, color:C.textMuted, marginBottom:14, lineHeight:1.5 }}>
                  Architecture details are auto-populated from your Terraform files and uploaded docs.
                  Edit any field to refine the analysis context.
                </div>
                {/* Re-analyze + reset bar */}
                <div style={{ display:"flex", gap:8, marginBottom:16, alignItems:"center" }}>
                  {archAnalyzing && <Loader2 size={14} style={{ color:C.accent, animation:"spin 1s linear infinite" }}/>}
                  <button onClick={reanalyze} style={{
                    ...SANS, fontSize:12, fontWeight:600, padding:"6px 14px",
                    background:C.surface2, border:`1px solid ${C.border2}`, borderRadius:7,
                    color:C.textSub, cursor:"pointer", display:"flex", alignItems:"center", gap:5,
                  }}><RotateCcw size={12}/> Re-analyze</button>
                  <button onClick={resetOverrides} style={{
                    ...SANS, fontSize:12, fontWeight:600, padding:"6px 14px",
                    background:"transparent", border:`1px solid ${C.border}`, borderRadius:7,
                    color:C.textMuted, cursor:"pointer", display:"flex", alignItems:"center", gap:5,
                  }}><RefreshCw size={12}/> Reset edits</button>
                  {archAnalysis && (
                    <span style={{ fontSize:11, color:C.textMuted, marginLeft:4 }}>
                      Confidence: {archAnalysis.confidence}%
                    </span>
                  )}
                </div>

                {/* Attribute chip groups */}
                {ATTR_GROUPS.map(group => (
                  <div key={group.label} style={{ marginBottom:20 }}>
                    <div style={{ fontSize:11, color:C.textMuted, fontWeight:700, textTransform:"uppercase",
                      letterSpacing:".08em", marginBottom:12 }}>{group.label}</div>
                    <div style={{ display:"flex", flexDirection:"column", gap:10 }}>
                      {group.keys.map(attrKey => {
                        const chips = ATTR_CHIPS[attrKey] || [];
                        const selected = attrs[attrKey];
                        const selectedArr = Array.isArray(selected) ? selected : (selected ? [selected] : []);
                        return (
                          <div key={attrKey}>
                            <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:6 }}>
                              {ATTR_LABELS[attrKey] || attrKey}
                              {SINGLE_SELECT.includes(attrKey) && (
                                <span style={{ marginLeft:6, fontWeight:400, opacity:0.6 }}>(single)</span>
                              )}
                            </div>
                            <div style={{ display:"flex", flexWrap:"wrap", gap:5 }}>
                              {chips.map(chip => {
                                const active = selectedArr.includes(chip);
                                const isAISelected = (archAnalysis?.attributes?.[attrKey] || []).includes?.(chip) ||
                                  archAnalysis?.attributes?.[attrKey] === chip;
                                return (
                                  <button key={chip} onClick={() => toggleAttrChip(attrKey, chip)} style={{
                                    background: active ? `${C.accent}22` : "transparent",
                                    border: `1px solid ${active ? C.accent : C.border2}`,
                                    borderRadius:20, padding:"3px 10px", fontSize:11,
                                    color: active ? C.accent : C.textMuted, cursor:"pointer", ...SANS,
                                    position:"relative",
                                  }}>
                                    {chip}
                                    {isAISelected && !active && (
                                      <span style={{ position:"absolute", top:-3, right:-3, width:6, height:6,
                                        borderRadius:"50%", background:C.accent, opacity:0.7 }}/>
                                    )}
                                  </button>
                                );
                              })}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ))}

                {/* Narrative text fields */}
                <div style={{ fontSize:11, color:C.textMuted, fontWeight:700, textTransform:"uppercase",
                  letterSpacing:".08em", marginBottom:12, marginTop:8 }}>Narrative Sections</div>
                <div style={{ display:"flex", flexDirection:"column", gap:12 }}>
                  {NARRATIVE_FIELDS.map(({ key, label, Icon }) => (
                    <div key={key}>
                      <div style={{ fontSize:11, color:C.textMuted, fontWeight:600, marginBottom:5,
                        display:"flex", alignItems:"center", gap:5 }}>
                        <Icon size={12}/> {label}
                      </div>
                      <textarea
                        value={narrative[key] || ""}
                        onChange={e => saveNarrativeField(key, e.target.value)}
                        placeholder={`Describe ${label.toLowerCase()}…`}
                        rows={2}
                        style={{ width:"100%", boxSizing:"border-box", background:C.bg, border:`1px solid ${C.border2}`,
                          borderRadius:8, padding:"8px 12px", color:C.text, fontSize:12, ...SANS,
                          outline:"none", resize:"vertical", lineHeight:1.6 }}
                        onFocus={e => e.target.style.borderColor = C.accent}
                        onBlur={e => e.target.style.borderColor = C.border2}
                      />
                    </div>
                  ))}
                </div>
              </div>
            </details>

          </div>
        )}

        {/* ═══════════════════════════════════════════════════════════════════ */}
        {/* PRODUCT LAYERS TAB                                                  */}
        {/* ═══════════════════════════════════════════════════════════════════ */}
        {activeTab === "layers" && (
          <div style={{ padding:"28px 32px", maxWidth:720 }}>

            <div style={{ marginBottom:20 }}>
              <div style={{ ...SANS, fontSize:16, fontWeight:700, color:C.text, marginBottom:6 }}>
                Layer 6 — Product / Application Modules
              </div>
              <div style={{ fontSize:13, color:C.textSub, lineHeight:1.6, maxWidth:560 }}>
                Enter your product module names to enable Layer 6 detection in the architecture analysis.
                These names are matched against your repository folder structure to score the
                Product/Application layer of the 7-layer enterprise architecture model.
              </div>
            </div>

            {/* Guidance card */}
            <div style={{ background:`${C.accent}08`, border:`1px solid ${C.accent}22`, borderRadius:10,
              padding:"14px 16px", marginBottom:24 }}>
              <div style={{ display:"flex", alignItems:"flex-start", gap:10 }}>
                <Package size={16} style={{ color:C.accent, flexShrink:0, marginTop:1 }}/>
                <div>
                  <div style={{ ...SANS, fontSize:12, fontWeight:700, color:C.accent, marginBottom:4 }}>
                    How Layer 6 scoring works
                  </div>
                  <div style={{ fontSize:12, color:C.textSub, lineHeight:1.6 }}>
                    The architecture analyzer searches your .tf files and folder paths for names you provide here.
                    A match counts as Layer 6 (Product/Application) being present.
                    Example module names: <code style={{ fontFamily:"monospace", fontSize:11, color:C.accent }}>module-kinesis-analytics</code>,{" "}
                    <code style={{ fontFamily:"monospace", fontSize:11, color:C.accent }}>module-rds-cluster</code>
                  </div>
                </div>
              </div>
            </div>

            {/* ChipInput */}
            <div style={{ background:C.surface, border:`1px solid ${productModuleNames.length?C.accent+"55":C.border}`,
              borderRadius:12, padding:"20px 22px", marginBottom:20 }}>
              <div style={{ ...SANS, fontSize:13, fontWeight:700, color:C.text, marginBottom:4,
                display:"flex", alignItems:"center", gap:8 }}>
                <Package size={15}/>
                Product Module Names
                {productModuleNames.length > 0 && (
                  <span style={{ fontSize:10, fontWeight:700, color:C.accent, background:`${C.accent}18`,
                    border:`1px solid ${C.accent}44`, borderRadius:9, padding:"1px 7px" }}>
                    {productModuleNames.length}
                  </span>
                )}
              </div>
              <div style={{ fontSize:11, color:C.textMuted, marginBottom:14 }}>
                Comma-separated or press Enter after each name. Press Backspace to remove the last chip.
              </div>
              <ChipInput
                value={productModuleNames}
                onAdd={onAddProductModules}
                onRemove={onRemoveProductModule}
                placeholder="e.g. module-kinesis-analytics, module-rds-cluster"
              />
            </div>

            {/* Status chip when empty */}
            {productModuleNames.length === 0 && (
              <div style={{ padding:"12px 16px", background:C.surface, border:`1px solid ${C.border}`,
                borderRadius:8, fontSize:12, color:C.textMuted, display:"flex", gap:8, alignItems:"center" }}>
                <Layers size={14} style={{ opacity:0.5 }}/>
                No product modules configured — Layer 6 will be scored as absent until at least one module name is added.
              </div>
            )}

          </div>
        )}

      </div>

      {/* CSS for spinner keyframe */}
      <style>{`@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}
