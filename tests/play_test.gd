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
	var html := FileAccess.get_file_as_string("res://site/index.html")
	ok(html.contains("<html lang=\"en\">") and not html.contains("lang=\"uk\"") and html.contains("Deep Bounce") and html.contains("November 13, 2026"),
		"policy source is English only, with developer and date filled in")
	print("PLAY " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
