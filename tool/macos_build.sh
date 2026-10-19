#!/usr/bin/env bash
# Builds the macOS app and opens the folder that contains it.
#
# The app is signed for this Mac only (not notarized). On another Mac,
# Gatekeeper blocks it the first time: open it, then allow it in
# System Settings › Privacy & Security › "Open Anyway".
set -euo pipefail
cd "$(dirname "$0")/../app"

flutter build macos --release
app="build/macos/Build/Products/Release/GeniusTransfer.app"
echo "Built app/$app"
open -R "$app"
