/**
 * create.js – create / edit post page logic.
 */
async function initCreate() {
  await renderNav();
  const user = await getCurrentUser();
  if (!user) { window.location.href = 'signin.html'; return; }

  // Live markdown preview
  const contentEl  = document.getElementById('content');
  const previewEl  = document.getElementById('preview');
  const titleEl    = document.getElementById('title');

  function updatePreview() {
    previewEl.innerHTML = renderMarkdown(contentEl.value);
  }

  contentEl.addEventListener('input', updatePreview);
  updatePreview();

  // Form submit
  document.getElementById('create-form').addEventListener('submit', async e => {
    e.preventDefault();
    hideAlert('alert');

    const title   = titleEl.value.trim();
    const content = contentEl.value.trim();
    const tags    = parseTags(document.getElementById('tags').value);
    const btn     = document.getElementById('btn-publish');

    if (!title)   { showAlert('alert', 'Title is required.', 'error'); return; }
    if (!content) { showAlert('alert', 'Content is required.', 'error'); return; }

    btn.disabled    = true;
    btn.textContent = 'Publishing…';

    try {
      const post = await databases.createDocument(
        APPWRITE_DB_ID,
        COL_POSTS,
        ID.unique(),
        {
          title,
          content,
          tags,
          authorId:   user.$id,
          authorName: user.name,
        }
      );
      window.location.href = `post.html?id=${post.$id}`;
    } catch (err) {
      showAlert('alert', err.message || 'Could not publish post.', 'error');
      btn.disabled    = false;
      btn.textContent = 'Publish';
    }
  });
}

document.addEventListener('DOMContentLoaded', initCreate);
