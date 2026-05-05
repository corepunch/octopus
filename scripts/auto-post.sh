#!/usr/bin/env bash
# =============================================================================
# auto-post.sh
#
# Posts one piece of content per seed user, each with a distinct post type
# and drawn from a different source – no more three identical link posts.
#
#   alice  → quote   (random quote from zenquotes.io, background photo from
#                      picsum.photos uploaded to Appwrite Storage)
#   bob    → link    (tech/interest-matched story from Hacker News Algolia)
#   carol  → photo   (NASA Astronomy Picture of the Day, uploaded to Storage;
#                      falls back to a picsum.photos image if APOD is a video)
#
# Post types are mapped via USER_POST_TYPE; override POST_AS to restrict which
# users post. Interests are read live from Appwrite profiles; hard-coded
# fallbacks are used only if the profile is unreachable.
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
BUCKET_ID="post-images"

POST_AS="${POST_AS:-alice bob carol}"

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Seed user definitions ─────────────────────────────────────────────────────
declare -A USER_ID=(
  [alice]="seed-user-alice-001"
  [bob]="seed-user-bob-0002"
  [carol]="seed-user-carol-003"
)

# Post type per user, derived from primary interests:
#   alice  = writer / philosopher  → quote
#   bob    = programmer / tech     → link (Hacker News)
#   carol  = designer / photographer → photo
declare -A USER_POST_TYPE=(
  [alice]="quote"
  [bob]="link"
  [carol]="photo"
)

# Fallback interests used only when the profile document has no interests field.
declare -A FALLBACK_INTERESTS=(
  [alice]="writing technology productivity books science philosophy film"
  [bob]="programming open-source web-development ai startups technology"
  [carol]="design photography art architecture film travel"
)

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

# ── Helper: download an image URL and upload to Appwrite Storage ──────────────
# Prints the uploaded file $id to stdout; all progress goes to stderr.
# Returns an empty string on failure (does not exit the script).
upload_photo() {
  local url="$1"
  local tmp; tmp=$(mktemp /tmp/auto-post-photo-XXXXXX.jpg)

  echo -e "${GREEN}[+]${NC}   Downloading image: $url" >&2
  if ! curl -sL --max-time 30 -o "$tmp" "$url"; then
    echo -e "${YELLOW}[~]${NC}   Could not download image – skipping." >&2
    rm -f "$tmp"; echo ""; return
  fi

  local raw; raw=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    -F "fileId=unique()" \
    -F "file=@${tmp};type=image/jpeg" \
    "$ENDPOINT/storage/buckets/$BUCKET_ID/files")
  rm -f "$tmp"

  local code; code=$(tail -n1 <<<"$raw")
  local resp; resp=$(sed '$d' <<<"$raw")

  if [[ "$code" -ge 400 ]]; then
    echo -e "${YELLOW}[~]${NC}   Storage upload failed (HTTP $code) – skipping." >&2
    echo "$resp" | jq -r '.message // "unknown error"' >&2
    echo ""; return
  fi

  echo "$resp" | jq -r '."$id" // empty'
}

# ── Helper: fetch interests for a user from the profiles collection ────────────
# Returns a space-separated string of interests, or the fallback if absent.
get_user_interests() {
  local uid="$1" fallback="$2"
  local raw
  if ! raw=$(curl -sf --max-time 15 \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$ENDPOINT/databases/$DB_ID/collections/profiles/documents/$uid" 2>/dev/null); then
    warn "  Could not reach Appwrite profile for $uid – using fallback."
    echo "$fallback"; return
  fi

  local interests; interests=$(echo "$raw" | jq -r '(.interests // []) | join(" ")' 2>/dev/null || echo "")
  if [[ -z "$interests" ]]; then
    warn "  No interests found in profile – using fallback."
    echo "$fallback"
  else
    echo "$interests"
  fi
}

# ── Interest → HN search term mapping ────────────────────────────────────────
get_search_term() {
  local interest="$1"
  case "$interest" in
    writing)         echo "writing craft"               ;;
    technology)      echo "technology"                  ;;
    productivity)    echo "productivity"                ;;
    books)           echo "books reading"               ;;
    science)         echo "science research"            ;;
    philosophy)      echo "philosophy"                  ;;
    film)            echo "film cinema"                 ;;
    programming)     echo "programming software"        ;;
    open-source)     echo "open source"                 ;;
    web-development) echo "web development"             ;;
    ai)              echo "artificial intelligence LLM" ;;
    startups)        echo "startup"                     ;;
    design)          echo "design UX"                   ;;
    photography)     echo "photography"                 ;;
    art)             echo "art"                         ;;
    architecture)    echo "architecture"                ;;
    travel)          echo "travel"                      ;;
    *)               echo "$interest"                   ;;
  esac
}

# ── Helper: search HN Algolia for a recent story matching a query ─────────────
# Returns JSON {title, url, points, author} or empty string on failure.
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

# ── Helper: fetch a random quote from zenquotes.io ────────────────────────────
# Returns JSON {text, author} or empty string on failure.
fetch_quote() {
  curl -s --max-time 15 "https://zenquotes.io/api/random" \
    | jq -c 'if type == "array" and length > 0 then .[0] | {text: .q, author: .a} else empty end' \
    2>/dev/null || echo ""
}

# ── Helper: fetch NASA Astronomy Picture of the Day ──────────────────────────
# Returns JSON {title, url, explanation} for image-type APODs, or empty string.
fetch_nasa_apod() {
  local raw; raw=$(curl -s --max-time 20 \
    "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY" 2>/dev/null || echo "")
  [[ -z "$raw" ]] && { echo ""; return; }

  local media_type; media_type=$(echo "$raw" | jq -r '.media_type // ""')
  if [[ "$media_type" != "image" ]]; then
    warn "  NASA APOD is not an image today (type: $media_type) – will use fallback."
    echo ""; return
  fi

  echo "$raw" | jq -c '{title: .title, url: .url, explanation: .explanation}' 2>/dev/null || echo ""
}

# ── Post type handlers ────────────────────────────────────────────────────────

# Quote post: fetch a quote from zenquotes.io and upload a background image.
do_quote_post() {
  local username="$1" uid="$2" interests="$3"

  info "  Fetching quote from zenquotes.io…"
  local quote_json; quote_json=$(fetch_quote)
  if [[ -z "$quote_json" ]]; then
    warn "  Failed to fetch quote from zenquotes.io (network timeout or invalid response) – skipping $username."
    return
  fi

  local text; text=$(echo "$quote_json"   | jq -r '.text')
  local author; author=$(echo "$quote_json" | jq -r '.author')
  local first_interest; first_interest=$(echo "$interests" | awk '{print $1}')

  # Background image: picsum seeded by interest + today's date for reproducibility
  local today; today=$(date -u +"%Y%m%d")
  local img_url="https://picsum.photos/seed/${first_interest}-${today}/1200/800"
  info "  Uploading background photo…"
  local img_id; img_id=$(upload_photo "$img_url")

  # Short personal commentary keyed to alice's primary interest
  local comment
  case "$first_interest" in
    writing|books)   comment="Found this while reading. It stuck with me." ;;
    philosophy)      comment="Something to sit with." ;;
    science)         comment="Empirical wisdom." ;;
    technology|ai)   comment="Still relevant in the age of machines." ;;
    film)            comment="Could be a line from a great film." ;;
    productivity)    comment="A reminder for the week ahead." ;;
    *)               comment="Worth sharing." ;;
  esac

  # Title: first 80 chars of the quote text (required by the schema)
  local title; title=$(echo "$text" | cut -c1-80)

  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid      "$uid" \
    --arg uname    "$username" \
    --arg title    "$title" \
    --arg text     "$text" \
    --arg author   "$author" \
    --arg comment  "$comment" \
    --arg interest "$first_interest" \
    --arg imgid    "$img_id" \
    '{
      documentId: "unique()",
      data: ({
        title:       $title,
        content:     $text,
        postType:    "quote",
        quoteSource: $author,
        userText:    $comment,
        authorId:    $uid,
        authorName:  $uname,
        tags:        [$interest, "quote", "inspiration"],
        published:   true
      } + (if $imgid != "" then { imageId: $imgid } else {} end)),
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  ✅  Posted quote as $username: $text"
}

# Link post: find an interest-matched story on Hacker News.
do_link_post() {
  local username="$1" uid="$2" interests="$3"

  local story="" matched_interest=""

  for interest in $interests; do
    local search_term; search_term=$(get_search_term "$interest")
    info "  Searching HN for: \"$search_term\""
    story=$(search_hn "$search_term")
    if [[ -n "$story" ]]; then
      matched_interest="$interest"
      info "  Found story for interest '$interest'"
      break
    fi
    warn "  No story for '$interest', trying next…"
  done

  if [[ -z "$story" ]]; then
    warn "  No HN story found for any interest of $username – skipping."
    return
  fi

  local title; title=$(echo "$story" | jq -r '.title')
  local url; url=$(echo "$story" | jq -r '.url')
  local points; points=$(echo "$story" | jq -r '.points')
  local hn_author; hn_author=$(echo "$story" | jq -r '.author')

  # Validate http/https to prevent stored XSS / broken links
  case "$url" in
    http://*|https://*) ;;
    *) warn "  Skipping story with non-http(s) URL: $url"; return ;;
  esac

  info "  Story : $title"
  info "  URL   : $url"
  info "  Points: $points by $hn_author on HN"

  local commentary="Interesting read on ${matched_interest//-/ }. Found this on Hacker News ($points points)."

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
        title:      $title,
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
}

# Photo post: NASA APOD image (falls back to a picsum image if APOD is a video).
do_photo_post() {
  local username="$1" uid="$2" interests="$3"
  local first_interest; first_interest=$(echo "$interests" | awk '{print $1}')

  info "  Fetching NASA Astronomy Picture of the Day…"
  local apod; apod=$(fetch_nasa_apod)

  local img_url="" title="" caption="" tag=""

  if [[ -n "$apod" ]]; then
    title=$(echo "$apod"   | jq -r '.title')
    img_url=$(echo "$apod" | jq -r '.url')
    local expl; expl=$(echo "$apod" | jq -r '.explanation')
    # Trim explanation to ~200 characters at a word boundary for the post caption
    caption=$(echo "$expl" | fold -s -w 200 | head -1)
    [[ ${#expl} -gt ${#caption} ]] && caption="${caption}…"
    tag="space"
  else
    # Fallback: picsum image seeded by first interest + today's date
    title="Photo of the day"
    local today; today=$(date -u +"%Y%m%d")
    img_url="https://picsum.photos/seed/${first_interest}-${today}/1200/800"
    caption="A visual find."
    tag="$first_interest"
  fi

  case "$img_url" in
    http://*|https://*) ;;
    *) warn "  Invalid image URL: $img_url – skipping $username."; return ;;
  esac

  info "  Uploading photo to Appwrite Storage…"
  local img_id; img_id=$(upload_photo "$img_url")

  if [[ -z "$img_id" ]]; then
    warn "  Image upload failed – skipping $username."
    return
  fi

  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid    "$uid" \
    --arg uname  "$username" \
    --arg title  "$title" \
    --arg cap    "$caption" \
    --arg imgid  "$img_id" \
    --arg tag    "$tag" \
    '{
      documentId: "unique()",
      data: {
        title:     $title,
        content:   $cap,
        postType:  "photo",
        imageId:   $imgid,
        authorId:  $uid,
        authorName: $uname,
        tags:      [$tag, "photography", "visual"],
        published: true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  ✅  Posted photo as $username: $title"
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

  post_type="${USER_POST_TYPE[$username]:-link}"
  info "Processing $username → $post_type post (interests: $interests)…"

  case "$post_type" in
    quote) do_quote_post "$username" "$uid" "$interests" ;;
    link)  do_link_post  "$username" "$uid" "$interests" ;;
    photo) do_photo_post "$username" "$uid" "$interests" ;;
    *)
      warn "Unknown post type '$post_type' for $username – falling back to link."
      do_link_post "$username" "$uid" "$interests"
      ;;
  esac
done

echo ""
info "✅  Auto-post complete."
