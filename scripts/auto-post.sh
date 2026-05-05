#!/usr/bin/env bash
# =============================================================================
# auto-post.sh
#
# For each seed user (alice, bob, carol), fetches their interests from the
# Appwrite profiles collection, searches the Hacker News Algolia API for a
# recent story matching one of those interests, then creates a link post in
# the Appwrite database.
#
# Interests are read live from the profile document so they stay in sync with
# any edits made via the UI. Hard-coded fallbacks are used only if the profile
# is unreachable or has no interests field.
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1  (default)
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0              (default)
#
# Optional:
#   POST_AS – space-separated list of usernames to post as (default: "alice bob carol")
#             e.g.  POST_AS="alice"   to post only as alice
#
# Usage (local):
#   export APPWRITE_API_KEY=<key>
#   bash scripts/auto-post.sh
#
# Usage (CI): see .github/workflows/auto-post.yml
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"
DB_ID="octopus-db"

POST_AS="${POST_AS:-alice bob carol}"

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Seed user definitions ─────────────────────────────────────────────────────
# These match the IDs created by seed-appwrite.sh
declare -A USER_ID=(
  [alice]="seed-user-alice-001"
  [bob]="seed-user-bob-0002"
  [carol]="seed-user-carol-003"
)

# Fallback interests used only when the profile document has no interests field.
declare -A FALLBACK_INTERESTS=(
  [alice]="writing technology productivity books science philosophy film"
  [bob]="programming open-source web-development ai startups technology"
  [carol]="design photography art architecture film travel"
)

# ── Helper: fetch interests for a user from the profiles collection ────────────
# Returns a space-separated string of interest values, or the fallback if absent.
get_user_interests() {
  local uid="$1" fallback="$2"
  local raw
  if ! raw=$(curl -sf --max-time 15 \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$ENDPOINT/databases/$DB_ID/collections/profiles/documents/$uid" 2>/dev/null); then
    warn "  Could not reach Appwrite profile for $uid – using fallback."
    echo "$fallback"
    return
  fi

  local interests; interests=$(echo "$raw" | jq -r '(.interests // []) | join(" ")' 2>/dev/null || echo "")
  if [[ -z "$interests" ]]; then
    warn "  No interests found in profile – using fallback."
    echo "$fallback"
  else
    echo "$interests"
  fi
}

# ── Interest → search terms mapping ──────────────────────────────────────────
# Maps an interest keyword to the search query used against HN Algolia.
get_search_term() {
  local interest="$1"
  case "$interest" in
    writing)        echo "writing craft"        ;;
    technology)     echo "technology"           ;;
    productivity)   echo "productivity"         ;;
    books)          echo "books reading"        ;;
    science)        echo "science research"     ;;
    philosophy)     echo "philosophy"           ;;
    film)           echo "film cinema"          ;;
    programming)    echo "programming software" ;;
    open-source)    echo "open source"          ;;
    web-development)echo "web development"      ;;
    ai)             echo "artificial intelligence LLM" ;;
    startups)       echo "startup"              ;;
    design)         echo "design UX"            ;;
    photography)    echo "photography"          ;;
    art)            echo "art"                  ;;
    architecture)   echo "architecture"         ;;
    travel)         echo "travel"               ;;
    *)              echo "$interest"            ;;
  esac
}

# ── Helper: Appwrite REST call ─────────────────────────────────────────────────
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

  if [[ "$code" -ge 400 ]]; then
    echo "$resp" | jq -r '.message // "unknown error"' >&2
    err_exit "HTTP $code – $method $path"
  fi
  echo "$resp"
}

# ── Helper: search HN Algolia for a recent story matching a query ─────────────
# Returns a JSON object {title, url, author, points} or empty string on failure.
search_hn() {
  local query="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query" 2>/dev/null \
    || echo "${query// /+}")

  local result; result=$(curl -s --max-time 15 \
    "https://hn.algolia.com/api/v1/search_by_date?query=${encoded}&tags=story&hitsPerPage=20" \
    | jq -c '
        .hits
        | map(select(.url != null and .url != "" and (.title | length) > 10))
        | first
        | if . == null then empty else
            { title: .title, url: .url, points: (.points // 0), author: (.author // "unknown") }
          end
      ' 2>/dev/null || echo "")

  echo "$result"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
for username in $POST_AS; do
  uid="${USER_ID[$username]:-}"
  if [[ -z "$uid" ]]; then
    warn "Unknown user '$username' – skipping."
    continue
  fi

  fallback="${FALLBACK_INTERESTS[$username]:-technology}"
  info "Fetching interests for $username from Appwrite profile…"
  interests=$(get_user_interests "$uid" "$fallback")
  info "Processing $username (interests: $interests)…"

  story=""
  matched_interest=""

  # Try each interest in order until we find a story with a URL
  for interest in $interests; do
    search_term=$(get_search_term "$interest")
    info "  Searching HN for: \"$search_term\""
    story=$(search_hn "$search_term")
    if [[ -n "$story" ]]; then
      matched_interest="$interest"
      info "  Found story for interest '$interest'"
      break
    fi
    warn "  No story found for '$interest', trying next…"
  done

  if [[ -z "$story" ]]; then
    warn "  No HN story found for any interest of $username – skipping."
    continue
  fi

  title=$(echo "$story" | jq -r '.title')
  url=$(echo "$story" | jq -r '.url')
  points=$(echo "$story" | jq -r '.points')
  hn_author=$(echo "$story" | jq -r '.author')

  # Validate that the URL uses http or https to prevent stored XSS / broken links
  case "$url" in
    http://*|https://*) ;;
    *)
      warn "  Skipping story with non-http(s) URL: $url"
      continue
      ;;
  esac

  info "  Story: $title"
  info "  URL  : $url"
  info "  Points: $points by $hn_author on HN"

  # Build a short user commentary
  commentary="Interesting read on ${matched_interest//-/ }. Found this on Hacker News ($points points)."

  # Create the link post
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid     "$uid" \
    --arg uname   "$username" \
    --arg title   "$title" \
    --arg url     "$url" \
    --arg comment "$commentary" \
    --arg tag     "$matched_interest" \
    '{
      documentId: "unique()",
      data: {
        content:    $comment,
        postType:   "link",
        linkUrl:    $url,
        authorId:   $uid,
        authorName: $uname,
        tags:       [$tag, "news", "hn"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  ✅  Posted link as $username: $title"
done

echo ""
info "✅  Auto-post complete."
