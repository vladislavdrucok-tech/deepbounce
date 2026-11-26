@tool
extends EditorPlugin
## Adds the DeepBounceAds Android library, Google Mobile Ads + UMP dependencies and the AdMob App ID
## (from res://config/monetization.cfg) to Android exports. Source: android_plugins/deepbounce-ads.

var export_plugin: AdsExportPlugin

func _enter_tree() -> void:
	export_plugin = AdsExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AdsExportPlugin extends EditorExportPlugin:
	const NAME := "DeepBounceAds"
	const ADMOB := preload("res://scripts/admob_ids.gd")
	# keep in sync with android_plugins/deepbounce-ads/ads/build.gradle.kts
	const DEPS := ["com.google.android.gms:play-services-ads:24.9.0", "com.google.android.ump:user-messaging-platform:3.2.0"]

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform, debug) -> PackedStringArray:
		return PackedStringArray([NAME + "/bin/" + NAME + ("-debug.aar" if debug else "-release.aar")])

	func _get_android_dependencies(platform, debug) -> PackedStringArray:
		return PackedStringArray(DEPS)

	func _get_android_manifest_application_element_contents(platform, debug) -> String:
		var cfg := ConfigFile.new()
		cfg.load("res://config/monetization.cfg")
		# The real App ID even in test mode: UMP looks up the owner's published GDPR message by it. Ad requests
		# still go to Google's test units while use_test_ads=true (scripts/admob_ids.gd).
		var app_id: String = ADMOB.manifest_app_id(cfg)
		if app_id.contains("3940256099942544") and not debug:
			push_warning("DeepBounceAds: release export with Google's TEST AdMob App ID (set real_app_id in config/monetization.cfg)")
		# Without this entry the Google Mobile Ads SDK stops the app at start.
		return '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s"/>\n' % app_id

	func _get_name() -> String:
		return NAME
