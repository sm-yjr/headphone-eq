#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build --build-system native --product EQVerify
VERIFY_BINARY="$(swift build --build-system native --show-bin-path)/EQVerify"
"$VERIFY_BINARY"
git diff --check
