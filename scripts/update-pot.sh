#!/bin/bash
# Regenerate locale/updatesmanager.pot from _("...") / _[[...]] in plugin Lua sources.
#
# Requires gettext (xgettext, optionally msgmerge):
#   Ubuntu/Debian: sudo apt-get install gettext
#   macOS: brew install gettext
#
# Usage (from repo root or plugin directory):
#   bash scripts/update-pot.sh           # update updatesmanager.pot only
#   bash scripts/update-pot.sh --merge   # also merge into locale/*.po

set -e

MERGE=0
if [ "${1:-}" = "--merge" ]; then
    MERGE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "updatesmanager.koplugin" ]; then
    PLUGIN_DIR="updatesmanager.koplugin"
elif [ -f "_meta.lua" ] && [ -f "lib/updatesmanager_i18n.lua" ]; then
    PLUGIN_DIR="."
else
    PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
fi

LOCALE_DIR="$PLUGIN_DIR/locale"
POT_FILE="$LOCALE_DIR/updatesmanager.pot"
FILE_LIST="$(mktemp)"

if ! command -v xgettext &> /dev/null; then
    echo "Error: xgettext not found. Install gettext."
    exit 1
fi

mkdir -p "$LOCALE_DIR"

find "$PLUGIN_DIR" -name '*.lua' \
    ! -name '*_example.lua' \
    -print | sort > "$FILE_LIST"

echo "Extracting strings from $(wc -l < "$FILE_LIST") Lua file(s)..."

xgettext --language=Lua \
    --from-code=UTF-8 \
    --keyword=_ \
    --keyword=T:1 \
    --add-comments='Translators:' \
    --package-name='updatesmanager.koplugin' \
    --package-version='' \
    --msgid-bugs-address='' \
    -o "$POT_FILE" \
    -f "$FILE_LIST"

rm -f "$FILE_LIST"

echo "✓ Wrote $POT_FILE ($(grep -c '^msgid ' "$POT_FILE" || echo 0) entries)"

if [ "$MERGE" -eq 1 ]; then
    if ! command -v msgmerge &> /dev/null; then
        echo "Error: msgmerge not found (needed for --merge)."
        exit 1
    fi
    shopt -s nullglob
    for po_file in "$LOCALE_DIR"/*.po; do
        echo "Merging into $(basename "$po_file")..."
        msgmerge --update --no-fuzzy-matching --previous "$po_file" "$POT_FILE"
        echo "✓ $(basename "$po_file")"
    done
    echo "PO files updated. Review fuzzy/obsolete entries in your editor."
fi

echo "Done. Translators: copy locale/updatesmanager.pot to locale/<lang>.po and fill msgstr."
