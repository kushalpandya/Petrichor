#!/bin/bash

REPO="kushalpandya/Petrichor"
APPCAST_FILE="appcast.xml"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
die() { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

echo "🔍 Checking for new releases..."
LATEST_RELEASE=$(curl -fsS "https://api.github.com/repos/$REPO/releases/latest") \
    || die "Could not fetch latest release"

VERSION=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || die "Could not parse latest release tag"
echo "📦 Latest release: $VERSION"

# Build number: beta-N → N, else major*100 + minor*10 + patch
if [[ "$VERSION" =~ beta-([0-9]+) ]]; then
    BUILD_NUMBER="${BASH_REMATCH[1]}"
else
    IFS='.' read -r maj min pat <<< "$VERSION"
    BUILD_NUMBER="$((maj * 100 + min * 10 + ${pat:-0}))"
fi
echo "   Build number: $BUILD_NUMBER"

if grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✅ Appcast already has $VERSION (build $BUILD_NUMBER)${NC}"
    exit 0
fi
echo -e "${YELLOW}🆕 New version detected: $VERSION (build $BUILD_NUMBER)${NC}"

# Pull body, published_at, and DMG URL out of the release JSON in one shot.
cat > "$TEMP_DIR/parse.py" <<'PYEOF'
import json, sys
tmp = sys.argv[1]
d = json.load(sys.stdin)
dmg = next((a['browser_download_url'] for a in d.get('assets', []) if a['name'].endswith('.dmg')), '')
open(f'{tmp}/dmg_url', 'w').write(dmg)
open(f'{tmp}/published_at', 'w').write(d.get('published_at', ''))
open(f'{tmp}/body.md', 'w').write(d.get('body', ''))
PYEOF
echo "$LATEST_RELEASE" | python3 "$TEMP_DIR/parse.py" "$TEMP_DIR"

DMG_URL=$(cat "$TEMP_DIR/dmg_url")
RELEASE_DATE=$(cat "$TEMP_DIR/published_at")
[ -n "$DMG_URL" ] || die "No DMG file found in release"

RFC_DATE=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$RELEASE_DATE" "+%a, %d %b %Y %H:%M:%S %z" 2>/dev/null) \
    || RFC_DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

echo "📥 Downloading DMG to calculate size..."
echo "   URL: $DMG_URL"
DMG_FILE="$TEMP_DIR/temp.dmg"
curl -L -# -o "$DMG_FILE" "$DMG_URL" || die "Failed to download DMG"
FILE_SIZE=$(stat -f%z "$DMG_FILE" 2>/dev/null || stat -c%s "$DMG_FILE" 2>/dev/null)
echo "📏 DMG size: $FILE_SIZE bytes"

# Markdown release notes → HTML for <description><![CDATA[...]]></description>.
# The (?<![\w/>]) lookbehind on the bare-#NNN regex prevents re-matching the
# digits inside an anchor tag we just emitted, so no placeholder dance is needed.
cat > "$TEMP_DIR/convert.py" <<'PYEOF'
import sys, re

REPO = "kushalpandya/Petrichor"
INDENT = " " * 16
pr_link = lambda n: f'<a href="https://github.com/{REPO}/pull/{n}">#{n}</a>'

def inline(text):
    text = re.sub(r'&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)', '&amp;', text)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', r'<a href="\2">\1</a>', text)
    text = re.sub(rf'https://github\.com/{re.escape(REPO)}/(?:pull|issues)/(\d+)',
                  lambda m: pr_link(m.group(1)), text)
    text = re.sub(r'(?<![\w/>])#(\d+)\b', lambda m: pr_link(m.group(1)), text)
    text = re.sub(r'\*\*([^*]+?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    return text

def convert(content):
    out, fc_url = [], None
    in_list = False
    def close():
        nonlocal in_list
        if in_list:
            out.append(f'{INDENT}</ul>'); in_list = False

    for line in content.replace('\r\n', '\n').split('\n'):
        line = line.strip()
        if not line:
            close(); continue
        if (m := re.match(r'^\*\*Full Changelog\*\*\s*:?\s*(\S+)', line)):
            close(); fc_url = m.group(1); continue
        if (m := re.match(r'^(#{1,6})\s+(.+)$', line)):
            close(); lvl = len(m.group(1))
            out.append(f'{INDENT}<h{lvl}>{inline(m.group(2))}</h{lvl}>'); continue
        if (m := re.match(r'^[\*\-]\s+(.+)$', line)):
            item = re.sub(r'^[a-f0-9]{7,40}\s+', '', m.group(1))
            if not in_list:
                out.append(f'{INDENT}<ul>'); in_list = True
            out.append(f'{INDENT}    <li>{inline(item)}</li>'); continue
        close()
        out.append(f'{INDENT}<p>{inline(line)}</p>')
    close()
    if fc_url:
        out.append(f'{INDENT}<p><a href="{inline(fc_url)}">Full Changelog</a></p>')
    return '\n'.join(out)

sys.stdout.write(convert(sys.stdin.read()))
PYEOF

RELEASE_HTML=$(python3 "$TEMP_DIR/convert.py" < "$TEMP_DIR/body.md")

echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📝 Sparkle EdDSA Signature Required${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "Run sign_update on the downloaded DMG:"
echo -e "  ${GREEN}./sign_update \"$DMG_FILE\"${NC}"
echo "(or ~/path/to/Sparkle/bin/sign_update if it's not on PATH)"
echo
echo 'It prints something like: sparkle:edSignature="MEUCIQCxxxx..."'
echo
read -p "Paste the signature (or press Enter to skip): " ED_SIGNATURE
ED_SIGNATURE="${ED_SIGNATURE#sparkle:edSignature=\"}"
ED_SIGNATURE="${ED_SIGNATURE%\"}"

NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version $VERSION</title>
            <pubDate>$RFC_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DMG_URL"$([ -n "$ED_SIGNATURE" ] && printf '\n                sparkle:edSignature="%s"' "$ED_SIGNATURE")
                length="$FILE_SIZE"
                type="application/octet-stream"
            />
            <description><![CDATA[
$RELEASE_HTML
            ]]></description>
        </item>
EOF
)

# Splice the new item in right after <language>en</language>, or create the file.
# (Avoid `awk -v item=...` here — BSD awk on macOS rejects multi-line -v values.)
if [ -f "$APPCAST_FILE" ] && grep -q '<language>en</language>' "$APPCAST_FILE"; then
    LANG_LINE=$(grep -n '<language>en</language>' "$APPCAST_FILE" | head -1 | cut -d: -f1)
    {
        head -n "$LANG_LINE" "$APPCAST_FILE"
        printf '%s\n' "$NEW_ITEM"
        tail -n +$((LANG_LINE + 1)) "$APPCAST_FILE"
    } > "${APPCAST_FILE}.tmp" && mv "${APPCAST_FILE}.tmp" "$APPCAST_FILE"
else
    cat > "$APPCAST_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Petrichor Updates</title>
        <description>Updates for Petrichor</description>
        <language>en</language>
$NEW_ITEM
    </channel>
</rss>
EOF
fi

echo
echo -e "${GREEN}✅ Updated $APPCAST_FILE${NC}"
echo "  • Version: $VERSION (build $BUILD_NUMBER)"
echo "  • Size:    $FILE_SIZE bytes"
[ -n "$ED_SIGNATURE" ] && echo "  • Signed:  ✓" \
    || echo -e "  • Signed:  ${YELLOW}skipped (sandboxed updates may fail)${NC}"
echo
echo "Next steps:"
echo "  git diff $APPCAST_FILE"
echo "  git add $APPCAST_FILE && git commit -m \"Update appcast for v$VERSION\""
echo "  git push origin gh-pages"
