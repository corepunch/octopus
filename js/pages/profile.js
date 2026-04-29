/**
 * profile.js – user profile page.
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
      // Profile doc might not exist; fall back to minimal info from posts
      profile = { userId: profileId, username: 'Unknown', bio: '' };
    }

    // Count followers / following / posts
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

    const initial = (profile.username || '?')[0].toUpperCase();
    const isOwn   = currentUser && currentUser.$id === profileId;

    let followBtn = '';
    if (currentUser && !isOwn) {
      const following = await isFollowingUser(profileId);
      followBtn = `<button id="follow-btn"
        class="btn ${following ? 'btn-secondary' : 'btn-primary'} btn-sm"
        onclick="toggleFollow('${profileId}', this)">
        ${following ? 'Unfollow' : 'Follow'}
      </button>`;
    }

    container.innerHTML = `
      <div class="profile-header">
        <div class="avatar">${escapeHtml(initial)}</div>
        <div class="profile-info">
          <h2>${escapeHtml(profile.username)}</h2>
          ${profile.bio ? `<p class="bio">${escapeHtml(profile.bio)}</p>` : ''}
          <div class="profile-stats">
            <span><strong>${followersRes.total}</strong> followers</span>
            <span><strong>${followingRes.total}</strong> following</span>
            <span><strong>${postsRes.total}</strong> posts</span>
          </div>
          <div style="margin-top:10px;">
            ${isOwn ? '<a href="settings.html" class="btn btn-secondary btn-sm">Edit Profile</a>' : followBtn}
          </div>
        </div>
      </div>
      <h3 class="section-heading">Posts</h3>
      <div id="user-posts"><div class="loading">Loading posts…</div></div>
    `;

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
  const following = btn.textContent.trim() === 'Unfollow';
  try {
    if (following) {
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

document.addEventListener('DOMContentLoaded', initProfile);
