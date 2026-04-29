/**
 * profile.js – user profile page.
 * All HTML is rendered by Handlebars partials registered in js/templates.js.
 */
let currentUser = null;

async function initProfile() {
  await renderNav();
  currentUser = await getCurrentUser();

  const profileId = getParam('id');
  if (!profileId) { window.location.href = 'index.html'; return; }

  const container = document.getElementById('profile-container');
  container.innerHTML = '<div class="loading">Loading profile…</div>';

  try {
    let profile;
    try {
      profile = await databases.getDocument(APPWRITE_DB_ID, COL_USERS, profileId);
    } catch {
      profile = { userId: profileId, username: 'Unknown', bio: '' };
    }

    const [followersRes, followingRes, postsRes] = await Promise.all([
      databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followingId', profileId), Query.limit(1),
      ]),
      databases.listDocuments(APPWRITE_DB_ID, COL_FOLLOWS, [
        Query.equal('followerId', profileId), Query.limit(1),
      ]),
      databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
        Query.equal('authorId', profileId), Query.limit(1),
      ]),
    ]);

    const isOwn      = !!(currentUser && currentUser.$id === profileId);
    const showFollow = !!(currentUser && !isOwn);
    const isFollowing = showFollow ? await isFollowingUser(profileId) : false;

    container.innerHTML = renderTemplate('profile-header', {
      profileId,
      username:    profile.username,
      bio:         profile.bio || '',
      followers:   followersRes.total,
      following:   followingRes.total,
      posts:       postsRes.total,
      isOwn,
      showFollow,
      isFollowing,
    });

    const btn = document.getElementById('follow-btn');
    if (btn) {
      btn.addEventListener('click', () => toggleFollow(profileId, btn));
    }

    loadUserPosts(profileId);
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>Profile not found.</p></div>';
    console.error(err);
  }
}

async function loadUserPosts(profileId) {
  const el = document.getElementById('user-posts');
  if (!el) return;
  try {
    const res = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
      Query.equal('authorId', profileId),
      Query.orderDesc('$createdAt'),
      Query.limit(30),
    ]);

    if (res.documents.length === 0) {
      el.innerHTML = '<div class="empty-state"><p>No posts yet.</p></div>';
      return;
    }

    el.innerHTML = res.documents
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
  } catch (err) {
    el.innerHTML = '<div class="empty-state"><p>Could not load posts.</p></div>';
    console.error(err);
  }
}

async function isFollowingUser(targetId) {
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
  const isUnfollowing = btn.textContent.trim().startsWith('Unfollow');
  try {
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

document.addEventListener('DOMContentLoaded', initProfile);
