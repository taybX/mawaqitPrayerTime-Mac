#!/bin/sh
# Runs MawaqitKit's unit tests. Builds in ~/Library/Caches so nothing lands in
# the project folder, which iCloud Drive would otherwise upload.
set -e
cd "$(dirname "$0")/../Packages/MawaqitKit"
exec swift test --scratch-path "$HOME/Library/Caches/MawaqitPrayerTime/MawaqitKit-build" "$@"
