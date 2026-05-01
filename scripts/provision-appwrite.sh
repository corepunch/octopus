#!/usr/bin/env bash
# =============================================================================
# provision-appwrite.sh
#
# Octopus-specific Appwrite provisioner.
# Delegates all database / storage work to the generic schema-parser, then
# registers the GitHub Pages web platform for CORS.
#
# Dependencies: curl, jq, yq (https://github.com/mikefarah/yq v4+)
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

ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

# Locate the schema and parser relative to this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../schemas/octopus-schema.yaml"
PARSER="${SCRIPT_DIR}/schema-parser.sh"

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[~]${NC} $*"; }

# ── 1. Provision database schema ───────────────────────────────────────────────
bash "$PARSER" "$SCHEMA_FILE"

# ── 2. Register Web Platform (CORS) ───────────────────────────────────────────
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

echo ""
info "✅  Octopus provisioning complete."
info "    Web platform: $PAGES_HOSTNAME"
echo ""
