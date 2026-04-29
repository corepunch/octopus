/**
 * Authentication helpers – shared across all pages.
 */

/**
 * Returns the current logged-in user, or null if not authenticated.
 */
async function getCurrentUser() {
  try {
    return await account.get();
  } catch {
    return null;
  }
}

/**
 * Sign in with email + password.
 */
async function signIn(email, password) {
  return account.createEmailPasswordSession(email, password);
}

/**
 * Register a new user account.
 */
async function signUp(email, password, name) {
  return account.create(ID.unique(), email, password, name);
}

/**
 * Sign out the current session.
 */
async function logout() {
  try {
    await account.deleteSession('current');
  } finally {
    window.location.href = 'index.html';
  }
}

/**
 * Ensure the user has a profile document in the `profiles` collection.
 * Called once after sign-up.
 */
async function ensureProfile(user) {
  try {
    await databases.getDocument(APPWRITE_DB_ID, COL_USERS, user.$id);
  } catch {
    // Profile doesn't exist yet – create it.
    await databases.createDocument(
      APPWRITE_DB_ID,
      COL_USERS,
      user.$id,
      {
        userId:   user.$id,
        username: user.name,
        bio:      '',
      }
    );
  }
}

/**
 * Render the navigation bar depending on auth state.
 */
async function renderNav() {
  const user = await getCurrentUser();
  const linksEl = document.getElementById('nav-links');
  if (!linksEl) return;

  if (user) {
    linksEl.innerHTML = `
      <span id="nav-user-name">${escapeHtml(user.name)}</span>
      <a href="create.html" class="btn-nav-primary btn">+ New Post</a>
      <a href="profile.html?id=${escapeHtml(user.$id)}">Profile</a>
      <a href="#" id="nav-sign-out">Sign Out</a>
    `;
    document.getElementById('nav-sign-out').addEventListener('click', e => {
      e.preventDefault();
      logout();
    });
  } else {
    linksEl.innerHTML = `
      <a href="search.html">Search</a>
      <a href="signin.html">Sign In</a>
      <a href="signup.html" class="btn-nav-primary btn">Sign Up</a>
    `;
  }
}

// escapeHtml is defined in utils.js and loaded before auth.js on every page.
