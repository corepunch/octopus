#!/usr/bin/env bash
# =============================================================================
# seed-appwrite.sh
#
# Populates (or re-seeds) the Octopus Appwrite database with sample data:
#   • 3 guest user profiles (no real auth accounts needed for seed data)
#   • 6 sample posts spread across those profiles
#   • 3 follow relationships
#
# Run with --reset to wipe all existing documents first (destructive!).
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1  (default)
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0              (default)
#
# Usage (local):
#   export APPWRITE_API_KEY=<key>
#   bash scripts/seed-appwrite.sh           # add sample data
#   bash scripts/seed-appwrite.sh --reset   # wipe + re-seed
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

DB_ID="octopus-db"
BUCKET_ID="post-images"
RESET=false
[[ "${1:-}" == "--reset" ]] && RESET=true

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

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

# ── Helper: list all document IDs in a collection ────────────────────────────
list_doc_ids() {
  local col="$1"
  curl -s \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$ENDPOINT/databases/$DB_ID/collections/$col/documents?limit=100" \
    | jq -r '.documents[]."$id"'
}

# ── Helper: delete all documents in a collection ─────────────────────────────
delete_all() {
  local col="$1"
  warn "  Deleting all documents in '$col'…"
  local ids; ids=$(list_doc_ids "$col")
  if [[ -z "$ids" ]]; then
    warn "  '$col' is already empty."
    return
  fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    aw DELETE "/databases/$DB_ID/collections/$col/documents/$id" >/dev/null
    echo -e "  ${YELLOW}[~]${NC} deleted $id"
  done <<<"$ids"
}

# ── Helper: delete all files in the storage bucket ───────────────────────────
delete_all_files() {
  warn "  Deleting all files in storage bucket '$BUCKET_ID'…"
  local ids; ids=$(curl -s \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$ENDPOINT/storage/buckets/$BUCKET_ID/files?limit=100" \
    | jq -r '.files[]."$id" // empty')
  if [[ -z "$ids" ]]; then
    warn "  Bucket '$BUCKET_ID' is already empty."
    return
  fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    curl -s -o /dev/null \
      -X DELETE \
      -H "X-Appwrite-Key: $API_KEY" \
      -H "X-Appwrite-Project: $PROJECT" \
      "$ENDPOINT/storage/buckets/$BUCKET_ID/files/$id"
    echo -e "  ${YELLOW}[~]${NC} deleted file $id"
  done <<<"$ids"
}

# ── Helper: download an image from a URL and upload to Appwrite Storage ──────
# Returns the Appwrite file $id on success, or empty string on failure.
upload_photo() {
  local url="$1"
  local tmp_file; tmp_file=$(mktemp /tmp/seed-photo-XXXXXX.jpg)

  info "  Downloading: $url"
  if ! curl -sL --max-time 30 -o "$tmp_file" "$url"; then
    warn "  Could not download image – skipping photo post."
    rm -f "$tmp_file"
    echo ""
    return
  fi

  local raw; raw=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    -F "fileId=unique()" \
    -F "file=@${tmp_file};type=image/jpeg" \
    "$ENDPOINT/storage/buckets/$BUCKET_ID/files")

  rm -f "$tmp_file"

  local code; code=$(tail -n1 <<<"$raw")
  local resp; resp=$(sed '$d' <<<"$raw")

  if [[ "$code" -ge 400 ]]; then
    warn "  Storage upload failed (HTTP $code) – skipping photo post."
    echo "$resp" | jq -r '.message // "unknown error"' >&2
    echo ""
    return
  fi

  echo "$resp" | jq -r '."$id"'
}

# ── Optional reset ────────────────────────────────────────────────────────────
if $RESET; then
  warn "⚠️  RESET MODE – deleting all existing documents and files…"
  delete_all likes
  delete_all comments
  delete_all follows
  delete_all posts
  delete_all profiles
  delete_all_files
  info "All documents and files deleted."
  echo ""
fi

# ── Seed data definitions ─────────────────────────────────────────────────────
# Fake user IDs – UUIDs that don't correspond to real auth accounts.
# The app's ensureProfile() will create real profiles on first login;
# these seed profiles let the feed look populated without real signups.
U1="seed-user-alice-001"
U2="seed-user-bob-0002"
U3="seed-user-carol-003"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")

# ── 1. Profiles ───────────────────────────────────────────────────────────────
info "Creating profiles…"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id   "$U1" \
  --arg uid  "$U1" \
  '{
    documentId: $id,
    data: {
      userId:   $uid,
      username: "alice",
      bio:      "Writer, thinker, Octopus early adopter. I write about tech and culture."
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  alice"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id   "$U2" \
  --arg uid  "$U2" \
  '{
    documentId: $id,
    data: {
      userId:   $uid,
      username: "bob",
      bio:      "Open-source contributor. Mainly writing about software and craft."
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  bob"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id   "$U3" \
  --arg uid  "$U3" \
  '{
    documentId: $id,
    data: {
      userId:   $uid,
      username: "carol",
      bio:      "Product designer and occasional essayist. Based in Berlin."
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  carol"

# ── 2. Posts ──────────────────────────────────────────────────────────────────
info "Creating posts…"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U1" \
  '{
    documentId: "unique()",
    data: {
      title:      "Hello, Octopus 🐙",
      content:    "## Welcome\n\nThis is the **first post** on Octopus.\n\nOctopus is an open markdown blog built on [Appwrite](https://appwrite.io). No build step, no npm — just static files served over a CDN.\n\n### What you can do\n\n- Write in **Markdown**\n- Follow other writers\n- Discover new posts on the feed\n\nHappy writing!",
      authorId:   $uid,
      authorName: "alice",
      tags:       ["announcement","octopus","writing"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Hello, Octopus"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U1" \
  '{
    documentId: "unique()",
    data: {
      title:      "Why I switched to Markdown for everything",
      content:    "## The plain-text revolution\n\nFor years I kept notes in a proprietary app. Then I discovered **Markdown** and never looked back.\n\n### Portability\n\nMarkdown files are just text. They open in any editor, travel in any `git` repo, and render beautifully everywhere.\n\n### Focus\n\nNo toolbar. No style menus. Just you and the words.\n\n```markdown\n**bold**, _italic_, [link](url)\n```\n\nThat is all you need.",
      authorId:   $uid,
      authorName: "alice",
      tags:       ["markdown","productivity","writing"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Markdown for everything"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U2" \
  '{
    documentId: "unique()",
    data: {
      title:      "Building without npm: a love story",
      content:    "## Zero-dependency frontend\n\nEvery JavaScript project ends up with a `node_modules` folder the size of a small country. What if we skipped that entirely?\n\n### CDN-first approach\n\nModern CDNs (jsDelivr, unpkg, Skypack) serve battle-tested libraries directly to the browser. No install step, no bundler, no config.\n\n```html\n<script src=\"https://cdn.jsdelivr.net/npm/handlebars@4.7.8/dist/handlebars.min.js\"></script>\n```\n\nThat single line gives you the full Handlebars templating engine.\n\n### Trade-offs\n\n- ✅  Zero setup\n- ✅  Always the pinned version\n- ⚠️  Requires internet at runtime\n- ⚠️  No tree-shaking\n\nFor a blog? The trade-offs are absolutely worth it.",
      authorId:   $uid,
      authorName: "bob",
      tags:       ["javascript","no-build","frontend","opinion"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Building without npm"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U2" \
  '{
    documentId: "unique()",
    data: {
      title:      "Appwrite as a backend for static sites",
      content:    "## Backend-as-a-Service for static files\n\nStatic sites are fast and cheap to host — but they struggle with dynamic data. **Appwrite** fills that gap.\n\n### What Appwrite gives you\n\n| Feature | Notes |\n|---|---|\n| Auth | Email/password, OAuth, magic links |\n| Database | Collections with indexes and document security |\n| Storage | File uploads with CDN |\n| Functions | Serverless compute |\n\n### Client SDK\n\n```js\nconst client = new Appwrite.Client()\n  .setEndpoint(APPWRITE_ENDPOINT)\n  .setProject(APPWRITE_PROJECT_ID);\n\nconst account = new Appwrite.Account(client);\nawait account.createEmailPasswordSession(email, password);\n```\n\nNo server required.",
      authorId:   $uid,
      authorName: "bob",
      tags:       ["appwrite","backend","javascript"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Appwrite for static sites"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U3" \
  '{
    documentId: "unique()",
    data: {
      title:      "Design tokens and the language of UI",
      content:    "## What is a design token?\n\nA design token is a named, platform-agnostic value that represents a design decision. Instead of hardcoding `#1a8cff` everywhere, you define:\n\n```css\n--color-primary: #1a8cff;\n```\n\nNow every component that uses `--color-primary` inherits the value — and changing the token changes them all.\n\n### Why it matters\n\nDesign tokens create a **shared vocabulary** between designers and developers. Figma exports tokens; code consumes tokens. No more spec-to-implementation drift.\n\n### Three levels of tokens\n\n1. **Global** – raw values (`--blue-500: #1a8cff`)\n2. **Alias** – semantic names (`--color-primary: var(--blue-500)`)\n3. **Component** – scoped (`--button-bg: var(--color-primary)`)",
      authorId:   $uid,
      authorName: "carol",
      tags:       ["design","css","tokens","frontend"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Design tokens"

aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U3" \
  '{
    documentId: "unique()",
    data: {
      title:      "Writing as thinking",
      content:    "## Why I write to understand\n\nI used to think you needed to understand something before you could write about it. I had it backwards.\n\n> Writing is not the record of thinking — it is the thinking itself.\n\n### The mechanism\n\nWhen I try to explain a concept in writing, gaps appear immediately. A vague mental model that felt solid collapses the moment it has to become sentences.\n\n### The practice\n\nI keep a daily note. Not for others — for me. Stream of consciousness, no editing, no structure.\n\nThen I revisit after a week. Some of it is noise. But some of it is the seed of something real.\n\n**Try it for 30 days.** You will think more clearly, I promise.",
      postType:   "text",
      authorId:   $uid,
      authorName: "carol",
      tags:       ["writing","thinking","productivity"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: Writing as thinking"

# ── New posts: mixed types ─────────────────────────────────────────────────────
info "Creating additional posts…"

# alice – quote post
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U1" \
  '{
    documentId: "unique()",
    data: {
      content:     "Simplicity is the ultimate sophistication.",
      postType:    "quote",
      quoteSource: "Leonardo da Vinci",
      userText:    "This has been my design north star for years. Less is always more.",
      authorId:    $uid,
      authorName:  "alice",
      tags:        ["design","quotes","simplicity"],
      published:   true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: quote – On simplicity"

# bob – link post
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U2" \
  '{
    documentId: "unique()",
    data: {
      content: "The official Appwrite documentation is surprisingly readable. Highly recommended for anyone building a BaaS-powered static site.",
      postType: "link",
      linkUrl:  "https://appwrite.io/docs",
      authorId:  $uid,
      authorName: "bob",
      tags:      ["appwrite","docs","reference"],
      published: true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: link – Appwrite Docs"

# carol – quote post
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U3" \
  '{
    documentId: "unique()",
    data: {
      content:     "Good design, when done well, should be invisible. It is only when it is done poorly that we notice it.",
      postType:    "quote",
      quoteSource: "Jony Ive",
      userText:    "The best interfaces are the ones users never have to think about.",
      authorId:    $uid,
      authorName:  "carol",
      tags:        ["design","ux","quotes"],
      published:   true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: quote – Good design"

# alice – link post
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U1" \
  '{
    documentId: "unique()",
    data: {
      content: "A free and open-source reference guide that explains how to use Markdown. Essential reading for any technical writer.",
      postType: "link",
      linkUrl:  "https://www.markdownguide.org",
      authorId:  $uid,
      authorName: "alice",
      tags:      ["markdown","writing","reference"],
      published: true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: link – Markdown Guide"

# bob – quote post with user reaction
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U2" \
  '{
    documentId: "unique()",
    data: {
      content:     "Programs must be written for people to read, and only incidentally for machines to execute.",
      postType:    "quote",
      quoteSource: "Harold Abelson",
      userText:    "This should be hanging on the wall of every engineering team. We spend far more time reading code than writing it — clarity is not a luxury, it is a professional responsibility.",
      authorId:    $uid,
      authorName:  "bob",
      tags:        ["programming","quotes","readability","softwareengineering"],
      published:   true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: quote – On readable code (bob)"

# alice – quote post with user reaction
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U1" \
  '{
    documentId: "unique()",
    data: {
      content:     "The scariest moment is always just before you start.",
      postType:    "quote",
      quoteSource: "Stephen King",
      userText:    "Every blank page I have ever faced. The trick I keep coming back to: lower the stakes. You are not writing the final version — you are writing the first bad version. That permission to be bad is what gets the words moving.",
      authorId:    $uid,
      authorName:  "alice",
      tags:        ["writing","quotes","creativity","advice"],
      published:   true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: quote – On starting (alice)"

# bob – text post about open source
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U2" \
  '{
    documentId: "unique()",
    data: {
      title:      "Why I contribute to open source",
      postType:   "text",
      content:    "## The honest truth\n\nPeople assume open-source contributors are altruistic saints. Some are. Most of us are just solving our own problems and sharing the fix.\n\n### The loop\n\n1. Hit a bug or missing feature.\n2. Dig into the code.\n3. Fix it.\n4. Send the patch upstream.\n\nThe patch benefits the maintainer. The process benefits me far more — reading unfamiliar codebases is the fastest way to grow as an engineer.\n\n### Start small\n\nFix a typo in the docs. Triage one issue. You do not need to write a whole feature on day one.",
      authorId:   $uid,
      authorName: "bob",
      tags:       ["opensource","programming","community"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: text – Why I contribute to open source"

# carol – text post on colour theory
aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
  --arg uid  "$U3" \
  '{
    documentId: "unique()",
    data: {
      title:      "A short guide to colour contrast",
      postType:   "text",
      content:    "## Why contrast matters\n\nPoor colour contrast is one of the most common accessibility failures on the web. WCAG 2.1 requires a **4.5:1** ratio for normal text and **3:1** for large text.\n\n### Quick checks\n\n- Use the [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)\n- Try your UI in greyscale — if it falls apart, contrast is probably the culprit\n- Avoid grey-on-white for body copy\n\n### The bonus\n\nHigh-contrast designs do not just help users with visual impairments. They are easier to read in bright sunlight, on cheap screens, and when you are tired.",
      authorId:   $uid,
      authorName: "carol",
      tags:       ["accessibility","design","css","colour"],
      published:  true
    },
    permissions: ["read(\"any\")"]
  }')" >/dev/null && info "  post: text – Colour contrast guide"

# ── 3. Photo posts (uploaded from picsum.photos) ─────────────────────────────
info "Uploading photo posts from picsum.photos…"

# alice – nature / landscape
IMG1=$(upload_photo "https://picsum.photos/seed/octopus-nature/1200/800")
if [[ -n "$IMG1" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U1" \
    --arg img "$IMG1" \
    '{
      documentId: "unique()",
      data: {
        content:    "Golden hour on a quiet trail. Some mornings the world just looks right.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "alice",
        tags:       ["photography","nature","morning"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Morning light (alice)"
fi

# bob – architecture / city
IMG2=$(upload_photo "https://picsum.photos/seed/octopus-city/1200/800")
if [[ -n "$IMG2" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U2" \
    --arg img "$IMG2" \
    '{
      documentId: "unique()",
      data: {
        content:    "Lines and angles everywhere. Urban spaces have a visual logic of their own.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "bob",
        tags:       ["photography","city","architecture"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: City geometry (bob)"
fi

# carol – abstract / texture
IMG3=$(upload_photo "https://picsum.photos/seed/octopus-abstract/1200/800")
if [[ -n "$IMG3" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U3" \
    --arg img "$IMG3" \
    '{
      documentId: "unique()",
      data: {
        content:    "Close-up surfaces reveal a whole other world of colour and form.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "carol",
        tags:       ["photography","texture","abstract","design"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Texture study (carol)"
fi

# alice – ocean / water
IMG4=$(upload_photo "https://picsum.photos/seed/octopus-ocean/1200/800")
if [[ -n "$IMG4" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U1" \
    --arg img "$IMG4" \
    '{
      documentId: "unique()",
      data: {
        content:    "There is something about open water that resets the mind completely. Stood here for half an hour and felt all the noise drain away.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "alice",
        tags:       ["photography","ocean","nature","mindfulness"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Ocean calm (alice)"
fi

# bob – coffee / workspace
IMG5=$(upload_photo "https://picsum.photos/seed/octopus-desk/1200/800")
if [[ -n "$IMG5" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U2" \
    --arg img "$IMG5" \
    '{
      documentId: "unique()",
      data: {
        content:    "The desk where most of this blog gets written. Minimal on purpose — distractions are the enemy of deep work.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "bob",
        tags:       ["photography","workspace","productivity","minimalism"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Workspace (bob)"
fi

# carol – street / people
IMG6=$(upload_photo "https://picsum.photos/seed/octopus-street/1200/800")
if [[ -n "$IMG6" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U3" \
    --arg img "$IMG6" \
    '{
      documentId: "unique()",
      data: {
        content:    "Street photography teaches you to see the world differently. Every corner is a composition waiting to be noticed.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "carol",
        tags:       ["photography","street","urban","composition"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Street scene (carol)"
fi

# alice – forest / light
IMG7=$(upload_photo "https://picsum.photos/seed/octopus-forest/1200/800")
if [[ -n "$IMG7" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U1" \
    --arg img "$IMG7" \
    '{
      documentId: "unique()",
      data: {
        content:    "Late autumn light through the trees. This is why I always carry a camera.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "alice",
        tags:       ["photography","forest","autumn","light"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Forest light (alice)"
fi

# bob – night city
IMG8=$(upload_photo "https://picsum.photos/seed/octopus-night/1200/800")
if [[ -n "$IMG8" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U2" \
    --arg img "$IMG8" \
    '{
      documentId: "unique()",
      data: {
        content:    "Cities come alive after dark. Long exposures turn headlights into rivers of light.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "bob",
        tags:       ["photography","city","night","longexposure"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Night city (bob)"
fi

# carol – minimalist interior
IMG9=$(upload_photo "https://picsum.photos/seed/octopus-interior/1200/800")
if [[ -n "$IMG9" ]]; then
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid "$U3" \
    --arg img "$IMG9" \
    '{
      documentId: "unique()",
      data: {
        content:    "Negative space is not empty — it is breathing room. This room gets it exactly right.",
        postType:   "photo",
        imageId:    $img,
        authorId:   $uid,
        authorName: "carol",
        tags:       ["photography","interior","design","minimalism"],
        published:  true
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  photo post: Minimalist interior (carol)"
fi

# ── 4. Follows ────────────────────────────────────────────────────────────────
info "Creating follow relationships…"

# bob follows alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg frid "$U2" \
  --arg fgid "$U1" \
  '{
    documentId: "unique()",
    data: { followerId: $frid, followingId: $fgid },
    permissions: ["read(\"users\")"]
  }')" >/dev/null && info "  bob → alice"

# carol follows alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg frid "$U3" \
  --arg fgid "$U1" \
  '{
    documentId: "unique()",
    data: { followerId: $frid, followingId: $fgid },
    permissions: ["read(\"users\")"]
  }')" >/dev/null && info "  carol → alice"

# alice follows carol
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg frid "$U1" \
  --arg fgid "$U3" \
  '{
    documentId: "unique()",
    data: { followerId: $frid, followingId: $fgid },
    permissions: ["read(\"users\")"]
  }')" >/dev/null && info "  alice → carol"

# ── 5. Fetch post IDs for comment & like seeds ────────────────────────────────
info "Fetching post IDs for comment/like seed data…"

# Grab first and second post for each seed author (ordered by creation time)
POST_ALICE=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U1%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)" \
  | jq -r '.documents[0]."$id" // empty')

POST_ALICE2=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U1%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)&queries[]=offset(1)" \
  | jq -r '.documents[0]."$id" // empty')

POST_BOB=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U2%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)" \
  | jq -r '.documents[0]."$id" // empty')

POST_BOB2=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U2%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)&queries[]=offset(1)" \
  | jq -r '.documents[0]."$id" // empty')

POST_CAROL=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U3%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)" \
  | jq -r '.documents[0]."$id" // empty')

POST_CAROL2=$(curl -s \
  -H "X-Appwrite-Key: $API_KEY" \
  -H "X-Appwrite-Project: $PROJECT" \
  "$ENDPOINT/databases/$DB_ID/collections/posts/documents?queries[]=equal(%22authorId%22,%22$U3%22)&queries[]=orderAsc(%22\$createdAt%22)&queries[]=limit(1)&queries[]=offset(1)" \
  | jq -r '.documents[0]."$id" // empty')

info "  alice post 1 : ${POST_ALICE:-<not found>}"
info "  alice post 2 : ${POST_ALICE2:-<not found>}"
info "  bob   post 1 : ${POST_BOB:-<not found>}"
info "  bob   post 2 : ${POST_BOB2:-<not found>}"
info "  carol post 1 : ${POST_CAROL:-<not found>}"
info "  carol post 2 : ${POST_CAROL2:-<not found>}"

# ── 6. Comments ───────────────────────────────────────────────────────────────
info "Creating comments…"

# bob comments on alice's first post (top-level)
if [[ -n "$POST_ALICE" ]]; then
  C1=$(aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_ALICE" \
    --arg uid  "$U2" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "bob",
        body:       "Great first post! This is exactly the kind of content I was hoping to find here.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" | jq -r '."$id"') && info "  bob → alice post (top-level)"

  # carol replies to bob's comment
  if [[ -n "$C1" ]]; then
    aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
      --arg pid  "$POST_ALICE" \
      --arg uid  "$U3" \
      --arg par  "$C1" \
      '{
        documentId: "unique()",
        data: {
          postId:     $pid,
          authorId:   $uid,
          authorName: "carol",
          body:       "Agreed! I also love how clean the layout is.",
          parentId:   $par
        },
        permissions: ["read(\"any\")"]
      }')" >/dev/null && info "  carol replies to bob"
  fi

  # carol also leaves a top-level comment
  C2=$(aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_ALICE" \
    --arg uid  "$U3" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "carol",
        body:       "Welcome to Octopus! Looking forward to reading more from you.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" | jq -r '."$id"') && info "  carol → alice post (top-level)"
fi

# alice comments on bob's first post (top-level)
if [[ -n "$POST_BOB" ]]; then
  C3=$(aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_BOB" \
    --arg uid  "$U1" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "alice",
        body:       "The zero-dependency approach is underrated. I switched to it for my own projects and never looked back.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" | jq -r '."$id"') && info "  alice → bob post (top-level)"

  # bob replies to his own comment thread
  if [[ -n "$C3" ]]; then
    aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
      --arg pid  "$POST_BOB" \
      --arg uid  "$U2" \
      --arg par  "$C3" \
      '{
        documentId: "unique()",
        data: {
          postId:     $pid,
          authorId:   $uid,
          authorName: "bob",
          body:       "Exactly! Once you remove the build step the whole mental model simplifies.",
          parentId:   $par
        },
        permissions: ["read(\"any\")"]
      }')" >/dev/null && info "  bob replies to alice"
  fi
fi

# bob comments on carol's first post
if [[ -n "$POST_CAROL" ]]; then
  aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_CAROL" \
    --arg uid  "$U2" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "bob",
        body:       "Design tokens changed how I collaborate with designers. Highly recommend anyone who hasn'"'"'t tried them.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  bob → carol post"
fi

# carol comments on alice's second post
if [[ -n "$POST_ALICE2" ]]; then
  aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_ALICE2" \
    --arg uid  "$U3" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "carol",
        body:       "The part about portability really resonates — I lost years of notes when I stopped using a proprietary app. Never again.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  carol → alice post 2"
fi

# alice comments on bob's second post
if [[ -n "$POST_BOB2" ]]; then
  C4=$(aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_BOB2" \
    --arg uid  "$U1" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "alice",
        body:       "The table comparing Appwrite features is super helpful. I always forget about magic links — do you use them in production?",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" | jq -r '."$id"') && info "  alice → bob post 2 (top-level)"

  # bob replies
  if [[ -n "$C4" ]]; then
    aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
      --arg pid  "$POST_BOB2" \
      --arg uid  "$U2" \
      --arg par  "$C4" \
      '{
        documentId: "unique()",
        data: {
          postId:     $pid,
          authorId:   $uid,
          authorName: "bob",
          body:       "Not yet — magic links require a mailer integration. For Octopus I stuck with email/password to keep setup minimal.",
          parentId:   $par
        },
        permissions: ["read(\"any\")"]
      }')" >/dev/null && info "  bob replies to alice on post 2"
  fi
fi

# alice and bob comment on carol's second post
if [[ -n "$POST_CAROL2" ]]; then
  aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_CAROL2" \
    --arg uid  "$U1" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "alice",
        body:       "\"Writing is not the record of thinking — it is the thinking itself.\" — this is so true. I started keeping a daily log six months ago and it has changed how I process ideas.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  alice → carol post 2"

  aw POST "/databases/$DB_ID/collections/comments/documents" "$(jq -n \
    --arg pid  "$POST_CAROL2" \
    --arg uid  "$U2" \
    '{
      documentId: "unique()",
      data: {
        postId:     $pid,
        authorId:   $uid,
        authorName: "bob",
        body:       "The 30-day challenge is real. I kept a dev journal for a month and now I can'"'"'t stop. Highly recommend.",
        parentId:   ""
      },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  bob → carol post 2"
fi

# ── 7. Likes ──────────────────────────────────────────────────────────────────
info "Creating likes…"

# bob likes alice's first post
if [[ -n "$POST_ALICE" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_ALICE" \
    --arg uid "$U2" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  bob liked alice's post"

  # carol likes alice's first post
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_ALICE" \
    --arg uid "$U3" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  carol liked alice's post"

  # bob likes carol's top-level comment (C2) on alice's post
  if [[ -n "${C2:-}" ]]; then
    aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
      --arg tid "$C2" \
      --arg uid "$U2" \
      '{
        documentId: "unique()",
        data: { targetId: $tid, targetType: "comment", userId: $uid },
        permissions: ["read(\"any\")"]
      }')" >/dev/null && info "  bob liked carol's comment"
  fi
fi

# alice likes bob's first post
if [[ -n "$POST_BOB" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_BOB" \
    --arg uid "$U1" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  alice liked bob's post"

  # carol likes bob's first post
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_BOB" \
    --arg uid "$U3" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  carol liked bob's post"
fi

# alice and bob like carol's first post
if [[ -n "$POST_CAROL" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_CAROL" \
    --arg uid "$U1" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  alice liked carol's post"

  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_CAROL" \
    --arg uid "$U2" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  bob liked carol's post"
fi

# alice likes bob's second post; carol likes alice's second post
if [[ -n "$POST_BOB2" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_BOB2" \
    --arg uid "$U1" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  alice liked bob's second post"
fi

if [[ -n "$POST_ALICE2" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_ALICE2" \
    --arg uid "$U3" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  carol liked alice's second post"
fi

if [[ -n "$POST_CAROL2" ]]; then
  aw POST "/databases/$DB_ID/collections/likes/documents" "$(jq -n \
    --arg tid "$POST_CAROL2" \
    --arg uid "$U2" \
    '{
      documentId: "unique()",
      data: { targetId: $tid, targetType: "post", userId: $uid },
      permissions: ["read(\"any\")"]
    }')" >/dev/null && info "  bob liked carol's second post"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
info "✅  Seed complete."
info "    Profiles : alice, bob, carol"
info "    Posts    : up to 24 (8 text, 4 quote, 3 link, 9 photo)"
info "    Follows  : 3"
info "    Comments : up to 13 (8 top-level + 4 replies)"
info "    Likes    : up to 12 (11 post + 1 comment)"
echo ""
warn "Note: seed profiles have fake user IDs and are read-only on the frontend."
warn "Real users can sign up and will get their own profiles via ensureProfile()."
