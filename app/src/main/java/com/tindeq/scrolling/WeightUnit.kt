package com.tindeq.scrolling

import android.content.Context
import kotlin.math.roundToInt

enum class WeightUnit(val key: String, val abbrev: String) {
    KG("kg", "kg"),
    LBS("lbs", "lbs"),
    ;

    companion object {
        fun fromKey(key: String?): WeightUnit =
            entries.find { it.key == key } ?: LBS
    }
}

object WeightUnits {
    const val LBS_PER_KG = 2.2046226218f
    const val MIN_GAP_KG = 0.5f
    const val SLIDER_STEP = 0.5f

    fun kgToDisplay(kg: Float, unit: WeightUnit): Float = when (unit) {
        WeightUnit.KG -> kg
        WeightUnit.LBS -> kg * LBS_PER_KG
    }

    fun displayToKg(display: Float, unit: WeightUnit): Float = when (unit) {
        WeightUnit.KG -> display
        WeightUnit.LBS -> display / LBS_PER_KG
    }

    fun snapToStep(value: Float): Float =
        (value / SLIDER_STEP).roundToInt() * SLIDER_STEP

    fun minSliderMax(unit: WeightUnit): Float = snapToStep(kgToDisplay(30f, unit))

    fun scrollSliderMin(unit: WeightUnit): Float = snapToStep(kgToDisplay(1f, unit))

    fun scrollSliderMax(unit: WeightUnit): Float = snapToStep(kgToDisplay(50f, unit))

    fun minGapDisplay(unit: WeightUnit): Float = kgToDisplay(MIN_GAP_KG, unit)

    fun format(context: Context, kg: Float, unit: WeightUnit): String {
        val display = kgToDisplay(kg, unit)
        val rounded = (display * 10f).roundToInt() / 10f
        return when (unit) {
            WeightUnit.KG -> context.getString(R.string.kg_format, rounded)
            WeightUnit.LBS -> context.getString(R.string.lbs_format, rounded)
        }
    }
}
