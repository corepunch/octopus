/**
 * Shared utilities used across multiple pages.
 */

/**
 * Escape a string for safe HTML insertion.
 */
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Returns a human-friendly "time ago" string from an ISO date string.
 */
function timeAgo(dateStr) {
  const now  = Date.now();
  const then = new Date(dateStr).getTime();
  const diff = Math.floor((now - then) / 1000);

  if (diff < 60)    return `${diff}s ago`;
  if (diff < 3600)  return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

/**
 * Render markdown to sanitised HTML using Marked.
 */
function renderMarkdown(md) {
  if (typeof marked === 'undefined') return escapeHtml(md);
  return marked.parse(md || '');
}

/**
 * Truncate text to `maxLen` characters, appending "…" if cut.
 */
function excerpt(text, maxLen) {
  maxLen = maxLen || 160;
  const clean = text.replace(/[#*`_~[\]()!|]/g, '').trim();
  return clean.length > maxLen ? clean.slice(0, maxLen) + '…' : clean;
}

/**
 * Parse a query-string parameter by name from the current URL.
 */
function getParam(name) {
  return new URLSearchParams(window.location.search).get(name);
}

/**
 * Show an alert element with a message.
 * @param {string} id   – element id
 * @param {string} msg  – message text
 * @param {string} type – 'error' | 'success' | 'info'
 */
function showAlert(id, msg, type) {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = `alert alert-${type || 'error'} show`;
  el.textContent = msg;
}

/**
 * Hide an alert element.
 */
function hideAlert(id) {
  const el = document.getElementById(id);
  if (el) el.className = 'alert';
}

/**
 * Compile and render a Handlebars template embedded in the page.
 * @param {string} templateId – id of the <script type="text/x-handlebars-template"> element
 * @param {object} data       – context data
 * @returns {string} rendered HTML
 */
function renderTemplate(templateId, data) {
  const src = document.getElementById(templateId);
  if (!src) return '';
  const template = Handlebars.compile(src.innerHTML);
  return template(data);
}

/**
 * Safely parse comma-separated tags from a string input.
 */
function parseTags(str) {
  return (str || '')
    .split(',')
    .map(t => t.trim().toLowerCase().replace(/\s+/g, '-'))
    .filter(t => t.length > 0)
    .slice(0, 10);
}

// ── Handlebars helpers ────────────────────────────────────────────────────────
// These let templates call helpers directly, e.g. {{timeAgo createdAt}}
// instead of requiring pre-computed values to be passed from JS.

/** {{timeAgo isoDateString}} → "3h ago" */
Handlebars.registerHelper('timeAgo', (date) => timeAgo(date));

/** {{excerpt content}} → stripped, truncated plain text */
Handlebars.registerHelper('excerpt', (text) => excerpt(text));

/** {{initial name}} → first character, uppercased */
Handlebars.registerHelper('initial', (name) => (name?.[0] || '?').toUpperCase());

/** {{urlEncode str}} → URI-encoded value safe for query strings */
Handlebars.registerHelper('urlEncode', (str) => encodeURIComponent(str));

/** {{markdown content}} → rendered HTML (SafeString, not double-escaped) */
Handlebars.registerHelper('markdown', (text) =>
  new Handlebars.SafeString(renderMarkdown(text))
);

