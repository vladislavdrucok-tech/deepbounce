@tool
extends EditorPlugin
## Adds the DeepBouncePlay Android library (Play Games Services v2 leaderboards + in-app review) to Android
## exports. The Play Games project ID comes from res://config/monetization.cfg [play_games] app_id; the manifest
## entry is added only when it is set (tools/android/build_release.sh writes the matching string resource).
## Source: android_plugins/deepbounce-play.

var export_plugin: PlayExportPlugin

func _enter_tree() -> void:
	export_plugin = PlayExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class PlayExportPlugin extends EditorExportPlugin:
	const NAME := "DeepBouncePlay"
	# keep in sync with android_plugins/deepbounce-play/play/build.gradle.kts
	const DEPS := ["com.google.android.gms:play-services-games-v2:21.0.0", "com.google.android.play:review:2.0.2"]

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform, debug) -> PackedStringArray:
		return PackedStringArray([NAME + "/bin/" + NAME + ("-debug.aar" if debug else "-release.aar")])

	func _get_android_dependencies(platform, debug) -> PackedStringArray:
		return PackedStringArray(DEPS)

	func _get_android_manifest_application_element_contents(platform, debug) -> String:
		var cfg := ConfigFile.new()
		cfg.load("res://config/monetization.cfg")
		var app_id := String(cfg.get_value("play_games", "app_id", ""))
		if app_id == "":
			return ""
		# must be a string resource: a literal number would be read as an integer and ignored by the SDK
		return '<meta-data android:name="com.google.android.gms.games.APP_ID" android:value="@string/game_services_project_id"/>\n'

	func _get_name() -> String:
		return NAME
