package com.deepbounce.play

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.play.core.review.ReviewManagerFactory
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Deep Bounce: Google Play Games Services v2 leaderboards and the Google Play in-app review.
 *
 * Play Games is started only when the game asks for it (startGames), which the game does only when a Play
 * Games project ID is configured: without the com.google.android.gms.games.APP_ID manifest entry the SDK must
 * not be initialised. Sign-in is automatic in v2 (no button needed); signIn() is the manual retry.
 * The in-app review and the store page work without Play Games.
 */
class DeepBouncePlay(godot: Godot) : GodotPlugin(godot) {

    private val tag = "DeepBouncePlay"
    private val gamesStarted = AtomicBoolean(false)
    private val rcLeaderboard = 9104

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(
        SignalInfo("signed_in", java.lang.Boolean::class.java, String::class.java),      // (authenticated, error)
        SignalInfo("score_submitted", String::class.java, java.lang.Boolean::class.java, String::class.java),
        SignalInfo("leaderboard_closed", java.lang.Boolean::class.java, String::class.java), // (shown, error)
        SignalInfo("review_finished", java.lang.Boolean::class.java, String::class.java),    // (flow ran, error)
    )

    private fun emit(name: String, vararg args: Any) {
        runOnRenderThread { emitSignal(name, *args) }
    }

    private fun ui(block: (Activity) -> Unit) {
        val act = activity ?: return
        act.runOnUiThread {
            try {
                block(act)
            } catch (e: Throwable) {
                Log.e(tag, "UI call failed", e)
            }
        }
    }

    @UsedByGodot
    fun startGames() {
        ui { act ->
            try {
                if (gamesStarted.compareAndSet(false, true)) {
                    PlayGamesSdk.initialize(act.applicationContext)
                }
                PlayGames.getGamesSignInClient(act).isAuthenticated
                    .addOnCompleteListener { t ->
                        val ok = t.isSuccessful && t.result.isAuthenticated
                        emit("signed_in", ok, if (t.isSuccessful) "" else (t.exception?.message ?: "error"))
                    }
            } catch (e: Throwable) {
                gamesStarted.set(false)
                emit("signed_in", false, e.message ?: "Play Games not available")
            }
        }
    }

    @UsedByGodot
    fun signIn() {
        ui { act ->
            if (!gamesStarted.get()) {
                emit("signed_in", false, "not started")
                return@ui
            }
            PlayGames.getGamesSignInClient(act).signIn()
                .addOnCompleteListener { t ->
                    val ok = t.isSuccessful && t.result.isAuthenticated
                    emit("signed_in", ok, if (t.isSuccessful) "" else (t.exception?.message ?: "error"))
                }
        }
    }

    @UsedByGodot
    fun submitScore(leaderboardId: String, score: Int) {
        ui { act ->
            if (!gamesStarted.get() || leaderboardId.isEmpty()) {
                emit("score_submitted", leaderboardId, false, "not started")
                return@ui
            }
            PlayGames.getLeaderboardsClient(act).submitScoreImmediate(leaderboardId, score.toLong())
                .addOnCompleteListener { t ->
                    emit("score_submitted", leaderboardId, t.isSuccessful, if (t.isSuccessful) "" else (t.exception?.message ?: "error"))
                }
        }
    }

    /** leaderboardId empty: the list of all leaderboards. */
    @UsedByGodot
    fun showLeaderboard(leaderboardId: String) {
        ui { act ->
            if (!gamesStarted.get()) {
                emit("leaderboard_closed", false, "not started")
                return@ui
            }
            val client = PlayGames.getLeaderboardsClient(act)
            val task = if (leaderboardId.isEmpty()) client.allLeaderboardsIntent else client.getLeaderboardIntent(leaderboardId)
            task.addOnCompleteListener { t ->
                if (t.isSuccessful) {
                    try {
                        act.startActivityForResult(t.result, rcLeaderboard)
                        emit("leaderboard_closed", true, "")
                    } catch (e: Throwable) {
                        emit("leaderboard_closed", false, e.message ?: "error")
                    }
                } else {
                    emit("leaderboard_closed", false, t.exception?.message ?: "error")
                }
            }
        }
    }

    /**
     * Google Play's in-app review card. Google decides whether the card is really shown (quota per user) and
     * does not tell the app; "review_finished(true)" only means the flow ran without an error.
     */
    @UsedByGodot
    fun requestReview() {
        ui { act ->
            val manager = ReviewManagerFactory.create(act)
            manager.requestReviewFlow().addOnCompleteListener { req ->
                if (!req.isSuccessful) {
                    emit("review_finished", false, req.exception?.message ?: "error")
                    return@addOnCompleteListener
                }
                manager.launchReviewFlow(act, req.result).addOnCompleteListener { flow ->
                    emit("review_finished", flow.isSuccessful, if (flow.isSuccessful) "" else (flow.exception?.message ?: "error"))
                }
            }
        }
    }

    /** The game's page in Google Play (for the "Rate the game" button in settings). */
    @UsedByGodot
    fun openStorePage() {
        ui { act ->
            val pkg = act.packageName
            try {
                act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")).setPackage("com.android.vending"))
            } catch (e: ActivityNotFoundException) {
                act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$pkg")))
            }
        }
    }
}
