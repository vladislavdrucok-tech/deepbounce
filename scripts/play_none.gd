extends Node
## Android build without the DeepBouncePlay plugin: leaderboards unavailable, no review card.

signal signed_in(ok: bool, error: String)
signal score_submitted(id: String, ok: bool, error: String)
signal leaderboard_closed(shown: bool, error: String)
signal review_finished(ok: bool, error: String)

func start_games() -> void:
	(func(): signed_in.emit(false, "DeepBouncePlay plugin missing")).call_deferred()

func sign_in() -> void:
	start_games()

func submit_score(id: String, _score: int) -> void:
	(func(): score_submitted.emit(id, false, "no plugin")).call_deferred()

func show_leaderboard(_id: String) -> void:
	(func(): leaderboard_closed.emit(false, "no plugin")).call_deferred()

func request_review() -> void:
	(func(): review_finished.emit(false, "no plugin")).call_deferred()

func open_store_page() -> void:
	OS.shell_open("https://play.google.com/store/apps/details?id=com.deepbounce.game")
