#!/usr/bin/env bash
# =============================================================================
# seed-100-posts.sh
#
# Generates 100 posts of various types (text, quote, link, photo) from 5
# seed users and creates follow relationships between them.
#
# Users created: alice, bob, carol, dave, eve
# Post distribution: ~55 text · ~20 quote · ~15 link · ~10 photo
#
# Run with --reset to delete all existing posts/follows first (keeps profiles).
#
# Required environment variables:
#   APPWRITE_API_KEY    – server-side API key (stored in GitHub Secrets)
#   APPWRITE_ENDPOINT   – e.g. https://fra.cloud.appwrite.io/v1  (default)
#   APPWRITE_PROJECT_ID – e.g. 69f1c06800389dc6a1a0              (default)
#
# Usage (local):
#   export APPWRITE_API_KEY=<key>
#   bash scripts/seed-100-posts.sh           # add data (idempotent)
#   bash scripts/seed-100-posts.sh --reset   # wipe posts/follows then re-seed
# =============================================================================
set -euo pipefail

ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT="${APPWRITE_PROJECT_ID:-69f1c06800389dc6a1a0}"
API_KEY="${APPWRITE_API_KEY:?APPWRITE_API_KEY is required}"

DB_ID="octopus-db"
BUCKET_ID="post-images"
RESET=false
[[ "${1:-}" == "--reset" ]] && RESET=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[~]${NC} $*"; }
err_exit(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }

# ── Appwrite REST helper (exits on >= 400, ignores 409 conflict) ─────────────
aw() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-s -w "\n%{http_code}" -X "$method"
    -H "Content-Type: application/json"
    -H "X-Appwrite-Key: $API_KEY"
    -H "X-Appwrite-Project: $PROJECT")
  [[ -n "$body" ]] && args+=(-d "$body")
  local raw; raw=$(curl "${args[@]}" "$ENDPOINT$path")
  local code; code=$(tail -n1 <<<"$raw")
  local resp; resp=$(sed '$d' <<<"$raw")
  if [[ "$code" -ge 400 && "$code" -ne 409 ]]; then
    echo "$resp" | jq -r '.message // "unknown error"' >&2
    err_exit "HTTP $code – $method $path"
  fi
  echo "$resp"
}

# ── List all document IDs in a collection (paginates up to 200) ──────────────
list_doc_ids() {
  local col="$1"
  curl -s \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "X-Appwrite-Project: $PROJECT" \
    "$ENDPOINT/databases/$DB_ID/collections/$col/documents?limit=200" \
    | jq -r '.documents[]."$id"'
}

# ── Delete all documents in a collection ─────────────────────────────────────
delete_all() {
  local col="$1"
  warn "  Deleting all documents in '$col'…"
  local ids; ids=$(list_doc_ids "$col")
  if [[ -z "$ids" ]]; then warn "  '$col' is already empty."; return; fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    aw DELETE "/databases/$DB_ID/collections/$col/documents/$id" >/dev/null
    echo -e "  ${YELLOW}[~]${NC} deleted $id"
  done <<<"$ids"
}

# ── Download an image and upload to Appwrite Storage ─────────────────────────
# Diagnostic output goes to stderr so the caller can capture only the file ID.
upload_photo() {
  local url="$1"
  local tmp; tmp=$(mktemp /tmp/seed-photo-XXXXXX.jpg)
  echo -e "${GREEN}[+]${NC}   Downloading: $url" >&2
  if ! curl -sL --max-time 30 -o "$tmp" "$url"; then
    echo -e "${YELLOW}[~]${NC}   Could not download image – skipping photo post." >&2
    rm -f "$tmp"; echo ""; return
  fi
  local raw; raw=$(curl -s -w "\n%{http_code}" -X POST \
    -H "X-Appwrite-Key: $API_KEY" -H "X-Appwrite-Project: $PROJECT" \
    -F "fileId=unique()" -F "file=@${tmp};type=image/jpeg" \
    "$ENDPOINT/storage/buckets/$BUCKET_ID/files")
  rm -f "$tmp"
  local code; code=$(tail -n1 <<<"$raw")
  local resp; resp=$(sed '$d' <<<"$raw")
  if [[ "$code" -ge 400 ]]; then
    echo -e "${YELLOW}[~]${NC}   Storage upload failed (HTTP $code) – skipping photo post." >&2
    echo "$resp" | jq -r '.message // "unknown error"' >&2; echo ""; return
  fi
  echo "$resp" | jq -r '."$id" // empty'
}

# ── Convenience wrappers ──────────────────────────────────────────────────────
create_text_post() {
  local uid="$1" uname="$2" title="$3" content="$4" tags_json="$5"
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid    "$uid"     \
    --arg uname  "$uname"   \
    --arg title  "$title"   \
    --arg body   "$content" \
    --argjson tags "$tags_json" \
    '{documentId:"unique()",data:{title:$title,content:$body,postType:"text",
      authorId:$uid,authorName:$uname,tags:$tags,published:true},
      permissions:["read(\"any\")"]}')" >/dev/null && info "  text: $title"
}

create_quote_post() {
  local uid="$1" uname="$2" title="$3" content="$4" source="$5" tags_json="$6"
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid    "$uid"     \
    --arg uname  "$uname"   \
    --arg title  "$title"   \
    --arg body   "$content" \
    --arg src    "$source"  \
    --argjson tags "$tags_json" \
    '{documentId:"unique()",data:{title:$title,content:$body,postType:"quote",
      quoteSource:$src,authorId:$uid,authorName:$uname,tags:$tags,published:true},
      permissions:["read(\"any\")"]}')" >/dev/null && info "  quote: $title"
}

create_link_post() {
  local uid="$1" uname="$2" title="$3" content="$4" url="$5" tags_json="$6"
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid    "$uid"     \
    --arg uname  "$uname"   \
    --arg title  "$title"   \
    --arg body   "$content" \
    --arg lurl   "$url"     \
    --argjson tags "$tags_json" \
    '{documentId:"unique()",data:{title:$title,content:$body,postType:"link",
      linkUrl:$lurl,authorId:$uid,authorName:$uname,tags:$tags,published:true},
      permissions:["read(\"any\")"]}')" >/dev/null && info "  link: $title"
}

create_photo_post() {
  local uid="$1" uname="$2" title="$3" content="$4" img_id="$5" tags_json="$6"
  [[ -z "$img_id" ]] && { warn "  No image ID – skipping photo: $title"; return; }
  aw POST "/databases/$DB_ID/collections/posts/documents" "$(jq -n \
    --arg uid    "$uid"     \
    --arg uname  "$uname"   \
    --arg title  "$title"   \
    --arg body   "$content" \
    --arg img    "$img_id"  \
    --argjson tags "$tags_json" \
    '{documentId:"unique()",data:{title:$title,content:$body,postType:"photo",
      imageId:$img,authorId:$uid,authorName:$uname,tags:$tags,published:true},
      permissions:["read(\"any\")"]}')" >/dev/null && info "  photo: $title"
}

# ── Optional reset ────────────────────────────────────────────────────────────
if $RESET; then
  warn "⚠️  RESET MODE – deleting all existing posts and follows…"
  delete_all follows
  delete_all posts
  info "Posts and follows deleted. Profiles kept."
  echo ""
fi

# ── User IDs ──────────────────────────────────────────────────────────────────
U1="seed-user-alice-001"
U2="seed-user-bob-0002"
U3="seed-user-carol-003"
U4="seed-user-dave-004"
U5="seed-user-eve-0005"

# ── 1. Profiles (409 = already exists = OK) ───────────────────────────────────
info "Ensuring profiles exist…"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id "$U1" --arg uid "$U1" \
  '{documentId:$id,data:{userId:$uid,username:"alice",
    bio:"Writer, thinker, Octopus early adopter. I write about tech and culture."},
    permissions:["read(\"any\")"]}')" >/dev/null && info "  alice"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id "$U2" --arg uid "$U2" \
  '{documentId:$id,data:{userId:$uid,username:"bob",
    bio:"Open-source contributor. Mainly writing about software and craft."},
    permissions:["read(\"any\")"]}')" >/dev/null && info "  bob"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id "$U3" --arg uid "$U3" \
  '{documentId:$id,data:{userId:$uid,username:"carol",
    bio:"Product designer and occasional essayist. Based in Berlin."},
    permissions:["read(\"any\")"]}')" >/dev/null && info "  carol"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id "$U4" --arg uid "$U4" \
  '{documentId:$id,data:{userId:$uid,username:"dave",
    bio:"Science communicator and amateur philosopher. Fascinated by systems thinking."},
    permissions:["read(\"any\")"]}')" >/dev/null && info "  dave"

aw POST "/databases/$DB_ID/collections/profiles/documents" "$(jq -n \
  --arg id "$U5" --arg uid "$U5" \
  '{documentId:$id,data:{userId:$uid,username:"eve",
    bio:"Musician, illustrator, and occasional coder. Writing about art and process."},
    permissions:["read(\"any\")"]}')" >/dev/null && info "  eve"

# ── 2. Pre-upload photos ──────────────────────────────────────────────────────
info "Uploading photos from picsum.photos…"
IMG_ALICE1=$(upload_photo "https://picsum.photos/seed/alice-morning/1200/800")
IMG_ALICE2=$(upload_photo "https://picsum.photos/seed/alice-forest/1200/800")
IMG_BOB1=$(upload_photo "https://picsum.photos/seed/bob-city/1200/800")
IMG_BOB2=$(upload_photo "https://picsum.photos/seed/bob-code/1200/800")
IMG_CAROL1=$(upload_photo "https://picsum.photos/seed/carol-texture/1200/800")
IMG_CAROL2=$(upload_photo "https://picsum.photos/seed/carol-studio/1200/800")
IMG_DAVE1=$(upload_photo "https://picsum.photos/seed/dave-cosmos/1200/800")
IMG_DAVE2=$(upload_photo "https://picsum.photos/seed/dave-nature/1200/800")
IMG_EVE1=$(upload_photo "https://picsum.photos/seed/eve-abstract/1200/800")
IMG_EVE2=$(upload_photo "https://picsum.photos/seed/eve-portrait/1200/800")

# =============================================================================
# 3. Posts — 100 total (55 text · 20 quote · 15 link · 10 photo)
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# ALICE — 20 posts  (11 text · 4 quote · 3 link · 2 photo)
# ─────────────────────────────────────────────────────────────────────────────
info "Creating Alice's posts…"

create_text_post "$U1" "alice" \
  "Hello, Octopus 🐙" \
  "## Welcome\n\nThis is the **first post** on Octopus.\n\nOctopus is an open markdown blog built on [Appwrite](https://appwrite.io). No build step, no npm — just static files served over a CDN.\n\n### What you can do\n\n- Write in **Markdown**\n- Follow other writers\n- Discover new posts on the feed\n\nHappy writing!" \
  '["announcement","octopus","writing"]'

create_text_post "$U1" "alice" \
  "Why I switched to Markdown for everything" \
  "## The plain-text revolution\n\nFor years I kept notes in a proprietary app. Then I discovered **Markdown** and never looked back.\n\n### Portability\n\nMarkdown files are just text. They open in any editor, travel in any \`git\` repo, and render beautifully everywhere.\n\n### Focus\n\nNo toolbar. No style menus. Just you and the words.\n\n\`\`\`markdown\n**bold**, _italic_, [link](url)\n\`\`\`\n\nThat is all you need." \
  '["markdown","productivity","writing"]'

create_text_post "$U1" "alice" \
  "The editor is not the point" \
  "## Tool obsession\n\nEvery few months a new text editor appears and writers spend a week debating fonts and keybindings instead of writing.\n\nThe editor is not the point. The cursor is. The words that follow the cursor — those are the point.\n\n### What actually matters\n\n1. Show up every day.\n2. Finish drafts even when they are bad.\n3. Edit ruthlessly.\n\nNo plugin changes that." \
  '["writing","tools","productivity"]'

create_text_post "$U1" "alice" \
  "On reading slowly" \
  "## The case for slow reading\n\nWe skim everything now. Articles, threads, emails — the eye bounces from heading to heading.\n\nBut some texts reward patience. Reading a chapter of Montaigne at walking pace is a different experience from reading a summary.\n\n### What slow reading gives you\n\n- You notice the architecture of a sentence, not just its conclusion.\n- You catch the author's hesitations — places where the thought is unresolved.\n- You arrive at the end having actually thought, not just processed." \
  '["reading","writing","books"]'

create_text_post "$U1" "alice" \
  "First draft rules" \
  "## Write it badly\n\nThe hardest part of writing is permission — permission to be mediocre on the page while the first draft exists.\n\nHere are my personal first-draft rules:\n\n1. **Never delete** while drafting. Move text to a scratch area instead.\n2. **No editing the previous sentence** until the paragraph is done.\n3. **Set a timer.** Constraints help. Twenty minutes of bad writing beats two hours of blank staring.\n\nThe first draft is just the raw material. The real work is rewriting." \
  '["writing","craft","process"]'

create_text_post "$U1" "alice" \
  "Against productivity culture" \
  "## Not everything should be optimised\n\nProductivity culture assumes that idle time is waste. I think that is wrong.\n\nSome of my best ideas arrived while walking without a podcast, cooking without a YouTube video running, or staring at the ceiling.\n\n> Rest is not the opposite of work. It is part of the same cycle.\n\nWhen I stopped filling every gap with content, I started actually generating ideas instead of merely consuming them." \
  '["productivity","culture","thinking"]'

create_text_post "$U1" "alice" \
  "Newsletters vs blogs" \
  "## Is the blog dead?\n\nEvery few years someone declares the blog dead. Yet here we are, still reading and writing them.\n\nNewsletters feel more intimate — there is a sender and a recipient, a subscription that implies commitment. Blogs feel more like a public library: anyone can walk in.\n\nI prefer the library. The fact that most visitors wander through once and never return is fine. The words are still there for whoever needs them." \
  '["writing","blogging","internet"]'

create_text_post "$U1" "alice" \
  "How I outline an essay" \
  "## My outline process\n\nI resist outlining too early. If I know exactly what I am going to say, the essay becomes a transcription, not a discovery.\n\nMy process:\n\n1. **Write a messy draft** — no structure, just ideas.\n2. **Extract the spine** — what is the one thing I am really saying?\n3. **Order the sections** so each one earns the next.\n4. **Revise toward the spine.** Cut everything that does not serve it.\n\nThe outline comes after, not before." \
  '["writing","essays","process"]'

create_text_post "$U1" "alice" \
  "Writing for one reader" \
  "## The imaginary reader\n\nWhen I sit down to write, I picture one person — a specific, intelligent friend who knows nothing about the topic but is genuinely curious.\n\nThis changes everything. It kills jargon. It forces clarity. It reminds me that the reader did not arrive with my context and does not owe me their attention.\n\nWrite for that person. Not for everyone. Not for critics. For one curious friend." \
  '["writing","audience","craft"]'

create_text_post "$U1" "alice" \
  "The paragraph as a unit of thought" \
  "## One idea per paragraph\n\nThe most useful structural rule I know: **one paragraph, one idea**.\n\nIf a paragraph contains two ideas, split it. If it contains no clear idea, cut it.\n\nThis forces you to know what you are saying at every step. You cannot hide behind long paragraphs that drift from thought to thought without commitment.\n\nCount your paragraphs. Each one should be a step in an argument, not filler between steps." \
  '["writing","style","craft"]'

create_text_post "$U1" "alice" \
  "What blogging taught me about thinking" \
  "## Writing in public as cognitive practice\n\nI started blogging to share ideas. I continued because I discovered it made me a better thinker.\n\nPublishing forces precision. You cannot be vague when someone might push back. You cannot be lazy when your name is attached.\n\nThe act of editing — cutting the weak sentences, strengthening the good ones — is identical to the act of clarifying your own thinking.\n\n**Blog not to be read but to think.** Being read is just the pleasant side effect." \
  '["blogging","thinking","writing"]'

create_quote_post "$U1" "alice" \
  "On simplicity" \
  "Simplicity is the ultimate sophistication." \
  "Leonardo da Vinci" \
  '["design","quotes","simplicity"]'

create_quote_post "$U1" "alice" \
  "The first sentence" \
  "Don't tell me the moon is shining; show me the glint of light on broken glass." \
  "Anton Chekhov" \
  '["writing","craft","quotes"]'

create_quote_post "$U1" "alice" \
  "On revision" \
  "The first draft of anything is shit." \
  "Ernest Hemingway" \
  '["writing","quotes","process"]'

create_quote_post "$U1" "alice" \
  "Clarity" \
  "If you can't explain it simply, you don't understand it well enough." \
  "Albert Einstein" \
  '["writing","clarity","quotes"]'

create_link_post "$U1" "alice" \
  "The Markdown Guide" \
  "A free and open-source reference guide that explains how to use Markdown — from basics to advanced syntax." \
  "https://www.markdownguide.org" \
  '["markdown","writing","reference"]'

create_link_post "$U1" "alice" \
  "Paul Graham's Essays" \
  "One of the best collections of essays on startups, ideas, and how to think. Start with 'How to Write Usefully'." \
  "https://paulgraham.com/articles.html" \
  '["writing","essays","reading"]'

create_link_post "$U1" "alice" \
  "Hemingway App" \
  "Paste your writing here and it highlights adverbs, passive voice, and overly complex sentences. Brutally useful." \
  "https://hemingwayapp.com" \
  '["writing","tools","editing"]'

create_photo_post "$U1" "alice" \
  "Morning light" \
  "Golden hour on a quiet trail. Some mornings the world just looks right." \
  "$IMG_ALICE1" \
  '["photography","nature","morning"]'

create_photo_post "$U1" "alice" \
  "Forest floor" \
  "Detail work. The things you walk past without noticing are often the most interesting." \
  "$IMG_ALICE2" \
  '["photography","nature","detail"]'

# ─────────────────────────────────────────────────────────────────────────────
# BOB — 20 posts  (11 text · 4 quote · 3 link · 2 photo)
# ─────────────────────────────────────────────────────────────────────────────
info "Creating Bob's posts…"

create_text_post "$U2" "bob" \
  "Building without npm: a love story" \
  "## Zero-dependency frontend\n\nEvery JavaScript project ends up with a \`node_modules\` folder the size of a small country. What if we skipped that entirely?\n\n### CDN-first approach\n\nModern CDNs (jsDelivr, unpkg) serve battle-tested libraries directly to the browser. No install step, no bundler, no config.\n\n\`\`\`html\n<script src=\"https://cdn.jsdelivr.net/npm/handlebars@4.7.8/dist/handlebars.min.js\"></script>\n\`\`\`\n\n### Trade-offs\n\n- ✅  Zero setup\n- ✅  Always the pinned version\n- ⚠️  Requires internet at runtime\n\nFor a blog? Absolutely worth it." \
  '["javascript","no-build","frontend"]'

create_text_post "$U2" "bob" \
  "Appwrite as a backend for static sites" \
  "## Backend-as-a-Service for static files\n\nStatic sites are fast and cheap to host — but they struggle with dynamic data. **Appwrite** fills that gap.\n\n### What Appwrite gives you\n\n| Feature | Notes |\n|---|---|\n| Auth | Email/password, OAuth, magic links |\n| Database | Collections with indexes and document security |\n| Storage | File uploads with CDN |\n\n### Client SDK\n\n\`\`\`js\nconst client = new Appwrite.Client()\n  .setEndpoint(ENDPOINT)\n  .setProject(PROJECT_ID);\n\`\`\`\n\nNo server required." \
  '["appwrite","backend","javascript"]'

create_text_post "$U2" "bob" \
  "Why I contribute to open source" \
  "## The honest truth\n\nPeople assume open-source contributors are altruistic saints. Some are. Most of us are just solving our own problems and sharing the fix.\n\n### The loop\n\n1. Hit a bug or missing feature.\n2. Dig into the code.\n3. Fix it.\n4. Send the patch upstream.\n\nThe patch benefits the maintainer. The process benefits me far more — reading unfamiliar codebases is the fastest way to grow as an engineer." \
  '["opensource","programming","community"]'

create_text_post "$U2" "bob" \
  "Git as a thinking tool" \
  "## Commits are checkpoints for thought\n\nI commit obsessively — small, descriptive commits every time an idea solidifies. Not just for code.\n\nThe commit log becomes a journal of decisions. Why did I make this choice? The message should answer that.\n\n\`\`\`\nrefactor: extract auth logic into separate module\n\nSession handling was mixed with routing. Separating them\nmakes testing easier and keeps route handlers readable.\n\`\`\`\n\nFuture you will thank present you." \
  '["git","programming","process"]'

create_text_post "$U2" "bob" \
  "The beauty of boring technology" \
  "## Choose boring\n\nThere is a concept in software engineering called **boring technology**. It means: pick the proven option, not the shiny new one.\n\nBoring technology has:\n- Exhaustive documentation.\n- Years of Stack Overflow answers.\n- Known failure modes.\n\nShiny technology has excitement. Boring technology ships products.\n\nI choose boring, then occasionally experiment on side projects. The main codebase does not need novelty — it needs reliability." \
  '["programming","engineering","opinion"]'

create_text_post "$U2" "bob" \
  "Bash scripting is underrated" \
  "## Shell scripts get the job done\n\nEvery time I start writing a Python script for a simple automation task I ask myself: could this be a few lines of bash?\n\nUsually the answer is yes.\n\nBash is everywhere. It has no install step. It composes naturally with Unix tools. It handles files and processes as first-class citizens.\n\n\`\`\`bash\nfor f in *.md; do\n  echo \"--- \$f ---\"\n  wc -w \"\$f\"\ndone\n\`\`\`\n\nTen lines of bash beats a 200-line Python script with three dependencies." \
  '["bash","scripting","programming"]'

create_text_post "$U2" "bob" \
  "Code review as teaching" \
  "## The review is not just about the code\n\nI try to leave at least one genuinely complimentary comment on every pull request. Not fake praise — I find something good and name it.\n\nReview is where culture is transmitted. If every comment is a correction, contributors learn that only mistakes matter. That is not true.\n\nA well-reviewed PR teaches the reviewer as much as the author. You have to understand code deeply enough to explain why it could be better." \
  '["programming","teamwork","culture"]'

create_text_post "$U2" "bob" \
  "Reading source code" \
  "## The most underrated skill in programming\n\nSchools teach you to write code. Nobody teaches you to read it.\n\nReading other people's code — really reading it, not just skimming for the function you need — is how you learn the patterns that no tutorial covers.\n\n### How I read unfamiliar code\n\n1. Start with the entry point.\n2. Follow one execution path all the way through.\n3. Note every assumption I can't verify yet.\n4. Come back to the assumptions after the path is clear.\n\nSlow it down. The code will tell you everything if you ask it questions." \
  '["programming","learning","craft"]'

create_text_post "$U2" "bob" \
  "YAGNI and the cost of abstraction" \
  "## You Aren't Gonna Need It\n\nEvery abstraction has a cost. The cost is complexity — one more layer between the reader and what the code actually does.\n\nThe YAGNI principle says: do not add it until you need it. Not 'when you probably will need it'. When you **actually** need it.\n\nAbstractions are correct. Premature abstractions are technical debt dressed up as engineering rigour.\n\nWrite the simple version first. Refactor when the duplication hurts." \
  '["programming","engineering","opinion"]'

create_text_post "$U2" "bob" \
  "Static analysis saved me hours last week" \
  "## The underused superpower\n\nI added ESLint to a small project last week and it flagged 14 issues before a single test ran. Three of them would have caused production bugs.\n\nStatic analysis is the cheapest kind of testing. It requires no test harness, no test data, and runs in milliseconds.\n\nIf your project does not have it: add it today. Start with the strictest config you can tolerate. Relax rules intentionally rather than permissively." \
  '["javascript","tooling","programming"]'

create_text_post "$U2" "bob" \
  "The README is the product" \
  "## First impressions in open source\n\nThe README is the first thing every contributor and user reads. It is the product landing page, the documentation index, and the contribution guide all in one.\n\nA good README answers:\n1. What does this do?\n2. How do I run it in 60 seconds?\n3. What is the project status?\n4. How do I contribute?\n\nIf it can't answer those four questions in under 300 words, it needs work." \
  '["opensource","documentation","writing"]'

create_quote_post "$U2" "bob" \
  "On complexity" \
  "Any fool can write code that a computer can understand. Good programmers write code that humans can understand." \
  "Martin Fowler" \
  '["programming","quotes","craft"]'

create_quote_post "$U2" "bob" \
  "Simplicity in design" \
  "It seems that perfection is attained not when there is nothing more to add, but when there is nothing more to remove." \
  "Antoine de Saint-Exupéry" \
  '["design","engineering","quotes"]'

create_quote_post "$U2" "bob" \
  "On debugging" \
  "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it." \
  "Brian W. Kernighan" \
  '["programming","debugging","quotes"]'

create_quote_post "$U2" "bob" \
  "Unix philosophy" \
  "Write programs that do one thing and do it well. Write programs to work together." \
  "Doug McIlroy" \
  '["unix","programming","quotes"]'

create_link_post "$U2" "bob" \
  "Appwrite Docs" \
  "The official Appwrite documentation. Surprisingly readable — start with the Databases section if you are building a data-driven app." \
  "https://appwrite.io/docs" \
  '["appwrite","docs","reference"]'

create_link_post "$U2" "bob" \
  "The Architecture of Open Source Applications" \
  "Case studies of how large open-source projects are structured. Essential reading for anyone who wants to design software at scale." \
  "https://aosabook.org" \
  '["architecture","programming","reading"]'

create_link_post "$U2" "bob" \
  "Bash Reference Manual" \
  "The full GNU Bash reference. I return to this every time I need to remember the exact syntax for parameter expansion or process substitution." \
  "https://www.gnu.org/software/bash/manual/bash.html" \
  '["bash","reference","linux"]'

create_photo_post "$U2" "bob" \
  "City geometry" \
  "Lines and angles everywhere. Urban spaces have a visual logic of their own." \
  "$IMG_BOB1" \
  '["photography","city","architecture"]'

create_photo_post "$U2" "bob" \
  "Workspace" \
  "The physical environment shapes the quality of thought. This corner works." \
  "$IMG_BOB2" \
  '["photography","workspace","productivity"]'

# ─────────────────────────────────────────────────────────────────────────────
# CAROL — 20 posts  (11 text · 4 quote · 3 link · 2 photo)
# ─────────────────────────────────────────────────────────────────────────────
info "Creating Carol's posts…"

create_text_post "$U3" "carol" \
  "Design tokens and the language of UI" \
  "## What is a design token?\n\nA design token is a named, platform-agnostic value that represents a design decision.\n\n\`\`\`css\n--color-primary: #1a8cff;\n--spacing-md:    16px;\n\`\`\`\n\nNow every component that uses \`--color-primary\` inherits the value — and changing the token changes them all.\n\n### Three levels of tokens\n\n1. **Global** – raw values\n2. **Alias** – semantic names\n3. **Component** – scoped" \
  '["design","css","tokens","frontend"]'

create_text_post "$U3" "carol" \
  "Writing as thinking" \
  "## Why I write to understand\n\nI used to think you needed to understand something before you could write about it. I had it backwards.\n\n> Writing is not the record of thinking — it is the thinking itself.\n\n### The mechanism\n\nWhen I try to explain a concept in writing, gaps appear immediately. A vague mental model that felt solid collapses the moment it has to become sentences.\n\n**Try it for 30 days.** You will think more clearly, I promise." \
  '["writing","thinking","productivity"]'

create_text_post "$U3" "carol" \
  "A short guide to colour contrast" \
  "## Why contrast matters\n\nPoor colour contrast is one of the most common accessibility failures on the web. WCAG 2.1 requires a **4.5:1** ratio for normal text.\n\n### Quick checks\n\n- Use the WebAIM Contrast Checker\n- Try your UI in greyscale — if it falls apart, contrast is probably the culprit\n- Avoid grey-on-white for body copy\n\n### The bonus\n\nHigh-contrast designs are easier to read in bright sunlight, on cheap screens, and when you are tired." \
  '["accessibility","design","css"]'

create_text_post "$U3" "carol" \
  "The grid is not decoration" \
  "## Why I always start with a grid\n\nBeginning designers treat the grid as optional infrastructure — something to add after the layout feels right. Professional designers treat it as the first decision.\n\nThe grid is not decoration. It is a system of relationships. When everything aligns to the same invisible structure, the result feels inevitable rather than arbitrary.\n\n### Eight-point grid\n\nAll spacing, sizing, and positioning is a multiple of 8px. It is one rule. It solves a thousand micro-decisions." \
  '["design","layout","grid"]'

create_text_post "$U3" "carol" \
  "Typography is voice" \
  "## The words and the face they wear\n\nThe same sentence set in a condensed sans-serif reads as urgent. In a wide-set serif, it reads as authoritative. In a playful script, as warm.\n\nTypography does not carry content — it carries **tone**. Get it wrong and the content fights the presentation.\n\n### Three type decisions that matter most\n\n1. **Hierarchy** — is it immediately clear what is heading and what is body?\n2. **Line length** — 60–75 characters is the comfortable reading width.\n3. **Leading** — 1.4× to 1.6× the font size for body text." \
  '["typography","design","css"]'

create_text_post "$U3" "carol" \
  "Why I sketch before I prototype" \
  "## The danger of fidelity too soon\n\nHigh-fidelity prototypes look finished. When something looks finished, feedback changes character — people comment on colours instead of structure, on micro-copy instead of information architecture.\n\nSketching (with a pen, on paper) keeps the conversation at the right level of abstraction.\n\nI spend the first day of any design project with a notebook. The screen comes later." \
  '["design","process","ux"]'

create_text_post "$U3" "carol" \
  "Designing for error states" \
  "## The overlooked part of any interface\n\nMost designers design the happy path. The happy path is not where users struggle.\n\nThe real experience happens at error states:\n- Form validation failures\n- Empty states\n- Network timeouts\n- Permission denials\n\nDesign these first. The effort reveals edge cases early and prevents the all-too-common 'Something went wrong' non-message." \
  '["ux","design","accessibility"]'

create_text_post "$U3" "carol" \
  "White space is not empty space" \
  "## The case for negative space\n\nNew designers fear white space. They fill it. The result is dense, claustrophobic, hard to read.\n\nWhite space does three things:\n\n1. **Establishes hierarchy** — elements with more space around them read as more important.\n2. **Groups related items** — proximity implies relationship.\n3. **Gives the eye a rest** — reading is work; space reduces the effort.\n\nThe next time a design feels crowded, delete something before adding anything." \
  '["design","layout","typography"]'

create_text_post "$U3" "carol" \
  "Design critique without ego" \
  "## Receiving feedback is a skill\n\nEarly in my career, design critique felt like personal attack. My work was me; criticism of my work was criticism of me.\n\nI eventually learned to separate the two. Here is what helped:\n\n1. **Present the problem first**, then the solution. The critique is of the solution's fitness to the problem.\n2. **Invite the most critical person in the room** to go first. Get the hard feedback while you still have energy to process it.\n3. **Say 'thank you' before responding to any criticism.** It creates a pause in which ego subsides." \
  '["design","process","culture"]'

create_text_post "$U3" "carol" \
  "Responsive design in 2025" \
  "## Beyond breakpoints\n\nBreakpoints feel dated. Fluid typography and container queries mean components can adapt to their context, not just the viewport.\n\n\`\`\`css\n/* Fluid type: scales between 16px at 320px viewport and 20px at 1200px */\nfont-size: clamp(1rem, 2.5vw, 1.25rem);\n\`\`\`\n\nThe goal is not 'looks good at 320, 768, and 1440'. The goal is 'looks good everywhere between 320 and 2560'.\n\nDesign the extremes. Trust CSS to handle the middle." \
  '["css","responsive","design"]'

create_text_post "$U3" "carol" \
  "A designer's case for learning CSS" \
  "## The best design tool is the medium itself\n\nI know designers who have never written a line of CSS. They produce beautiful Figma files and hand them off. The handoff is where the design dies.\n\nLearning CSS does not mean becoming a developer. It means understanding the constraints and capabilities of the canvas you are designing for.\n\nAn hour with flexbox and grid will change your design thinking permanently." \
  '["css","design","frontend"]'

create_quote_post "$U3" "carol" \
  "Good design is invisible" \
  "Good design, when done well, should be invisible. It is only when it is done poorly that we notice it." \
  "Jony Ive" \
  '["design","ux","quotes"]'

create_quote_post "$U3" "carol" \
  "On constraints" \
  "The enemy of art is the absence of limitations." \
  "Orson Welles" \
  '["design","creativity","quotes"]'

create_quote_post "$U3" "carol" \
  "Dieter Rams on design" \
  "Good design is as little design as possible." \
  "Dieter Rams" \
  '["design","minimalism","quotes"]'

create_quote_post "$U3" "carol" \
  "On aesthetics" \
  "Have nothing in your house that you do not know to be useful or believe to be beautiful." \
  "William Morris" \
  '["design","craft","quotes"]'

create_link_post "$U3" "carol" \
  "Refactoring UI" \
  "Practical design advice from the makers of Tailwind CSS. Every tip is actionable and immediately applicable." \
  "https://www.refactoringui.com" \
  '["design","ui","reference"]'

create_link_post "$U3" "carol" \
  "WebAIM Contrast Checker" \
  "Paste your foreground and background colours to check WCAG contrast ratios instantly. Bookmark this." \
  "https://webaim.org/resources/contrastchecker/" \
  '["accessibility","design","tools"]'

create_link_post "$U3" "carol" \
  "CSS Tricks — A Complete Guide to Flexbox" \
  "The definitive visual reference for flexbox. I still consult it for the alignment properties." \
  "https://css-tricks.com/snippets/css/a-guide-to-flexbox/" \
  '["css","layout","reference"]'

create_photo_post "$U3" "carol" \
  "Texture study" \
  "Close-up surfaces reveal a whole other world of colour and form." \
  "$IMG_CAROL1" \
  '["photography","texture","abstract"]'

create_photo_post "$U3" "carol" \
  "Studio light" \
  "The quality of light in a space determines its character entirely." \
  "$IMG_CAROL2" \
  '["photography","design","studio"]'

# ─────────────────────────────────────────────────────────────────────────────
# DAVE — 20 posts  (11 text · 4 quote · 3 link · 2 photo)
# ─────────────────────────────────────────────────────────────────────────────
info "Creating Dave's posts…"

create_text_post "$U4" "dave" \
  "What systems thinking actually means" \
  "## Beyond linear cause and effect\n\nMost people learn to think in chains: A causes B, B causes C. Systems thinking asks: what if B also feeds back into A?\n\n### Feedback loops\n\n- **Reinforcing loops** amplify change (growth, collapse).\n- **Balancing loops** resist change (thermostats, predator/prey).\n\nAlmost every real-world problem — from climate change to urban traffic — is a system of interacting feedback loops, not a chain." \
  '["systems","thinking","science"]'

create_text_post "$U4" "dave" \
  "Why the scientific method matters more than ever" \
  "## A method, not a set of facts\n\nScience is often mistaken for a collection of facts. It is actually a method for generating reliable knowledge: hypothesis, experiment, falsification, replication.\n\nThe facts change. The method is the durable part.\n\n> If a study cannot be replicated, it has produced nothing.\n\nThis is not a criticism of scientists. It is the self-correcting mechanism of the enterprise." \
  '["science","epistemology","thinking"]'

create_text_post "$U4" "dave" \
  "The Fermi estimation habit" \
  "## Order-of-magnitude thinking\n\nFermi estimation: make a rough numerical guess from first principles, without looking anything up.\n\n*How many piano tuners are in Chicago?*\n\n1. ~3 million people in Chicago.\n2. ~1 in 20 households has a piano → 150,000 pianos.\n3. A piano needs tuning once a year → 150,000 tunings/year.\n4. A tuner does ~4 tunings/day × 250 days = 1,000/year.\n5. ~150 tuners.\n\nThe real number is ~125–200. The method is more valuable than the answer." \
  '["math","thinking","estimation"]'

create_text_post "$U4" "dave" \
  "Emergence: when the whole is more than its parts" \
  "## Properties that appear from interaction\n\nConsciousness is not in any individual neuron. Wetness is not in any individual water molecule. Traffic jams have no single cause.\n\nThese are **emergent properties** — features of a system that cannot be predicted from the components alone.\n\nEmergence is why reductionism has limits. Some phenomena can only be understood at the level of the system, not the parts." \
  '["science","complexity","systems"]'

create_text_post "$U4" "dave" \
  "On being wrong" \
  "## Error as information\n\nI was taught to fear being wrong. School graded me on correctness. Professional life rewarded confidence.\n\nBut wrong beliefs are data. If a prediction fails, the model needs updating. If an argument collapses, the conclusion was premature.\n\nThe goal is not to be right. The goal is to update toward truth as efficiently as possible. Sometimes that means being publicly wrong and correcting quickly.\n\n**Being wrong is the beginning of learning, not the end of credibility.**" \
  '["epistemology","thinking","philosophy"]'

create_text_post "$U4" "dave" \
  "The map is not the territory" \
  "## Alfred Korzybski's most useful insight\n\nA map is useful precisely because it is not the territory. It simplifies, abstracts, highlights what the cartographer thought mattered.\n\nEvery model, theory, and framework is a map. The danger is forgetting that.\n\nEconomic models are maps. Personality tests are maps. Political ideologies are maps.\n\nUse your maps. Just check them against the territory periodically." \
  '["philosophy","thinking","epistemology"]'

create_text_post "$U4" "dave" \
  "Evolution is not progress" \
  "## Correcting a common misunderstanding\n\nEvolution has no direction, no goal, no preferred endpoint. It is simply differential reproduction — some variants leave more descendants than others.\n\nThere is no 'higher' or 'lower' form of life. A bacterium that has thrived for three billion years is not inferior to a human who has existed for 300,000.\n\nRemoving the teleology from evolution does not make it less wonderful. It makes it more astonishing: complexity without a plan." \
  '["biology","evolution","science"]'

create_text_post "$U4" "dave" \
  "Information theory in plain English" \
  "## What Claude Shannon actually discovered\n\nShannon's key insight: **information is surprise**. A message contains more information the less predictable it is.\n\nIf I tell you the sun rose this morning, I have transmitted almost no information — you already expected it. If I tell you it rose in the west, I have transmitted a great deal.\n\nThis is why compression works. Predictable sequences are redundant. Remove the redundancy; keep the surprise.\n\nEvery digital communication you have ever sent operates on this principle." \
  '["computing","information","science"]'

create_text_post "$U4" "dave" \
  "The anthropic principle, briefly explained" \
  "## Why the universe seems fine-tuned for us\n\nThe constants of physics — the strength of gravity, the mass of the electron — seem improbably calibrated for complex structure and life to exist.\n\nThe anthropic principle offers a simple (and often overlooked) explanation: we can only observe universes in which observers can exist. If the constants were different, we would not be here to notice.\n\nThis is not mysticism. It is selection bias applied at the largest possible scale." \
  '["cosmology","philosophy","science"]'

create_text_post "$U4" "dave" \
  "Second-order effects and why we miss them" \
  "## Thinking one step further than the obvious\n\nFirst-order effect: the rent control policy makes rent cheaper.\nSecond-order effect: landlords convert apartments to condos, reducing rental supply.\nThird-order effect: rents for uncontrolled units rise.\n\nWe notice first-order effects immediately. Second-order effects take time and are harder to attribute causally.\n\nThe most consequential decisions in policy, business, and personal life are determined by second and third-order effects. First-order thinking is just intuition." \
  '["systems","thinking","economics"]'

create_text_post "$U4" "dave" \
  "Calibration: knowing how much you know" \
  "## The meta-skill of accurate confidence\n\nCalibration is the degree to which your confidence matches your accuracy. A well-calibrated person who says they are '70% sure' is right about 70% of the time.\n\nMost people are overconfident — they are right far less often than they believe.\n\nThe good news: calibration can be trained. Keep a prediction log. Track your hit rate by confidence level. The feedback loop is humbling and effective." \
  '["epistemology","probability","thinking"]'

create_quote_post "$U4" "dave" \
  "On models" \
  "All models are wrong, but some are useful." \
  "George E. P. Box" \
  '["science","statistics","quotes"]'

create_quote_post "$U4" "dave" \
  "Russell on thinking" \
  "The whole problem with the world is that fools and fanatics are always so certain of themselves, and wiser people so full of doubts." \
  "Bertrand Russell" \
  '["philosophy","thinking","quotes"]'

create_quote_post "$U4" "dave" \
  "Feynman on knowing" \
  "The first principle is that you must not fool yourself — and you are the easiest person to fool." \
  "Richard Feynman" \
  '["science","epistemology","quotes"]'

create_quote_post "$U4" "dave" \
  "Sagan on extraordinary claims" \
  "Extraordinary claims require extraordinary evidence." \
  "Carl Sagan" \
  '["science","skepticism","quotes"]'

create_link_post "$U4" "dave" \
  "Complexity Explorables" \
  "Interactive simulations of complex systems: emergence, phase transitions, flocking, epidemics. The best way to build intuition for non-linear dynamics." \
  "https://www.complexity-explorables.org" \
  '["science","complexity","interactive"]'

create_link_post "$U4" "dave" \
  "Our World in Data" \
  "Carefully sourced data visualisations on global development, health, and environment. The antidote to anecdotal worldviews." \
  "https://ourworldindata.org" \
  '["data","science","reference"]'

create_link_post "$U4" "dave" \
  "3Blue1Brown — YouTube" \
  "Mathematical animations that build deep intuition from first principles. 'Essence of Linear Algebra' is the best introduction to the subject I have found anywhere." \
  "https://www.youtube.com/@3blue1brown" \
  '["math","education","video"]'

create_photo_post "$U4" "dave" \
  "The cosmos, approximated" \
  "Every time I look at a long-exposure photograph of the night sky I have to remind myself that the light in each of those points is thousands of years old." \
  "$IMG_DAVE1" \
  '["photography","science","cosmos"]'

create_photo_post "$U4" "dave" \
  "Systems in miniature" \
  "A rock pool is a complete ecosystem. Every surface is occupied by something that eats and is eaten." \
  "$IMG_DAVE2" \
  '["photography","biology","nature"]'

# ─────────────────────────────────────────────────────────────────────────────
# EVE — 20 posts  (11 text · 4 quote · 3 link · 2 photo)
# ─────────────────────────────────────────────────────────────────────────────
info "Creating Eve's posts…"

create_text_post "$U5" "eve" \
  "Making things for the sake of making things" \
  "## The amateur's advantage\n\nAn amateur makes things for love. A professional makes things for money. These are not opposed, but they pull in different directions under pressure.\n\nThe amateur's advantage: when no one is paying, no one is waiting, and no one will be disappointed. You can fail completely and call it practice.\n\nI make music that nobody asked for, illustrate books that don't exist, and write essays for an audience of one. Most of it is bad. Some of it is the most honest work I have ever produced." \
  '["art","creativity","process"]'

create_text_post "$U5" "eve" \
  "On learning an instrument as an adult" \
  "## Unlearning the fear of being a beginner\n\nI started learning piano at 28. Everyone told me I had started too late.\n\nI did not have a natural talent. What I had was the ability to practice deliberately — something most child learners do not yet have.\n\nTwo years later I can play things that genuinely move me. The process of learning also moved me. Struggle, small victories, struggle again.\n\nThere is no 'too late' for anything you have not tried." \
  '["music","learning","creativity"]'

create_text_post "$U5" "eve" \
  "Constraints breed creativity" \
  "## Why limitation is a gift\n\nThe most creative periods of my work have come from restrictions, not freedoms.\n\nA limited colour palette forces compositional clarity. A twelve-bar blues forces harmonic economy. A 250-word limit forces precision.\n\nOpen-ended prompts produce open-ended, wandering results. Constraints focus attention. Attention is where creativity lives.\n\nNext time you are stuck: add a constraint. Remove a tool. Set a limit." \
  '["creativity","art","process"]'

create_text_post "$U5" "eve" \
  "The sketchbook as a private space" \
  "## Work that is not for anyone\n\nMy sketchbook is the one place I have never felt self-conscious. No one will see it. No one asked for it. The only audience is future me, and future me is forgiving.\n\nI fill it with bad drawings, half-ideas, colour experiments, notes to myself. It is a compost heap. Slowly, things decompose into something usable.\n\nEvery creative person needs a compost heap. Call it a sketchbook, a notebook, a draft folder — the name does not matter. The freedom does." \
  '["art","process","creativity"]'

create_text_post "$U5" "eve" \
  "What improv taught me about collaboration" \
  "## Yes, and\n\nThe first rule of improv: never negate your partner's reality. Whatever they offer, you accept it and build on it: **yes, and**.\n\nThis is also the first rule of good collaboration.\n\nNegating a colleague's idea kills momentum. You can redirect, refine, or complicate — but if you reject the offer, you restart from zero.\n\nThe creative output of a group that practices 'yes, and' is consistently richer than one that practices 'yes, but'." \
  '["creativity","collaboration","improv"]'

create_text_post "$U5" "eve" \
  "Analogue tools in a digital world" \
  "## Why I still draw by hand\n\nDigital tools have undo. They have layers, infinite canvas, perfect lines.\n\nPen on paper has none of that. Every mark is permanent. The line is imperfect. The texture is real.\n\nI find I think differently with a pen. Slower, more committed. Less tempted to fiddle infinitely and call it editing.\n\nI do final work digitally. But I sketch, plan, and think on paper. The constraint keeps me honest." \
  '["art","tools","process"]'

create_text_post "$U5" "eve" \
  "Learning to finish things" \
  "## The most important skill nobody teaches\n\nI have one hard drive of abandoned projects: half-composed songs, illustrated stories that stop at chapter three, essays I got bored of midway.\n\nFinishing is a skill. It is not glamorous. The end of a project is almost never the exciting beginning — it is maintenance, polish, and saying goodbye.\n\nI now have a rule: **finish one thing before starting the next**. It changed everything. The work is better because I have to make it work, not just abandon it when it stops being fun." \
  '["creativity","process","craft"]'

create_text_post "$U5" "eve" \
  "Music as emotional memory" \
  "## Why songs take you places\n\nA song heard at an emotionally intense moment becomes entangled with that moment. Later, hearing it unpacks the whole memory — the smell of the room, the quality of the light.\n\nThis is not metaphor. The auditory cortex is closely linked to the hippocampus and the amygdala. Music is literally stored near emotion and memory.\n\nSome songs I cannot listen to in public because they would produce a response I cannot explain to strangers. This seems like a reasonable price for the gift." \
  '["music","neuroscience","art"]'

create_text_post "$U5" "eve" \
  "The difference between influence and imitation" \
  "## How to learn from artists you love\n\nImitation: reproduce their surface — the style, the palette, the technique.\nInfluence: internalise their principles — the intention, the problem-solving, the care.\n\nThe best way to be influenced rather than imitative is to ask: **what problem were they solving?** Not: what did the result look like?\n\nAnswer that question, then solve the same problem with your own tools and sensibility." \
  '["art","creativity","learning"]'

create_text_post "$U5" "eve" \
  "The audience you are not making work for" \
  "## On the tyranny of imagined critics\n\nI used to write and draw with an imagined critic in my head. A composite of every harsh review I had ever read. She was never satisfied.\n\nAt some point I evicted her.\n\nThe work improved. Not immediately — I lost some discipline at first. But eventually I found my own discipline, which is more useful because it comes from inside.\n\nThe imagined critic does not actually want you to succeed. She wants you to stop." \
  '["creativity","art","writing"]'

create_text_post "$U5" "eve" \
  "Silence as a compositional element" \
  "## What John Cage understood\n\nIn music, silence is not the absence of music. It is one of the instruments.\n\nThe pause before a phrase gives the phrase weight. The gap between movements lets the ear (and the listener) breathe.\n\nThis principle applies everywhere:\n\n- In writing, the paragraph break gives the sentence room.\n- In design, white space gives the element importance.\n- In conversation, the held pause is not dead time — it is thinking time.\n\nMaster silence. It is available to everyone, used by almost no one." \
  '["music","art","design"]'

create_quote_post "$U5" "eve" \
  "Picasso on creation" \
  "Every act of creation is first of all an act of destruction." \
  "Pablo Picasso" \
  '["art","creativity","quotes"]'

create_quote_post "$U5" "eve" \
  "On style" \
  "Style is knowing who you are, what you want to say, and not giving a damn." \
  "Gore Vidal" \
  '["art","writing","quotes"]'

create_quote_post "$U5" "eve" \
  "The artist's obligation" \
  "An artist is not paid for his labor but for his vision." \
  "James McNeill Whistler" \
  '["art","creativity","quotes"]'

create_quote_post "$U5" "eve" \
  "On practice" \
  "An amateur practises until they can play it correctly. A professional practises until they cannot play it incorrectly." \
  "Percy C. Buck" \
  '["music","craft","quotes"]'

create_link_post "$U5" "eve" \
  "Lines of Code — music & code zine" \
  "A beautifully designed zine at the intersection of music, visual art, and programming. Free to read online." \
  "https://linesofcode.art" \
  '["music","art","coding"]'

create_link_post "$U5" "eve" \
  "Bandcamp" \
  "The best place to buy music directly from artists. The interface is ugly; the economics are better for musicians than any streaming platform." \
  "https://bandcamp.com" \
  '["music","art","community"]'

create_link_post "$U5" "eve" \
  "The Creative Independent" \
  "In-depth interviews with artists, musicians, and writers about their process. Every interview teaches me something." \
  "https://thecreativeindependent.com" \
  '["art","creativity","reading"]'

create_photo_post "$U5" "eve" \
  "Abstract study I" \
  "Sometimes I take a photo just to see what a composition looks like through the lens instead of my eye." \
  "$IMG_EVE1" \
  '["photography","abstract","art"]'

create_photo_post "$U5" "eve" \
  "Portrait in available light" \
  "Available light means accepting what the moment offers. That constraint produces more honest images than a studio." \
  "$IMG_EVE2" \
  '["photography","portrait","light"]'

# =============================================================================
# 4. Follow relationships (each user follows 3–4 others)
# =============================================================================
info "Creating follow relationships…"

# bob → alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U2" --arg fg "$U1" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  bob → alice"

# carol → alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U3" --arg fg "$U1" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  carol → alice"

# alice → carol
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U1" --arg fg "$U3" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  alice → carol"

# dave → alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U4" --arg fg "$U1" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  dave → alice"

# dave → bob
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U4" --arg fg "$U2" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  dave → bob"

# eve → carol
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U5" --arg fg "$U3" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  eve → carol"

# eve → alice
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U5" --arg fg "$U1" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  eve → alice"

# alice → dave
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U1" --arg fg "$U4" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  alice → dave"

# bob → eve
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U2" --arg fg "$U5" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  bob → eve"

# carol → dave
aw POST "/databases/$DB_ID/collections/follows/documents" "$(jq -n \
  --arg fr "$U3" --arg fg "$U4" \
  '{documentId:"unique()",data:{followerId:$fr,followingId:$fg},
    permissions:["read(\"users\")"]}')" >/dev/null && info "  carol → dave"

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
info "✅  Seed complete."
info "    Profiles : alice, bob, carol, dave, eve"
info "    Posts    : 100 (55 text · 20 quote · 15 link · 10 photo)"
info "    Follows  : 10"
echo ""
warn "Note: seed profiles have fake user IDs and are read-only on the frontend."
warn "Real users can sign up and will get their own profiles via ensureProfile()."
