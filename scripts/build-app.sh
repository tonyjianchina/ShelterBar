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
target_triple=arm64-apple-macosx14.0
deployment_target=${target_triple#arm64-apple-macosx}
# The default Swift Build engine records the deployment target as the linked
# SDK version (LC_BUILD_VERSION sdk). Linking "against SDK 14" would opt the app
# into old-SDK compatibility behaviour on newer macOS, so record the real SDK.
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
linker_flags="-Xlinker -platform_version -Xlinker macos -Xlinker $deployment_target -Xlinker $sdk_version"
local_signing_name=${SHELTERBAR_LOCAL_SIGNING_NAME:-"ShelterBar Local Code Signing"}
app_dir="$project_dir/dist/ShelterBar.app"
mkdir -p "$project_dir/dist"
staging_root=$(mktemp -d "$project_dir/dist/.ShelterBar.XXXXXX")
staged_app="$staging_root/ShelterBar.app"
trap 'rm -rf "$staging_root"' EXIT

# shellcheck disable=SC2086 # linker_flags is intentionally word-split.
swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --product ShelterBar $linker_flags
# shellcheck disable=SC2086
binary_path=$(swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --show-bin-path $linker_flags)

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
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged_app/Contents/Info.plist")
set -- --force --sign "$signing_identity" --timestamp=none
if [ "$signing_identity" != - ]; then
    # Pin the designated requirement to bundle id + exact leaf certificate so
    # TCC grants survive every future release signed with the same identity.
    # A self-signed cert has no Apple anchor, so make the DR explicit.
    leaf_sha1=$(security find-certificate -a -Z -c "${SHELTERBAR_CODESIGN_CERT_NAME:-$signing_identity}" 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3; exit }')
    if [ -z "$leaf_sha1" ]; then
        echo "Could not read the certificate hash for $signing_identity." >&2
        exit 1
    fi
    set -- "$@" "-r=designated => identifier \"$bundle_id\" and certificate leaf = H\"$leaf_sha1\""
    # Hardened runtime is optional without notarization; ShelterBar needs no
    # runtime exceptions. Set SHELTERBAR_HARDENED_RUNTIME=0 to disable.
    if [ "${SHELTERBAR_HARDENED_RUNTIME:-1}" = 1 ]; then
        set -- "$@" --options runtime
    fi
fi
codesign "$@" "$staged_app"
codesign --verify --strict --verbose=2 "$staged_app"
codesign -d -r- "$staged_app" 2>&1 | sed -n 's/^designated => /Designated requirement: /p' >&2
rm -rf "$app_dir"
mv "$staged_app" "$app_dir"
echo "$app_dir"
