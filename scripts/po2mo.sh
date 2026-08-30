#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "updatesmanager.koplugin" ]; then
    PLUGIN_DIR="updatesmanager.koplugin"
elif [ -f "_meta.lua" ] && [ -f "lib/updatesmanager_i18n.lua" ]; then
    PLUGIN_DIR="."
else
    PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
fi

LOCALE_DIR="$PLUGIN_DIR/locale"

if [ ! -d "$LOCALE_DIR" ]; then
    echo "No locale/ directory — skipping PO validation"
    exit 0
fi

if ! command -v msgfmt &> /dev/null; then
    echo "Error: msgfmt not found. Install gettext (e.g. apt-get install gettext)."
    exit 1
fi

found=0
for po_file in "$LOCALE_DIR"/*.po; do
    if [ -f "$po_file" ]; then
        found=1
        echo "Checking $(basename "$po_file")..."
        msgfmt --check-format -o /dev/null "$po_file"
        echo "✓ $(basename "$po_file")"
    fi
done

if [ "$found" -eq 0 ]; then
    echo "No .po files in $LOCALE_DIR — nothing to validate"
fi

echo "Locale PO validation complete."
