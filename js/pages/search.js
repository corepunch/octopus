/**
 * search.js – search page logic.
 * All HTML is rendered by Handlebars partials registered in js/templates.js.
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

  const url = new URL(window.location.href);
  url.searchParams.set('q', raw);
  url.searchParams.delete('tag');
  window.history.replaceState(null, '', url.toString());

  try {
    let postDocs, userDocs;

    if (raw.startsWith('#')) {
      const tagVal = raw.slice(1).toLowerCase();
      [postDocs, userDocs] = await Promise.all([
        // tags is a key-indexed array field; Query.equal checks for containment.
        databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
          Query.equal('tags', tagVal),
          Query.orderDesc('$createdAt'),
          Query.limit(30),
        ]),
        Promise.resolve({ documents: [] }),
      ]);
    } else {
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
      html += renderTemplate('section-heading', { title: 'People' });
      html += userDocs.documents
        .map(u => renderTemplate('user-result', {
          id:       u.userId,
          username: u.username,
          bio:      u.bio || '',
        }))
        .join('');
    }

    if (postDocs.documents.length > 0) {
      html += renderTemplate('section-heading', { title: 'Posts' });
      html += postDocs.documents
        .map(post => renderTemplate('post-card', {
          id:          post.$id,
          title:       post.title,
          authorId:    post.authorId,
          authorName:  post.authorName,
          content:     post.content,
          tags:        post.tags || [],
          createdAt:   post.$createdAt,
          postType:    post.postType || 'text',
          imageUrl:    post.imageId ? getImageUrl(post.imageId) : '',
          linkUrl:     post.linkUrl || '',
          quoteSource: post.quoteSource || '',
        }))
        .join('');
    }

    if (!html) {
      html = renderTemplate('no-results', { query: raw });
    }

    container.innerHTML = html;
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>Search failed. Ensure full-text indexes are set up in Appwrite.</p></div>';
    console.error(err);
  }
}

document.addEventListener('DOMContentLoaded', initSearch);
