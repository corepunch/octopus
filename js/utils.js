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
 * Render markdown to safe HTML.
 * Uses DOMPurify to sanitize the output when available, preventing XSS from
 * user-generated content that contains raw HTML inside the markdown source.
 */
function renderMarkdown(md) {
  const source = md || '';
  if (typeof marked === 'undefined') return escapeHtml(source);
  const rawHtml = marked.parse(source);
  if (typeof DOMPurify !== 'undefined') return DOMPurify.sanitize(rawHtml);
  return rawHtml;
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
 * Render a registered Handlebars partial by name.
 * All templates are registered in js/templates.js via Handlebars.registerPartial().
 * @param {string} name – partial name (e.g. 'post-card')
 * @param {object} data – context data passed to the template
 * @returns {string} rendered HTML
 */
function renderTemplate(name, data) {
  const fn = Handlebars.partials[name];
  if (typeof fn !== 'function') {
    console.error(`Template "${name}" not registered. Check js/templates.js.`);
    return '';
  }
  return fn(data);
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

/**
 * {{icon "name"}} → inline SVG string (SafeString, sourced from ICONS in icons.js).
 * Always use this helper for icons inside templates instead of hard-coding SVG.
 * Example: {{icon "pen-line"}} New Post
 */
Handlebars.registerHelper('icon', (name) =>
  new Handlebars.SafeString((typeof ICONS !== 'undefined' && ICONS[name]) || '')
);

/**
 * Return an icon SVG followed by a space and the given label text.
 * Convenience wrapper used in JS (not Handlebars) to keep button HTML concise.
 * @param {string} name  – icon key from ICONS
 * @param {string} label – visible button label
 * @returns {string} safe HTML string – icon is always from ICONS (never user input)
 */
function iconLabel(name, label) {
  const svg = (typeof ICONS !== 'undefined' && ICONS[name]) || '';
  return svg + ' ' + escapeHtml(label);
}

/**
 * Return just the icon SVG for icon-only controls.
 * @param {string} name – icon key from ICONS
 * @returns {string} safe HTML string – icon is always from ICONS
 */
function iconOnly(name) {
  return (typeof ICONS !== 'undefined' && ICONS[name]) || '';
}

/** {{eq a b}} → true if a === b (used for post-type conditionals) */
Handlebars.registerHelper('eq', (a, b) => a === b);

/**
 * Validate a URL and return it only if it uses http or https.
 * Returns an empty string for any other scheme (javascript:, data:, etc.)
 * to prevent stored XSS via link posts.
 * @param {string} url
 * @returns {string}
 */
function sanitizeUrl(url) {
  if (!url) return '';
  try {
    const u = new URL(url);
    return (u.protocol === 'http:' || u.protocol === 'https:') ? url : '';
  } catch {
    return '';
  }
}

/** {{safeUrl url}} → the URL if http/https, empty string otherwise */
Handlebars.registerHelper('safeUrl', (url) => sanitizeUrl(url));

/**
 * Return the public view URL for an Appwrite Storage file.
 * @param {string} fileId – Appwrite Storage file $id
 * @returns {string} absolute URL to view the file
 */
function getImageUrl(fileId) {
  if (!fileId) return '';
  return `${APPWRITE_ENDPOINT}/storage/buckets/${APPWRITE_BUCKET_ID}/files/${fileId}/view?project=${APPWRITE_PROJECT_ID}`;
}

/**
 * Compress an image File to JPEG at ~30% quality.
 * Downscales so neither dimension exceeds 1200 px.
 * @param {File} file
 * @returns {Promise<File>} compressed JPEG File
 */
function compressImage(file) {
  return new Promise(function (resolve, reject) {
    var reader = new FileReader();
    reader.onerror = reject;
    reader.onload = function (e) {
      var img = new Image();
      img.onerror = reject;
      img.onload = function () {
        var MAX = 1200;
        var w = img.width, h = img.height;
        if (w > MAX || h > MAX) {
          if (w > h) { h = Math.round(h * MAX / w); w = MAX; }
          else       { w = Math.round(w * MAX / h); h = MAX; }
        }
        var canvas = document.createElement('canvas');
        canvas.width  = w;
        canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0, w, h);
        canvas.toBlob(function (blob) {
          if (blob) resolve(new File([blob], 'image.jpg', { type: 'image/jpeg' }));
          else      reject(new Error('Image compression failed'));
        }, 'image/jpeg', 0.30);
      };
      img.src = e.target.result;
    };
    reader.readAsDataURL(file);
  });
}

/**
 * Share a post using the Web Share API when available, falling back to
 * writing the post URL to the clipboard.
 *
 * @param {string} id    – post document $id
 * @param {string} title – post title (used as share title)
 */
function sharePost(id, title) {
  const url = new URL('post.html?id=' + encodeURIComponent(id), window.location.href).href;
  if (navigator.share) {
    navigator.share({ title: title || 'Octopus post', url }).catch(() => {});
  } else if (navigator.clipboard) {
    navigator.clipboard.writeText(url).catch(() => {});
  }
}

// Global click delegation for share buttons rendered inside dynamic templates.
document.addEventListener('click', function (e) {
  const btn = e.target.closest('[data-share-id]');
  if (btn) sharePost(btn.dataset.shareId, btn.dataset.shareTitle);
});
