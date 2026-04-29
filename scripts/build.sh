#!/usr/bin/env bash
# scripts/build.sh – Generate root HTML pages from XHTML sources using xsltproc.
#
# Usage:
#   bash scripts/build.sh
#
# Requires xsltproc (apt: xsltproc / brew: libxslt).
# Each src/<name>.xhtml is transformed by src/page.xsl into <name>.html at the
# repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/src"
XSL="$SRC_DIR/page.xsl"

for xhtml_file in "$SRC_DIR"/*.xhtml; do
  name="$(basename "$xhtml_file" .xhtml)"
  out="$ROOT_DIR/${name}.html"
  echo "  Building ${name}.html …"
  xsltproc --novalid -o "$out" "$XSL" "$xhtml_file"
done

echo "Done."
