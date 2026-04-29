/**
 * icons.js – Lucide icon SVG strings (MIT licence, https://lucide.dev).
 *
 * All icons use the standard Lucide format: 24×24 viewBox, stroke-based,
 * currentColor fill, so they inherit button/link colour automatically.
 *
 * Usage in Handlebars templates (via the {{icon}} helper registered in utils.js):
 *   {{icon "pen-line"}}  →  inlined <svg …>…</svg>
 *
 * Usage on static HTML elements (auto-processed at DOMContentLoaded):
 *   <button data-icon="log-in">Sign In</button>
 *   → prepends the matching SVG before the button's text
 *
 * Icon catalogue
 * ──────────────
 * home           Home / Feed
 * pen-line       Write / New Post
 * user           Profile
 * log-out        Sign Out
 * log-in         Sign In
 * user-plus      Sign Up / Follow
 * user-minus     Unfollow
 * search         Search
 * users          Find people / followers
 * settings       Edit Profile
 * message-circle Comment
 * repeat-2       Repost
 * share-2        Share
 * x              Cancel / close
 * send           Publish / submit
 */

/* eslint-disable */
const ICONS = (function () {

  function svg(paths) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" ' +
      'viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' +
      'aria-hidden="true">' + paths + '</svg>';
  }

  return {
    'home': svg(
      '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>' +
      '<polyline points="9 22 9 12 15 12 15 22"/>'
    ),
    'pen-line': svg(
      '<path d="M12 20h9"/>' +
      '<path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"/>' +
      '<path d="m15 5 3 3"/>'
    ),
    'user': svg(
      '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/>' +
      '<circle cx="12" cy="7" r="4"/>'
    ),
    'log-out': svg(
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>' +
      '<polyline points="16 17 21 12 16 7"/>' +
      '<line x1="21" x2="9" y1="12" y2="12"/>'
    ),
    'log-in': svg(
      '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/>' +
      '<polyline points="10 17 15 12 10 7"/>' +
      '<line x1="15" x2="3" y1="12" y2="12"/>'
    ),
    'user-plus': svg(
      '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>' +
      '<circle cx="9" cy="7" r="4"/>' +
      '<line x1="19" x2="19" y1="8" y2="14"/>' +
      '<line x1="22" x2="16" y1="11" y2="11"/>'
    ),
    'user-minus': svg(
      '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>' +
      '<circle cx="9" cy="7" r="4"/>' +
      '<line x1="22" x2="16" y1="11" y2="11"/>'
    ),
    'search': svg(
      '<circle cx="11" cy="11" r="8"/>' +
      '<path d="m21 21-4.3-4.3"/>'
    ),
    'users': svg(
      '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>' +
      '<circle cx="9" cy="7" r="4"/>' +
      '<path d="M22 21v-2a4 4 0 0 0-3-3.87"/>' +
      '<path d="M16 3.13a4 4 0 0 1 0 7.75"/>'
    ),
    'settings': svg(
      '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/>' +
      '<circle cx="12" cy="12" r="3"/>'
    ),
    'message-circle': svg(
      '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>'
    ),
    'repeat-2': svg(
      '<path d="m2 9 3-3 3 3"/>' +
      '<path d="M13 18H7a2 2 0 0 1-2-2V6"/>' +
      '<path d="m22 15-3 3-3-3"/>' +
      '<path d="M11 6h6a2 2 0 0 1 2 2v10"/>'
    ),
    'share-2': svg(
      '<circle cx="18" cy="5" r="3"/>' +
      '<circle cx="6" cy="12" r="3"/>' +
      '<circle cx="18" cy="19" r="3"/>' +
      '<line x1="8.59" x2="15.42" y1="13.51" y2="17.49"/>' +
      '<line x1="15.41" x2="8.59" y1="6.51" y2="10.49"/>'
    ),
    'x': svg(
      '<path d="M18 6 6 18"/>' +
      '<path d="m6 6 12 12"/>'
    ),
    'send': svg(
      '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/>' +
      '<path d="m21.854 2.147-10.94 10.939"/>'
    ),
  };
}());

/**
 * Auto-process any static element that carries a data-icon attribute.
 * Called once at DOMContentLoaded – only covers elements already in the HTML.
 * Dynamically-rendered templates use the {{icon "name"}} Handlebars helper instead.
 */
document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('[data-icon]').forEach(function (el) {
    var name = el.getAttribute('data-icon');
    var iconSvg = ICONS[name];
    if (iconSvg) {
      el.insertAdjacentHTML('afterbegin', iconSvg + ' ');
    }
  });
});
