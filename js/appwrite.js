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
// A TypeError here almost always means the current origin is not registered
// as a Web Platform on the Appwrite project (CORS 403).
// Fix: Project → Overview → Platforms → Add Platform → Web.
client.ping()
  .then(() => console.info('[Octopus] Appwrite connection OK'))
  .catch(err => console.warn('[Octopus] Appwrite ping failed – if you see CORS errors, add this origin as a Web Platform in the Appwrite Console (Project → Overview → Platforms)', err));
