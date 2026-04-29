/**
 * Appwrite client initialisation.
 * Must be loaded AFTER config.js and the Appwrite SDK CDN script.
 *
 * The Appwrite SDK IIFE build exposes everything on window.Appwrite.
 */

const { Client, Account, Databases, Query, ID } = Appwrite;

const client = new Client()
  .setEndpoint(APPWRITE_ENDPOINT)
  .setProject(APPWRITE_PROJECT_ID);

const account   = new Account(client);
const databases = new Databases(client);

// Verify the connection to the Appwrite backend on every page load.
client.ping()
  .then(() => console.info('[Octopus] Appwrite connection OK'))
  .catch(err => console.warn('[Octopus] Appwrite ping failed – check config.js', err));
