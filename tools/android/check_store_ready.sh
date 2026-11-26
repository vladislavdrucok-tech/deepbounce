#!/bin/sh
# Refuses to call a build "ready for Google Play production" while test settings are still in place.
#   tools/android/check_store_ready.sh        (run from deep_bounce/)
cd "$(dirname "$0")/../.."
CFG=config/monetization.cfg
fail=0
val() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$CFG" | head -1; }
[ "$(val use_test_ads)" = "false" ] || { echo "NOT READY: [admob] use_test_ads must be false"; fail=1; }
for k in real_app_id real_rewarded_revive real_rewarded_double real_interstitial; do
	v=$(val $k)
	case "$v" in ca-app-pub-*) ;; *) echo "NOT READY: [admob] $k is empty or not an AdMob ID"; fail=1;; esac
	case "$v" in *3940256099942544*) echo "NOT READY: [admob] $k is Google's TEST id"; fail=1;; esac
done
# Security blocker: without the licence key purchase signatures cannot be verified on the device.
tools/android/license_key.sh >/dev/null 2>&1; lk=$?
if [ $lk -eq 2 ]; then
	echo "NOT READY (SECURITY BLOCKER): no Play licence key — [billing] license_key or DEEPBOUNCE_PLAY_LICENSE_KEY (Play Console → Monetization setup → Licensing)"; fail=1
elif [ $lk -ne 0 ]; then
	echo "NOT READY (SECURITY BLOCKER): the Play licence key is invalid: $(tools/android/license_key.sh)"; fail=1
fi
[ -n "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] && [ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] || { echo "NOT READY: release keystore not set in the environment"; fail=1; }
grep -q 'boot_splash/image="res://assets/brand/splash.png"' project.godot || { echo "NOT READY: splash missing"; fail=1; }
echo "version: $(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg) (code $(sed -n 's/^version\/code=//p' export_presets.cfg))"
[ $fail -eq 0 ] && echo "READY for a production build: tools/android/build_release.sh aab" || echo "Fix the items above, or upload to Internal testing only (test ads are fine there)."
exit $fail
