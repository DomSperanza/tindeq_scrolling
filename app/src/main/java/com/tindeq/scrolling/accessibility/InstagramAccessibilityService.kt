package com.tindeq.scrolling.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import com.tindeq.scrolling.ForceGateController
import com.tindeq.scrolling.ForceSnapshot
import com.tindeq.scrolling.GateMode
import com.tindeq.scrolling.R
import com.tindeq.scrolling.WeightUnits
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.ceil

class InstagramAccessibilityService : AccessibilityService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var overlayJob: Job? = null
    private var windowManager: WindowManager? = null
    private var overlay: FrameLayout? = null
    private var overlayLabel: TextView? = null
    private var overlayBlocking = false
    private var hud: TextView? = null
    private var swipeBlocker: SwipeBlockerView? = null
    private var instagramForeground = false
    private var lastKickAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayJob = scope.launch {
            ForceGateController.state.collectLatest { snapshot ->
                if (!snapshot.gateEnabled || !snapshot.connected || !instagramForeground) {
                    hideHud()
                    hideOverlay()
                    hideSwipeBlocker()
                    return@collectLatest
                }
                val handsFree = ForceGateController.settings.handsFreeOnly
                val blockSwipesOnly = handsFree &&
                    (snapshot.mode == GateMode.HOLDING || snapshot.mode == GateMode.WARNING)
                updateSwipeBlocker(blockSwipesOnly)
                when (snapshot.mode) {
                    GateMode.WARNING -> showOverlay(
                        currentKg = snapshot.weightKg,
                        graceSeconds = graceSeconds(snapshot.graceRemainingMs),
                        blocking = false,
                    )
                    GateMode.BLOCKED -> {
                        if (ForceGateController.settings.closeInstagramWhenBlocked) {
                            hideOverlay()
                            hideHud()
                            hideSwipeBlocker()
                            kickInstagramHome()
                        } else {
                            showOverlay(
                                currentKg = snapshot.weightKg,
                                graceSeconds = 0,
                                blocking = true,
                            )
                        }
                    }
                    else -> hideOverlay()
                }
                val kicked = snapshot.mode == GateMode.BLOCKED &&
                    ForceGateController.settings.closeInstagramWhenBlocked
                if (!kicked) {
                    updateHud(snapshot)
                }
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED,
            -> updateInstagramForeground()
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        overlayJob?.cancel()
        scope.cancel()
        hideOverlay()
        hideHud()
        hideSwipeBlocker()
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun performReelSwipe() {
        if (!instagramForeground || !ForceGateController.settings.gateEnabled) return
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels.toFloat()
        val height = metrics.heightPixels.toFloat()
        val startY = height * 0.78f
        val endY = height * 0.22f
        val x = width * 0.5f

        val path = Path().apply {
            moveTo(x, startY)
            lineTo(x, endY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 280)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    private fun forwardTap(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    private fun kickInstagramHome() {
        if (!instagramForeground) return
        val now = System.currentTimeMillis()
        if (now - lastKickAt < 1200L) return
        lastKickAt = now
        performGlobalAction(GLOBAL_ACTION_HOME)
        Toast.makeText(this, R.string.instagram_closed_pull, Toast.LENGTH_SHORT).show()
    }

    private fun updateInstagramForeground() {
        val active = rootInActiveWindow?.packageName?.toString() == INSTAGRAM_PACKAGE
        if (active != instagramForeground) {
            instagramForeground = active
            ForceGateController.setInstagramActive(active)
            if (!active) {
                hideOverlay()
                hideHud()
                hideSwipeBlocker()
            }
        }
    }

    private fun updateSwipeBlocker(show: Boolean) {
        if (!show) {
            hideSwipeBlocker()
            return
        }
        if (swipeBlocker != null) return
        val wm = windowManager ?: return
        val blocker = SwipeBlockerView(this) { x, y -> forwardTap(x, y) }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        runCatching { wm.addView(blocker, params) }
        swipeBlocker = blocker
    }

    private fun hideSwipeBlocker() {
        val wm = windowManager ?: return
        val view = swipeBlocker ?: return
        runCatching { wm.removeView(view) }
        swipeBlocker = null
    }

    private fun updateHud(snapshot: ForceSnapshot) {
        val unit = ForceGateController.settings.weightUnit
        val current = WeightUnits.format(this, snapshot.weightKg, unit)
        val needed = WeightUnits.format(this, ForceGateController.settings.minPullKg, unit)
        val text = getString(R.string.hud_text, current, needed)
        val accent = when (snapshot.mode) {
            GateMode.HOLDING -> Color.parseColor("#FF69F0AE")
            GateMode.WARNING -> Color.parseColor("#FFFFD740")
            GateMode.BLOCKED -> Color.parseColor("#FFFF5252")
            else -> Color.WHITE
        }

        hud?.let {
            if (it.text != text) it.text = text
            if (it.currentTextColor != accent) it.setTextColor(accent)
            return
        }

        val wm = windowManager ?: return
        val density = resources.displayMetrics.density
        val padH = (12 * density).toInt()
        val padV = (6 * density).toInt()
        val view = TextView(this).apply {
            this.text = text
            setTextColor(accent)
            textSize = 12f
            setPadding(padH, padV, padH, padV)
            background = GradientDrawable().apply {
                cornerRadius = 100f * density
                setColor(Color.parseColor("#B3000000"))
            }
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (12 * density).toInt()
            y = statusBarHeight() + (8 * density).toInt()
        }
        runCatching { wm.addView(view, params) }
        hud = view
    }

    private fun hideHud() {
        val wm = windowManager ?: return
        val view = hud ?: return
        runCatching { wm.removeView(view) }
        hud = null
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
    }

    private fun showOverlay(currentKg: Float, graceSeconds: Int, blocking: Boolean) {
        val unit = ForceGateController.settings.weightUnit
        val min = ForceGateController.settings.minPullKg
        val current = WeightUnits.format(this, currentKg, unit)
        val needed = WeightUnits.format(this, min, unit)
        val text = if (blocking) {
            getString(R.string.overlay_blocked_detail, current, needed)
        } else {
            getString(R.string.overlay_warning_detail, graceSeconds, current, needed)
        }

        if (overlay != null && overlayBlocking == blocking) {
            overlayLabel?.text = text
            return
        }

        hideOverlay()
        val wm = windowManager ?: return
        val container = FrameLayout(this).apply {
            setBackgroundColor(
                if (blocking) Color.parseColor("#CC000000") else Color.parseColor("#99000000"),
            )
        }
        val label = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = if (blocking) 20f else 18f
            gravity = Gravity.CENTER
            this.text = text
            setPadding(48, 48, 48, 48)
        }
        container.addView(
            label,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )

        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (!blocking) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
        }

        wm.addView(container, params)
        overlay = container
        overlayLabel = label
        overlayBlocking = blocking
    }

    private fun hideOverlay() {
        val wm = windowManager ?: return
        val view = overlay ?: return
        runCatching { wm.removeView(view) }
        overlay = null
        overlayLabel = null
        overlayBlocking = false
    }

    private fun graceSeconds(remainingMs: Long): Int =
        ceil(remainingMs / 1000.0).toInt().coerceAtLeast(1)

    companion object {
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        var instance: InstagramAccessibilityService? = null
            private set
    }
}
