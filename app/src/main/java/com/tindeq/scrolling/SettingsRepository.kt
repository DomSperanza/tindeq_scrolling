package com.tindeq.scrolling

import android.content.Context

class SettingsRepository(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): GateSettings = GateSettings(
        minPullKg = prefs.getFloat(KEY_MIN_PULL, 2f),
        scrollPullKg = prefs.getFloat(KEY_SCROLL_PULL, 8f),
        gateEnabled = prefs.getBoolean(KEY_GATE_ENABLED, false),
        weightUnit = WeightUnit.fromKey(prefs.getString(KEY_WEIGHT_UNIT, WeightUnit.LBS.key)),
        handsFreeOnly = prefs.getBoolean(KEY_HANDS_FREE_ONLY, false),
        closeInstagramWhenBlocked = prefs.getBoolean(KEY_CLOSE_INSTAGRAM, true),
    )

    fun save(settings: GateSettings) {
        prefs.edit()
            .putFloat(KEY_MIN_PULL, settings.minPullKg)
            .putFloat(KEY_SCROLL_PULL, settings.scrollPullKg)
            .putBoolean(KEY_GATE_ENABLED, settings.gateEnabled)
            .putString(KEY_WEIGHT_UNIT, settings.weightUnit.key)
            .putBoolean(KEY_HANDS_FREE_ONLY, settings.handsFreeOnly)
            .putBoolean(KEY_CLOSE_INSTAGRAM, settings.closeInstagramWhenBlocked)
            .apply()
    }

    fun setWeightUnit(unit: WeightUnit) {
        prefs.edit().putString(KEY_WEIGHT_UNIT, unit.key).apply()
    }

    fun setGateEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_GATE_ENABLED, enabled).apply()
    }

    companion object {
        private const val PREFS = "tindeq_gate"
        private const val KEY_MIN_PULL = "min_pull_kg"
        private const val KEY_SCROLL_PULL = "scroll_pull_kg"
        private const val KEY_GATE_ENABLED = "gate_enabled"
        private const val KEY_WEIGHT_UNIT = "weight_unit"
        private const val KEY_HANDS_FREE_ONLY = "hands_free_only"
        private const val KEY_CLOSE_INSTAGRAM = "close_instagram_when_blocked"
    }
}
