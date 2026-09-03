#!/bin/bash

REPO="kushalpandya/Petrichor"
APPCAST_FILE="appcast.xml"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
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

# Markdown release notes -> HTML for <description><![CDATA[...]]></description>.
# Handles headings, nested lists, GitHub callouts (> [!IMPORTANT]), code spans,
# emphasis, @mentions, bare URLs, and #NNN references, escaping everything else.
cat > "$TEMP_DIR/convert.py" <<'PYEOF'
import sys, re

REPO = "kushalpandya/Petrichor"
BASE = 16  # column the outermost block element sits at inside the CDATA

# GitHub redirects /issues/N to /pull/N (and back) automatically, so a single
# form covers both without needing to know which one N actually is.
def ref_link(n):
    return f'<a href="https://github.com/{REPO}/issues/{n}">#{n}</a>'

def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def inline(text, codes):
    # Stash code spans first so nothing below rewrites their contents.
    def stash(m):
        codes.append(m.group(1))
        return f'\x00{len(codes) - 1}\x00'
    text = re.sub(r'`([^`]+)`', stash, text)
    text = esc(text)
    text = re.sub(r'!\[[^\]]*\]\([^)\s]+\)', '', text)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)\s]+)\)', r'<a href="\2">\1</a>', text)
    text = re.sub(rf'(?<![">])https://github\.com/{re.escape(REPO)}/(?:pull|issues)/(\d+)\b',
                  lambda m: ref_link(m.group(1)), text)
    text = re.sub(r'(?<![">])(https?://[^\s<"]+[^\s<".,;:)])',
                  r'<a href="\1">\1</a>', text)
    text = re.sub(r'(?<![\w/>])#(\d+)\b', lambda m: ref_link(m.group(1)), text)
    text = re.sub(r'\*\*([^*]+?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'(?<![\w*])\*([^*\n]+?)\*(?!\w)', r'<em>\1</em>', text)
    text = re.sub(r'(?<![\w>/"=@.-])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)\b',
                  r'<a href="https://github.com/\1">@\1</a>', text)
    return re.sub(r'\x00(\d+)\x00',
                  lambda m: f'<code>{esc(codes[int(m.group(1))])}</code>', text)

def convert(content):
    out, codes = [], []
    stack = []        # source indent width of each open <ul>
    pending = None    # text of an <li> not yet written (may still gain children)
    quote = None      # blockquote lines being collected
    fc_url = None

    emit = lambda s, col: out.append(' ' * col + s)
    ul_col = lambda d: BASE + 8 * (d - 1)
    li_col = lambda d: ul_col(d) + 4

    def flush(close=True):
        nonlocal pending
        if pending is not None:
            emit(f'<li>{pending}' + ('</li>' if close else ''), li_col(len(stack)))
            pending = None

    def close_lists(min_indent=None):
        while stack and (min_indent is None or min_indent < stack[-1]):
            flush()
            emit('</ul>', ul_col(len(stack)))
            stack.pop()
            if stack:
                emit('</li>', li_col(len(stack)))

    def flush_quote():
        nonlocal quote
        if quote is None:
            return
        lines, label = quote, None
        quote = None
        if lines and (m := re.fullmatch(r'\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]', lines[0])):
            label = m.group(1).capitalize()
            lines = lines[1:]
        paras, cur = [], []
        for line in lines:
            if line:
                cur.append(line)
            elif cur:
                paras.append(cur); cur = []
        if cur:
            paras.append(cur)
        if not paras:
            return
        emit('<blockquote>', BASE)
        for i, para in enumerate(paras):
            html = [inline(line, codes) for line in para]
            if i == 0 and label:
                bold = re.fullmatch(r'\*\*(.+)\*\*', para[0])
                body = inline(bold.group(1) if bold else para[0], codes)
                html[0] = (f'<strong>{label}: {body}</strong>' if bold
                           else f'<strong>{label}:</strong> {body}')
            # GitHub renders single newlines in release bodies as hard breaks.
            emit('<p>' + '<br>'.join(html) + '</p>', BASE + 4)
        emit('</blockquote>', BASE)

    for raw in content.replace('\r\n', '\n').replace('\t', '    ').split('\n'):
        line = raw.strip()

        if (m := re.match(r'^\s*>\s?(.*)$', raw)):
            if quote is None:
                close_lists(); flush(); quote = []
            quote.append(m.group(1).strip())
            continue
        flush_quote()

        if not line:
            continue  # blank lines keep loose lists open; only blocks close them

        if (m := re.match(r'^\*\*Full Changelog\*\*\s*:?\s*(\S+)', line)):
            close_lists(); fc_url = m.group(1)
            continue

        if (m := re.match(r'^(#{1,6})\s+(.+)$', line)):
            close_lists()
            lvl = len(m.group(1))
            emit(f'<h{lvl}>{inline(m.group(2), codes)}</h{lvl}>', BASE)
            continue

        if (m := re.match(r'^(\s*)[\*\-+]\s+(.+)$', raw)):
            indent = len(m.group(1))
            item = inline(re.sub(r'^[a-f0-9]{7,40}\s+', '', m.group(2).strip()), codes)
            if not stack:
                emit('<ul>', ul_col(1)); stack.append(indent)
            elif indent > stack[-1]:
                flush(close=False)
                stack.append(indent)
                emit('<ul>', ul_col(len(stack)))
            else:
                close_lists(indent)
                flush()
            pending = item
            continue

        # An indented non-bullet line continues the bullet above it.
        if pending is not None and raw[:1].isspace():
            pending += ' ' + inline(line, codes)
            continue

        close_lists()
        emit(f'<p>{inline(line, codes)}</p>', BASE)

    flush_quote()
    close_lists()
    if fc_url:
        emit(f'<p><a href="{esc(fc_url)}">Full Changelog</a></p>', BASE)
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
            <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
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

python3 -c "import sys,xml.dom.minidom; xml.dom.minidom.parse('$APPCAST_FILE')" 2>/dev/null \
    || die "$APPCAST_FILE is not well-formed XML after the update - inspect it before committing"

echo
echo -e "${GREEN}✅ Updated $APPCAST_FILE${NC}"
echo "  • Version: $VERSION (build $BUILD_NUMBER)"
echo "  • Size:    $FILE_SIZE bytes"
echo "  • Min OS:  $MIN_SYSTEM_VERSION"
[ -n "$ED_SIGNATURE" ] && echo "  • Signed:  ✓" \
    || echo -e "  • Signed:  ${YELLOW}skipped (sandboxed updates may fail)${NC}"
echo
echo "Next steps:"
echo "  git diff $APPCAST_FILE"
echo "  git add $APPCAST_FILE && git commit -m \"Update appcast for v$VERSION\""
echo "  git push origin gh-pages"
