#!/bin/sh
# Inspect the actual Mach-O; compile flags alone are not evidence of exclusion.
set -eu
flavor=${1:?Usage: verify-distribution.sh direct|app-store /path/ShelterBar.app}
app=${2:?Pass the built app bundle}
binary="$app/Contents/MacOS/ShelterBar"
[ -f "$binary" ] || { echo "Missing executable: $binary" >&2; exit 1; }
[ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ] || { echo 'Missing privacy manifest' >&2; exit 1; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
/usr/bin/strings -a "$binary" > "$scratch/strings"
/usr/bin/nm "$binary" > "$scratch/symbols"
case "$flavor" in
    direct)
        grep -Fq 'api.github.com/repos/tonyjianchina/ShelterBar/releases' "$scratch/strings"
        # Xcode strips private Swift symbols from archives; the embedded
        # installer script and readiness handshake must survive that strip.
        grep -Fq 'ShelterBar-Updater' "$scratch/strings"
        grep -Fq 'ShelterBarUpdate-' "$scratch/strings"
        grep -Fq 'SHELTERBAR_UPDATE_READY_FILE' "$scratch/strings"
        echo 'Verified direct distribution: GitHub feed and installer present.'
        ;;
    app-store)
        if grep -E 'api\.github\.com/repos/tonyjianchina/ShelterBar/releases|ShelterBar-Updater|ShelterBarUpdate-|SHELTERBAR_UPDATE_READY_FILE|MenuBarClientCore|MBAssessmentMode|initWithAllowedSystemItems:allowedBundleIdentifiers:' "$scratch/strings"; then
            echo 'Forbidden updater or private API strings in audit build.' >&2; exit 1
        fi
        if grep -E 'UpdateInstaller|UpdateReadiness|UpdateCheckCache|ReleaseCandidate|GitHubRelease|UpdateInstallPlan' "$scratch/symbols"; then
            echo 'Updater implementation symbols in audit build.' >&2; exit 1
        fi
        echo 'Verified updater-free audit: no GitHub updater or private visibility API.'
        ;;
    *) echo 'Flavor must be direct or app-store.' >&2; exit 1 ;;
esac
