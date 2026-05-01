#!/usr/bin/env bash
# =============================================================================
# provision-appwrite.sh  (v2 – adds comments and likes collections)
#
# Creates the Octopus database schema on Appwrite using the REST API.
# No npm / Node.js required – only curl and jq.
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0
#
# Usage (local):
#   export APPWRITE_API_KEY=<key>
#   bash scripts/provision-appwrite.sh
#
# Usage (CI): see .github/workflows/provision.yml
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

DB_ID="octopus-db"
DB_NAME="Octopus"

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Helper: Appwrite REST call ─────────────────────────────────────────────────
# Usage: aw <method> <path> [body_json]
# Prints the response body; exits non-zero on HTTP >= 400 (except 409 = already exists,
# 403 = free-tier resource limit = also treat as "already exists" for idempotency)
aw() {
  local method="$1" path="$2" body="${3:-}"
  local args=(
    -s -w "\n%{http_code}"
    -X "$method"
    -H "Content-Type: application/json"
    -H "X-Appwrite-Key: $API_KEY"
    -H "X-Appwrite-Project: $PROJECT"
  )
  [[ -n "$body" ]] && args+=(-d "$body")
  local raw; raw=$(curl "${args[@]}" "$ENDPOINT$path")
  local code; code=$(tail -n1 <<<"$raw")
  local resp; resp=$(sed '$d' <<<"$raw")

  if [[ "$code" -ge 400 && "$code" -ne 409 && "$code" -ne 403 ]]; then
    echo "$resp" | jq -r '.message // "unknown error"' >&2
    err_exit "HTTP $code – $method $path"
  fi
  echo "$resp"
}

# ── Helper: create attribute, skip if 409 or 403 ──────────────────────────────
attr() {
  local col="$1" type="$2" body="$3"
  local raw; raw=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    -d "$body" \
    "$ENDPOINT/databases/$DB_ID/collections/$col/attributes/$type")
  local code; code=$(tail -n1 <<<"$raw")
  if [[ "$code" -ge 400 && "$code" -ne 409 && "$code" -ne 403 ]]; then
    sed '$d' <<<"$raw" | jq -r '.message // empty' >&2
    err_exit "HTTP $code – creating $type attribute on $col"
  fi
}

# ── Helper: poll until all attributes in a collection are 'available' ──────────
# Usage: wait_for_attrs <collectionId> [timeout_seconds=60]
wait_for_attrs() {
  local col="$1" timeout="${2:-60}" elapsed=0 interval=3
  info "  → waiting for attributes to become available…"
  while true; do
    local statuses
    statuses=$(curl -s \
      -H "X-Appwrite-Key: $API_KEY" \
      -H "X-Appwrite-Project: $PROJECT" \
      "$ENDPOINT/databases/$DB_ID/collections/$col/attributes" \
      | jq -r '.attributes[].status' 2>/dev/null || echo "")

    # All must be 'available'; none can be 'processing' or 'stuck'
    if [[ -n "$statuses" ]] && ! grep -q -E 'processing|stuck' <<<"$statuses"; then
      info "  → attributes ready."
      return 0
    fi
    if (( elapsed >= timeout )); then
      err_exit "Timed out waiting for attributes on '$col' after ${timeout}s"
    fi
    sleep "$interval"
    (( elapsed += interval ))
  done
}

# ── 1. Create database ─────────────────────────────────────────────────────────
info "Creating database '$DB_ID'…"
aw POST "/databases" \
  "{\"databaseId\":\"$DB_ID\",\"name\":\"$DB_NAME\"}" >/dev/null
info "Database ready."

# ── 2. Collection: posts ───────────────────────────────────────────────────────
info "Creating collection 'posts'…"
aw POST "/databases/$DB_ID/collections" "$(jq -n \
  --arg id   "posts" \
  --arg name "Posts" \
  '{
    collectionId: $id,
    name:         $name,
    documentSecurity: true,
    permissions: [
      "read(\"any\")",
      "create(\"users\")"
    ]
  }')" >/dev/null

info "  → attributes…"
# title: string(256) optional — only used by text posts
attr posts string "$(jq -n \
  '{key:"title", size:256, required:false}')"

# content: string(65535) required  (markdown body / quote text / photo caption / link description)
attr posts string "$(jq -n \
  '{key:"content", size:65535, required:false}')"

# authorId: string(36) required  (Appwrite user $id)
attr posts string "$(jq -n \
  '{key:"authorId", size:36, required:true}')"

# authorName: string(128) required
attr posts string "$(jq -n \
  '{key:"authorName", size:128, required:true}')"

# tags: string[] – up to 10 tags, each 64 chars
attr posts string "$(jq -n \
  '{key:"tags", size:64, required:false, array:true}')"

# published: boolean (default true)
attr posts boolean "$(jq -n \
  '{key:"published", required:false, default:true}')"

# postType: string(16) — "text" | "photo" | "quote" | "link"
attr posts string "$(jq -n \
  '{key:"postType", size:16, required:false, default:"text"}')"

# imageId: string(36) — Appwrite Storage file ID (photo posts)
attr posts string "$(jq -n \
  '{key:"imageId", size:36, required:false}')"

# linkUrl: string(2048) — URL for link posts
attr posts string "$(jq -n \
  '{key:"linkUrl", size:2048, required:false}')"

# quoteSource: string(256) — attribution for quote posts
attr posts string "$(jq -n \
  '{key:"quoteSource", size:256, required:false}')"

# userText: string(2048) — poster's optional opinion on a quote post
attr posts string "$(jq -n \
  '{key:"userText", size:2048, required:false}')"

info "  → indexes…"
# Wait for all attributes to be available before creating indexes
wait_for_attrs posts

# Full-text search on title
aw POST "/databases/$DB_ID/collections/posts/indexes" "$(jq -n \
  '{
    key:        "idx_title_ft",
    type:       "fulltext",
    attributes: ["title"],
    orders:     ["ASC"]
  }')" >/dev/null

# Key index on authorId (get all posts by a user)
aw POST "/databases/$DB_ID/collections/posts/indexes" "$(jq -n \
  '{
    key:        "idx_author",
    type:       "key",
    attributes: ["authorId"],
    orders:     ["ASC"]
  }')" >/dev/null

# Key index on published (filter published posts)
aw POST "/databases/$DB_ID/collections/posts/indexes" "$(jq -n \
  '{
    key:        "idx_published",
    type:       "key",
    attributes: ["published"],
    orders:     ["ASC"]
  }')" >/dev/null

info "Collection 'posts' done."
# Note: Appwrite does not support indexes on array attributes (tags[]).
# Tag search uses Query.equal('tags', value) which works without an index
# via a collection scan. For large datasets consider a dedicated tags collection.

# ── 3. Collection: follows ─────────────────────────────────────────────────────
info "Creating collection 'follows'…"
aw POST "/databases/$DB_ID/collections" "$(jq -n \
  --arg id   "follows" \
  --arg name "Follows" \
  '{
    collectionId: $id,
    name:         $name,
    documentSecurity: true,
    permissions: [
      "read(\"users\")",
      "create(\"users\")"
    ]
  }')" >/dev/null

info "  → attributes…"
attr follows string "$(jq -n '{key:"followerId",  size:36, required:true}')"
attr follows string "$(jq -n '{key:"followingId", size:36, required:true}')"

info "  → indexes…"
wait_for_attrs follows

# Who does a given user follow?
aw POST "/databases/$DB_ID/collections/follows/indexes" "$(jq -n \
  '{
    key:        "idx_follower",
    type:       "key",
    attributes: ["followerId"],
    orders:     ["ASC"]
  }')" >/dev/null

# Who follows a given user?
aw POST "/databases/$DB_ID/collections/follows/indexes" "$(jq -n \
  '{
    key:        "idx_following",
    type:       "key",
    attributes: ["followingId"],
    orders:     ["ASC"]
  }')" >/dev/null

# Unique pair – prevent duplicate follows
aw POST "/databases/$DB_ID/collections/follows/indexes" "$(jq -n \
  '{
    key:        "idx_unique_follow",
    type:       "unique",
    attributes: ["followerId","followingId"],
    orders:     ["ASC","ASC"]
  }')" >/dev/null

info "Collection 'follows' done."

# ── 4. Collection: profiles ────────────────────────────────────────────────────
info "Creating collection 'profiles'…"
aw POST "/databases/$DB_ID/collections" "$(jq -n \
  --arg id   "profiles" \
  --arg name "Profiles" \
  '{
    collectionId: $id,
    name:         $name,
    documentSecurity: true,
    permissions: [
      "read(\"any\")",
      "create(\"users\")"
    ]
  }')" >/dev/null

info "  → attributes…"
attr profiles string "$(jq -n '{key:"userId",   size:36,   required:true}')"
attr profiles string "$(jq -n '{key:"username", size:128,  required:true}')"
attr profiles string "$(jq -n '{key:"bio",      size:1024, required:false, default:""}')"

info "  → indexes…"
wait_for_attrs profiles

# Unique userId (one profile per user)
aw POST "/databases/$DB_ID/collections/profiles/indexes" "$(jq -n \
  '{
    key:        "idx_user_id_unique",
    type:       "unique",
    attributes: ["userId"],
    orders:     ["ASC"]
  }')" >/dev/null

# Full-text search on username
aw POST "/databases/$DB_ID/collections/profiles/indexes" "$(jq -n \
  '{
    key:        "idx_username_ft",
    type:       "fulltext",
    attributes: ["username"],
    orders:     ["ASC"]
  }')" >/dev/null

info "Collection 'profiles' done."

# ── 5. Collection: comments ───────────────────────────────────────────────────
info "Creating collection 'comments'…"
aw POST "/databases/$DB_ID/collections" "$(jq -n \
  --arg id   "comments" \
  --arg name "Comments" \
  '{
    collectionId: $id,
    name:         $name,
    documentSecurity: true,
    permissions: [
      "read(\"any\")",
      "create(\"users\")"
    ]
  }')" >/dev/null

info "  → attributes…"
# postId: the post being commented on
attr comments string "$(jq -n '{key:"postId",     size:36,   required:true}')"
# authorId: commenter's Appwrite user $id
attr comments string "$(jq -n '{key:"authorId",   size:36,   required:true}')"
# authorName: display name at comment time
attr comments string "$(jq -n '{key:"authorName", size:128,  required:true}')"
# body: comment text (plain text, max 4096 chars)
attr comments string "$(jq -n '{key:"body",       size:4096, required:true}')"
# parentId: empty string for top-level comments, parent comment $id for replies
attr comments string "$(jq -n '{key:"parentId",   size:36,   required:false, default:""}')"

info "  → indexes…"
wait_for_attrs comments

# All comments on a post
aw POST "/databases/$DB_ID/collections/comments/indexes" "$(jq -n \
  '{
    key:        "idx_comments_post",
    type:       "key",
    attributes: ["postId"],
    orders:     ["ASC"]
  }')" >/dev/null

# All replies under a parent comment
aw POST "/databases/$DB_ID/collections/comments/indexes" "$(jq -n \
  '{
    key:        "idx_comments_parent",
    type:       "key",
    attributes: ["parentId"],
    orders:     ["ASC"]
  }')" >/dev/null

info "Collection 'comments' done."

# ── 6. Collection: likes ───────────────────────────────────────────────────────
info "Creating collection 'likes'…"
aw POST "/databases/$DB_ID/collections" "$(jq -n \
  --arg id   "likes" \
  --arg name "Likes" \
  '{
    collectionId: $id,
    name:         $name,
    documentSecurity: true,
    permissions: [
      "read(\"any\")",
      "create(\"users\")"
    ]
  }')" >/dev/null

info "  → attributes…"
# targetId: the $id of the post or comment being liked
attr likes string "$(jq -n '{key:"targetId",   size:36, required:true}')"
# targetType: "post" or "comment"
attr likes string "$(jq -n '{key:"targetType", size:16, required:true}')"
# userId: the user who liked
attr likes string "$(jq -n '{key:"userId",     size:36, required:true}')"

info "  → indexes…"
wait_for_attrs likes

# All likes for a given target (count likes per post/comment)
aw POST "/databases/$DB_ID/collections/likes/indexes" "$(jq -n \
  '{
    key:        "idx_likes_target",
    type:       "key",
    attributes: ["targetId"],
    orders:     ["ASC"]
  }')" >/dev/null

# Prevent duplicate likes: one like per user per target type+id
aw POST "/databases/$DB_ID/collections/likes/indexes" "$(jq -n \
  '{
    key:        "idx_likes_unique",
    type:       "unique",
    attributes: ["userId","targetType","targetId"],
    orders:     ["ASC","ASC","ASC"]
  }')" >/dev/null

info "Collection 'likes' done."

# ── 7. Storage bucket: post-images ────────────────────────────────────────────
info "Creating storage bucket 'post-images'…"
bucket_raw=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/storage/buckets" \
  -d "$(jq -n '{
    bucketId:    "post-images",
    name:        "Post Images",
    permissions: ["read(\"any\")", "create(\"users\")"],
    fileSecurity: false,
    enabled:     true,
    maximumFileSize: 10485760,
    allowedFileExtensions: ["jpg","jpeg","png","gif","webp","avif"]
  }')")
bucket_code=$(tail -n1 <<<"$bucket_raw")
if [[ "$bucket_code" -eq 201 || "$bucket_code" -eq 200 ]]; then
  info "  → Storage bucket 'post-images' created."
elif [[ "$bucket_code" -eq 409 ]]; then
  info "  → Storage bucket 'post-images' already exists – skipping."
else
  warn "  → Could not create storage bucket (HTTP $bucket_code)."
  sed '$d' <<<"$bucket_raw" | jq -r '.message // empty' >&2
fi

# ── 8. Register Web Platform (CORS) ───────────────────────────────────────────
# Appwrite blocks browser requests from origins that are not registered as Web
# platforms on the project (HTTP 403 / CORS errors). Registering the platform
# here means users who run this script never have to do it manually.
#
# GITHUB_PAGES_HOSTNAME – override when the deployment domain differs from the
#                         default. Leave unset to use corepunch.github.io.
PAGES_HOSTNAME="${GITHUB_PAGES_HOSTNAME:-corepunch.github.io}"
info "Registering Web platform '$PAGES_HOSTNAME'…"

platform_raw=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/projects/$PROJECT/platforms" \
  -d "{\"type\":\"web\",\"name\":\"GitHub Pages\",\"hostname\":\"$PAGES_HOSTNAME\"}")
platform_code=$(tail -n1 <<<"$platform_raw")

if [[ "$platform_code" -eq 201 || "$platform_code" -eq 200 ]]; then
  info "  → Web platform '$PAGES_HOSTNAME' registered."
elif [[ "$platform_code" -eq 409 ]]; then
  info "  → Web platform '$PAGES_HOSTNAME' already exists – skipping."
else
  warn "  → Could not register Web platform automatically (HTTP $platform_code)."
  warn "     Add it manually in the Appwrite Console to fix CORS errors:"
  warn "     Project → Overview → Platforms → Add Platform → Web"
  warn "     Hostname: $PAGES_HOSTNAME"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
info "✅  Appwrite schema provisioned successfully."
info "    Database    : $DB_ID"
info "    Collections : posts, follows, profiles, comments, likes"
info "    Storage     : post-images"
info "    Web platform: $PAGES_HOSTNAME"
echo ""
