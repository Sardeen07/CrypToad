#!/usr/bin/env bash
# Saves a screenshot of the booted iOS Simulator into docs/screenshots/.
#
#   ./scripts/screenshot.sh home
#   ./scripts/screenshot.sh roundup
#
# Run the app in the simulator (⌘R in Xcode), navigate to the screen, then run this.
set -euo pipefail

name="${1:?usage: $0 <name>   e.g. home, roundup, dca, card, trade}"
dir="$(cd "$(dirname "$0")/.." && pwd)/docs/screenshots"
mkdir -p "$dir"

xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
xcrun simctl io booted screenshot "$dir/$name.png"
echo "Saved docs/screenshots/$name.png"
