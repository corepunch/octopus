/**
 * signin.js – sign-in page logic.
 */
async function initSignIn() {
  await renderNav();
  const user = await getCurrentUser();
  if (user) { window.location.href = 'index.html'; return; }

  document.getElementById('signin-form').addEventListener('submit', async e => {
    e.preventDefault();
    hideAlert('alert');

    const email    = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;
    const btn      = document.getElementById('btn-signin');

    btn.disabled    = true;
    btn.textContent = 'Signing in…';

    try {
      await signIn(email, password);
      window.location.href = 'index.html';
    } catch (err) {
      showAlert('alert', err.message || 'Invalid email or password.', 'error');
      btn.disabled    = false;
      btn.textContent = 'Sign In';
    }
  });
}

document.addEventListener('DOMContentLoaded', initSignIn);
