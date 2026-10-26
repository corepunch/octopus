#!/usr/bin/env bash
# =============================================================================
# seed-avatars.sh
#
# Gives the seed users (alice, bob, carol, dave, eve) profile photos. Each
# portrait in scripts/avatars/<username>.jpg is uploaded to the post-images
# bucket and its file ID stored in the profile's `avatarId`, the attribute the
# website, the Octopus app and Chat read. Profiles that don't exist yet are
# skipped, so run it after seed-appwrite.sh or seed-100-posts.sh.
#
# Re-running replaces each photo and deletes the one it replaces.
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1  (default)
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0              (default)
#
# Usage (local):
#   export APPWRITE_API_KEY=<key>
#   bash scripts/seed-avatars.sh
# =============================================================================
set -euo pipefail

ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

DB_ID="octopus-db"
BUCKET_ID="post-images"
AVATAR_DIR="$(cd "$(dirname "$0")" && pwd)/avatars"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# curl with the server key; prints the body and fails on HTTP errors.
aw() {
  local raw code
  raw=$(curl -s -w "\n%{http_code}" \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$@")
  code=$(tail -n1 <<<"$raw")
  if [[ "$code" -ge 400 ]]; then
    sed '$d' <<<"$raw" | jq -r '.message // "unknown error"' >&2
    return 1
  fi
  sed '$d' <<<"$raw"
}

declare -A USERS=(
  [alice]="seed-user-alice-001"
  [bob]="seed-user-bob-0002"
  [carol]="seed-user-carol-003"
  [dave]="seed-user-dave-004"
  [eve]="seed-user-eve-0005"
)

info "Uploading seed profile photos…"
for name in alice bob carol dave eve; do
  uid="${USERS[$name]}"
  photo="$AVATAR_DIR/$name.jpg"
  if [[ ! -f "$photo" ]]; then
    warn "  $name has no portrait at $photo – skipping."
    continue
  fi

  if ! profile=$(aw "$ENDPOINT/databases/$DB_ID/collections/profiles/documents/$uid" 2>/dev/null); then
    warn "  $name has no profile yet – skipping."
    continue
  fi
  previous=$(jq -r '.avatarId // empty' <<<"$profile")

  file=$(aw -X POST \
    -F "fileId=unique()" \
    -F "file=@${photo};type=image/jpeg" \
    -F 'permissions[]=read("any")' \
    "$ENDPOINT/storage/buckets/$BUCKET_ID/files") || err_exit "Upload failed for $name"
  file_id=$(jq -r '."$id"' <<<"$file")

  aw -X PATCH -H "Content-Type: application/json" \
    -d "$(jq -n --arg id "$file_id" '{data:{avatarId:$id}}')" \
    "$ENDPOINT/databases/$DB_ID/collections/profiles/documents/$uid" >/dev/null \
    || err_exit "Could not set $name's avatarId (has the provision workflow added it?)"
  info "  $name → $file_id"

  if [[ -n "$previous" && "$previous" != "$file_id" ]]; then
    aw -X DELETE "$ENDPOINT/storage/buckets/$BUCKET_ID/files/$previous" >/dev/null 2>&1 \
      || warn "  could not delete $name's previous photo $previous"
  fi
done
info "✅  Profile photos set."
