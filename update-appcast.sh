#!/bin/bash

# Configuration
REPO_OWNER="kushalpandya"
REPO_NAME="Petrichor"
APPCAST_FILE="appcast.xml"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

echo "🔍 Checking for new releases..."

# Get latest release from GitHub API
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest")

# Extract version (remove 'v' prefix)
VERSION_TAG=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
VERSION=${VERSION_TAG#v}  # Remove 'v' prefix

if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Error: Could not fetch latest release${NC}"
    exit 1
fi

echo "📦 Latest release: $VERSION"

# Check if version already exists in appcast
if grep -q "<sparkle:version>$VERSION</sparkle:version>" "$APPCAST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✅ Appcast is already up to date with version $VERSION${NC}"
    exit 0
fi

echo -e "${YELLOW}🆕 New version detected: $VERSION${NC}"

# Extract release details
RELEASE_DATE=$(echo "$LATEST_RELEASE" | grep -o '"published_at": *"[^"]*"' | cut -d'"' -f4)
RELEASE_BODY=$(echo "$LATEST_RELEASE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('body', ''))
")

# Convert GitHub timestamp to RFC 822 format
RFC_DATE=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$RELEASE_DATE" "+%a, %d %b %Y %H:%M:%S %z" 2>/dev/null)
if [ -z "$RFC_DATE" ]; then
    # Fallback for different date format
    RFC_DATE=$(date -R)
    echo -e "${YELLOW}⚠️  Warning: Could not parse release date, using current date${NC}"
fi

# Find DMG download URL
DMG_URL=$(echo "$LATEST_RELEASE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].endswith('.dmg'):
        print(asset['browser_download_url'])
        break
")

if [ -z "$DMG_URL" ]; then
    echo -e "${RED}❌ Error: No DMG file found in release${NC}"
    exit 1
fi

echo "📥 Downloading DMG to calculate size..."
echo "   URL: $DMG_URL"

# Download DMG to get file size
DMG_FILE="$TEMP_DIR/temp.dmg"
if ! curl -L -# -o "$DMG_FILE" "$DMG_URL"; then
    echo -e "${RED}❌ Error: Failed to download DMG${NC}"
    exit 1
fi

# Get file size in bytes
FILE_SIZE=$(stat -f%z "$DMG_FILE")
echo "📏 DMG size: $FILE_SIZE bytes"

# Convert markdown release notes to HTML
RELEASE_HTML=$(echo "$RELEASE_BODY" | python3 -c "
import sys
import re

content = sys.stdin.read()

# Split into sections
sections = []
current_section = None
current_items = []

for line in content.split('\n'):
    line = line.strip()
    if line.startswith('## '):
        if current_section and current_items:
            sections.append((current_section, current_items))
        current_section = line[3:]
        current_items = []
    elif line.startswith('* '):
        # Remove commit hash if present
        item = re.sub(r'^[a-f0-9]{7}\s+', '', line[2:])
        current_items.append(item)
    elif line.startswith('**Full Changelog**:'):
        # Extract URL
        url_match = re.search(r'https://[^\s]+', line)
        if url_match and current_items:
            current_items.append(f'<a href=\"{url_match.group()}\">Full Changelog</a>')

if current_section and current_items:
    sections.append((current_section, current_items))

# Generate HTML
html_parts = []
for section, items in sections:
    if section.lower() != 'full changelog':
        html_parts.append(f'<h2>{section}</h2>')
        html_parts.append('<ul>')
        for item in items:
            if not item.startswith('<a href'):
                html_parts.append(f'    <li>{item}</li>')
        html_parts.append('</ul>')
        
# Add full changelog link if present
for section, items in sections:
    for item in items:
        if item.startswith('<a href'):
            html_parts.append(f'<p>{item}</p>')
            break

print('\\n'.join(html_parts))
")

# Create new item XML
NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version $VERSION</title>
            <pubDate>$RFC_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/v$VERSION/Petrichor-$VERSION-Universal.dmg"
                length="$FILE_SIZE"
                type="application/octet-stream" />
            <description><![CDATA[
                $RELEASE_HTML
            ]]></description>
        </item>
EOF
)

# Backup current appcast if it exists
if [ -f "$APPCAST_FILE" ]; then
    cp "$APPCAST_FILE" "${APPCAST_FILE}.bak"
fi

# Create the new appcast file
{
    # Write the header
    cat <<'EOF_HEADER'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Petrichor Updates</title>
        <description>Updates for Petrichor</description>
        <language>en</language>
EOF_HEADER

    # Add the new item
    echo "$NEW_ITEM"
    
    # If backup exists, add any existing items (except duplicates of the same version)
    if [ -f "${APPCAST_FILE}.bak" ]; then
        # Extract existing items, skipping any with the same version
        in_item=false
        skip_item=false
        while IFS= read -r line; do
            if echo "$line" | grep -q "<item>"; then
                in_item=true
                item_content="$line"
            elif [ "$in_item" = true ]; then
                item_content="$item_content
$line"
                if echo "$line" | grep -q "<sparkle:version>$VERSION</sparkle:version>"; then
                    skip_item=true
                fi
                if echo "$line" | grep -q "</item>"; then
                    if [ "$skip_item" = false ]; then
                        echo "$item_content"
                    fi
                    in_item=false
                    skip_item=false
                    item_content=""
                fi
            fi
        done < "${APPCAST_FILE}.bak"
    fi
    
    # Write the footer
    cat <<'EOF_FOOTER'
    </channel>
</rss>
EOF_FOOTER
} > "${APPCAST_FILE}.tmp"

# Move temp file to actual appcast file
mv "${APPCAST_FILE}.tmp" "$APPCAST_FILE"

# Clean up backup if it exists
if [ -f "${APPCAST_FILE}.bak" ]; then
    rm "${APPCAST_FILE}.bak"
fi

echo -e "${GREEN}✅ Successfully updated appcast.xml with version $VERSION${NC}"
echo ""
echo "Next steps:"
echo "1. Review: git diff appcast.xml"
echo "2. Commit: git add appcast.xml && git commit -m \"Update appcast for v$VERSION\""
echo "3. Push:   git push origin gh-pages"