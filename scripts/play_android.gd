extends Node
## Play Games + review backend on Android: the DeepBouncePlay plugin (android_plugins/deepbounce-play).

signal signed_in(ok: bool, error: String)
signal score_submitted(id: String, ok: bool, error: String)
signal leaderboard_closed(shown: bool, error: String)
signal review_finished(ok: bool, error: String)

var p: Object

func _ready() -> void:
	p = Engine.get_singleton("DeepBouncePlay")
	p.connect("signed_in", func(a, e): signed_in.emit(bool(a), String(e)))
	p.connect("score_submitted", func(i, a, e): score_submitted.emit(String(i), bool(a), String(e)))
	p.connect("leaderboard_closed", func(a, e): leaderboard_closed.emit(bool(a), String(e)))
	p.connect("review_finished", func(a, e): review_finished.emit(bool(a), String(e)))

func start_games() -> void:
	p.startGames()

func sign_in() -> void:
	p.signIn()

func submit_score(id: String, score: int) -> void:
	p.submitScore(id, score)

func show_leaderboard(id: String) -> void:
	p.showLeaderboard(id)

func request_review() -> void:
	p.requestReview()

func open_store_page() -> void:
	p.openStorePage()
