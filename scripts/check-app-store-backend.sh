#!/bin/sh
# Intentional, non-overridable release gate until the core has a real backend.
# Remove this gate only together with a sandbox-compatible implementation and
# real collection / restore / original-menu acceptance on supported displays.
set -eu
cat >&2 <<'MESSAGE'
error: ShelterBar does not yet have a sandbox-compatible collection backend.
The current core needs cross-app Accessibility and synthetic HID events.
The updater-free audit removes private APIs but cannot replace those operations.
Apple documents no Accessibility entitlement for sandboxed apps.
The legacy separator-length technique is not a working macOS 27 fallback.
Public assessment-session APIs are not documented for ordinary menu-bar utilities.
App Store build/archive is blocked; no nonfunctional sandbox package is produced.
See docs/validation/MAS-SANDBOX-20261128.md for the renewed feasibility review.
See docs/MAC-APP-STORE.md for packaging boundaries and remaining work.
MESSAGE
exit 1
