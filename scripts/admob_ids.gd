extends RefCounted
## Which AdMob IDs a build uses, read from config/monetization.cfg. Shared by the Android export plugin
## (App ID in AndroidManifest) and the Ads autoload (ad unit per placement), and covered by tests.
##
##  * AndroidManifest always gets the REAL App ID once it is configured. Google's UMP SDK finds the app's
##    published GDPR message by this App ID, so the test App ID would hide the owner's consent message.
##  * Ad units: Google's test units while use_test_ads=true (Closed testing), the real ones only with
##    use_test_ads=false (production, and only after tools/android/check_store_ready.sh passes).
##  * The forced EEA geography for the consent form only on registered test devices.

const PLACEMENT_KEYS := {"revive": "rewarded_revive", "double": "rewarded_double", "interstitial": "interstitial"}

static func test_mode(cfg: ConfigFile) -> bool:
	return bool(cfg.get_value("admob", "use_test_ads", true)) or String(cfg.get_value("admob", "real_app_id", "")) == ""

static func manifest_app_id(cfg: ConfigFile) -> String:
	var real := String(cfg.get_value("admob", "real_app_id", "")).strip_edges()
	if real != "":
		return real
	return String(cfg.get_value("admob", "test_app_id", ""))

static func unit(cfg: ConfigFile, placement: String) -> String:
	var key: String = PLACEMENT_KEYS[placement]
	return String(cfg.get_value("admob", ("test_" if test_mode(cfg) else "real_") + key, ""))

static func test_devices(cfg: ConfigFile) -> String:
	var ids: PackedStringArray = []
	for s in String(cfg.get_value("admob", "test_device_ids", "")).split(","):
		if s.strip_edges() != "":
			ids.append(s.strip_edges())
	return ",".join(ids)

static func debug_eea(cfg: ConfigFile) -> bool:
	## UMP applies debug settings only to the hashed devices listed with them; without any listed device the
	## forced EEA is never requested, so ordinary testers see the real geography.
	return test_mode(cfg) and bool(cfg.get_value("admob", "debug_geography_eea", false)) and test_devices(cfg) != ""
