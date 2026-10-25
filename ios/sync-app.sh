#!/bin/sh
# Copies the Shecurity app (the app/ folder of the main branch) into the iPhone app,
# so it ships inside the app and works without a connection.
# Usage: ios/sync-app.sh path/to/shecurity-main/app
set -e
src="${1:?give the path to the app folder of the main branch}"
dst="$(dirname "$0")/Shecurity/www"
rm -rf "$dst"
mkdir -p "$dst"
(cd "$src" && tar cf - --exclude=sw.js .) | (cd "$dst" && tar xf -)
echo "Copied $(find "$dst" -type f | wc -l | tr -d ' ') files into $dst"
