#!/bin/sh
# Checks the Google Play licence key (Play Console → Deep Bounce → Monetize with Play → Monetization setup →
# Licensing: "Base64-encoded RSA public key"). It is a PUBLIC key: it can only verify purchase signatures.
#   tools/android/license_key.sh            check the key the build will use
#   tools/android/license_key.sh "<key>"    check a key before putting it anywhere
# The key comes from [billing] license_key in config/monetization.cfg, or — to keep it out of the repository —
# from the environment variable DEEPBOUNCE_PLAY_LICENSE_KEY at build time (build_release.sh writes it into the
# exported copy of the config only and restores the file afterwards).
# Exit: 0 valid RSA key, 1 invalid, 2 missing.
cd "$(dirname "$0")/../.."
KEY="$1"
if [ -z "$KEY" ]; then
	KEY=$(sed -n '/^\[billing\]/,/^\[/s/^license_key="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' config/monetization.cfg | head -1)
	[ -z "$KEY" ] && KEY="$DEEPBOUNCE_PLAY_LICENSE_KEY"
fi
KEY=$(printf '%s' "$KEY" | sed 's/-----[A-Z ]*-----//g' | tr -d ' \t\r\n')
if [ -z "$KEY" ]; then
	echo "licence key: MISSING — purchase signatures cannot be verified (allowed for internal/closed testing only)"
	exit 2
fi
INFO=$(printf '%s' "$KEY" | base64 -d 2>/dev/null | openssl pkey -pubin -inform DER -noout -text 2>/dev/null | head -1)
case "$INFO" in
	*"Public-Key: ("*" bit)"*)
		if printf '%s' "$KEY" | base64 -d 2>/dev/null | openssl rsa -pubin -inform DER -noout 2>/dev/null; then
			echo "licence key: OK (RSA, $(echo "$INFO" | sed 's/.*(\(.*\)).*/\1/'))"
			exit 0
		fi
		echo "licence key: INVALID — not an RSA key"; exit 1 ;;
	*) echo "licence key: INVALID — not a Base64 X.509 public key (copy it again from Play Console → Licensing)"; exit 1 ;;
esac
