#!/usr/bin/env bash
# scripts/build.sh – Generate root HTML pages from XML sources using xsltproc.
#
# Usage:
#   bash scripts/build.sh
#
# Requires xsltproc (apt: xsltproc / brew: libxslt).
# Each src/<name>.xml is transformed by src/page.xsl into <name>.html at the
# repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/src"
XSL="$SRC_DIR/page.xsl"

for xml_file in "$SRC_DIR"/*.xml; do
  name="$(basename "$xml_file" .xml)"
  out="$ROOT_DIR/${name}.html"
  echo "  Building ${name}.html …"
  xsltproc --novalid -o "$out" "$XSL" "$xml_file"
done

echo "Done."
