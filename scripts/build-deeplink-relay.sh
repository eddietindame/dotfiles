#!/usr/bin/env bash
# Build and register the bertie-dev:// relay. Run this on the CLIENT mac (the
# one you browse from), not the mini.
#
#   ./build-deeplink-relay.sh [install-dir]      default: ~/Applications

set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/bertie-deeplink-relay.applescript"
dest_dir="${1:-$HOME/Applications}"
app="$dest_dir/Bertie Deep Link Relay.app"
scheme="bertie-dev"
bundle_id="com.eddietindame.bertie-deeplink-relay"

mkdir -p "$dest_dir"
rm -rf "$app"
osacompile -o "$app" "$src"

plist="$app/Contents/Info.plist"
pb=/usr/libexec/PlistBuddy
# osacompile does not emit CFBundleIdentifier, so add it rather than set it
"$pb" -c "Add :CFBundleIdentifier string $bundle_id" "$plist" 2>/dev/null ||
  "$pb" -c "Set :CFBundleIdentifier $bundle_id" "$plist"
"$pb" -c "Add :CFBundleURLTypes array" "$plist"
"$pb" -c "Add :CFBundleURLTypes:0:CFBundleURLName string Bertie Dev Deep Link" "$plist"
"$pb" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$plist"
"$pb" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $scheme" "$plist"

lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$lsregister" -f "$app"

echo "built and registered: $app"
echo "test with: open '$scheme://relay-test/ping'"
echo "(the mini's dev app should log '=== RECEIVED open-url EVENT ===')"
