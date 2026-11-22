#!/bin/sh
# Builds the app (Release unless you pass Debug) and prints the path of the .app.
# Build files go to Xcode's DerivedData in ~/Library, not the project folder,
# because the project lives in iCloud Drive.
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/MawaqitPrayerTime-cli"
xcodebuild -project MawaqitPrayerTime.xcodeproj -scheme MawaqitPrayerTime \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" -quiet build
echo "$DERIVED/Build/Products/$CONFIG/MawaqitPrayerTime.app"
