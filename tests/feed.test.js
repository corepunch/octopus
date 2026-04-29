/**
 * tests/feed.test.js – unit tests for js/pages/index.js (loadPosts)
 *
 * Verifies that:
 *  • Posts are rendered correctly when the API call succeeds.
 *  • The actual error message (e.g. "Load failed") is surfaced when the API
 *    call fails, rather than a generic "Check your Appwrite config." string.
 *  • The empty-state template is used when no posts are returned.
 *  • The "Following" tab shows a sign-in prompt for unauthenticated users.
 */

// ── DOM setup ─────────────────────────────────────────────────────────────────
// Provide the minimal HTML that loadPosts() needs.
beforeEach(() => {
  document.body.innerHTML = `
    <div id="posts"><div class="loading">Loading posts…</div></div>
    <button class="feed-tab active" data-tab="discover">Discover</button>
    <button class="feed-tab"        data-tab="following">Following</button>
  `;
  jest.clearAllMocks();
  // Reset renderTemplate to return something identifiable per call
  renderTemplate.mockImplementation((name) => `<div data-template="${name}"></div>`);
});

const { loadPosts } = require('../js/pages/index.js');

// ── Helper data ───────────────────────────────────────────────────────────────
const samplePost = {
  $id:        'post-1',
  title:      'Hello World',
  authorId:   'user-1',
  authorName: 'Alice',
  content:    'Some content',
  tags:       ['test'],
  $createdAt: '2024-01-01T00:00:00Z',
};

// ── Discover tab ──────────────────────────────────────────────────────────────

describe('loadPosts() – discover tab', () => {
  test('renders post cards when the API returns documents', async () => {
    databases.listDocuments.mockResolvedValue({ documents: [samplePost] });

    await loadPosts('discover');

    expect(databases.listDocuments).toHaveBeenCalled();
    expect(renderTemplate).toHaveBeenCalledWith('post-card', expect.objectContaining({
      id:    samplePost.$id,
      title: samplePost.title,
    }));
    expect(document.getElementById('posts').innerHTML).toContain('data-template="post-card"');
  });

  test('renders empty-feed template when no documents are returned', async () => {
    databases.listDocuments.mockResolvedValue({ documents: [] });

    await loadPosts('discover');

    expect(renderTemplate).toHaveBeenCalledWith('empty-feed', expect.anything());
  });

  test('surfaces the real error message when the API call fails', async () => {
    const err = new Error('Load failed');
    databases.listDocuments.mockRejectedValue(err);

    await loadPosts('discover');

    const html = document.getElementById('posts').innerHTML;
    // Must show the actual error – not a generic config message
    expect(html).toContain('Load failed');
    // Must NOT show the old hardcoded generic message
    expect(html).not.toContain('Check your Appwrite config');
  });

  test('surfaces "Failed to fetch" (Chrome network error) in the error message', async () => {
    databases.listDocuments.mockRejectedValue(new Error('Failed to fetch'));

    await loadPosts('discover');

    expect(document.getElementById('posts').innerHTML).toContain('Failed to fetch');
  });

  test('shows a meaningful message even when the error has no .message', async () => {
    databases.listDocuments.mockRejectedValue({ code: 0 });

    await loadPosts('discover');

    const html = document.getElementById('posts').innerHTML;
    expect(html).toContain('Could not load posts');
  });
});

// ── Following tab ─────────────────────────────────────────────────────────────

describe('loadPosts() – following tab, unauthenticated', () => {
  test('shows sign-in prompt when there is no current user', async () => {
    // currentUser is module-level in index.js and starts as null
    await loadPosts('following');

    expect(renderTemplate).toHaveBeenCalledWith('sign-in-prompt', expect.anything());
    // Should not hit the database at all
    expect(databases.listDocuments).not.toHaveBeenCalled();
  });
});
