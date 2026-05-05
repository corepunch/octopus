#!/usr/bin/env bash
# =============================================================================
# auto-post.sh
#
# Discovers high-engagement content from Reddit, rephrases it with GitHub
# Models AI (gpt-4o-mini), and posts it to Octopus via the Appwrite REST API.
#
#   alice  → quote  (Reddit r/quotes / r/Showerthoughts / r/Stoicism + AI)
#   bob    → link   (Reddit interest-matched subreddits + AI; HN fallback)
#   carol  → photo  (NASA APOD with AI caption; random picsum fallback)
#
# Post types are mapped via USER_POST_TYPE; override POST_AS to restrict which
# users post. Interests are read live from Appwrite profiles; hard-coded
# fallbacks are used only if the profile is unreachable.
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   GITHUB_TOKEN        – GitHub token used for GitHub Models AI access
#
# Optional:
#   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID (defaults provided)
#   POST_AS   – space-separated usernames to post as (default: "alice bob carol")
#   AI_MODEL  – GitHub Models model name (default: gpt-4o-mini)
#
# Usage (local):
#   export APPWRITE_API_KEY=<key> GITHUB_TOKEN=<token>
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
AI_MODEL="${AI_MODEL:-gpt-4o-mini}"

POST_AS="${POST_AS:-alice bob carol}"

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[~]${NC} $*" >&2; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Seed user definitions ─────────────────────────────────────────────────────
declare -A USER_ID=(
  [alice]="seed-user-alice-001"
  [bob]="seed-user-bob-0002"
  [carol]="seed-user-carol-003"
)

# Post type per user, derived from primary interests:
#   alice  = writer / philosopher  → quote (Reddit + AI rephrase)
#   bob    = programmer / tech     → link  (Reddit + AI commentary)
#   carol  = designer / photographer → photo (NASA APOD + AI caption)
declare -A USER_POST_TYPE=(
  [alice]="quote"
  [bob]="link"
  [carol]="photo"
)

# Fallback interests used only when the profile document has no interests field.
declare -A FALLBACK_INTERESTS=(
  [alice]="philosophy writing books science productivity film"
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

# ── Helper: call GitHub Models AI ─────────────────────────────────────────────
# Usage: call_ai <system_prompt> <user_prompt>
# Prints the AI response to stdout; returns empty string on any failure.
call_ai() {
  local system_prompt="$1"
  local user_prompt="$2"

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    warn "  GITHUB_TOKEN not set – AI rephrasing unavailable."
    echo ""; return
  fi

  local payload; payload=$(jq -n \
    --arg model  "$AI_MODEL" \
    --arg system "$system_prompt" \
    --arg user   "$user_prompt" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user",   content: $user}
      ],
      temperature: 0.85,
      max_tokens: 200
    }')

  local raw; raw=$(curl -s --max-time 30 \
    -X POST "https://models.inference.ai.azure.com/chat/completions" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null || echo "")

  echo "$raw" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo ""
}

# ── Helper: fetch top posts from a Reddit subreddit ───────────────────────────
# Usage: fetch_reddit_top <subreddit> [time: hour|day|week|month]
# Returns a JSON array of {title, text, score, url, link_url, subreddit} objects.
fetch_reddit_top() {
  local subreddit="$1"
  local t="${2:-week}"

  local raw; raw=$(curl -s --max-time 20 \
    -H "User-Agent: octopus-autopost/1.0 (+https://github.com/corepunch/octopus)" \
    -H "Accept: application/json" \
    "https://www.reddit.com/r/${subreddit}/top.json?limit=25&t=${t}" 2>/dev/null || echo "")

  [[ -z "$raw" ]] && { echo "[]"; return; }

  # Filter: score > 50, meaningful title, not deleted/removed
  echo "$raw" | jq -c '
    [
      .data.children[]
      | .data
      | select(
          .score > 50
          and (.title | length) > 10
          and (.title   | ascii_downcase | test("\\[removed\\]|\\[deleted\\]") | not)
          and (.selftext | ascii_downcase | test("\\[removed\\]|\\[deleted\\]") | not)
        )
      | {
          title:     .title,
          text:      (.selftext // ""),
          score:     .score,
          url:       ("https://reddit.com" + .permalink),
          link_url:  (.url // ""),
          subreddit: .subreddit
        }
    ]
  ' 2>/dev/null || echo "[]"
}

# ── Helper: pick a random item from a JSON array ──────────────────────────────
pick_random_item() {
  local arr="$1"
  local len; len=$(echo "$arr" | jq 'length' 2>/dev/null || echo "0")
  if [[ "$len" -eq 0 ]]; then echo ""; return; fi
  local idx=$(( RANDOM % len ))
  echo "$arr" | jq -c ".[$idx]" 2>/dev/null || echo ""
}

# ── Helpers: map interests to relevant subreddits ─────────────────────────────
get_quote_subreddits() {
  local interest="$1"
  case "$interest" in
    philosophy|writing|books) echo "quotes Stoicism Showerthoughts philosophy" ;;
    science)                  echo "quotes EverythingScience Showerthoughts"   ;;
    film|art)                 echo "quotes TrueFilm Showerthoughts"            ;;
    productivity)             echo "quotes getdisciplined Showerthoughts"      ;;
    technology|ai)            echo "quotes Futurology Showerthoughts"          ;;
    *)                        echo "quotes Showerthoughts LifeProTips"         ;;
  esac
}

get_link_subreddits() {
  local interest="$1"
  case "$interest" in
    programming)     echo "programming learnprogramming coding"     ;;
    open-source)     echo "opensource linux commandline"            ;;
    web-development) echo "webdev javascript Frontend"              ;;
    ai)              echo "MachineLearning artificial OpenAI"       ;;
    startups)        echo "startups Entrepreneur business"          ;;
    technology)      echo "technology Futurology gadgets"           ;;
    science)         echo "science EverythingScience space"         ;;
    design)          echo "Design graphic_design UI_Design"         ;;
    philosophy)      echo "philosophy AskPhilosophy"                ;;
    books)           echo "books booksuggestions literature"        ;;
    film)            echo "TrueFilm movies flicks"                  ;;
    productivity)    echo "productivity gtd getdisciplined"         ;;
    writing)         echo "writing WritingPrompts worldbuilding"    ;;
    art)             echo "Art ImaginaryLandscapes"                 ;;
    architecture)    echo "architecture UrbanPlanning"              ;;
    travel)          echo "travel solotravel backpacking"           ;;
    *)               echo "interesting todayilearned interestingasfuck" ;;
  esac
}

# ── HN Algolia fallback (used when Reddit is unavailable for link posts) ──────
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

# ── Helper: build a unique random picsum seed (interest + two RANDOM words) ───
random_picsum_seed() {
  local interest="$1"
  echo "${interest}-${RANDOM}-${RANDOM}"
}



# Quote post: find an interesting post from Reddit and rephrase it with AI.
do_quote_post() {
  local username="$1" uid="$2" interests="$3"

  local reddit_post="" used_subreddit=""
  for interest in $interests; do
    local subs; subs=$(get_quote_subreddits "$interest")
    for sub in $subs; do
      info "  Searching r/$sub for quote inspiration…"
      local posts; posts=$(fetch_reddit_top "$sub" "week")
      local item; item=$(pick_random_item "$posts")
      if [[ -n "$item" ]]; then
        reddit_post="$item"
        used_subreddit="$sub"
        break 2
      fi
    done
  done

  local quote_text="" quote_source=""

  if [[ -n "$reddit_post" ]]; then
    local reddit_title; reddit_title=$(echo "$reddit_post" | jq -r '.title')
    local reddit_body;  reddit_body=$(echo  "$reddit_post" | jq -r '.text // ""')
    # Append body preview (with ": " separator) only if body is non-empty; truncate to 300 chars
    local source_text="${reddit_title}${reddit_body:+: ${reddit_body:0:300}}"
    info "  Asking AI to craft a quote inspired by: $reddit_title"
    local ai_response; ai_response=$(call_ai \
      "You are a thoughtful writer who distills wisdom into short, memorable quotes. Write a single, original quote (1-2 sentences, under 140 characters) inspired by the given text. Do NOT copy the text verbatim. Output only the quote itself, no attribution or quotation marks." \
      "Inspire a quote from this: ${source_text:0:500}")
    if [[ -n "$ai_response" ]]; then
      quote_text="$ai_response"
      quote_source="AI – inspired by r/$used_subreddit"
    else
      # AI unavailable: use the Reddit title directly
      quote_text="$reddit_title"
      quote_source="r/$used_subreddit"
    fi
  fi

  # Last resort: zenquotes.io
  if [[ -z "$quote_text" ]]; then
    warn "  Reddit unavailable – falling back to zenquotes.io"
    local q_json; q_json=$(curl -s --max-time 15 "https://zenquotes.io/api/random" \
      | jq -c 'if type == "array" and length > 0 then .[0] | {text: .q, author: .a} else empty end' \
      2>/dev/null || echo "")
    if [[ -z "$q_json" ]]; then
      warn "  All quote sources failed – skipping $username."
      return
    fi
    quote_text=$(echo "$q_json" | jq -r '.text')
    quote_source=$(echo "$q_json" | jq -r '.author')
  fi

  local first_interest; first_interest=$(echo "$interests" | awk '{print $1}')

  # Background image: picsum with a random seed so each run produces a unique image
  local rand_seed; rand_seed=$(random_picsum_seed "$first_interest")
  local img_url="https://picsum.photos/seed/${rand_seed}/1200/800"
  info "  Uploading background photo…"
  local img_id; img_id=$(upload_photo "$img_url")

  # AI-generated personal reaction
  local comment=""
  comment=$(call_ai \
    "You are $username, a thoughtful person who loves $first_interest. Write a brief, genuine 1-sentence reaction (under 80 characters) to a quote. Be authentic, not generic." \
    "Write your reaction to: \"${quote_text:0:200}\"")
  [[ -z "$comment" ]] && comment="Worth sitting with."

  local title; title=$(echo "$quote_text" | cut -c1-80)

  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid      "$uid" \
    --arg uname    "$username" \
    --arg title    "$title" \
    --arg text     "$quote_text" \
    --arg source   "$quote_source" \
    --arg comment  "$comment" \
    --arg interest "$first_interest" \
    --arg imgid    "$img_id" \
    '{
      documentId: "unique()",
      data: ({
        title:       $title,
        content:     $text,
        postType:    "quote",
        quoteSource: $source,
        userText:    $comment,
        authorId:    $uid,
        authorName:  $uname,
        tags:        [$interest, "quote", "inspiration"],
        published:   true
      } + (if $imgid != "" then { imageId: $imgid } else {} end)),
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  ✅  Posted quote as $username: $quote_text"
}

# Link post: find a high-engagement Reddit post and write AI commentary.
do_link_post() {
  local username="$1" uid="$2" interests="$3"

  local reddit_post="" matched_interest="" used_subreddit=""
  for interest in $interests; do
    local subs; subs=$(get_link_subreddits "$interest")
    for sub in $subs; do
      info "  Searching r/$sub for interesting content…"
      local posts; posts=$(fetch_reddit_top "$sub" "week")
      local item; item=$(pick_random_item "$posts")
      if [[ -n "$item" ]]; then
        reddit_post="$item"
        matched_interest="$interest"
        used_subreddit="$sub"
        break 2
      fi
    done
  done

  local title="" url="" commentary="" source_tag="reddit"

  if [[ -n "$reddit_post" ]]; then
    title=$(echo "$reddit_post" | jq -r '.title')
    local score; score=$(echo "$reddit_post" | jq -r '.score')
    local link_url; link_url=$(echo "$reddit_post" | jq -r '.link_url // ""')
    local reddit_url; reddit_url=$(echo "$reddit_post" | jq -r '.url')
    local reddit_text; reddit_text=$(echo "$reddit_post" | jq -r '.text // ""')

    # Prefer the external link over the Reddit thread
    if [[ "$link_url" =~ ^https?:// ]] && [[ "$link_url" != *reddit.com* ]]; then
      url="$link_url"
    else
      url="$reddit_url"
    fi

    info "  Found post: $title ($score points on r/$used_subreddit)"
    local context="${title}${reddit_text:+ – ${reddit_text:0:300}}"
    commentary=$(call_ai \
      "You are $username, a knowledgeable person passionate about ${matched_interest//-/ }. Write a compelling 1-2 sentence post sharing an interesting find. Be insightful and conversational. Under 180 characters." \
      "Write a short post about: \"$context\"")
    [[ -z "$commentary" ]] && commentary="Interesting read on ${matched_interest//-/ }. Worth a look."

  else
    # Reddit unavailable – fall back to Hacker News
    warn "  Reddit unavailable – falling back to Hacker News."
    source_tag="hn"
    local story="" hn_matched=""
    for interest in $interests; do
      local search_term; search_term=$(get_search_term "$interest")
      info "  Searching HN for: \"$search_term\""
      story=$(search_hn "$search_term")
      if [[ -n "$story" ]]; then hn_matched="$interest"; break; fi
    done

    if [[ -z "$story" ]]; then
      warn "  No story found for any interest of $username – skipping."
      return
    fi

    title=$(echo "$story" | jq -r '.title')
    url=$(echo "$story"   | jq -r '.url')
    local points; points=$(echo "$story" | jq -r '.points')
    matched_interest="$hn_matched"
    commentary=$(call_ai \
      "You are $username, a knowledgeable person passionate about ${matched_interest//-/ }. Write a compelling 1-2 sentence post sharing an interesting find. Be insightful and conversational. Under 180 characters." \
      "Write a short post about: \"$title\"")
    [[ -z "$commentary" ]] && commentary="Interesting read on ${matched_interest//-/ }. Found on Hacker News ($points points)."
  fi

  # Validate URL
  case "$url" in
    http://*|https://*) ;;
    *) warn "  Skipping post with non-http(s) URL: $url"; return ;;
  esac

  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid     "$uid" \
    --arg uname   "$username" \
    --arg title   "$title" \
    --arg url     "$url" \
    --arg comment "$commentary" \
    --arg tag     "$matched_interest" \
    --arg src     "$source_tag" \
    '{
      documentId: "unique()",
      data: {
        title:      $title,
        content:    $comment,
        postType:   "link",
        linkUrl:    $url,
        authorId:   $uid,
        authorName: $uname,
        tags:       [$tag, "news", $src],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  ✅  Posted link as $username: $title"
}

# Photo post: NASA APOD with AI-written caption; random picsum fallback.
do_photo_post() {
  local username="$1" uid="$2" interests="$3"
  local first_interest; first_interest=$(echo "$interests" | awk '{print $1}')

  info "  Fetching NASA Astronomy Picture of the Day…"
  local apod; apod=$(fetch_nasa_apod)

  local img_url="" title="" caption="" tag=""

  if [[ -n "$apod" ]]; then
    title=$(echo "$apod"   | jq -r '.title')
    img_url=$(echo "$apod" | jq -r '.url')
    local explanation; explanation=$(echo "$apod" | jq -r '.explanation')
    tag="space"
    caption=$(call_ai \
      "You are $username, a creative person who loves astronomy and photography. Write an engaging 1-2 sentence caption for an astronomy photo. Be enthusiastic and vivid. Under 200 characters." \
      "Write a caption for NASA's Astronomy Picture of the Day titled: \"$title\". Context: ${explanation:0:400}")
    if [[ -z "$caption" ]]; then
      caption=$(echo "$explanation" | fold -s -w 200 | head -1)
      [[ ${#explanation} -gt ${#caption} ]] && caption="${caption}…"
    fi
  else
    # Fallback: picsum with a fully random seed so same-day re-runs differ
    title="Photo of the day"
    local rand_seed; rand_seed=$(random_picsum_seed "$first_interest")
    img_url="https://picsum.photos/seed/${rand_seed}/1200/800"
    caption=$(call_ai \
      "You are $username, a photographer and designer. Write a short, poetic 1-sentence caption for a beautiful photo. Under 100 characters." \
      "Write a caption for a beautiful ${first_interest//-/ } photo")
    [[ -z "$caption" ]] && caption="A visual find."
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
