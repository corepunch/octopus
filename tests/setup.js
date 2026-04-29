/**
 * tests/setup.js – global stubs shared across all test files.
 *
 * Jest loads this file before each test file (setupFiles in jest.config.js).
 * It provides the browser globals that the source files expect so the modules
 * can be required without errors.
 */

// ── Appwrite config constants ────────────────────────────────────────────────
global.APPWRITE_ENDPOINT   = 'https://fra.cloud.appwrite.io/v1';
global.APPWRITE_PROJECT_ID = 'test-project';
global.APPWRITE_DB_ID      = 'octopus-db';
global.COL_POSTS           = 'posts';
global.COL_FOLLOWS         = 'follows';
global.COL_USERS           = 'profiles';

// ── Appwrite SDK stubs ───────────────────────────────────────────────────────
global.account = {
  get:                          jest.fn(),
  create:                       jest.fn(),
  createEmailPasswordSession:   jest.fn(),
  deleteSession:                jest.fn(),
};

global.databases = {
  getDocument:    jest.fn(),
  createDocument: jest.fn(),
  listDocuments:  jest.fn(),
};

global.Query = {
  equal:     jest.fn((a, v) => `equal(${a},${v})`),
  orderDesc: jest.fn((a)    => `orderDesc(${a})`),
  limit:     jest.fn((n)    => `limit(${n})`),
};

global.ID = { unique: jest.fn(() => 'unique-id') };

// ── Handlebars stub ──────────────────────────────────────────────────────────
global.Handlebars = {
  registerHelper:  jest.fn(),
  registerPartial: jest.fn(),
  compile:         jest.fn(() => jest.fn(() => '<div>compiled</div>')),
  partials:        {},
  templates:       {},
};

// ── Utility stubs ────────────────────────────────────────────────────────────
global.escapeHtml = (str) =>
  String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

global.renderTemplate = jest.fn(() => '<div>rendered</div>');
global.renderNav      = jest.fn(async () => {});

// ── window.location stub ─────────────────────────────────────────────────────
// jsdom throws on assignment to window.location.href; stub it.
delete global.window.location;
global.window.location = { href: '' };
