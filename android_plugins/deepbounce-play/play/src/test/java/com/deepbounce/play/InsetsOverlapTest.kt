package com.deepbounce.play

import org.junit.Assert.assertArrayEquals
import org.junit.Test

/** Regression tests for the Android 15/16 safe-area fix: insets must be clipped to the game view. */
class InsetsOverlapTest {
    private fun ov(ins: IntArray, x: Int, y: Int, w: Int, h: Int, ww: Int = 1080, wh: Int = 2400) =
        DeepBouncePlay.overlap(ins[0], ins[1], ins[2], ins[3], x, y, w, h, ww, wh)

    @Test fun edgeToEdgeWindowKeepsFullInsets() {     // Android 15+: game view = whole window
        assertArrayEquals(intArrayOf(0, 96, 0, 132), ov(intArrayOf(0, 96, 0, 132), 0, 0, 1080, 2400))
    }

    @Test fun viewAlreadyBetweenBarsGetsNoInsets() {   // Android <= 14, bars visible, decor fits system windows
        assertArrayEquals(intArrayOf(0, 0, 0, 0), ov(intArrayOf(0, 96, 0, 132), 0, 96, 1080, 2400 - 96 - 132))
    }

    @Test fun cutoutBeyondStatusBarIsKept() {          // cutout 120 px, status bar 96 px already outside the view
        assertArrayEquals(intArrayOf(0, 24, 0, 0), ov(intArrayOf(0, 120, 0, 0), 0, 96, 1080, 2304))
    }

    @Test fun landscapeSideCutoutAndHiddenBars() {
        assertArrayEquals(intArrayOf(80, 0, 0, 0), ov(intArrayOf(80, 0, 0, 0), 0, 0, 2400, 1080, 2400, 1080))
    }

    @Test fun insetsNeverExceedTheView() {
        assertArrayEquals(intArrayOf(0, 300, 0, 0), ov(intArrayOf(0, 5000, 0, 0), 0, 0, 1080, 300, 1080, 300))
    }
}
