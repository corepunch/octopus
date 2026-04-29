/**
 * index.js – main feed page logic.
 * All HTML is rendered by Handlebars partials registered in js/templates.js.
 */
let currentUser = null;
let activeTab   = 'discover';

async function initFeed() {
  await renderNav();
  currentUser = await getCurrentUser();
  renderSidebarUser();

  // Wire up feed tab buttons via data attributes + addEventListener
  document.querySelectorAll('.feed-tab').forEach(btn => {
    btn.addEventListener('click', () => loadPosts(btn.dataset.tab));
  });

  loadPosts(activeTab);
}

function renderSidebarUser() {
  const el = document.getElementById('sidebar-user');
  if (!el) return;
  if (currentUser) {
    el.innerHTML = renderTemplate('user-widget', {
      name: currentUser.name,
      id:   currentUser.$id,
    });
    const signOutBtn = document.getElementById('sidebar-sign-out');
    if (signOutBtn) {
      signOutBtn.addEventListener('click', () => logout());
    }
  } else {
    el.innerHTML = renderTemplate('guest-widget', {});
  }
}

async function loadPosts(tab) {
  activeTab = tab;
  document.querySelectorAll('.feed-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));

  const container = document.getElementById('posts');
  container.innerHTML = '<div class="loading">Loading posts…</div>';

  try {
    let docs;
    if (tab === 'following') {
      // Following tab requires authentication
      if (!currentUser) {
        container.innerHTML = renderTemplate('sign-in-prompt', {});
        return;
      }
      const follows = await databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followerId', currentUser.$id),
        Query.limit(50),
      ]);
      const ids = follows.documents.map(f => f.followingId);
      if (ids.length === 0) {
        container.innerHTML = renderTemplate('no-following', {});
        return;
      }
      docs = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
        Query.equal('authorId', ids),
        Query.orderDesc('$createdAt'),
        Query.limit(30),
      ]);
    } else {
      docs = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
        Query.orderDesc('$createdAt'),
        Query.limit(30),
      ]);
    }

    if (docs.documents.length === 0) {
      container.innerHTML = renderTemplate('empty-feed', {});
      return;
    }

    container.innerHTML = docs.documents
      .map(post => renderTemplate('post-card', {
        id:         post.$id,
        title:      post.title,
        authorId:   post.authorId,
        authorName: post.authorName,
        content:    post.content,
        tags:       post.tags || [],
        createdAt:  post.$createdAt,
      }))
      .join('');
  } catch (e) {
    container.innerHTML = '<div class="empty-state"><p>Could not load posts. Check your Appwrite config.</p></div>';
    console.error(e);
  }
}

document.addEventListener('DOMContentLoaded', initFeed);
