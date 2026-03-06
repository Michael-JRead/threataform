/**
 * src/lib/ingestion/PDFExtractor.js
 * Extracts text from PDF files using pdfjs-dist.
 * Load order: (1) npm pdfjs-dist, (2) esm.sh CDN fallback.
 */

const PDF_CDN = 'https://esm.sh/pdfjs-dist@3.11.174';
const PDF_WORKER_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/{ver}/pdf.worker.min.js';

let pdfjsLib = null;

async function getPDFJS() {
  if (!pdfjsLib) {
    // 1. Try installed npm package
    try {
      pdfjsLib = await import(/* @vite-ignore */ 'pdfjs-dist');
    } catch {
      // 2. CDN ESM fallback (no npm required)
      try {
        pdfjsLib = await import(/* @vite-ignore */ PDF_CDN);
      } catch {
        throw new Error('PDF extraction unavailable. Install pdfjs-dist or check internet access.');
      }
    }
    // Set worker (always use CDN worker matching version)
    if (typeof window !== 'undefined') {
      const ver = pdfjsLib.version ?? '3.11.174';
      pdfjsLib.GlobalWorkerOptions.workerSrc =
        PDF_WORKER_CDN.replace('{ver}', ver);
    }
  }
  return pdfjsLib;
}

/**
 * Extract text from a PDF file.
 * @param {ArrayBuffer|File} input
 * @param {object}           [opts]
 * @param {number}           [opts.maxPages=200]
 * @returns {Promise<{ text, metadata, tables, codeBlocks }>}
 */
export async function extractPDF(input, { maxPages = 200 } = {}) {
  const pdfjs       = await getPDFJS();
  const arrayBuffer = input instanceof ArrayBuffer ? input : await input.arrayBuffer();
  const pdf         = await pdfjs.getDocument({ data: arrayBuffer }).promise;
  const numPages    = Math.min(pdf.numPages, maxPages);

  const pageTexts = [];
  const tables    = [];

  for (let p = 1; p <= numPages; p++) {
    const page    = await pdf.getPage(p);
    const content = await page.getTextContent();

    // Group items by approximate Y position (rows)
    const byY = new Map();
    for (const item of content.items) {
      const y   = Math.round(item.transform[5] / 10) * 10;
      const row = byY.get(y) ?? [];
      row.push({ x: item.transform[4], text: item.str });
      byY.set(y, row);
    }

    const rows = Array.from(byY.entries())
      .sort(([ya], [yb]) => yb - ya)
      .map(([, items]) => items.sort((a, b) => a.x - b.x).map(i => i.text).join(' '));

    let tableBuffer = [];
    for (const row of rows) {
      if (_isTableRow(row)) {
        tableBuffer.push(row.split(/\s{3,}/).filter(Boolean));
      } else {
        if (tableBuffer.length >= 2) {
          tables.push({ headers: tableBuffer[0], rows: tableBuffer.slice(1) });
          tableBuffer = [];
        }
        pageTexts.push(row);
      }
    }
    if (tableBuffer.length >= 2) {
      tables.push({ headers: tableBuffer[0], rows: tableBuffer.slice(1) });
    }
  }

  const metadata = { type: 'pdf', pages: pdf.numPages };
  try {
    const info = await pdf.getMetadata();
    Object.assign(metadata, {
      title:   info.info?.Title ?? '',
      author:  info.info?.Author ?? '',
      subject: info.info?.Subject ?? '',
    });
  } catch { /* metadata optional */ }

  return {
    text:       pageTexts.join('\n').replace(/\n{3,}/g, '\n\n').trim(),
    metadata,
    tables,
    codeBlocks: [],
  };
}

function _isTableRow(row) {
  return /\s{3,}/.test(row) && row.trim().length > 10;
}
