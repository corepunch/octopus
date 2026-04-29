/**
 * index.js – main feed page logic.
 */
let currentUser = null;
let activeTab   = 'discover';

async function initFeed() {
  await renderNav();
  currentUser = await getCurrentUser();
  renderSidebarUser();

  // Wire up feed tab buttons via event delegation (no inline onclick)
  document.querySelectorAll('.feed-tab').forEach(btn => {
    btn.addEventListener('click', () => loadPosts(btn.dataset.tab));
  });

  loadPosts(activeTab);
}

function renderSidebarUser() {
  const el = document.getElementById('sidebar-user');
  if (!el) return;
  if (currentUser) {
    el.innerHTML = renderTemplate('tpl-user-widget', {
      name: currentUser.name,
      id:   currentUser.$id,
    });
    // Attach sign-out listener after template is in the DOM
    const signOutBtn = document.getElementById('sidebar-sign-out');
    if (signOutBtn) {
      signOutBtn.addEventListener('click', () => logout());
    }
  } else {
    el.innerHTML = renderTemplate('tpl-guest-widget', {});
  }
}

async function loadPosts(tab) {
  activeTab = tab;
  document.querySelectorAll('.feed-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));

  const container = document.getElementById('posts');
  container.innerHTML = '<div class="loading">Loading posts…</div>';

  try {
    let docs;
    if (tab === 'following' && currentUser) {
      // Fetch IDs of users the current user follows
      const follows = await databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followerId', currentUser.$id),
        Query.limit(50),
      ]);
      const ids = follows.documents.map(f => f.followingId);
      if (ids.length === 0) {
        container.innerHTML = `<div class="empty-state"><p>You're not following anyone yet.</p>
          <a href="search.html" class="btn btn-primary" style="margin-top:12px;display:inline-block;">Find people to follow</a></div>`;
        return;
      }
      docs = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
        Query.equal('authorId', ids),
        Query.orderDesc('$createdAt'),
        Query.limit(30),
      ]);
    } else {
      // Discover – all recent posts
      docs = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
        Query.orderDesc('$createdAt'),
        Query.limit(30),
      ]);
    }

    if (docs.documents.length === 0) {
      container.innerHTML = '<div class="empty-state"><p>No posts yet. Be the first!</p></div>';
      return;
    }

    container.innerHTML = docs.documents
      .map(post => renderTemplate('tpl-post-card', {
        id:         post.$id,
        title:      post.title,
        authorId:   post.authorId,
        authorName: post.authorName,
        excerpt:    excerpt(post.content),
        tags:       (post.tags || []),
        timeAgo:    timeAgo(post.$createdAt),
      }))
      .join('');
  } catch (e) {
    container.innerHTML = `<div class="empty-state"><p>Could not load posts. Check your Appwrite config.</p></div>`;
    console.error(e);
  }
}

document.addEventListener('DOMContentLoaded', initFeed);
