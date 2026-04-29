#!/usr/bin/env bash
# scripts/build.sh – Generate site into dist/ from XHTML sources using xsltproc.
#
# Usage:
#   bash scripts/build.sh
#
# Requires xsltproc (apt: xsltproc / brew: libxslt).
# Each src/<name>.xhtml is transformed by src/page.xsl into dist/<name>.html.
# Static assets (css/, js/, templates/) are copied into dist/ alongside them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/src"
XSL="$SRC_DIR/page.xsl"
DIST_DIR="$ROOT_DIR/dist"

# Ensure nullglob is set so an empty match produces zero iterations, not a
# literal pattern string.
shopt -s nullglob
xhtml_files=("$SRC_DIR"/*.xhtml)
if [[ ${#xhtml_files[@]} -eq 0 ]]; then
  echo "Error: no .xhtml source files found in $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

for xhtml_file in "${xhtml_files[@]}"; do
  name="$(basename "$xhtml_file" .xhtml)"
  out="$DIST_DIR/${name}.html"
  echo "  Building ${name}.html …"
  xsltproc --novalid -o "$out" "$XSL" "$xhtml_file"
done

# Copy static assets into dist/ so the site is self-contained.
for asset in css js templates; do
  cp -r "$ROOT_DIR/$asset" "$DIST_DIR/"
done

echo "Done."
