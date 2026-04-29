/**
 * post.js – single post view.
 */
let currentUser = null;

async function initPost() {
  await renderNav();
  currentUser = await getCurrentUser();

  const postId = getParam('id');
  if (!postId) { window.location.href = 'index.html'; return; }

  const container = document.getElementById('post-container');
  container.innerHTML = '<div class="loading">Loading post…</div>';

  try {
    const post = await databases.getDocument(APPWRITE_DB_ID, COL_POSTS, postId);

    document.title = `${post.title} – Octopus`;

    container.innerHTML = `
      <h1 class="post-page-title">${escapeHtml(post.title)}</h1>
      <div class="post-page-meta">
        By <a href="profile.html?id=${post.authorId}" class="author-link">${escapeHtml(post.authorName)}</a>
        · ${timeAgo(post.$createdAt)}
        ${(post.tags || []).map(t => `<a href="search.html?tag=${encodeURIComponent(t)}" class="tag">#${escapeHtml(t)}</a>`).join(' ')}
      </div>
      <div class="markdown-body" id="post-body"></div>
    `;

    document.getElementById('post-body').innerHTML = renderMarkdown(post.content);

    // Sidebar
    renderPostSidebar(post);
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>Post not found.</p></div>';
    console.error(err);
  }
}

async function renderPostSidebar(post) {
  const sidebar = document.getElementById('sidebar-content');
  if (!sidebar) return;

  // Author profile info
  let authorHtml = `<div class="widget">
    <h3>Author</h3>
    <a href="profile.html?id=${post.authorId}" style="font-weight:bold;">${escapeHtml(post.authorName)}</a>`;

  if (currentUser && currentUser.$id !== post.authorId) {
    const following = await isFollowing(post.authorId);
    authorHtml += `<div style="margin-top:10px;">
      <button id="follow-btn" class="btn ${following ? 'btn-secondary' : 'btn-primary'} btn-sm"
        onclick="toggleFollow('${post.authorId}', this)">
        ${following ? 'Unfollow' : 'Follow'}
      </button>
    </div>`;
  }
  authorHtml += '</div>';

  // More posts by same author
  let morePosts = '';
  try {
    const more = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
      Query.equal('authorId', post.authorId),
      Query.notEqual('$id', post.$id),
      Query.orderDesc('$createdAt'),
      Query.limit(5),
    ]);
    if (more.documents.length > 0) {
      morePosts = `<div class="widget"><h3>More from ${escapeHtml(post.authorName)}</h3>
        ${more.documents.map(p => `<div style="margin-bottom:8px;"><a href="post.html?id=${p.$id}">${escapeHtml(p.title)}</a></div>`).join('')}
      </div>`;
    }
  } catch {}

  sidebar.innerHTML = authorHtml + morePosts;
}

async function isFollowing(targetId) {
  if (!currentUser) return false;
  try {
    const res = await databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
      Query.equal('followerId', currentUser.$id),
      Query.equal('followingId', targetId),
      Query.limit(1),
    ]);
    return res.documents.length > 0;
  } catch { return false; }
}

async function toggleFollow(targetId, btn) {
  if (!currentUser) { window.location.href = 'signin.html'; return; }
  btn.disabled = true;
  try {
    const following = btn.textContent.trim() === 'Unfollow';
    if (following) {
      // Find and delete follow document
      const res = await databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followerId', currentUser.$id),
        Query.equal('followingId', targetId),
        Query.limit(1),
      ]);
      if (res.documents.length > 0) {
        await databases.deleteDocument(APPWRITE_DB_ID, COL_FOLLOWS, res.documents[0].$id);
      }
      btn.textContent = 'Follow';
      btn.className   = 'btn btn-primary btn-sm';
    } else {
      await databases.createDocument(APPWRITE_DB_ID, COL_FOLLOWS, ID.unique(), {
        followerId:  currentUser.$id,
        followingId: targetId,
      });
      btn.textContent = 'Unfollow';
      btn.className   = 'btn btn-secondary btn-sm';
    }
  } catch (err) {
    console.error(err);
  } finally {
    btn.disabled = false;
  }
}

document.addEventListener('DOMContentLoaded', initPost);
