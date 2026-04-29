/**
 * signup.js – sign-up page logic.
 */
async function initSignUp() {
  await renderNav();
  const user = await getCurrentUser();
  if (user) { window.location.href = 'index.html'; return; }

  document.getElementById('signup-form').addEventListener('submit', async e => {
    e.preventDefault();
    hideAlert('alert');

    const name     = document.getElementById('name').value.trim();
    const email    = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;
    const confirm  = document.getElementById('confirm').value;
    const btn      = document.getElementById('btn-signup');

    if (password !== confirm) {
      showAlert('alert', 'Passwords do not match.', 'error');
      return;
    }
    if (password.length < 8) {
      showAlert('alert', 'Password must be at least 8 characters.', 'error');
      return;
    }

    btn.disabled    = true;
    btn.textContent = 'Creating account…';

    try {
      const newUser = await signUp(email, password, name);
      // Log in immediately after sign-up
      await signIn(email, password);
      await ensureProfile(newUser);
      window.location.href = 'index.html';
    } catch (err) {
      showAlert('alert', err.message || 'Could not create account.', 'error');
      btn.disabled    = false;
      btn.textContent = 'Create Account';
    }
  });
}

document.addEventListener('DOMContentLoaded', initSignUp);
