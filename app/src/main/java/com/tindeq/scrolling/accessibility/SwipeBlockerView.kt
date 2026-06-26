package com.tindeq.scrolling.accessibility

import android.content.Context
import android.view.MotionEvent
import android.widget.FrameLayout
import kotlin.math.abs
import kotlin.math.hypot

class SwipeBlockerView(
    context: Context,
    private val onForwardTap: (x: Float, y: Float) -> Unit,
) : FrameLayout(context) {
    private var downX = 0f
    private var downY = 0f
    private var blocking = false
    private val swipeThresholdPx = 56f * resources.displayMetrics.density
    private val tapSlopPx = 18f * resources.displayMetrics.density

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                blocking = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = abs(event.x - downX)
                val dy = abs(event.y - downY)
                if (dy > swipeThresholdPx && dy > dx * 1.15f) {
                    blocking = true
                }
                return blocking
            }
            MotionEvent.ACTION_UP -> {
                val wasBlocking = blocking
                val isTap = hypot(event.x - downX, event.y - downY) <= tapSlopPx
                blocking = false
                if (!wasBlocking && isTap) {
                    onForwardTap(event.rawX, event.rawY)
                }
                return wasBlocking
            }
            MotionEvent.ACTION_CANCEL -> {
                blocking = false
                return false
            }
        }
        return false
    }
}
