/**
 * tests/auth.test.js – unit tests for js/auth.js
 *
 * Focuses on ensureProfile(), which contained a bug where ALL errors thrown by
 * databases.getDocument() were caught and silently swallowed, causing the
 * subsequent databases.createDocument() call to fail with the original network
 * error (e.g. "Load failed" on Safari) instead of propagating it to the UI.
 */

const { ensureProfile, signUp, signIn, getCurrentUser } = require('../js/auth.js');

// Helper: build an AppwriteException-like error
function appwriteError(message, code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

beforeEach(() => {
  jest.clearAllMocks();
});

// ── ensureProfile ─────────────────────────────────────────────────────────────

describe('ensureProfile()', () => {
  const user = { $id: 'user-abc', name: 'Alice' };

  test('does nothing when the profile document already exists', async () => {
    databases.getDocument.mockResolvedValue({ $id: user.$id });

    await ensureProfile(user);

    expect(databases.getDocument).toHaveBeenCalledWith(
      APPWRITE_DB_ID, COL_USERS, user.$id
    );
    expect(databases.createDocument).not.toHaveBeenCalled();
  });

  test('creates profile document when getDocument returns 404', async () => {
    databases.getDocument.mockRejectedValue(appwriteError('Not found', 404));
    databases.createDocument.mockResolvedValue({ $id: user.$id });

    await ensureProfile(user);

    expect(databases.createDocument).toHaveBeenCalledWith(
      APPWRITE_DB_ID,
      COL_USERS,
      user.$id,
      { userId: user.$id, username: user.name, bio: '' }
    );
  });

  test('rethrows a network error ("Load failed") without calling createDocument', async () => {
    // Simulates what happens on Safari when CORS blocks the fetch
    databases.getDocument.mockRejectedValue(appwriteError('Load failed', 0));

    await expect(ensureProfile(user)).rejects.toThrow('Load failed');
    expect(databases.createDocument).not.toHaveBeenCalled();
  });

  test('rethrows "Failed to fetch" (Chrome network error) without calling createDocument', async () => {
    databases.getDocument.mockRejectedValue(appwriteError('Failed to fetch', 0));

    await expect(ensureProfile(user)).rejects.toThrow('Failed to fetch');
    expect(databases.createDocument).not.toHaveBeenCalled();
  });

  test('rethrows unexpected server errors (500) without calling createDocument', async () => {
    databases.getDocument.mockRejectedValue(appwriteError('Internal Server Error', 500));

    await expect(ensureProfile(user)).rejects.toThrow('Internal Server Error');
    expect(databases.createDocument).not.toHaveBeenCalled();
  });

  test('propagates createDocument errors to the caller', async () => {
    databases.getDocument.mockRejectedValue(appwriteError('Not found', 404));
    databases.createDocument.mockRejectedValue(appwriteError('Permission denied', 401));

    await expect(ensureProfile(user)).rejects.toThrow('Permission denied');
  });
});

// ── signUp ────────────────────────────────────────────────────────────────────

describe('signUp()', () => {
  test('delegates to account.create with a unique ID', async () => {
    account.create.mockResolvedValue({ $id: 'new-user' });

    const result = await signUp('alice@example.com', 'password123', 'Alice');

    expect(account.create).toHaveBeenCalledWith(
      'unique-id', 'alice@example.com', 'password123', 'Alice'
    );
    expect(result).toEqual({ $id: 'new-user' });
  });

  test('propagates account.create errors to the caller', async () => {
    account.create.mockRejectedValue(appwriteError('Load failed', 0));

    await expect(signUp('a@b.com', 'pass1234', 'Bob')).rejects.toThrow('Load failed');
  });
});

// ── signIn ────────────────────────────────────────────────────────────────────

describe('signIn()', () => {
  test('delegates to account.createEmailPasswordSession', async () => {
    account.createEmailPasswordSession.mockResolvedValue({ $id: 'session-1' });

    const result = await signIn('alice@example.com', 'password123');

    expect(account.createEmailPasswordSession).toHaveBeenCalledWith(
      'alice@example.com', 'password123'
    );
    expect(result).toEqual({ $id: 'session-1' });
  });
});

// ── getCurrentUser ────────────────────────────────────────────────────────────

describe('getCurrentUser()', () => {
  test('returns user when session exists', async () => {
    account.get.mockResolvedValue({ $id: 'u1', name: 'Alice' });

    const user = await getCurrentUser();
    expect(user).toEqual({ $id: 'u1', name: 'Alice' });
  });

  test('returns null when not authenticated', async () => {
    account.get.mockRejectedValue(appwriteError('Unauthorized', 401));

    const user = await getCurrentUser();
    expect(user).toBeNull();
  });
});
