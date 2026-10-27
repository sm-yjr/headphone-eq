#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
CONFIGURATION=release UNIVERSAL=1 ./script/build_and_run.sh --build-only
APP="dist/HeadphoneEQ.app"
# Credentials stay in the maintainer's Keychain and are never stored in the repo.
if [[ -n "${HEADPHONE_EQ_NOTARY_PROFILE:-}" ]]; then
  [[ "${HEADPHONE_EQ_SIGNING_IDENTITY:--}" != "-" ]] || { echo "Notarization requires Developer ID signing." >&2;exit 1; }
  ditto -c -k --sequesterRsrc --keepParent "$APP" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --keychain-profile "$HEADPHONE_EQ_NOTARY_PROFILE" --wait --output-format json > dist/notarization.json
  python3 -c 'import json;assert json.load(open("dist/notarization.json"))["status"] == "Accepted", "Notarization was not accepted"'
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
ZIP="HeadphoneEQ-${VERSION}-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ZIP"
(cd dist && shasum -a 256 "$ZIP" > SHA256SUMS.txt)
echo "dist/$ZIP"
