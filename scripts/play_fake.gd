extends Node
## Simulated Play Games and review for desktop runs and tests (never used on Android).

signal signed_in(ok: bool, error: String)
signal score_submitted(id: String, ok: bool, error: String)
signal leaderboard_closed(shown: bool, error: String)
signal review_finished(ok: bool, error: String)

var auth_ok := true            # false: the player is not signed in to Play Games
var network_ok := true
var scores := {}               # leaderboard id -> best score "on the server"
var submits := 0
var shown := 0                 # leaderboard screens opened
var reviews := 0               # review flows started
var store_pages := 0

func _later(f: Callable) -> void:
	get_tree().create_timer(0.05).timeout.connect(f)

func start_games() -> void:
	_later(func(): signed_in.emit(auth_ok, "" if auth_ok else "not signed in"))

func sign_in() -> void:
	_later(func(): signed_in.emit(auth_ok, "" if auth_ok else "sign-in cancelled"))

func submit_score(id: String, score: int) -> void:
	submits += 1
	_later(func():
		if not network_ok:
			score_submitted.emit(id, false, "network")
			return
		scores[id] = maxi(int(scores.get(id, 0)), score)
		score_submitted.emit(id, true, ""))

func show_leaderboard(_id: String) -> void:
	_later(func():
		if not network_ok:
			leaderboard_closed.emit(false, "network")
			return
		shown += 1
		leaderboard_closed.emit(true, ""))

func request_review() -> void:
	reviews += 1
	_later(func(): review_finished.emit(true, ""))

func open_store_page() -> void:
	store_pages += 1
