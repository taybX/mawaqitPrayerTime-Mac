#!/bin/sh
# Builds a Release copy and puts it in /Applications, replacing the old one,
# then starts it. Settings and the chosen mosque are kept.
set -e
APP=$("$(dirname "$0")/build.sh" Release | tail -n 1)
pkill -x MawaqitPrayerTime 2>/dev/null && sleep 1 || true
rm -rf /Applications/MawaqitPrayerTime.app
ditto "$APP" /Applications/MawaqitPrayerTime.app
open /Applications/MawaqitPrayerTime.app
echo "Installed /Applications/MawaqitPrayerTime.app"
