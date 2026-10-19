#!/usr/bin/env bash
# Builds GeniusTransfer (release) and installs it on an iPhone.
#
# With a free Apple ID ("Personal Team") the install expires after 7 days:
# run this again each week. Release mode is required: Flutter debug builds
# on iOS 14+ only start when launched from Xcode or `flutter run`.
#
#   tool/ios_install.sh                 # lists connected iPhones
#   tool/ios_install.sh "iPhone Marley" # name or id from that list
set -euo pipefail
cd "$(dirname "$0")/../app"

if [[ $# -lt 1 ]]; then
  echo "Connected iOS devices (plug in, or same Wi-Fi with wireless debugging):"
  flutter devices | grep -i " ios " || echo "  none found"
  echo
  echo "Usage: tool/ios_install.sh <device name or id>"
  exit 1
fi

flutter build ios --release
flutter install --release -d "$1"
echo "Installed. If iOS says the developer is not trusted: on the iPhone open"
echo "Settings › General › VPN & Device Management, tap your Apple ID, Trust."
