package com.deepbounce.play

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.play.core.review.ReviewManagerFactory
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Deep Bounce: Google Play Games Services v2 leaderboards and the Google Play in-app review.
 *
 * Play Games is started only when the game asks for it (startGames), which the game does only when a Play
 * Games project ID is configured: without the com.google.android.gms.games.APP_ID manifest entry the SDK must
 * not be initialised. Sign-in is automatic in v2 (no button needed); signIn() is the manual retry.
 * The in-app review and the store page work without Play Games.
 *
 * Also the game's full-screen handling (Android 15/16 edge-to-edge): the app always draws edge to edge, the
 * system bars are hidden with WindowInsetsControllerCompat (no deprecated Window#setDecorFitsSystemWindows,
 * setStatusBarColor or setNavigationBarColor), and the real system-bar + display-cutout insets are reported to
 * the game so its layout keeps every button clear of them.
 */
class DeepBouncePlay(godot: Godot) : GodotPlugin(godot) {

    companion object {
        /** Window insets (l, t, r, b) clipped to a view at (x, y) of size w×h inside a window of size ww×wh. */
        @JvmStatic
        fun overlap(l: Int, t: Int, r: Int, b: Int, x: Int, y: Int, w: Int, h: Int, ww: Int, wh: Int): IntArray =
            intArrayOf(
                (l - x).coerceIn(0, w),
                (t - y).coerceIn(0, h),
                (r - (ww - x - w)).coerceIn(0, w),
                (b - (wh - y - h)).coerceIn(0, h),
            )
    }

    private val tag = "DeepBouncePlay"
    private val gamesStarted = AtomicBoolean(false)
    private val rcLeaderboard = 9104
    private val immersive = AtomicBoolean(false)
    private val lastInsets = AtomicReference(intArrayOf(-1, -1, -1, -1))

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(
        SignalInfo("signed_in", java.lang.Boolean::class.java, String::class.java),      // (authenticated, error)
        SignalInfo("score_submitted", String::class.java, java.lang.Boolean::class.java, String::class.java),
        SignalInfo("leaderboard_closed", java.lang.Boolean::class.java, String::class.java), // (shown, error)
        SignalInfo("review_finished", java.lang.Boolean::class.java, String::class.java),    // (flow ran, error)
        // (left, top, right, bottom) in window pixels: visible system bars + display cutout
        SignalInfo("insets_changed", Integer::class.java, Integer::class.java, Integer::class.java, Integer::class.java),
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

    // ---------------------------------------------------------------- full screen and insets

    /** Hide (true) or show (false) the status and navigation bars; a swipe from the edge shows them briefly. */
    @UsedByGodot
    fun setImmersive(enabled: Boolean) {
        immersive.set(enabled)
        ui { act -> applyImmersive(act) }
    }

    private fun applyImmersive(act: Activity) {
        val window = act.window ?: return
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (immersive.get()) {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
        readInsets(act)
    }

    /** Reads the current insets on the UI thread; emits insets_changed when they differ from the last report. */
    @UsedByGodot
    fun refreshInsets() {
        ui { act -> readInsets(act) }
    }

    private fun readInsets(act: Activity) {
        val decor = act.window?.decorView ?: return
        val root = ViewCompat.getRootWindowInsets(decor) ?: return
        val i = root.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        // The insets are relative to the whole window. Below Android 15 a window that is not edge to edge lays the
        // game view out between visible bars already, so only the part of each inset that overlaps the game view
        // itself is reported (otherwise the bars would be subtracted twice).
        val view: View = godot.renderView?.view ?: act.findViewById(android.R.id.content) ?: decor
        if (view.width <= 0 || view.height <= 0) return
        val loc = IntArray(2)
        view.getLocationInWindow(loc)
        val now = overlap(i.left, i.top, i.right, i.bottom, loc[0], loc[1], view.width, view.height, decor.width, decor.height)
        if (!now.contentEquals(lastInsets.getAndSet(now))) {
            emit("insets_changed", now[0], now[1], now[2], now[3])
        }
    }

    override fun onMainResume() {
        // back from an ad, the Google Play window or another app: bars hidden again, insets re-read
        if (immersive.get()) ui { act -> applyImmersive(act) } else ui { act -> readInsets(act) }
    }

    // ---------------------------------------------------------------- Play Games

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
