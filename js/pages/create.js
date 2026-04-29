/**
 * create.js – create post page logic (multi-type: text, photo, quote, link).
 */
let createPostType = 'text';

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
  <li>Title is optional for photo posts</li>
</ul>`,
  quote: `<h3>Quote Tips</h3>
<ul class="tip-list">
  <li>Keep the quote concise and punchy</li>
  <li>Add the source: a person, book, or URL</li>
  <li>Title is optional for quote posts</li>
</ul>`,
  link: `<h3>Link Tips</h3>
<ul class="tip-list">
  <li>Paste the full URL including https://</li>
  <li>Add a title to give context</li>
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

  // ── Live markdown preview (text post only) ───────────────────────────────
  const contentEl = document.getElementById('content');
  const previewEl = document.getElementById('preview');

  function updatePreview() {
    previewEl.innerHTML = renderMarkdown(contentEl.value);
  }
  contentEl.addEventListener('input', updatePreview);
  updatePreview();

  // ── Photo preview ────────────────────────────────────────────────────────
  document.getElementById('photo-file').addEventListener('change', function () {
    const file = this.files[0];
    if (!file) return;
    const wrap = document.getElementById('photo-preview-wrap');
    const img  = document.getElementById('photo-preview-img');
    const url  = URL.createObjectURL(file);
    img.src    = url;
    wrap.style.display = 'block';
  });

  // ── Form submit ──────────────────────────────────────────────────────────
  document.getElementById('create-form').addEventListener('submit', async e => {
    e.preventDefault();
    hideAlert('alert');

    const tags = parseTags(document.getElementById('tags').value);
    const btn  = document.getElementById('btn-publish');
    btn.disabled    = true;
    btn.textContent = 'Publishing…';

    try {
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
        const title     = document.getElementById('title').value.trim();
        if (!fileInput.files[0]) { showAlert('alert', 'Please choose an image.', 'error'); return; }

        showAlert('alert', 'Compressing and uploading image…', 'info');
        const compressed = await compressImage(fileInput.files[0]);
        const uploaded   = await storage.createFile(APPWRITE_BUCKET_ID, ID.unique(), compressed);
        docData.imageId  = uploaded.$id;
        docData.title    = title || 'Photo';
        docData.content  = caption;

      } else if (createPostType === 'quote') {
        const quoteText   = document.getElementById('quote-text').value.trim();
        const quoteSource = document.getElementById('quote-source').value.trim();
        const title       = document.getElementById('title').value.trim();
        if (!quoteText) { showAlert('alert', 'Quote text is required.', 'error'); return; }
        docData.title       = title || quoteText.slice(0, 80);
        docData.content     = quoteText;
        docData.quoteSource = quoteSource;

      } else if (createPostType === 'link') {
        const linkUrl = document.getElementById('link-url').value.trim();
        const desc    = document.getElementById('link-desc').value.trim();
        const title   = document.getElementById('title').value.trim();
        if (!linkUrl) { showAlert('alert', 'URL is required.', 'error'); return; }
        docData.title   = title || linkUrl;
        docData.content = desc;
        docData.linkUrl = linkUrl;
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

  // Update picker button states
  document.querySelectorAll('.post-type-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.type === type);
  });

  // Show/hide form sections
  ['text', 'photo', 'quote', 'link'].forEach(t => {
    const el = document.getElementById('section-' + t);
    if (el) el.style.display = (t === type) ? '' : 'none';
  });

  // Show/hide title field (always visible but labelled differently)
  const titleLabel = document.querySelector('#field-title label');
  if (titleLabel) {
    titleLabel.textContent = (type === 'photo' || type === 'quote')
      ? 'Title (optional)'
      : type === 'link' ? 'Title' : 'Title';
  }

  // Update sidebar tips
  const tips = document.getElementById('type-tips');
  if (tips) tips.innerHTML = TYPE_TIPS[type] || TYPE_TIPS.text;
}

document.addEventListener('DOMContentLoaded', initCreate);

