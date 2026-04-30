/**
 * create.js – create post page logic (multi-type: text, photo, quote, link).
 */
let createPostType = 'text';

// Track the current photo preview object URL so it can be revoked when replaced.
let photoPreviewUrl = null;

// Sidebar tip copy per post type
const TYPE_TIPS = {
  text: `<h3>Writing Tips</h3>
<ul class="tip-list">
  <li>Use <strong>**bold**</strong> or <em>*italic*</em></li>
  <li>Add headings with <strong>#</strong></li>
  <li>Link with <strong>[text](url)</strong></li>
  <li>Code blocks with <strong>\`\`\`</strong></li>
</ul>`,
  photo: `<h3>Photo Tips</h3>
<ul class="tip-list">
  <li>Images are compressed to JPEG at 30% quality</li>
  <li>Max dimension: 1200 px</li>
  <li>Add an optional caption below the image</li>
</ul>`,
  quote: `<h3>Quote Tips</h3>
<ul class="tip-list">
  <li>Keep the quote concise and punchy</li>
  <li>Add the source: a person, book, or URL</li>
  <li>Share your own opinion in "Your thoughts"</li>
</ul>`,
  link: `<h3>Link Tips</h3>
<ul class="tip-list">
  <li>Paste the full URL including https://</li>
  <li>Use the description to explain why it matters</li>
</ul>`,
};

async function initCreate() {
  await renderNav();
  const user = await getCurrentUser();
  if (!user) { window.location.href = 'signin.html'; return; }

  // ── Type picker ──────────────────────────────────────────────────────────
  document.querySelectorAll('.post-type-btn').forEach(btn => {
    btn.addEventListener('click', () => switchType(btn.dataset.type));
  });

  // ── Write / Preview tabs ─────────────────────────────────────────────────
  const contentEl    = document.getElementById('content');
  const writePaneEl  = document.getElementById('md-write-pane');
  const previewPaneEl = document.getElementById('md-preview-pane');
  const tabWrite     = document.getElementById('tab-write');
  const tabPreview   = document.getElementById('tab-preview');

  function updatePreview() {
    previewPaneEl.innerHTML = renderMarkdown(contentEl.value);
  }

  tabWrite.addEventListener('click', () => {
    tabWrite.classList.add('active');
    tabWrite.setAttribute('aria-selected', 'true');
    tabPreview.classList.remove('active');
    tabPreview.setAttribute('aria-selected', 'false');
    writePaneEl.style.display = 'block';
    previewPaneEl.style.display = 'none';
    contentEl.focus();
  });

  tabPreview.addEventListener('click', () => {
    updatePreview();
    tabPreview.classList.add('active');
    tabPreview.setAttribute('aria-selected', 'true');
    tabWrite.classList.remove('active');
    tabWrite.setAttribute('aria-selected', 'false');
    previewPaneEl.style.display = 'block';
    writePaneEl.style.display = 'none';
  });

  // ── Photo preview (revoke previous object URL to avoid memory leaks) ─────
  document.getElementById('photo-file').addEventListener('change', function () {
    const file = this.files[0];
    if (!file) return;
    if (photoPreviewUrl) {
      URL.revokeObjectURL(photoPreviewUrl);
    }
    photoPreviewUrl = URL.createObjectURL(file);
    const wrap = document.getElementById('photo-preview-wrap');
    const imgEl = document.getElementById('photo-preview-img');
    imgEl.src = photoPreviewUrl;
    wrap.style.display = 'block';
  });

  // ── Initialise form for the default type ─────────────────────────────────
  switchType(createPostType);

  // ── Form submit ──────────────────────────────────────────────────────────
  document.getElementById('create-form').addEventListener('submit', async e => {
    e.preventDefault();
    hideAlert('alert');

    const tags = parseTags(document.getElementById('tags').value);
    const btn  = document.getElementById('btn-publish');

    // ── Validate first; button is not disabled until validation passes ───
    let docData = { tags, authorId: user.$id, authorName: user.name, postType: createPostType };

    if (createPostType === 'text') {
      const title   = document.getElementById('title').value.trim();
      const content = contentEl.value.trim();
      if (!title)   { showAlert('alert', 'Title is required.', 'error'); return; }
      if (!content) { showAlert('alert', 'Content is required.', 'error'); return; }
      docData.title   = title;
      docData.content = content;

    } else if (createPostType === 'photo') {
      const fileInput = document.getElementById('photo-file');
      const caption   = document.getElementById('photo-caption').value.trim();
      if (!fileInput.files[0]) { showAlert('alert', 'Please choose an image.', 'error'); return; }
      docData.content = caption;

    } else if (createPostType === 'quote') {
      const quoteText   = document.getElementById('quote-text').value.trim();
      const quoteSource = document.getElementById('quote-source').value.trim();
      const userText    = document.getElementById('quote-user-text').value.trim();
      if (!quoteText) { showAlert('alert', 'Quote text is required.', 'error'); return; }
      docData.content     = quoteText;
      docData.quoteSource = quoteSource;
      if (userText) docData.userText = userText;

    } else if (createPostType === 'link') {
      const linkUrl = document.getElementById('link-url').value.trim();
      const desc    = document.getElementById('link-desc').value.trim();
      if (!linkUrl) { showAlert('alert', 'URL is required.', 'error'); return; }
      // Require http/https to prevent javascript: or data: XSS
      if (!sanitizeUrl(linkUrl)) {
        showAlert('alert', 'URL must start with http:// or https://', 'error');
        return;
      }
      docData.content = desc;
      docData.linkUrl = linkUrl;
    }

    // ── All validation passed – disable button and publish ───────────────
    btn.disabled    = true;
    btn.textContent = 'Publishing…';

    try {
      if (createPostType === 'photo') {
        showAlert('alert', 'Compressing and uploading image…', 'info');
        const fileInput  = document.getElementById('photo-file');
        const compressed = await compressImage(fileInput.files[0]);
        const uploaded   = await storage.createFile(APPWRITE_BUCKET_ID, ID.unique(), compressed);
        docData.imageId  = uploaded.$id;
      }

      hideAlert('alert');
      const post = await databases.createDocument(APPWRITE_DB_ID, COL_POSTS, ID.unique(), docData);
      window.location.href = `post.html?id=${post.$id}`;
    } catch (err) {
      showAlert('alert', err.message || 'Could not publish post.', 'error');
      btn.disabled    = false;
      btn.textContent = 'Publish';
    }
  });
}

function switchType(type) {
  createPostType = type;

  // Revoke photo preview URL when switching away from photo type
  if (type !== 'photo' && photoPreviewUrl) {
    URL.revokeObjectURL(photoPreviewUrl);
    photoPreviewUrl = null;
    const wrap = document.getElementById('photo-preview-wrap');
    if (wrap) wrap.style.display = 'none';
  }

  // Update picker button states
  document.querySelectorAll('.post-type-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.type === type);
  });

  // Show/hide form sections
  ['text', 'photo', 'quote', 'link'].forEach(t => {
    const el = document.getElementById('section-' + t);
    if (el) el.style.display = (t === type) ? '' : 'none';
  });

  // Show/hide title field (only for text posts)
  const titleField = document.getElementById('field-title');
  if (titleField) {
    titleField.style.display = (type === 'text') ? '' : 'none';
  }

  // Update sidebar tips
  const tips = document.getElementById('type-tips');
  if (tips) tips.innerHTML = TYPE_TIPS[type] || TYPE_TIPS.text;
}

document.addEventListener('DOMContentLoaded', initCreate);

