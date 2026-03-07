/**
 * src/lib/ingestion/FileRouter.js
 * Routes any file type to the correct extractor.
 * All extractors are lazy-loaded to avoid bundle bloat.
 *
 * Usage:
 *   import { extractFile } from './FileRouter.js';
 *   const { text, metadata, tables, entities, codeBlocks } = await extractFile(file);
 */

import { ner, normalizeText } from '../llm/NLP.js';

/** Map of file extension → extractor loader */
const EXTRACTORS = {
  // Documents
  pdf:   () => import('./PDFExtractor.js').then(m => m.extractPDF),
  docx:  () => import('./DocxExtractor.js').then(m => m.extractDOCX),
  doc:   () => import('./DocxExtractor.js').then(m => m.extractDOCX),

  // Spreadsheets
  xlsx:  () => import('./SpreadsheetExtractor.js').then(m => ({ fn: m.extractSpreadsheet, passName: true })),
  xls:   () => import('./SpreadsheetExtractor.js').then(m => ({ fn: m.extractSpreadsheet, passName: true })),
  csv:   () => import('./SpreadsheetExtractor.js').then(m => ({ fn: m.extractSpreadsheet, passName: true })),

  // Presentations
  pptx:  () => import('./PresentationExtractor.js').then(m => m.extractPPTX),

  // Images
  png:   () => import('./ImageExtractor.js').then(m => m.extractImage),
  jpg:   () => import('./ImageExtractor.js').then(m => m.extractImage),
  jpeg:  () => import('./ImageExtractor.js').then(m => m.extractImage),
  tiff:  () => import('./ImageExtractor.js').then(m => m.extractImage),
  tif:   () => import('./ImageExtractor.js').then(m => m.extractImage),
  bmp:   () => import('./ImageExtractor.js').then(m => m.extractImage),

  // Audio / Video
  mp3:   () => import('./AudioExtractor.js').then(m => m.extractAudio),
  wav:   () => import('./AudioExtractor.js').then(m => m.extractAudio),
  m4a:   () => import('./AudioExtractor.js').then(m => m.extractAudio),
  mp4:   () => import('./AudioExtractor.js').then(m => m.extractAudio),
  webm:  () => import('./AudioExtractor.js').then(m => m.extractAudio),
  ogg:   () => import('./AudioExtractor.js').then(m => m.extractAudio),

  // CloudFormation (virtual extension, resolved by content sniff or .cfn.json)
  cfnjson: () => import('../iac/CFNParser.js').then(m =>
    async (text, filename) => {
      const { resources, gaps } = m.extractCFNResources(text, filename);
      return {
        text: resources.map(r =>
          `[CFN Resource: ${r.type} "${r.name}"]\n${r.body}`
        ).join('\n\n'),
        metadata: {
          type:          'cfn',
          resourceCount: resources.length,
          gaps,
        },
        tables:       [],
        codeBlocks:   [],
        cfnResources: resources,  // pass-through for parseCFNFiles() caller
      };
    }
  ),

  // Structured data
  json:  () => import('./StructuredExtractor.js').then(m => m.extractJSON),
  yaml:  () => import('./StructuredExtractor.js').then(m => m.extractYAML),
  yml:   () => import('./StructuredExtractor.js').then(m => m.extractYAML),
  tf:    () => import('./StructuredExtractor.js').then(m => m.extractHCL),
  hcl:   () => import('./StructuredExtractor.js').then(m => m.extractHCL),
  xml:   () => import('./StructuredExtractor.js').then(m => m.extractXML),

  // Markup
  html:  () => import('./MarkupExtractor.js').then(m => m.extractHTML),
  htm:   () => import('./MarkupExtractor.js').then(m => m.extractHTML),
  md:    () => import('./MarkupExtractor.js').then(m => m.extractMarkdown),
  rst:   () => import('./MarkupExtractor.js').then(m => m.extractRST),

  // Plain text fallback (also handles .tf files that are text)
  txt:   () => Promise.resolve(text => ({ text, metadata: { type: 'txt' }, tables: [], codeBlocks: [] })),
  log:   () => Promise.resolve(text => ({ text, metadata: { type: 'log' }, tables: [], codeBlocks: [] })),
};

/** Regex to detect CloudFormation signature in JSON content */
const CFN_SIGNATURE_RE = /"AWSTemplateFormatVersion"|"Resources"\s*:\s*\{[\s\S]{1,500}"AWS::/;

/**
 * Extract text and metadata from any file.
 *
 * @param {File|{ name: string, arrayBuffer: Function, text: Function, type?: string }} file
 * @param {object} [opts]
 * @param {boolean} [opts.runNER=true]   Run SecurityNER on extracted text
 * @returns {Promise<{
 *   text:       string,
 *   metadata:   object,
 *   tables:     Array<{headers, rows}>,
 *   codeBlocks: Array<{lang, code}>,
 *   entities:   Array<{type, value, start, end, confidence}>,
 * }>}
 */
export async function extractFile(file, { runNER = true } = {}) {
  const filename = file.name ?? 'unknown';
  const ext      = filename.split('.').pop()?.toLowerCase() ?? 'txt';

  // ── CloudFormation content sniffing ──────────────────────────────────────
  // .cfn.json is explicit; plain .json files get a 2KB content peek
  let effectiveExt = ext;
  if (ext === 'json') {
    if (filename.toLowerCase().endsWith('.cfn.json')) {
      effectiveExt = 'cfnjson';
    } else {
      try {
        // Peek first 2KB without reading the whole file
        const peek = await (file.slice ? file.slice(0, 2048).text() : file.text());
        if (CFN_SIGNATURE_RE.test(peek)) {
          effectiveExt = 'cfnjson';
        }
      } catch { /* fall through to normal JSON handling */ }
    }
  }

  const loader = EXTRACTORS[effectiveExt] ?? EXTRACTORS['txt'];

  let result;

  try {
    const resolved = await loader();
    let extractor;
    let passName = false;

    if (typeof resolved === 'object' && resolved.fn) {
      extractor = resolved.fn;
      passName  = resolved.passName;
    } else {
      extractor = resolved;
    }

    // Determine input: text extractors need string, others take ArrayBuffer or File
    const isTextBased = ['json', 'yaml', 'yml', 'hcl', 'tf', 'xml', 'html',
                          'htm', 'md', 'rst', 'txt', 'log', 'csv',
                          'cfnjson'].includes(effectiveExt);

    let input;
    if (isTextBased) {
      input = await file.text();
    } else if (passName) {
      input = await file.arrayBuffer();
    } else {
      input = file; // Pass File object directly (PDF, Image, Audio accept File)
    }

    result = passName
      ? await extractor(input, filename)
      : await extractor(input, filename);  // cfnjson extractor needs filename for paveLayer

  } catch (err) {
    console.warn(`[FileRouter] Extraction failed for ${filename}:`, err);
    result = {
      text:       `[Extraction failed: ${err.message}]`,
      metadata:   { type: effectiveExt, error: err.message },
      tables:     [],
      codeBlocks: [],
    };
  }

  // Normalise text
  result.text = normalizeText(result.text ?? '');

  // Add filename to metadata
  result.metadata = { filename, ...result.metadata };

  // Run NER
  result.entities = runNER ? ner.extract(result.text).entities : [];

  return result;
}

/**
 * Check if a file type is supported.
 * @param {string} filename
 * @returns {boolean}
 */
export function isSupported(filename) {
  const ext = filename.split('.').pop()?.toLowerCase() ?? '';
  if (ext === 'json') return true;  // json is always supported (may be cfnjson)
  return ext in EXTRACTORS;
}
