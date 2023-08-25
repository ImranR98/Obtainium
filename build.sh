#!/bin/bash
# Convenience script

CURR_DIR="$(pwd)"
trap "cd "$CURR_DIR"" EXIT

git fetch && git merge origin/main && git push                                               # Typically run after a PR to main, so bring dev up to date
rm ./build/app/outputs/flutter-apk/* 2>/dev/null                                             # Get rid of older builds if any
flutter build apk && flutter build apk --split-per-abi                                       # Build (both split and combined APKs)
for file in ./build/app/outputs/flutter-apk/*.sha1; do gpg --sign --detach-sig "$file"; done # Generate PGP signatures
rsync -r ./build/app/outputs/flutter-apk/ ~/Downloads/Obtainium-build/                       # Dropoff in Downloads to allow for drag-drop into Flatpak Firefox
cd ~/Downloads/Obtainium-build/                                                              # Make zips just in case (for in-comment uploads)
for apk in *.apk; do
    PREFIX="$(echo "$apk" | head -c -5)"
    zip "$PREFIX" "$PREFIX"*
done
mkdir -p zips
mv *.zip zips/
