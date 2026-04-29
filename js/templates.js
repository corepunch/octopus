/**
 * templates.js – all Handlebars templates in one place.
 *
 * Inspired by the howardmann/handlebars_example approach: templates live in
 * their own files (templates/*.handlebars) and are compiled + registered as
 * Handlebars partials so that any page can call renderTemplate(name, data)
 * or use {{> partial-name}} inside another template.
 *
 * In the reference repo a CLI pre-compilation step produced this file.
 * Here we inline the source strings directly so that no build step is needed
 * while still keeping templates/ as the canonical, readable source files.
 */
(function () {

  // ── Shared ────────────────────────────────────────────────────────────────

  /** Post card – used on the feed, profile, and search pages. */
  const postCard = `
<div class="post-card post-card--{{postType}}">
  {{#if (eq postType "photo")}}
    {{#if imageUrl}}<a href="post.html?id={{id}}" class="post-card-image-wrap"><img class="post-card-image" src="{{imageUrl}}" alt="{{title}}" loading="lazy"/></a>{{/if}}
    <div class="post-card-body">
      <div class="post-meta">
        by <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
        · {{timeAgo createdAt}}
      </div>
      {{#if title}}<a href="post.html?id={{id}}" class="post-card-title">{{title}}</a>{{/if}}
      {{#if content}}<p class="post-excerpt">{{excerpt content}}</p>{{/if}}
      <div>{{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}</div>
      <div class="post-actions">
        <a href="post.html?id={{id}}" class="action-btn">{{icon "message-circle"}} Comment</a>
        <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
      </div>
    </div>
  {{else if (eq postType "quote")}}
    <div class="post-card-body">
      <div class="post-meta">
        by <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
        · {{timeAgo createdAt}}
      </div>
      <a href="post.html?id={{id}}" class="post-card-quote-link">
        <blockquote class="post-card-quote">{{content}}</blockquote>
        {{#if quoteSource}}<cite class="post-card-quote-source">— {{quoteSource}}</cite>{{/if}}
      </a>
      <div style="margin-top:6px;">{{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}</div>
      <div class="post-actions">
        <a href="post.html?id={{id}}" class="action-btn">{{icon "message-circle"}} Comment</a>
        <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
      </div>
    </div>
  {{else if (eq postType "link")}}
    <div class="post-card-body">
      <div class="post-meta">
        by <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
        · {{timeAgo createdAt}}
      </div>
      <a href="post.html?id={{id}}" class="post-card-title">{{title}}</a>
      {{#if linkUrl}}<a href="{{linkUrl}}" class="post-card-link-url" target="_blank" rel="noopener noreferrer">{{icon "link"}} {{linkUrl}}</a>{{/if}}
      {{#if content}}<p class="post-excerpt">{{excerpt content}}</p>{{/if}}
      <div>{{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}</div>
      <div class="post-actions">
        <a href="post.html?id={{id}}" class="action-btn">{{icon "message-circle"}} Comment</a>
        <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
      </div>
    </div>
  {{else}}
    <div class="post-card-body">
      <a href="post.html?id={{id}}" class="post-card-title">{{title}}</a>
      <div class="post-meta">
        by <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
        · {{timeAgo createdAt}}
      </div>
      <p class="post-excerpt">{{excerpt content}}</p>
      <div>
        {{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}
      </div>
      <div class="post-actions">
        <a href="post.html?id={{id}}" class="action-btn">{{icon "message-circle"}} Comment</a>
        <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
      </div>
    </div>
  {{/if}}
</div>`;

  /** Sidebar widget – signed-in state. */
  const userWidget = `
<div class="widget">
  <h3>You</h3>
  <div class="widget-user-name"><a href="profile.html?id={{urlEncode id}}">{{name}}</a></div>
  <div class="widget-actions">
    <a href="create.html" class="btn btn-primary btn-sm">{{icon "pen-line"}} New Post</a>
    <a href="profile.html?id={{urlEncode id}}" class="btn btn-secondary btn-sm">{{icon "user"}} Profile</a>
    <button class="btn btn-danger btn-sm" id="sidebar-sign-out">{{icon "log-out"}} Sign Out</button>
  </div>
</div>`;

  /** Sidebar widget – signed-out state. */
  const guestWidget = `
<div class="widget">
  <h3>Join Octopus</h3>
  <p class="muted-copy" style="margin-bottom:10px;">Follow writers and get personalised posts.</p>
  <div style="display:flex;gap:6px;">
    <a href="signin.html" class="btn btn-secondary btn-sm">{{icon "log-in"}} Sign In</a>
    <a href="signup.html" class="btn btn-primary btn-sm">{{icon "user-plus"}} Sign Up</a>
  </div>
</div>`;

  // ── index.html ────────────────────────────────────────────────────────────

  const noFollowing = `
<div class="empty-state">
  <p>You're not following anyone yet.</p>
  <a href="search.html" class="btn btn-primary" style="margin-top:12px;">{{icon "users"}} Find people to follow</a>
</div>`;

  const emptyFeed = `
<div class="empty-state"><p>No posts yet. Be the first!</p></div>`;

  const signInPrompt = `
<div class="empty-state">
  <p>Sign in to see posts from writers you follow.</p>
  <a href="signin.html" class="btn btn-primary" style="margin-top:12px;">{{icon "log-in"}} Sign In</a>
</div>`;

  // ── post.html ─────────────────────────────────────────────────────────────

  /** Post title, meta and rendered body (type-aware). */
  const postHeader = `
{{#if (eq postType "photo")}}
  {{#if imageUrl}}<img class="post-page-image" src="{{imageUrl}}" alt="{{title}}"/>{{/if}}
  <div class="post-page-meta" style="margin-top:16px;">
    By <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
    · {{timeAgo createdAt}}
    {{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}
  </div>
  <div class="post-actions" style="margin-bottom:20px;">
    <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
    <button class="action-btn" disabled title="Repost coming soon">{{icon "repeat-2"}} Repost</button>
  </div>
  {{#if content}}<div class="markdown-body">{{markdown content}}</div>{{/if}}
{{else if (eq postType "quote")}}
  <div class="post-page-meta">
    By <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
    · {{timeAgo createdAt}}
    {{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}
  </div>
  <div class="post-actions" style="margin-bottom:20px;">
    <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
    <button class="action-btn" disabled title="Repost coming soon">{{icon "repeat-2"}} Repost</button>
  </div>
  <blockquote class="post-page-quote">{{content}}</blockquote>
  {{#if quoteSource}}<cite class="post-page-quote-source">— {{quoteSource}}</cite>{{/if}}
{{else if (eq postType "link")}}
  <h1 class="post-page-title">{{title}}</h1>
  <div class="post-page-meta">
    By <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
    · {{timeAgo createdAt}}
    {{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}
  </div>
  <div class="post-actions" style="margin-bottom:20px;">
    <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
    <button class="action-btn" disabled title="Repost coming soon">{{icon "repeat-2"}} Repost</button>
  </div>
  {{#if linkUrl}}<a href="{{linkUrl}}" class="post-page-link-card" target="_blank" rel="noopener noreferrer">{{icon "link"}} {{linkUrl}}</a>{{/if}}
  {{#if content}}<div class="markdown-body" style="margin-top:16px;">{{markdown content}}</div>{{/if}}
{{else}}
  <h1 class="post-page-title">{{title}}</h1>
  <div class="post-page-meta">
    By <a href="profile.html?id={{urlEncode authorId}}" class="author-link">{{authorName}}</a>
    · {{timeAgo createdAt}}
    {{#each tags}}<a href="search.html?tag={{urlEncode this}}" class="tag">#{{this}}</a>{{/each}}
  </div>
  <div class="post-actions" style="margin-bottom:20px;">
    <button class="action-btn" data-share-id="{{id}}" data-share-title="{{title}}">{{icon "share-2"}} Share</button>
    <button class="action-btn" disabled title="Repost coming soon">{{icon "repeat-2"}} Repost</button>
  </div>
  <div class="markdown-body">{{markdown content}}</div>
{{/if}}`;

  /** Sidebar author widget with optional follow/unfollow button. */
  const postAuthor = `
<div class="widget">
  <h3>Author</h3>
  <a href="profile.html?id={{urlEncode authorId}}" style="font-weight:bold;">{{authorName}}</a>
  {{#if showFollow}}
  <div style="margin-top:10px;">
    <button id="follow-btn"
      class="btn {{#if following}}btn-secondary{{else}}btn-primary{{/if}} btn-sm"
      data-target-id="{{authorId}}">
      {{#if following}}{{icon "user-minus"}} Unfollow{{else}}{{icon "user-plus"}} Follow{{/if}}
    </button>
  </div>
  {{/if}}
</div>`;

  /** Sidebar "More from author" list. */
  const morePosts = `
<div class="widget">
  <h3>More from {{authorName}}</h3>
  {{#each posts}}
  <div style="margin-bottom:8px;">
    <a href="post.html?id={{urlEncode id}}">{{title}}</a>
  </div>
  {{/each}}
</div>`;

  // ── profile.html ──────────────────────────────────────────────────────────

  /** Profile header: avatar, stats, follow/edit button and posts container. */
  const profileHeader = `
<div class="profile-header">
  <div class="avatar">{{initial username}}</div>
  <div class="profile-info">
    <h2>{{username}}</h2>
    {{#if bio}}<p class="bio">{{bio}}</p>{{/if}}
    <div class="profile-stats">
      <span><strong>{{followers}}</strong> followers</span>
      <span><strong>{{following}}</strong> following</span>
      <span><strong>{{posts}}</strong> posts</span>
    </div>
    <div style="margin-top:10px;">
      {{#if isOwn}}
        <a href="settings.html" class="btn btn-secondary btn-sm">{{icon "settings"}} Edit Profile</a>
      {{else if showFollow}}
        <button id="follow-btn"
          class="btn {{#if isFollowing}}btn-secondary{{else}}btn-primary{{/if}} btn-sm"
          data-target-id="{{profileId}}">
          {{#if isFollowing}}{{icon "user-minus"}} Unfollow{{else}}{{icon "user-plus"}} Follow{{/if}}
        </button>
      {{/if}}
    </div>
  </div>
</div>
<h3 class="section-heading">Posts</h3>
<div id="user-posts"><div class="loading">Loading posts…</div></div>`;

  // ── search.html ───────────────────────────────────────────────────────────

  /** User result card. */
  const userResult = `
<div class="post-card" style="display:flex;align-items:center;gap:12px;">
  <div class="avatar" style="width:40px;height:40px;font-size:18px;">{{initial username}}</div>
  <div>
    <a href="profile.html?id={{urlEncode id}}" class="user-result-link">{{username}}</a>
    {{#if bio}}<div class="post-excerpt" style="margin-top:3px;">{{bio}}</div>{{/if}}
  </div>
</div>`;

  const sectionHeading = `<h3 class="section-heading">{{title}}</h3>`;

  const noResults = `
<div class="empty-state">
  <p>No results found for "<strong>{{query}}</strong>".</p>
</div>`;

  // ── auth.js nav ───────────────────────────────────────────────────────────

  /** Signed-in navigation links. */
  const navAuth = `
<a href="create.html" class="btn-nav-primary btn" aria-label="New Post" title="New Post">{{icon "pen-line"}}</a>
<a href="profile.html?id={{urlEncode id}}" aria-label="Profile" title="Profile">{{icon "user"}}</a>
<a href="#" id="nav-sign-out" aria-label="Sign Out" title="Sign Out">{{icon "log-out"}}</a>`;

  // ── Register all templates as Handlebars partials ─────────────────────────
  const defs = {
    'post-card':       postCard,
    'user-widget':     userWidget,
    'guest-widget':    guestWidget,
    'no-following':    noFollowing,
    'empty-feed':      emptyFeed,
    'sign-in-prompt':  signInPrompt,
    'post-header':     postHeader,
    'post-author':     postAuthor,
    'more-posts':      morePosts,
    'profile-header':  profileHeader,
    'user-result':     userResult,
    'section-heading': sectionHeading,
    'no-results':      noResults,
    'nav-auth':        navAuth,
  };

  for (const [name, src] of Object.entries(defs)) {
    Handlebars.registerPartial(name, Handlebars.compile(src));
  }

  // Mirror partials onto Handlebars.templates so page JS can call
  // Handlebars.templates['post-card'](data) if preferred.
  Handlebars.templates = Handlebars.partials;

}());
