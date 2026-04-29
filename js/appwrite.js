/**
 * Appwrite client initialisation.
 * Must be loaded AFTER config.js and the Appwrite SDK script.
 */

// Appwrite SDK is exposed as `window.Appwrite` via the IIFE CDN build.
const { Client, Account, Databases, Query, ID } = Appwrite;

const client = new Client()
  .setEndpoint(APPWRITE_ENDPOINT)
  .setProject(APPWRITE_PROJECT_ID);

const account   = new Account(client);
const databases = new Databases(client);
