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
