#!/bin/zsh
# Re-renders the app icon from the SwiftUI mark and rebuilds Resources/AppIcon.icon (+ docs/logo.png).
# Run after changing LogoMark in Sources/Core/Theme.swift:  Tools/make-icon.sh
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/opensearch-icon"
DD="${TMPDIR:-/tmp}/opensearch-icon-dd"
xcodebuild -project OpenSearch.xcodeproj -scheme OpenSearch -configuration Debug -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build -quiet
rm -rf "$OUT"
"$DD/Build/Products/Debug/Open Search.app/Contents/MacOS/Open Search" --export-icon "$OUT"

ICON=Resources/AppIcon.icon
rm -rf "$ICON"
mkdir -p "$ICON/Assets"
cp "$OUT/mark-white-1024.png" "$ICON/Assets/mark.png"
cat > "$ICON/icon.json" <<'JSON'
{
  "fill" : { "automatic-gradient" : "extended-srgb:1.00000,0.42000,0.08000,1.00000" },
  "groups" : [
    {
      "layers" : [ { "glass" : true, "image-name" : "mark.png", "name" : "mark" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "circles" : [ "watchOS" ], "squares" : "shared" }
}
JSON
mkdir -p docs
cp "$OUT/icon-1024.png" docs/icon.png
cp "$OUT/logo-512.png" docs/logo.png
echo "Rebuilt $ICON and docs/icon.png, docs/logo.png"
