extends Node
## Player ranking and store rating (autoload "Play"):
##  * Google Play Games Services leaderboards — "Depth record" (Endless Mode) and "Level stars" (out of 150).
##    Scores are sent after every finished run / won level and again at start (so offline play catches up);
##    Google keeps only the best score per player. Nothing is sent unless a Play Games project is configured
##    in config/monetization.cfg [play_games] and the player is signed in to Play Games.
##  * Google Play in-app review — asked rarely and only at a good moment, see [review] in the same file.
##  * "Rate the game" in settings opens the game's Google Play page.

signal changed
signal leaderboards_result(shown: bool)

const AndroidPlay := preload("res://scripts/play_android.gd")
const FakePlay := preload("res://scripts/play_fake.gd")
const NoPlay := preload("res://scripts/play_none.gd")

var backend: Node
var cfg := ConfigFile.new()
var started := false
var signed := false
var _want_show := false
var _pending := {}        # leaderboard id -> score waiting for sign-in

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg.load("res://config/monetization.cfg")
	if OS.get_name() == "Android":
		use_backend(AndroidPlay.new() if Engine.has_singleton("DeepBouncePlay") else NoPlay.new())
		G.diag("[play] DeepBouncePlay plugin: %s, Play Games %s" % ["found" if Engine.has_singleton("DeepBouncePlay") else "MISSING",
			"configured" if configured() else "not configured"])
	else:
		use_backend(FakePlay.new())

func use_backend(b: Node) -> void:
	if backend:
		backend.queue_free()
	backend = b
	add_child(b)
	b.signed_in.connect(_on_signed_in)
	b.score_submitted.connect(_on_score)
	b.leaderboard_closed.connect(_on_leaderboard)
	b.review_finished.connect(func(ok, err): G.diag("[play] review flow %s %s" % ["ran" if ok else "failed", err]))
	started = false
	signed = false
	_want_show = false
	_pending = {}

func board(kind: String) -> String:
	return String(cfg.get_value("play_games", "leaderboard_" + kind, ""))

func configured() -> bool:
	## On desktop the simulated service is always "configured" so the flows can be tested.
	if OS.get_name() != "Android":
		return true
	return String(cfg.get_value("play_games", "app_id", "")) != ""

# ---------------------------------------------------------------- leaderboards

func start() -> void:
	if started or not configured():
		return
	started = true
	backend.start_games()

func _on_signed_in(ok: bool, error: String) -> void:
	signed = ok
	if OS.get_name() == "Android":
		G.diag("[play] signed in: %s %s" % [ok, error])
	if ok:
		# catch up: the bests reached so far (also those made offline)
		submit("depth", int(G.meta.best))
		submit("stars", G.level_stars_total())
		for id in _pending.keys():
			backend.submit_score(id, int(_pending[id]))
		_pending.clear()
	if _want_show:
		_want_show = false
		if ok:
			backend.show_leaderboard("")
		else:
			leaderboards_result.emit(false)
	changed.emit()

func submit(kind: String, score: int) -> void:
	if not configured() or score <= 0:
		return
	var id := board(kind)
	if OS.get_name() != "Android" and id == "":
		id = kind              # simulated boards are named by kind
	if id == "":
		return
	if signed:
		backend.submit_score(id, score)
	else:
		_pending[id] = maxi(int(_pending.get(id, 0)), score)

func _on_score(id: String, ok: bool, error: String) -> void:
	if not ok and OS.get_name() == "Android":
		G.diag("[play] score not sent to %s: %s" % [id, error])

func show_leaderboards() -> void:
	## The Google Play Games screen with both leaderboards. Emits leaderboards_result(false) when it cannot
	## be opened (not configured, not signed in, no network).
	if not configured():
		leaderboards_result.emit(false)
		return
	if not started:
		_want_show = true
		start()
		return
	if signed:
		backend.show_leaderboard("")
	else:
		_want_show = true
		backend.sign_in()

func _on_leaderboard(shown: bool, error: String) -> void:
	if not shown and OS.get_name() == "Android":
		G.diag("[play] leaderboards not shown: %s" % error)
	leaderboards_result.emit(shown)

# ---------------------------------------------------------------- rating the game

func review_due(result: Dictionary) -> bool:
	## A good moment only: a new depth record or a level won with 3 stars, enough play behind, not too often.
	if result.is_empty():
		return false
	var good := (String(result.get("mode", "")) == "endless" and bool(result.get("record", false))) \
		or (bool(result.get("won", false)) and int(result.get("stars", 0)) == 3)
	if not good:
		return false
	if int(G.ads.finished_total) < int(cfg.get_value("review", "min_finished_runs", 6)):
		return false
	if int(G.meta.get("review_n", 0)) >= int(cfg.get_value("review", "max_prompts", 3)):
		return false
	var days := (Time.get_unix_time_from_system() - float(G.meta.get("review_t", 0))) / 86400.0
	return days >= float(cfg.get_value("review", "min_days_between", 30))

func maybe_ask_review(result: Dictionary) -> bool:
	if not review_due(result):
		return false
	G.meta["review_n"] = int(G.meta.get("review_n", 0)) + 1
	G.meta["review_t"] = int(Time.get_unix_time_from_system())
	G.save_game()
	backend.request_review()
	return true

func open_store_page() -> void:
	backend.open_store_page()
