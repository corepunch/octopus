/**
 * post.js – single post view.
 * All HTML is rendered by Handlebars partials registered in js/templates.js.
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

    const postType = post.postType || 'text';
    let pageTitle;
    if (postType === 'text') {
      pageTitle = post.title || 'Post';
    } else if (postType === 'quote') {
      pageTitle = (post.content || '').slice(0, 60) + ((post.content || '').length > 60 ? '…' : '');
    } else if (postType === 'link') {
      try { pageTitle = new URL(post.linkUrl).hostname; } catch { pageTitle = post.linkUrl || 'Link'; }
    } else {
      pageTitle = 'Photo';
    }
    document.title = `${pageTitle} – Octopus`;

    container.innerHTML = renderTemplate('post-header', {
      id:          post.$id,
      title:       post.title,
      authorId:    post.authorId,
      authorName:  post.authorName,
      createdAt:   post.$createdAt,
      content:     post.content,
      tags:        post.tags || [],
      postType,
      imageUrl:    post.imageId ? getImageUrl(post.imageId) : '',
      linkUrl:     post.linkUrl || '',
      quoteSource: post.quoteSource || '',
      userText:    post.userText || '',
    });

    renderPostSidebar(post);
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>Post not found.</p></div>';
    console.error(err);
  }
}

async function renderPostSidebar(post) {
  const sidebar = document.getElementById('sidebar-content');
  if (!sidebar) return;

  const showFollow = !!(currentUser && currentUser.$id !== post.authorId);
  const following  = showFollow ? await isFollowing(post.authorId) : false;

  sidebar.innerHTML = renderTemplate('post-author', {
    authorId:   post.authorId,
    authorName: post.authorName,
    showFollow,
    following,
  });

  const followBtn = document.getElementById('follow-btn');
  if (followBtn) {
    followBtn.addEventListener('click', () => toggleFollow(post.authorId, followBtn));
  }

  // More posts by the same author
  try {
    const more = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
      Query.equal('authorId', post.authorId),
      Query.notEqual('$id', post.$id),
      Query.orderDesc('$createdAt'),
      Query.limit(5),
    ]);
    if (more.documents.length > 0) {
      sidebar.innerHTML += renderTemplate('more-posts', {
        authorName: post.authorName,
        posts:      more.documents.map(p => ({ id: p.$id, label: postLabel(p) })),
      });
    }
  } catch { /* sidebar still shows author widget */ }
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
    const isUnfollowing = btn.textContent.trim().startsWith('Unfollow');
    if (isUnfollowing) {
      const res = await databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followerId', currentUser.$id),
        Query.equal('followingId', targetId),
        Query.limit(1),
      ]);
      if (res.documents.length > 0) {
        await databases.deleteDocument(APPWRITE_DB_ID, COL_FOLLOWS, res.documents[0].$id);
      }
      btn.innerHTML = iconLabel('user-plus', 'Follow');
      btn.className   = 'btn btn-primary btn-sm';
    } else {
      await databases.createDocument(APPWRITE_DB_ID, COL_FOLLOWS, ID.unique(), {
        followerId:  currentUser.$id,
        followingId: targetId,
      });
      btn.innerHTML = iconLabel('user-minus', 'Unfollow');
      btn.className   = 'btn btn-secondary btn-sm';
    }
  } catch (err) {
    console.error(err);
  } finally {
    btn.disabled = false;
  }
}

document.addEventListener('DOMContentLoaded', initPost);

/**
 * Compute a short display label for a post, used in "More from X" sidebar.
 * Text posts use their title; other types derive a label from their content.
 * @param {object} p – Appwrite post document
 * @returns {string}
 */
function postLabel(p) {
  const type = p.postType || 'text';
  if (type === 'text') return p.title || 'Untitled';
  if (type === 'quote') {
    const q = p.content || '';
    return q.length > 60 ? q.slice(0, 60) + '…' : q;
  }
  if (type === 'link') {
    try { return new URL(p.linkUrl).hostname; } catch { return p.linkUrl || 'Link'; }
  }
  return 'Photo';
}
