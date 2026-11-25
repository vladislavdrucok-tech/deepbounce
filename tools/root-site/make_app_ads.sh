#!/bin/sh
# Writes app-ads.txt for the root developer site from the AdMob publisher ID (AdMob → Settings → Account information).
#   tools/root-site/make_app_ads.sh pub-1234567890123456 [output dir]
# The publisher ID is public (it is in every ad request), but it must be the real one: never a placeholder.
set -e
PUB="$1"
OUT="${2:-$(dirname "$0")/out}"
if ! printf '%s' "$PUB" | grep -Eq '^pub-[0-9]{16}$'; then
	echo "usage: $0 pub-XXXXXXXXXXXXXXXX (16 digits, from AdMob → Settings → Account information)" >&2
	exit 1
fi
mkdir -p "$OUT"
printf 'google.com, %s, DIRECT, f08c47fec0942fa0\n' "$PUB" > "$OUT/app-ads.txt"
cp "$(dirname "$0")/index.html" "$OUT/index.html"
touch "$OUT/.nojekyll"
echo "written: $OUT/app-ads.txt, $OUT/index.html, $OUT/.nojekyll"
cat "$OUT/app-ads.txt"
