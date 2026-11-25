extends Node
## Leaderboards and the rating prompt against the simulated Play Games service.
##   godot --headless --path . res://tests/play_test.tscn

const FakePlay := preload("res://scripts/play_fake.gd")
var fails := 0

func ok(cond: bool, name: String, info := "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + ("" if info == "" else "  (" + info + ")"))
	if not cond:
		fails += 1

func wait(t := 0.2) -> void:
	await get_tree().create_timer(t).timeout

func _ready() -> void:
	G.test_no_save = true
	G.reset_defaults()
	var results: Array = []
	Play.leaderboards_result.connect(func(s): results.append(s))
	# not signed in: scores wait, the leaderboard screen reports it cannot open
	var fake := FakePlay.new()
	fake.auth_ok = false
	Play.use_backend(fake)
	G.meta.best = 31
	Play.start()
	await wait()
	Play.submit("depth", 31)
	await wait()
	ok(not Play.signed and fake.submits == 0 and fake.scores.is_empty(), "not signed in to Play Games: nothing is sent")
	Play.show_leaderboards()
	await wait()
	ok(results == [false] and fake.shown == 0, "leaderboards button reports 'unavailable' instead of hanging", str(results))
	# the player signs in: the waiting score and the current bests are sent
	fake.auth_ok = true
	G.levels.stars = {"L01": 3, "L02": 2}
	Play.show_leaderboards()
	await wait(0.4)
	ok(Play.signed and int(fake.scores.get("depth", 0)) == 31 and int(fake.scores.get("stars", 0)) == 5,
		"after sign-in the depth record and the level stars reach the leaderboards", str(fake.scores))
	ok(results == [false, true] and fake.shown == 1, "and the leaderboard screen opens", str(results))
	# a worse score never lowers the stored best; a better one raises it
	Play.submit("depth", 12)
	Play.submit("depth", 44)
	await wait()
	ok(int(fake.scores.depth) == 44, "only the best score counts", str(fake.scores.depth))
	# no network: the game carries on
	fake.network_ok = false
	Play.submit("depth", 50)
	Play.show_leaderboards()
	await wait()
	ok(int(fake.scores.depth) == 44 and results[-1] == false, "no network: the score is not lost locally, the screen says unavailable")
	fake.network_ok = true
	# rating prompt rules
	var rec := {"mode": "endless", "record": true, "won": false, "stars": 0}
	var plain := {"mode": "endless", "record": false, "won": false, "stars": 0}
	var win3 := {"mode": "level", "record": false, "won": true, "stars": 3}
	var win2 := {"mode": "level", "record": false, "won": true, "stars": 2}
	G.ads.finished_total = 2
	ok(not Play.review_due(rec), "rating is not asked during the first runs")
	G.ads.finished_total = 6
	ok(Play.review_due(rec) and Play.review_due(win3) and not Play.review_due(plain) and not Play.review_due(win2),
		"asked only after a new record or a 3-star level")
	ok(Play.maybe_ask_review(rec) and fake.reviews == 1, "the Google Play review card is requested once")
	ok(not Play.maybe_ask_review(win3) and fake.reviews == 1, "not again within 30 days")
	G.meta.review_t = int(Time.get_unix_time_from_system()) - 31 * 86400
	ok(Play.maybe_ask_review(win3) and fake.reviews == 2, "after 30 days it may be asked again")
	G.meta.review_t = 0
	Play.maybe_ask_review(rec)
	G.meta.review_t = 0
	ok(not Play.maybe_ask_review(rec) and fake.reviews == 3, "never more than three times in total", "asked %d" % fake.reviews)
	Play.open_store_page()
	ok(fake.store_pages == 1, "'Rate the Game' in settings opens the store page")
	# Privacy Policy entry in settings points at the published HTTPS page
	var cfg := ConfigFile.new()
	cfg.load("res://config/monetization.cfg")
	var url := String(cfg.get_value("legal", "privacy_policy_url", ""))
	ok(url == "https://vladislavdrucok-tech.github.io/deepbounce/", "Settings → Privacy Policy opens the published page", url)
	var terms := String(cfg.get_value("legal", "terms_of_use_url", ""))
	ok(terms == "https://vladislavdrucok-tech.github.io/deepbounce/terms-of-use.html" and FileAccess.file_exists("res://site/terms-of-use.html"),
		"Settings → Terms of Use opens the published page", terms)
	var html := FileAccess.get_file_as_string("res://site/index.html")
	ok(html.contains("<html lang=\"en\">") and not html.contains("lang=\"uk\"") and html.contains("Deep Bounce") and html.contains("November 13, 2026"),
		"policy source is English only, with developer and date filled in")
	# safe area: visible system bars and a display cutout are kept clear of the layout
	var M := load("res://scripts/main.gd")
	var vp := Vector2(720, 1600)
	var win := Vector2(1080, 2400)
	var full := Rect2i(0, 0, 1080, 2400)
	var r1: Rect2 = M.safe_rect_for(vp, win, full, Vector4i(0, 0, 0, 0))
	ok(r1 == Rect2(0, 0, 720, 1600), "bars hidden: the whole screen is used", str(r1))
	var r2: Rect2 = M.safe_rect_for(vp, win, full, Vector4i(0, 96, 0, 63))
	ok(is_equal_approx(r2.position.y, 64.0) and is_equal_approx(r2.end.y, 1558.0), "status bar and navigation bar visible: layout starts below and ends above them", str(r2))
	var r3: Rect2 = M.safe_rect_for(Vector2(1600, 1000), Vector2(2400, 1500), Rect2i(120, 0, 2280, 1500), Vector4i(0, 0, 0, 0))
	ok(is_equal_approx(r3.position.x, 80.0), "landscape with a camera cutout on the side: the cutout is avoided", str(r3))
	var r4: Rect2 = M.safe_rect_for(vp, win, full, Vector4i(-1, -1, -1, -1))
	ok(r4 == Rect2(0, 0, 720, 1600), "insets not reported yet: Godot's safe area alone")
	# Android 15/16 regressions: orientation per screen class, no deprecated edge-to-edge calls in our activity
	ok(not M.large_for(Vector2(1080, 2400), Vector2(1080, 2400), 420.0), "phone 1080x2400 @420 dpi (411 dp) is not a large screen")
	ok(M.large_for(Vector2(1600, 2560), Vector2(1600, 2560), 320.0), "tablet 1600x2560 @320 dpi (800 dp) is a large screen")
	ok(M.large_for(Vector2(1080, 2400), Vector2(2208, 1840), 420.0), "unfolded foldable: the new window size counts even if the screen size lags")
	ok(not M.large_for(Vector2(1080, 2280), Vector2(1080, 2280), 440.0), "folded again (outer screen 393 dp): portrait again")
	ok(M.wanted_orientation(false) == DisplayServer.SCREEN_SENSOR_PORTRAIT and M.wanted_orientation(true) == DisplayServer.SCREEN_SENSOR,
		"phones ask for portrait, large screens (sw >= 600 dp) may rotate")
	var act := FileAccess.get_file_as_string("res://tools/android/template/GodotApp.java")
	var code := ""
	for line in act.split("\n"):
		if not line.strip_edges().begins_with("/") and not line.strip_edges().begins_with("*"):
			code += line + "\n"
	var banned := ["EdgeToEdge", "enableImmersiveMode", "enableEdgeToEdge", "setDecorFitsSystemWindows",
		"setStatusBarColor", "setNavigationBarColor", "setSystemUiVisibility", "FLAG_FULLSCREEN", "FLAG_LAYOUT_NO_LIMITS"]
	var found := []
	for b in banned:
		if code.contains(b):
			found.append(b)
	ok(found.is_empty() and code.contains("WindowInsetsControllerCompat") and code.contains("hide(WindowInsetsCompat.Type.systemBars())"),
		"template activity hides the bars without deprecated window APIs", str(found))
	var build := FileAccess.get_file_as_string("res://tools/android/build_release.sh")
	ok(build.contains("cp tools/android/template/GodotApp.java android/build/src/com/godot/game/GodotApp.java"),
		"the build copies the activity into the Gradle template")
	var ep := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok(ep.contains("screen/immersive_mode=false") and ep.contains("screen/edge_to_edge=false"),
		"Godot's own immersive / edge-to-edge switches stay off (they call setDecorFitsSystemWindows)")
	ok(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == DisplayServer.SCREEN_SENSOR,
		"manifest does not lock the orientation (resizable on large screens)")
	print("PLAY " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
