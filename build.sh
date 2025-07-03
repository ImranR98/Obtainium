#!/bin/bash
# Convenience script

CURR_DIR="$(pwd)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
trap "cd \"$CURR_DIR\"" EXIT
cd "$SCRIPT_DIR"

if [ -z "$1" ]; then
    git fetch && git merge origin/main && git push # Typically run after a PR to main, so bring dev up to date
fi

# Update local Flutter
git submodule update --remote
cd .flutter
git fetch
git checkout stable
git pull
FLUTTER_GIT_URL="https://github.com/flutter/flutter/" ./bin/flutter upgrade
cd ..

# Keep global Flutter, if any, in sync
if [ -f ~/flutter/bin/flutter ]; then
    cd ~/flutter
    ./bin/flutter channel stable
    ./bin/flutter upgrade
    cd "$SCRIPT_DIR"
fi

if [ -z "$(which flutter)" ]; then
    export PATH="$PATH:$SCRIPT_DIR/.flutter/bin"
fi

rm ./build/app/outputs/flutter-apk/* 2>/dev/null                                       # Get rid of older builds if any
flutter build apk --flavor normal && flutter build apk --split-per-abi --flavor normal # Build (both split and combined APKs)
for file in ./build/app/outputs/flutter-apk/app-*normal*.apk*; do mv "$file" "${file//-normal/}"; done
flutter build apk --flavor fdroid -t lib/main_fdroid.dart && # Do the same for the F-Droid flavour
    flutter build apk --split-per-abi --flavor fdroid -t lib/main_fdroid.dart
for file in ./build/app/outputs/flutter-apk/*.sha1; do gpg --sign --detach-sig "$file"; done # Generate PGP signatures
rsync -r ./build/app/outputs/flutter-apk/ ~/Downloads/Obtainium-build/                       # Dropoff in Downloads to allow for drag-drop into Flatpak Firefox
cd ~/Downloads/Obtainium-build/                                                              # Make zips just in case (for in-comment uploads)
for apk in *.apk; do
    PREFIX="$(echo "$apk" | head -c -5)"
    zip "$PREFIX" "$PREFIX"*
done
mkdir -p zips
mv *.zip zips/
