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
    document.title = `${postLabel(post)} – Octopus`;

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

    // Append the comments section below the post body
    const commentsEl = document.createElement('div');
    commentsEl.id = 'comments-section';
    commentsEl.className = 'comments-section';
    container.appendChild(commentsEl);

    renderPostSidebar(post);
    loadPostLikes(post.$id);
    loadComments(post.$id);
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>Post not found.</p></div>';
    console.error(err);
  }
}

// ── Likes ──────────────────────────────────────────────────────────────────────

/**
 * Load like count + current-user liked state for the post; update the like button.
 */
async function loadPostLikes(postId) {
  const btn      = document.getElementById('post-like-btn');
  const countEl  = document.getElementById('post-like-count');
  if (!btn || !countEl) return;

  try {
    const [countRes, likedRes] = await Promise.all([
      databases.listDocuments(APPWRITE_DB_ID, COL_LIKES, [
        Query.equal('targetId',   postId),
        Query.equal('targetType', 'post'),
        Query.limit(1),
      ]),
      currentUser
        ? databases.listDocuments(APPWRITE_DB_ID, COL_LIKES, [
            Query.equal('targetId',   postId),
            Query.equal('targetType', 'post'),
            Query.equal('userId',     currentUser.$id),
            Query.limit(1),
          ])
        : Promise.resolve({ documents: [], total: 0 }),
    ]);

    // Appwrite returns total count in the response
    const total  = countRes.total;
    const liked  = likedRes.documents.length > 0;
    countEl.textContent = total;
    btn.classList.toggle('action-btn--liked', liked);
    btn.dataset.liked   = liked ? '1' : '';
    btn.dataset.likeDoc = liked ? likedRes.documents[0].$id : '';
  } catch (err) {
    countEl.textContent = '0';
    console.error(err);
  }

  btn.addEventListener('click', () => toggleLike(btn, postId, 'post'));
}

/**
 * Toggle a like on a post or comment.
 * @param {HTMLElement} btn        – the clicked like button
 * @param {string}      targetId   – document $id being liked
 * @param {string}      targetType – "post" | "comment"
 */
async function toggleLike(btn, targetId, targetType) {
  if (!currentUser) { window.location.href = 'signin.html'; return; }
  btn.disabled = true;

  const countEl = btn.querySelector('.like-count') || document.getElementById('post-like-count');
  const isLiked = btn.dataset.liked === '1';

  try {
    if (isLiked) {
      let docId = btn.dataset.likeDoc;
      if (!docId) {
        // Fallback: look up the like document
        const res = await databases.listDocuments(APPWRITE_DB_ID, COL_LIKES, [
          Query.equal('targetId',   targetId),
          Query.equal('targetType', targetType),
          Query.equal('userId',     currentUser.$id),
          Query.limit(1),
        ]);
        docId = res.documents[0] ? res.documents[0].$id : '';
      }
      if (docId) {
        await databases.deleteDocument(APPWRITE_DB_ID, COL_LIKES, docId);
      }
      btn.dataset.liked   = '';
      btn.dataset.likeDoc = '';
      btn.classList.remove('action-btn--liked');
      if (countEl) countEl.textContent = Math.max(0, parseInt(countEl.textContent, 10) - 1);
    } else {
      const doc = await databases.createDocument(APPWRITE_DB_ID, COL_LIKES, ID.unique(), {
        targetId,
        targetType,
        userId: currentUser.$id,
      });
      btn.dataset.liked   = '1';
      btn.dataset.likeDoc = doc.$id;
      btn.classList.add('action-btn--liked');
      if (countEl) countEl.textContent = parseInt(countEl.textContent, 10) + 1;
    }
  } catch (err) {
    console.error(err);
  } finally {
    btn.disabled = false;
  }
}

// ── Comments ───────────────────────────────────────────────────────────────────

/**
 * Load all comments for a post, group replies under their parents, and render.
 */
async function loadComments(postId) {
  const section = document.getElementById('comments-section');
  if (!section) return;

  section.innerHTML = '<div class="loading" style="padding:20px 0;">Loading comments…</div>';

  try {
    // Fetch all comments for this post in one request (limit 100 is sufficient for a blog)
    const res = await databases.listDocuments(APPWRITE_DB_ID, COL_COMMENTS, [
      Query.equal('postId', postId),
      Query.orderAsc('$createdAt'),
      Query.limit(100),
    ]);

    const allComments = res.documents;

    // Separate top-level from replies
    const topLevel = allComments.filter(c => !c.parentId);
    const replies   = allComments.filter(c =>  c.parentId);

    // Build a map parentId → replies[]
    const replyMap = {};
    for (const r of replies) {
      if (!replyMap[r.parentId]) replyMap[r.parentId] = [];
      replyMap[r.parentId].push(r);
    }

    // Fetch like counts + liked state for all comments at once
    const commentIds = allComments.map(c => c.$id);
    const likeCounts   = {};
    const likedDocMap  = {};  // commentId → like document $id (for un-liking)

    if (commentIds.length > 0) {
      const [likeRes, userLikeRes] = await Promise.all([
        databases.listDocuments(APPWRITE_DB_ID, COL_LIKES, [
          Query.equal('targetType', 'comment'),
          Query.equal('targetId',   commentIds.slice(0, 25)),
          Query.limit(100),
        ]),
        currentUser
          ? databases.listDocuments(APPWRITE_DB_ID, COL_LIKES, [
              Query.equal('targetType', 'comment'),
              Query.equal('targetId',   commentIds.slice(0, 25)),
              Query.equal('userId',     currentUser.$id),
              Query.limit(100),
            ])
          : Promise.resolve({ documents: [] }),
      ]);

      for (const like of likeRes.documents) {
        likeCounts[like.targetId] = (likeCounts[like.targetId] || 0) + 1;
      }
      for (const like of userLikeRes.documents) {
        likedDocMap[like.targetId] = like.$id;
      }
    }

    // Map a comment document to template data
    function commentData(c, isReply) {
      return {
        id:         c.$id,
        authorId:   c.authorId,
        authorName: c.authorName,
        createdAt:  c.$createdAt,
        body:       escapeHtml(c.body),
        likeCount:  likeCounts[c.$id] || 0,
        liked:      !!likedDocMap[c.$id],
        replies:    [],
        isReply,
      };
    }

    // Render top-level comments with their replies
    let commentsHtml = topLevel.map(c => {
      const data = commentData(c, false);
      data.replies = (replyMap[c.$id] || []).map(r => commentData(r, true));
      return renderTemplate('comment-item', data);
    }).join('');

    const commentCount = allComments.length;
    const heading = `<h3 class="section-heading" style="margin-top:28px;">${commentCount} Comment${commentCount !== 1 ? 's' : ''}</h3>`;
    const form = buildCommentForm(postId, null);
    section.innerHTML = heading + form + (commentsHtml || '<div class="empty-state" style="padding:24px 0;"><p>No comments yet. Be the first!</p></div>');

    // Attach like listeners to comment like buttons
    section.querySelectorAll('.action-btn--like[data-like-type="comment"]').forEach(btn => {
      const cid = btn.dataset.likeId;
      if (currentUser && likedDocMap[cid]) {
        btn.dataset.liked   = '1';
        btn.dataset.likeDoc = likedDocMap[cid];
      }
      btn.addEventListener('click', () => toggleLike(btn, cid, 'comment'));
    });

    // Attach reply form toggles
    section.querySelectorAll('.reply-btn').forEach(btn => {
      btn.addEventListener('click', () => toggleReplyForm(btn, postId));
    });

    // Attach the main comment form submit
    const mainForm = document.getElementById('comment-form-main');
    if (mainForm) {
      mainForm.addEventListener('submit', e => handleCommentSubmit(e, postId, null, mainForm));
    }
  } catch (err) {
    section.innerHTML = '<div class="empty-state" style="padding:24px 0;"><p>Could not load comments.</p></div>';
    console.error(err);
  }
}

/**
 * Build an HTML string for a comment submission form.
 * @param {string}      postId   – post being commented on
 * @param {string|null} parentId – parent comment id, null for top-level
 * @param {string}      [formId] – form element id
 */
function buildCommentForm(postId, parentId, formId) {
  formId = formId || (parentId ? 'comment-form-reply-' + parentId : 'comment-form-main');
  if (!currentUser) {
    return '<p class="muted-copy" style="margin:12px 0;">' +
      '<a href="signin.html">Sign in</a> to leave a comment.</p>';
  }
  return `<form class="comment-form" id="${escapeHtml(formId)}" data-post-id="${escapeHtml(postId)}" data-parent-id="${escapeHtml(parentId || '')}">
  <div class="form-group" style="margin-bottom:8px;">
    <textarea class="form-control comment-textarea" name="body" rows="3"
      placeholder="${parentId ? 'Write a reply…' : 'Write a comment…'}"
      maxlength="4096" required></textarea>
  </div>
  <div style="display:flex;gap:8px;align-items:center;">
    <button type="submit" class="btn btn-primary btn-sm">${iconOnly('send')} ${parentId ? 'Reply' : 'Comment'}</button>
    ${parentId ? `<button type="button" class="btn btn-secondary btn-sm cancel-reply-btn">${iconOnly('x')} Cancel</button>` : ''}
  </div>
</form>`;
}

/**
 * Show or hide an inline reply form beneath a comment.
 */
function toggleReplyForm(btn, postId) {
  const commentId  = btn.dataset.commentId;
  const authorName = btn.dataset.authorName;
  const commentEl  = document.getElementById('comment-' + commentId);
  if (!commentEl) return;

  const existingForm = commentEl.querySelector('.comment-reply-form-wrap');
  if (existingForm) {
    existingForm.remove();
    return;
  }

  const wrap = document.createElement('div');
  wrap.className = 'comment-reply-form-wrap';
  wrap.innerHTML = `<p class="muted-copy" style="margin:8px 0 4px;">Replying to <strong>${escapeHtml(authorName)}</strong></p>` +
    buildCommentForm(postId, commentId);
  commentEl.appendChild(wrap);

  const replyForm = wrap.querySelector('form');
  if (replyForm) {
    replyForm.addEventListener('submit', e => handleCommentSubmit(e, postId, commentId, replyForm));
  }
  const cancelBtn = wrap.querySelector('.cancel-reply-btn');
  if (cancelBtn) cancelBtn.addEventListener('click', () => wrap.remove());
}

/**
 * Handle comment or reply form submission.
 */
async function handleCommentSubmit(e, postId, parentId, form) {
  e.preventDefault();
  if (!currentUser) { window.location.href = 'signin.html'; return; }

  const textarea  = form.querySelector('.comment-textarea');
  const submitBtn = form.querySelector('[type="submit"]');
  const body      = textarea.value.trim();
  if (!body) return;

  submitBtn.disabled = true;
  try {
    await databases.createDocument(APPWRITE_DB_ID, COL_COMMENTS, ID.unique(), {
      postId,
      authorId:   currentUser.$id,
      authorName: currentUser.name,
      body,
      parentId:   parentId || '',
    });
    // Reload comments to show new entry
    await loadComments(postId);
  } catch (err) {
    console.error(err);
    submitBtn.disabled = false;
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

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
