/**
 * Appwrite configuration – Octopus project
 *
 * These values are provisioned by scripts/provision-appwrite.sh.
 * Do NOT commit a real API key here; the key lives only in GitHub Secrets.
 */
const APPWRITE_ENDPOINT   = 'https://fra.cloud.appwrite.io/v1';
const APPWRITE_PROJECT_ID = '69f1c06800389dc6a1a0';

// Database (created by the provision script)
const APPWRITE_DB_ID = 'octopus-db';

// Collection IDs – must match what the provision script creates
const COL_POSTS   = 'posts';
const COL_FOLLOWS = 'follows';
const COL_USERS   = 'profiles';

// Storage bucket for post images (created by the provision script)
const APPWRITE_BUCKET_ID = 'post-images';
