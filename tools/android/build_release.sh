#!/bin/sh
# Deep Bounce: signed release APK and AAB through the Godot Gradle build.
#   tools/android/build_release.sh [apk|aab|both]      (run from deep_bounce/)
# Needs: Godot 4.5.1 + export templates, JDK 17+, Android SDK with platforms;android-36 and build-tools;36.0.0,
# and the release key passed in the environment (never stored in the repository):
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
set -e
WHAT=${1:-both}
G=${GODOT:-godot}
cd "$(dirname "$0")/../.."
VERSION=$(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg)
mkdir -p build
# Ads: test mode unless config/monetization.cfg says use_test_ads=false; a production-ads build is refused while
# anything in tools/android/check_store_ready.sh is missing (licence key, real ad units, keystore...).
if grep -q '^use_test_ads=false' config/monetization.cfg; then
	echo "Ads: PRODUCTION (real AdMob App ID and ad units)"
	tools/android/check_store_ready.sh || { echo "refusing a production-ads build: fix the items above"; exit 1; }
else
	echo "Ads: TEST (real AdMob App ID in the manifest for UMP, Google's test ad units) — for internal / closed testing"
fi
# Play licence key: a key that is set but broken would make every purchase fail its check — refuse in any mode.
set +e; tools/android/license_key.sh; LK=$?; set -e
if [ $LK -eq 1 ]; then echo "refusing the build: fix the Play licence key"; exit 1; fi
# A key given only in the environment goes into the exported config for this build and nowhere else.
CFG_BACKUP=""
if [ -n "$DEEPBOUNCE_PLAY_LICENSE_KEY" ] && grep -q '^license_key=""' config/monetization.cfg; then
	CFG_BACKUP=$(mktemp)
	cp config/monetization.cfg "$CFG_BACKUP"
	trap 'cp "$CFG_BACKUP" config/monetization.cfg; rm -f "$CFG_BACKUP"' EXIT INT TERM
	K=$(printf '%s' "$DEEPBOUNCE_PLAY_LICENSE_KEY" | sed 's/-----[A-Z ]*-----//g' | tr -d ' \t\r\n')
	sed -i "s|^license_key=\"\"|license_key=\"$K\"|" config/monetization.cfg
	echo "Play licence key: taken from DEEPBOUNCE_PLAY_LICENSE_KEY for this build (config file restored afterwards)"
fi
"$G" --headless --path . --import >/dev/null 2>&1 || true

games_resource() {
	# Play Games Services needs its project ID as a string resource (a literal number in the manifest is ignored)
	ID=$(sed -n '/^\[play_games\]/,/^\[/s/^app_id="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' config/monetization.cfg | head -1)
	if [ -d android/build/res ]; then
		mkdir -p android/build/res/values
		if [ -n "$ID" ]; then
			printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="game_services_project_id" translatable="false">%s</string>\n</resources>\n' "$ID" > android/build/res/values/deepbounce_games.xml
		else
			rm -f android/build/res/values/deepbounce_games.xml
		fi
	fi
}

prepare_template() {
	# The Godot 4.5.1 template compiles against API 35; Google Play now requires target API 36.
	if [ -f android/build/config.gradle ]; then
		sed -i "s/compileSdk         : 35/compileSdk         : 36/; s/buildTools         : '35.0.0'/buildTools         : '36.0.0'/" android/build/config.gradle
		grep -q "android.suppressUnsupportedCompileSdk" android/build/gradle.properties || \
			echo "android.suppressUnsupportedCompileSdk=36" >> android/build/gradle.properties
	fi
	# Activity without the deprecated edge-to-edge calls of the stock template (see the file's header)
	if [ -d android/build/src/com/godot/game ]; then
		cp tools/android/template/GodotApp.java android/build/src/com/godot/game/GodotApp.java
	fi
}

export_one() {   # $1 = 0 (apk) / 1 (aab), $2 = output path
	sed -i "s/^gradle_build\/export_format=.*/gradle_build\/export_format=$1/" export_presets.cfg
	if [ ! -f android/build/config.gradle ]; then
		"$G" --headless --path . --install-android-build-template --export-release "Android" "$2" || true
		prepare_template
	fi
	prepare_template
	games_resource
	"$G" --headless --path . --export-release "Android" "$2"
}

if [ "$WHAT" = "apk" ] || [ "$WHAT" = "both" ]; then export_one 0 "build/DeepBounce-$VERSION.apk"; fi
if [ "$WHAT" = "aab" ] || [ "$WHAT" = "both" ]; then export_one 1 "build/DeepBounce-$VERSION.aab"; fi
sed -i "s/^gradle_build\/export_format=.*/gradle_build\/export_format=0/" export_presets.cfg
ls -la build/DeepBounce-$VERSION.*
