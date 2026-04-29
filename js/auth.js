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
  } catch (err) {
    // Only create the profile when the document genuinely doesn't exist.
    // Re-throw network errors, permission errors, etc. so the caller can
    // surface a meaningful message instead of masking them.
    if (err.code === 404) {
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
    } else {
      throw err;
    }
  }
}

/**
 * Render the navigation bar depending on auth state.
 * Uses the 'nav-auth' Handlebars partial (registered in js/templates.js)
 * so all values are auto-escaped; the urlEncode helper ensures the profile
 * ID is correctly percent-encoded in the href query string.
 */
async function renderNav() {
  const user = await getCurrentUser();
  const linksEl = document.getElementById('nav-links');
  if (!linksEl) return;

  if (user) {
    linksEl.innerHTML = renderTemplate('nav-auth', { name: user.name, id: user.$id });
    document.getElementById('nav-sign-out').addEventListener('click', e => {
      e.preventDefault();
      logout();
    });
  } else {
    const ic = typeof ICONS !== 'undefined' ? ICONS : {};
    linksEl.innerHTML =
      '<a href="search.html">' + (ic['search'] || '') + ' Search</a>' +
      '<a href="signin.html">' + (ic['log-in'] || '') + ' Sign In</a>' +
      '<a href="signup.html" class="btn-nav-primary btn">' + (ic['user-plus'] || '') + ' Sign Up</a>';
  }
}

// escapeHtml is defined in utils.js and loaded before auth.js on every page.
