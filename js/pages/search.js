/**
 * search.js – search page logic.
 */
async function initSearch() {
  await renderNav();

  const q   = getParam('q')   || '';
  const tag = getParam('tag') || '';

  if (q)   document.getElementById('q').value = q;
  if (tag) document.getElementById('q').value = '#' + tag;

  document.getElementById('search-form').addEventListener('submit', e => {
    e.preventDefault();
    doSearch();
  });

  if (q || tag) doSearch();
}

async function doSearch() {
  const raw = document.getElementById('q').value.trim();
  if (!raw) return;

  const container = document.getElementById('results');
  container.innerHTML = '<div class="loading">Searching…</div>';

  // Update URL without reload
  const url = new URL(window.location.href);
  url.searchParams.set('q', raw);
  url.searchParams.delete('tag');
  window.history.replaceState(null, '', url.toString());

  try {
    let postDocs, userDocs;

    // Tag search (#hashtag)
    if (raw.startsWith('#')) {
      const tagVal = raw.slice(1).toLowerCase();
      [postDocs, userDocs] = await Promise.all([
        databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
          Query.search('tags', tagVal),
          Query.orderDesc('$createdAt'),
          Query.limit(30),
        ]),
        Promise.resolve({ documents: [] }),
      ]);
    } else {
      // Full-text search on title + username
      [postDocs, userDocs] = await Promise.all([
        databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
          Query.search('title', raw),
          Query.orderDesc('$createdAt'),
          Query.limit(20),
        ]),
        databases.listDocuments(APPWRITE_DB_ID, COL_USERS, [
          Query.search('username', raw),
          Query.limit(10),
        ]),
      ]);
    }

    let html = '';

    if (userDocs.documents.length > 0) {
      html += `<h3 class="section-heading">People</h3>`;
      html += userDocs.documents
        .map(u => renderTemplate('tpl-user-result', {
          id:       u.userId,
          username: u.username,
          bio:      u.bio || '',
          initial:  (u.username || '?')[0].toUpperCase(),
        }))
        .join('');
    }

    if (postDocs.documents.length > 0) {
      html += `<h3 class="section-heading" style="margin-top:${userDocs.documents.length ? 20 : 0}px">Posts</h3>`;
      html += postDocs.documents
        .map(post => renderTemplate('tpl-post-result', {
          id:         post.$id,
          title:      post.title,
          authorId:   post.authorId,
          authorName: post.authorName,
          excerpt:    excerpt(post.content),
          tags:       (post.tags || []),
          timeAgo:    timeAgo(post.$createdAt),
        }))
        .join('');
    }

    if (!html) {
      html = `<div class="empty-state"><p>No results found for "<strong>${escapeHtml(raw)}</strong>".</p></div>`;
    }

    container.innerHTML = html;
  } catch (err) {
    container.innerHTML = `<div class="empty-state"><p>Search failed. Ensure full-text indexes are set up in Appwrite.</p></div>`;
    console.error(err);
  }
}

document.addEventListener('DOMContentLoaded', initSearch);
