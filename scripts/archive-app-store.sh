#!/bin/sh
# Local archive only. This script never uploads or submits anything.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$project_dir/scripts/check-app-store-backend.sh"
# These commands become reachable only after implementing and accepting a real
# sandbox backend and replacing the gate as part of that reviewed change.
: "${SHELTERBAR_DEVELOPMENT_TEAM:?Set the Apple Developer team ID}"
xcodebuild -project "$project_dir/ShelterBar.xcodeproj" \
    -scheme ShelterBar-AppStore -configuration AppStore \
    -destination 'generic/platform=macOS' \
    -archivePath "$project_dir/dist/app-store/ShelterBar.xcarchive" \
    DEVELOPMENT_TEAM="$SHELTERBAR_DEVELOPMENT_TEAM" archive
