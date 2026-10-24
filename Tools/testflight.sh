#!/bin/zsh
# Archives Open Search (sandboxed, Mac App Store signing) and uploads it to App Store Connect for TestFlight.
# Needs: an app record for ca.loganhawkins.opensearch (platform macOS) in App Store Connect, and Xcode signed in
# to your Apple ID (Xcode > Settings > Accounts). Automatic signing creates the distribution certificates.
# Usage: Tools/testflight.sh [build-number]   (defaults to a timestamp; every upload needs a new one)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:-$(date +%y%m%d%H%M)}"
OUT="${TMPDIR:-/tmp}/opensearch-tf-$BUILD"   # outside synced folders, which add xattrs that break signing
rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate >/dev/null
echo "Archiving build $BUILD..."
xcodebuild archive -project OpenSearch.xcodeproj -scheme OpenSearch -destination "generic/platform=macOS" \
  -archivePath "$OUT/OpenSearch.xcarchive" -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=W6U2585855 \
  ENABLE_APP_SANDBOX=YES ENABLE_HARDENED_RUNTIME=YES CURRENT_PROJECT_VERSION="$BUILD" | tail -5
echo "Uploading to App Store Connect..."
xcodebuild -exportArchive -archivePath "$OUT/OpenSearch.xcarchive" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates | tail -8
echo "Done. The build appears in App Store Connect > TestFlight after processing (usually 5-20 minutes)."
