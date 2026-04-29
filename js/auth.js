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
 * Also populates #left-nav with the section navigation column.
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
    linksEl.innerHTML =
      '<a href="search.html">'                                      + iconLabel('search',    'Search')   + '</a>' +
      '<a href="signin.html">'                                      + iconLabel('log-in',    'Sign In')  + '</a>' +
      '<a href="signup.html" class="btn-nav-primary btn">'          + iconLabel('user-plus', 'Sign Up')  + '</a>';
  }

  renderLeftNav(user);
}

/**
 * Populate the left-navigation column (#left-nav) with section links.
 * The column is always present on feed pages; its content depends on auth state.
 */
function renderLeftNav(user) {
  const leftNav = document.getElementById('left-nav');
  if (!leftNav) return;

  const currentPath = window.location.pathname.split('/').pop() || 'index.html';

  function navItem(href, icon, label, isButton) {
    const active = href && currentPath === href ? ' active' : '';
    if (isButton) {
      return '<button class="left-nav-item' + active + '" id="left-nav-sign-out">' +
        iconLabel(icon, label) + '</button>';
    }
    return '<a href="' + href + '" class="left-nav-item' + active + '">' +
      iconLabel(icon, label) + '</a>';
  }

  let items =
    '<div class="left-nav-section">' + navItem('index.html',  'home',     'Home')    + '</div>' +
    '<div class="left-nav-section">' + navItem('search.html', 'search',   'Explore') + '</div>';

  if (user) {
    items +=
      '<hr class="left-nav-divider"/>' +
      '<div class="left-nav-section">' + navItem('create.html', 'pen-line', 'Write')   + '</div>' +
      '<div class="left-nav-section">' + navItem('profile.html?id=' + encodeURIComponent(user.$id), 'user', 'Profile') + '</div>' +
      '<hr class="left-nav-divider"/>' +
      '<div class="left-nav-section">' + navItem(null, 'log-out', 'Sign Out', true) + '</div>';
  } else {
    items +=
      '<hr class="left-nav-divider"/>' +
      '<div class="left-nav-section">' + navItem('signin.html', 'log-in',   'Sign In') + '</div>' +
      '<div class="left-nav-section">' + navItem('signup.html', 'user-plus', 'Sign Up') + '</div>';
  }

  leftNav.innerHTML = items;

  if (user) {
    const signOutBtn = document.getElementById('left-nav-sign-out');
    if (signOutBtn) {
      signOutBtn.addEventListener('click', () => logout());
    }
  }
}

// escapeHtml is defined in utils.js and loaded before auth.js on every page.
