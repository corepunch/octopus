#!/usr/bin/env bash
# =============================================================================
# schema-parser.sh
#
# Generic Appwrite schema provisioner.
# Reads a YAML schema file and provisions all databases, collections,
# attributes, indexes, and storage buckets via the Appwrite REST API.
#
# Dependencies: curl, jq, yq (https://github.com/mikefarah/yq v4+)
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0
#
# Usage:
#   bash scripts/schema-parser.sh schemas/octopus-schema.yaml
# =============================================================================
set -euo pipefail

SCHEMA_FILE="${1:?Usage: schema-parser.sh <schema.yaml>}"
ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:?APPWRITE_PROJECT_ID is required}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

# ── Dependency check ───────────────────────────────────────────────────────────
for cmd in curl jq yq; do
  command -v "$cmd" &>/dev/null || {
    echo "Error: '$cmd' is not installed. See https://github.com/mikefarah/yq for yq." >&2
    exit 1
  }
done

[[ -f "$SCHEMA_FILE" ]] || { echo "Error: schema file not found: $SCHEMA_FILE" >&2; exit 1; }

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Helper: Appwrite REST call ─────────────────────────────────────────────────
# Usage: aw <method> <path> [body_json]
# Exits non-zero on HTTP >= 400 (except 409 = already exists,
# 403 = free-tier resource limit — both treated as idempotent success).
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
# Usage: create_attr <collectionId> <type> <body_json>
create_attr() {
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

# ── Read top-level schema values ───────────────────────────────────────────────
DB_ID=$(yq '.database.id' "$SCHEMA_FILE")
DB_NAME=$(yq '.database.name' "$SCHEMA_FILE")

# ── 1. Create database ─────────────────────────────────────────────────────────
info "Creating database '$DB_ID'…"
aw POST "/databases" \
  "{\"databaseId\":\"$DB_ID\",\"name\":\"$DB_NAME\"}" >/dev/null
info "Database ready."

# ── 2. Collections ─────────────────────────────────────────────────────────────
col_count=$(yq '.collections | length' "$SCHEMA_FILE")

for (( ci=0; ci<col_count; ci++ )); do
  col_id=$(yq ".collections[$ci].id" "$SCHEMA_FILE")
  col_name=$(yq ".collections[$ci].name" "$SCHEMA_FILE")
  doc_security=$(yq ".collections[$ci].documentSecurity // true" "$SCHEMA_FILE")
  permissions_json=$(yq -o json ".collections[$ci].permissions" "$SCHEMA_FILE")

  info "Creating collection '$col_id'…"
  aw POST "/databases/$DB_ID/collections" "$(jq -n \
    --arg id "$col_id" \
    --arg name "$col_name" \
    --argjson docSec "$doc_security" \
    --argjson perms "$permissions_json" \
    '{collectionId: $id, name: $name, documentSecurity: $docSec, permissions: $perms}')" >/dev/null

  # ── Attributes ──────────────────────────────────────────────────────────────
  attr_count=$(yq ".collections[$ci].attributes | length" "$SCHEMA_FILE")

  if [[ "$attr_count" -gt 0 ]]; then
    info "  → attributes…"
    for (( ai=0; ai<attr_count; ai++ )); do
      # Extract the full attribute object as JSON; yq preserves correct types
      # (numbers stay numbers, booleans stay booleans, strings stay strings).
      attr_json=$(yq -o json ".collections[$ci].attributes[$ai]" "$SCHEMA_FILE")
      attr_type=$(echo "$attr_json" | jq -r '.type')

      # Remove the 'type' field — Appwrite takes it as a URL path parameter,
      # not in the request body.
      body=$(echo "$attr_json" | jq 'del(.type)')

      create_attr "$col_id" "$attr_type" "$body"
    done
  fi

  # ── Indexes ─────────────────────────────────────────────────────────────────
  idx_count=$(yq ".collections[$ci].indexes | length" "$SCHEMA_FILE")

  if [[ "$idx_count" -gt 0 ]]; then
    info "  → indexes…"
    wait_for_attrs "$col_id"

    for (( ii=0; ii<idx_count; ii++ )); do
      idx_json=$(yq -o json ".collections[$ci].indexes[$ii]" "$SCHEMA_FILE")
      aw POST "/databases/$DB_ID/collections/$col_id/indexes" "$idx_json" >/dev/null
    done
  fi

  info "Collection '$col_id' done."
done

# ── 3. Storage buckets ─────────────────────────────────────────────────────────
bucket_count=$(yq '.storage | length' "$SCHEMA_FILE")

if [[ "$bucket_count" -gt 0 ]]; then
  for (( bi=0; bi<bucket_count; bi++ )); do
    bucket_id=$(yq ".storage[$bi].id" "$SCHEMA_FILE")
    bucket_name=$(yq ".storage[$bi].name" "$SCHEMA_FILE")
    bucket_json=$(yq -o json ".storage[$bi]" "$SCHEMA_FILE")

    # Remap schema fields to Appwrite bucket API fields
    bucket_body=$(echo "$bucket_json" | jq '{
      bucketId:              .id,
      name:                  .name,
      permissions:           .permissions,
      fileSecurity:          (.fileSecurity // false),
      enabled:               (.enabled // true),
      maximumFileSize:       (.maximumFileSize // 10485760),
      allowedFileExtensions: (.allowedFileExtensions // [])
    }')

    info "Creating storage bucket '$bucket_id'…"
    bucket_raw=$(curl -s -w "\n%{http_code}" \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Appwrite-Key: $API_KEY" \
      -H "X-Appwrite-Project: $PROJECT" \
      -d "$bucket_body" \
      "$ENDPOINT/storage/buckets")
    bucket_code=$(tail -n1 <<<"$bucket_raw")

    if [[ "$bucket_code" -eq 201 || "$bucket_code" -eq 200 ]]; then
      info "  → Storage bucket '$bucket_id' created."
    elif [[ "$bucket_code" -eq 409 ]]; then
      info "  → Storage bucket '$bucket_id' already exists – skipping."
    else
      warn "  → Could not create storage bucket '$bucket_id' (HTTP $bucket_code)."
      sed '$d' <<<"$bucket_raw" | jq -r '.message // empty' >&2
    fi
  done
fi

# ── Done ───────────────────────────────────────────────────────────────────────
col_ids=$(yq -o json '.collections[].id' "$SCHEMA_FILE" | jq -rs 'join(", ")')
bucket_ids=$(yq -o json '.storage[].id' "$SCHEMA_FILE" 2>/dev/null | jq -rs 'join(", ")' || echo "none")

echo ""
info "✅  Schema provisioned successfully."
info "    Database    : $DB_ID"
info "    Collections : $col_ids"
info "    Storage     : $bucket_ids"
echo ""
