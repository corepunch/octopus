# Copilot Instructions – Octopus

Octopus is a **zero-build, static-file** blogging platform deployed on GitHub Pages with Appwrite as its backend.
These instructions capture the conventions established across agent sessions so that Copilot generates consistent code.

---

## Folder structure

```
octopus/
├── src/                # XHTML page sources — edit these, not the generated HTML
│   ├── page.xsl        # Shared XSLT template (nav, head, script tags)
│   ├── index.xhtml
│   ├── signin.xhtml
│   ├── signup.xhtml
│   ├── create.xhtml
│   ├── search.xhtml
│   ├── post.xhtml
│   ├── profile.xhtml
│   ├── about.xhtml
│   ├── terms.xhtml
│   ├── privacy.xhtml
│   └── impressum.xhtml
│
├── css/
│   └── style.css       # Single global stylesheet
│
├── js/
│   ├── config.js       # Appwrite endpoint / project / collection IDs
│   ├── appwrite.js     # Appwrite SDK initialisation (client, account, databases)
│   ├── templates.js    # All Handlebars templates compiled + registered as partials
│   ├── utils.js        # Shared helpers (escapeHtml, timeAgo, renderTemplate, …)
│   ├── auth.js         # getCurrentUser, signIn, signUp, logout, renderNav
│   └── pages/
│       ├── index.js    # Feed page logic
│       ├── post.js     # Single post page logic
│       ├── profile.js  # Profile page logic
│       ├── search.js   # Search page logic
│       ├── create.js   # Create/edit post logic
│       ├── signin.js   # Sign-in page logic
│       └── signup.js   # Sign-up page logic
│
├── templates/          # Canonical Handlebars source files (*.handlebars)
│   ├── post-card.handlebars
│   ├── post-header.handlebars
│   ├── post-author.handlebars
│   ├── more-posts.handlebars
│   ├── profile-header.handlebars
│   ├── user-widget.handlebars
│   ├── guest-widget.handlebars
│   ├── user-result.handlebars
│   ├── nav-auth.handlebars
│   ├── section-heading.handlebars
│   ├── no-results.handlebars
│   ├── no-following.handlebars
│   ├── empty-feed.handlebars
│   └── sign-in-prompt.handlebars
│
└── scripts/            # Bash provisioning / seeding scripts (no Node required)
    ├── provision-appwrite.sh
    └── seed-appwrite.sh
```

Each HTML page is standalone – it loads its own `<script>` tags in the order described below and calls `document.addEventListener('DOMContentLoaded', initXxx)`.

---

## XHTML + XSLT build system

### How pages are authored

- **Never edit generated HTML files directly.** All pages are authored as small XHTML files in `src/` and transformed into `dist/*.html` by `scripts/build.sh` using `xsltproc`.
- The shared template `src/page.xsl` wraps every page with the `<nav>`, `<head>`, and CDN `<script>` tags.
- To build locally: `bash scripts/build.sh` (requires `xsltproc` — `apt install xsltproc` or `brew install libxslt`).

### Page element attributes

```xml
<page title="…"           ← <title> text
      name="…"            ← page script basename (js/pages/<name>.js); omit for static pages
      type="feed|static"  ← layout type (default: "feed")
      markdown="true|false">  ← include marked + DOMPurify CDN scripts
  <body>…page HTML…</body>
</page>
```

### Layout types

| `type` | Description |
|---|---|
| `feed` (default) | Two-column layout with sidebar. Page JS (`js/pages/<name>.js`) is loaded. Use for interactive pages with Appwrite data. |
| `static` | No sidebar. Content is wrapped in `.static-col` (680 px centred). No page-specific JS — auth/nav scripts are still loaded so the nav bar renders. Use for legal pages, About, etc. |

### Adding a new feed page

1. Create `src/<name>.xhtml` with `<page title="…" name="<name>" type="feed">`.
2. Create `js/pages/<name>.js` with the page logic.
3. Place the two-column layout (`.page-wrap`, `.main-col`, `.sidebar`) inside `<body>`.

### Adding a new static page

1. Create `src/<name>.xhtml` with `<page title="…" type="static">` (no `name` attribute needed).
2. Place content inside `<div class="static-col">…</div>` within `<body>`.
3. No page-specific JS file is required.

---

## No npm / no build step

**Never add a `package.json`, `node_modules`, or any build tool.**

- All dependencies are loaded from CDN `<script>` tags. The **required** scripts that every page must load, in this fixed order:

  ```html
  <script src="https://cdn.jsdelivr.net/npm/handlebars@4.7.8/dist/handlebars.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/appwrite@16/dist/iife/sdk.js"></script>
  <script src="js/config.js"></script>
  <script src="js/appwrite.js"></script>
  <script src="js/templates.js"></script>
  <script src="js/utils.js"></script>
  <script src="js/auth.js"></script>
  <script src="js/pages/<page-name>.js"></script>
  ```

- Add `marked` and `DOMPurify` **only on pages that render markdown** (currently `index.html`, `post.html`, `create.html`). Place them immediately before the Appwrite SDK script:

  ```html
  <script src="https://cdn.jsdelivr.net/npm/marked@11/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.5/dist/purify.min.js"></script>
  ```

  `utils.js` guards every call with `typeof marked` / `typeof DOMPurify`, so pages that omit these scripts still work correctly.

- The load order matters: `config.js` → `appwrite.js` → `templates.js` → `utils.js` → `auth.js` → page script.
- Pin CDN dependencies to their **exact version** as shown in the snippets above (e.g. `handlebars@4.7.8`, `dompurify@3.2.5`). Only update a pinned version when there is a known breaking change or security fix.
- Provisioning and seeding scripts use only `bash`, `curl`, and `jq` – no Node.

---

## Handlebars – use it as much as possible

### Philosophy

Prefer Handlebars templates over raw HTML string concatenation in page JS. Use `renderTemplate(name, data)` (defined in `utils.js`) for every significant DOM insertion.

> **Current exceptions** (avoid repeating these patterns in new code):
> - `js/auth.js` renders the signed-out nav links via string literals because the fragment is trivial and static.
> - Some pages render one-off error/not-found states as inline `<div class="empty-state">…</div>` strings. New error states should use a registered template instead.

### Template files

- The canonical source for each template lives in `templates/<name>.handlebars`.
- The compiled versions are inlined as template-literal strings in `js/templates.js` and registered as Handlebars partials via `Handlebars.registerPartial(name, Handlebars.compile(src))`.
- When you add a new template:
  1. Create `templates/<name>.handlebars` with the HTML fragment.
  2. Add the same string as a `const` in `js/templates.js` and register it in the `defs` map at the bottom.

### Registered Handlebars helpers (defined in `utils.js`)

| Helper | Usage | Output |
|---|---|---|
| `{{timeAgo isoDate}}` | `{{timeAgo createdAt}}` | `"3h ago"` |
| `{{excerpt content}}` | `{{excerpt content}}` | stripped, truncated plain text |
| `{{initial name}}` | `{{initial username}}` | first character, uppercased |
| `{{urlEncode str}}` | `{{urlEncode authorId}}` | URI-encoded value |
| `{{markdown content}}` | `{{markdown content}}` | rendered + sanitised HTML (`SafeString`) |

Use these helpers inside templates instead of pre-computing values in JS. For example:

```handlebars
<a href="profile.html?id={{urlEncode authorId}}">{{authorName}}</a>
· {{timeAgo createdAt}}
<p>{{excerpt content}}</p>
```

### Calling templates from JS

```js
// Render a partial by name, returns an HTML string
container.innerHTML = renderTemplate('post-card', {
  id:         post.$id,
  title:      post.title,
  authorId:   post.authorId,
  authorName: post.authorName,
  content:    post.content,
  tags:       post.tags || [],
  createdAt:  post.$createdAt,
});

// Render a list of items
container.innerHTML = docs.documents
  .map(post => renderTemplate('post-card', { /* … */ }))
  .join('');
```

### Using partials inside templates

Register the partial with a dash-case name (e.g. `'post-card'`) then reference it with `{{> post-card}}` inside another template.

### Conditional and loop patterns

```handlebars
{{#if showFollow}}
  <button id="follow-btn"
    class="btn {{#if following}}btn-secondary{{else}}btn-primary{{/if}} btn-sm"
    data-target-id="{{authorId}}">
    {{#if following}}Unfollow{{else}}Follow{{/if}}
  </button>
{{/if}}

{{#each tags}}
  <a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>
{{/each}}
```

### Empty / loading states

Use a dedicated template (e.g. `empty-feed`, `no-results`, `no-following`) for reusable empty states rather than inline strings. Loading indicators are the only exception; inline strings are acceptable there:

```js
container.innerHTML = '<div class="loading">Loading…</div>';
```

One-off, page-specific error messages (e.g. "Post not found") may also be inlined where a dedicated template would be overkill.

---

## Appwrite usage

### Configuration (`js/config.js`)

```js
const APPWRITE_ENDPOINT   = 'https://fra.cloud.appwrite.io/v1';
const APPWRITE_PROJECT_ID = '69f1c06800389dc6a1a0';
const APPWRITE_DB_ID      = 'octopus-db';

// Collection IDs – must match the provision script
const COL_POSTS   = 'posts';
const COL_FOLLOWS = 'follows';
const COL_USERS   = 'profiles';
```

Never hard-code endpoint / project IDs outside `config.js`.

### Client initialisation (`js/appwrite.js`)

```js
const { Client, Account, Databases, Query, ID } = Appwrite;

const client    = new Client().setEndpoint(APPWRITE_ENDPOINT).setProject(APPWRITE_PROJECT_ID);
const account   = new Account(client);
const databases = new Databases(client);
```

`account` and `databases` are globals available in every page script.

### Authentication patterns (`js/auth.js`)

```js
// Get current user (returns null if not logged in)
const user = await getCurrentUser();

// Sign in
await signIn(email, password);

// Register
const user = await account.create(ID.unique(), email, password, name);

// Sign out
await logout(); // redirects to index.html

// Render nav bar (call on every page)
await renderNav();
```

Always call `renderNav()` at the top of every `initXxx()` function.

### Database patterns

```js
// Read a single document
const post = await databases.getDocument(APPWRITE_DB_ID, COL_POSTS, postId);

// List documents with filters
const docs = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
  Query.equal('authorId', userId),
  Query.orderDesc('$createdAt'),
  Query.limit(30),
]);

// Create a document
await databases.createDocument(APPWRITE_DB_ID, COL_FOLLOWS, ID.unique(), {
  followerId:  currentUser.$id,
  followingId: targetId,
});

// Delete a document
await databases.deleteDocument(APPWRITE_DB_ID, COL_FOLLOWS, docId);

// Search (fulltext index required on the attribute)
const results = await databases.listDocuments(APPWRITE_DB_ID, COL_POSTS, [
  Query.search('title', query),
  Query.limit(20),
]);
```

### Database schema (collections)

| Collection | Key attributes |
|---|---|
| `posts` | `title` (string 256), `content` (string 65535), `authorId` (string 36), `authorName` (string 128), `tags` (string[] 64), `published` (bool) |
| `follows` | `followerId` (string 36), `followingId` (string 36) |
| `profiles` | `userId` (string 36), `username` (string 128), `bio` (string 1024) |

The profile document ID is always the Appwrite user `$id`.

### Appwrite metadata fields

Appwrite injects `$id`, `$createdAt`, `$updatedAt`, `$permissions` on every document. Use `$id` as the document identifier and `$createdAt` for timestamps.

### Error handling

Wrap every Appwrite call in try/catch. Show user-facing errors via `showAlert(elementId, message, 'error')` (defined in `utils.js`). Log technical errors to `console.error`.

---

## Page structure conventions

Every page script follows this pattern:

```js
let currentUser = null;

async function initPageName() {
  await renderNav();           // always first
  currentUser = await getCurrentUser();
  // … page-specific setup
}

document.addEventListener('DOMContentLoaded', initPageName);
```

Every HTML page follows this structure:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Page Title – Octopus</title>
  <link rel="stylesheet" href="css/style.css" />
</head>
<body>

<nav id="nav">
  <a class="nav-logo" href="index.html">🐙 Octopus</a>
  <div class="nav-links" id="nav-links"></div>
</nav>

<div class="page-wrap">
  <div class="main-col">
    <!-- main content injected by JS -->
  </div>
  <aside class="sidebar">
    <!-- optional sidebar content -->
  </aside>
</div>

<!-- Required CDN scripts in fixed order -->
<script src="https://cdn.jsdelivr.net/npm/handlebars@4.7.8/dist/handlebars.min.js"></script>
<!-- Add marked + DOMPurify only on pages that render markdown -->
<!-- <script src="https://cdn.jsdelivr.net/npm/marked@11/marked.min.js"></script>   -->
<!-- <script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.5/dist/purify.min.js"></script> -->
<script src="https://cdn.jsdelivr.net/npm/appwrite@16/dist/iife/sdk.js"></script>
<script src="js/config.js"></script>
<script src="js/appwrite.js"></script>
<script src="js/templates.js"></script>
<script src="js/utils.js"></script>
<script src="js/auth.js"></script>
<script src="js/pages/<page-name>.js"></script>
</body>
</html>
```

---

## Tests

There is no test runner or framework. Because there is no npm, do **not** add Jest, Mocha, or any other npm-based test tool.

The `tests/` directory holds plain HTML test files. To add tests for utility functions or Handlebars helpers, create `tests/<name>.test.html`:
- Load the same CDN scripts as a normal page (add `marked`/`DOMPurify` if the file under test needs them).
- Import the JS file under test with a `<script src="../js/…">` tag.
- Run assertions using the inline helper below.
- Open the file directly in a browser; all results appear in the console.

```js
function assert(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console[ok ? 'log' : 'error'](`${ok ? '✓' : '✗'} ${label}`, ok ? '' : `\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
}
```

See `tests/utils.test.html` for a working example covering `timeAgo`, `excerpt`, `escapeHtml`, and `parseTags`.

---

## CSS

- All styles live in `css/style.css`. Do not add inline `<style>` blocks.
- Use the existing utility classes: `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-danger`, `.btn-sm`, `.btn-nav-primary`, `.alert`, `.alert-error`, `.alert-success`, `.loading`, `.empty-state`, `.post-card`, `.widget`, `.form-group`, `.form-control`, `.tag`, `.avatar`.
- Inline styles are acceptable only for one-off layout tweaks directly on an element (e.g. `style="margin-top:10px"`), matching the existing code style.

---

## Security

- Never trust user-generated content. All template output is auto-escaped by Handlebars by default.
- Use `{{markdown content}}` (which wraps `renderMarkdown` + DOMPurify) when rendering markdown; never use `{{{triple-stache}}}` for user content.
- Never store secrets in source files. API keys live in GitHub Secrets and are passed to scripts at runtime.
- The Appwrite `client.ping()` call in `appwrite.js` verifies the connection on every page load and logs a warning to the console if it fails.
