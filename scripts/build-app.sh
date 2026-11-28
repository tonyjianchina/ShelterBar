#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
if [ "${SHELTERBAR_ENABLE_APP_SANDBOX:-0}" != 0 ] || [ "${SHELTERBAR_APP_SANDBOX:-0}" != 0 ]; then
    echo "Refusing to enable App Sandbox." >&2
    echo "The current hide and drag path is incompatible with it, so no sandboxed build is produced." >&2
    echo "See docs/MAC-APP-STORE.md." >&2
    exit 1
fi
distribution=${SHELTERBAR_DISTRIBUTION:-direct}
case "$distribution" in
    direct) distribution_flags= ;;
    app-store)
        distribution_flags="-Xswiftc -DSHELTERBAR_APP_STORE"
        echo "Updater-free audit flavor: GitHub updater and private visibility API are compiled out." >&2
        echo "App Sandbox is not enabled. This is an audit artifact; do not install or upload it." >&2
        echo "See docs/MAC-APP-STORE.md." >&2
        ;;
    *)
        echo "SHELTERBAR_DISTRIBUTION must be direct or app-store." >&2
        exit 1
        ;;
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
if [ "$distribution" = app-store ]; then
    app_dir="$project_dir/dist/updater-free-audit/ShelterBar.app"
else
    app_dir="$project_dir/dist/ShelterBar.app"
fi
mkdir -p "$(dirname "$app_dir")"
mkdir -p "$project_dir/dist"
staging_root=$(mktemp -d "$project_dir/dist/.ShelterBar.XXXXXX")
staged_app="$staging_root/ShelterBar.app"
trap 'rm -rf "$staging_root"' EXIT

# shellcheck disable=SC2086 # linker_flags and distribution_flags are intentionally word-split.
swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --product ShelterBar $linker_flags $distribution_flags
# shellcheck disable=SC2086
binary_path=$(swift build --package-path "$project_dir" --configuration "$configuration" \
    --triple "$target_triple" --force-resolved-versions --show-bin-path $linker_flags $distribution_flags)

mkdir -p "$staged_app/Contents/MacOS"
mkdir -p "$staged_app/Contents/Resources"
cp "$binary_path/ShelterBar" "$staged_app/Contents/MacOS/ShelterBar"
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/PrivacyInfo.xcprivacy" "$staged_app/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R "$project_dir/Resources/en.lproj" "$staged_app/Contents/Resources/en.lproj"
cp -R "$project_dir/Resources/zh-Hans.lproj" "$staged_app/Contents/Resources/zh-Hans.lproj"

plutil -lint "$staged_app/Contents/Info.plist"
plutil -lint "$staged_app/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$staged_app/Contents/Resources/en.lproj/InfoPlist.strings"
plutil -lint "$staged_app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
for key in NSAccessibilityUsageDescription NSScreenCaptureUsageDescription LSApplicationCategoryType CFBundleDevelopmentRegion; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$staged_app/Contents/Info.plist" >/dev/null
done
category=$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$staged_app/Contents/Info.plist")
if [ "$category" != "public.app-category.utilities" ]; then
    echo "LSApplicationCategoryType must be public.app-category.utilities." >&2
    exit 1
fi
encryption=$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$staged_app/Contents/Info.plist")
if [ "$encryption" != false ]; then
    echo "ITSAppUsesNonExemptEncryption must be false." >&2
    exit 1
fi
tracking=$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$staged_app/Contents/Resources/PrivacyInfo.xcprivacy")
if [ "$tracking" != false ]; then
    echo "Privacy manifest must declare NSPrivacyTracking false." >&2
    exit 1
fi
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
if codesign -d --entitlements :- "$staged_app" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
    echo "Refusing to produce a build with the App Sandbox entitlement." >&2
    echo "See docs/MAC-APP-STORE.md." >&2
    exit 1
fi
"$project_dir/scripts/verify-distribution.sh" "$distribution" "$staged_app"
codesign -d -r- "$staged_app" 2>&1 | sed -n 's/^designated => /Designated requirement: /p' >&2
rm -rf "$app_dir"
mv "$staged_app" "$app_dir"
echo "$app_dir"
