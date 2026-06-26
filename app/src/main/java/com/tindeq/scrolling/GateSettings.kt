package com.tindeq.scrolling

data class GateSettings(
    val minPullKg: Float = 2f,
    val scrollPullKg: Float = 8f,
    val gateEnabled: Boolean = false,
    val weightUnit: WeightUnit = WeightUnit.LBS,
    val handsFreeOnly: Boolean = false,
    val closeInstagramWhenBlocked: Boolean = true,
)
