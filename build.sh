#!/bin/zsh
# Builds Open Search and installs it to ~/Applications. Run: ./build.sh
# Signs with your Apple Development identity when one exists (so macOS keeps Keychain access between rebuilds),
# otherwise ad-hoc.
set -e
cd "$(dirname "$0")"
xcodegen generate >/dev/null
DD="${TMPDIR:-/tmp}/opensearch-dd"   # outside synced folders, which add xattrs that break signing
xcodebuild -project OpenSearch.xcodeproj -scheme OpenSearch -configuration Release -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build -quiet
APP="$DD/Build/Products/Release/Open Search.app"
xattr -cr "$APP"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --deep --sign "${IDENTITY:--}" "$APP" >/dev/null
DEST="$HOME/Applications/Open Search.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto --norsrc --noextattr "$APP" "$DEST"
echo "Installed $DEST (signed: ${IDENTITY:-ad-hoc})"
