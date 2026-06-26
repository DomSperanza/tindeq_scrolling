package com.tindeq.scrolling

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class GateMode {
    IDLE,
    HOLDING,
    WARNING,
    BLOCKED,
}

enum class ConnectionPhase {
    IDLE,
    SCANNING,
    CONNECTING,
    CONNECTED,
    FAILED,
}

data class ForceSnapshot(
    val weightKg: Float = 0f,
    val mode: GateMode = GateMode.IDLE,
    val connected: Boolean = false,
    val instagramActive: Boolean = false,
    val gateEnabled: Boolean = false,
    val scrollArmed: Boolean = true,
    val graceRemainingMs: Long = 0L,
)

object ForceGateController {
    private val _state = MutableStateFlow(ForceSnapshot())
    val state: StateFlow<ForceSnapshot> = _state.asStateFlow()

    private val _connection = MutableStateFlow(ConnectionPhase.IDLE)
    val connection: StateFlow<ConnectionPhase> = _connection.asStateFlow()

    private val _connectionError = MutableStateFlow<String?>(null)
    val connectionError: StateFlow<String?> = _connectionError.asStateFlow()

    var settings: GateSettings = GateSettings()
        private set

    fun setConnectionPhase(phase: ConnectionPhase, errorMessage: String? = null) {
        _connection.value = phase
        _connectionError.value = errorMessage
    }

    private var scrollArmed = true
    private var lastScrollAt = 0L
    private var belowMinSince: Long? = null

    fun updateSettings(newSettings: GateSettings) {
        settings = newSettings
        publish()
    }

    fun setConnected(connected: Boolean) {
        _state.value = _state.value.copy(connected = connected)
        if (connected) {
            _connection.value = ConnectionPhase.CONNECTED
            _connectionError.value = null
        } else {
            scrollArmed = true
            belowMinSince = null
            if (_connection.value == ConnectionPhase.CONNECTED) {
                _connection.value = ConnectionPhase.IDLE
            }
            publish(weight = 0f, mode = GateMode.IDLE, graceRemainingMs = 0L)
        }
    }

    fun setInstagramActive(active: Boolean) {
        _state.value = _state.value.copy(instagramActive = active)
        if (!active) belowMinSince = null
    }

    fun onWeight(weightKg: Float): ScrollTrigger? {
        if (!settings.gateEnabled || !_state.value.connected) {
            belowMinSince = null
            publish(weight = weightKg, mode = GateMode.IDLE, graceRemainingMs = 0L)
            return null
        }

        val now = System.currentTimeMillis()
        val mode: GateMode
        val graceRemainingMs: Long

        if (weightKg >= settings.minPullKg) {
            belowMinSince = null
            mode = GateMode.HOLDING
            graceRemainingMs = 0L
        } else {
            val since = belowMinSince ?: now.also { belowMinSince = it }
            val elapsed = now - since
            graceRemainingMs = (GRACE_MS - elapsed).coerceAtLeast(0L)
            mode = if (elapsed >= GRACE_MS) GateMode.BLOCKED else GateMode.WARNING
        }

        var trigger: ScrollTrigger? = null
        if (
            mode == GateMode.HOLDING &&
            scrollArmed &&
            weightKg >= settings.scrollPullKg &&
            System.currentTimeMillis() - lastScrollAt > SCROLL_COOLDOWN_MS
        ) {
            scrollArmed = false
            lastScrollAt = System.currentTimeMillis()
            trigger = ScrollTrigger(weightKg)
        }

        if (weightKg < settings.scrollPullKg * SCROLL_REARM_RATIO) {
            scrollArmed = true
        }

        publish(weight = weightKg, mode = mode, graceRemainingMs = graceRemainingMs)
        return trigger
    }

    private fun publish(
        weight: Float = _state.value.weightKg,
        mode: GateMode = _state.value.mode,
        graceRemainingMs: Long = _state.value.graceRemainingMs,
    ) {
        _state.value = _state.value.copy(
            weightKg = weight,
            mode = mode,
            gateEnabled = settings.gateEnabled,
            scrollArmed = scrollArmed,
            graceRemainingMs = graceRemainingMs,
        )
    }

    data class ScrollTrigger(val weightKg: Float)

    private const val SCROLL_COOLDOWN_MS = 600L
    private const val SCROLL_REARM_RATIO = 0.85f
    const val GRACE_MS = 3_000L
}
