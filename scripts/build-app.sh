#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
if [ "$(uname -s)" != Darwin ]; then
    echo "ShelterBar must be built on macOS with Swift 6.2 or newer." >&2
    exit 1
fi

# Keep the release architecture and deployment target independent of the host.
target_triple=arm64-apple-macosx26.0
local_signing_name=${SHELTERBAR_LOCAL_SIGNING_NAME:-"ShelterBar Local Code Signing"}
app_dir="$project_dir/dist/ShelterBar.app"
mkdir -p "$project_dir/dist"
staging_root=$(mktemp -d "$project_dir/dist/.ShelterBar.XXXXXX")
staged_app="$staging_root/ShelterBar.app"
trap 'rm -rf "$staging_root"' EXIT

swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --product ShelterBar
binary_path=$(swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --show-bin-path)

mkdir -p "$staged_app/Contents/MacOS"
mkdir -p "$staged_app/Contents/Resources"
cp "$binary_path/ShelterBar" "$staged_app/Contents/MacOS/ShelterBar"
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"

plutil -lint "$staged_app/Contents/Info.plist"
if [ "$(lipo -archs "$staged_app/Contents/MacOS/ShelterBar")" != arm64 ]; then
    echo "Expected a single Apple Silicon (arm64) executable." >&2
    exit 1
fi
signing_identity=${SHELTERBAR_CODESIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -v name="$local_signing_name" 'index($0, "\"" name "\"") { print $2; exit }')
    if [ -z "$signing_identity" ]; then
        signing_identity=-
        echo "No stable ShelterBar signing identity found; using ad-hoc signing." >&2
        echo "Run scripts/setup-local-signing.sh once to preserve macOS permissions across local builds." >&2
    else
        echo "Signing with stable local identity: $local_signing_name" >&2
    fi
elif [ "$signing_identity" = - ]; then
    echo "Signing ad-hoc as explicitly requested." >&2
else
    echo "Signing with explicitly requested identity: $signing_identity" >&2
fi
codesign --force --sign "$signing_identity" --timestamp=none "$staged_app"
codesign --verify --strict --verbose=2 "$staged_app"
rm -rf "$app_dir"
mv "$staged_app" "$app_dir"
echo "$app_dir"
