package com.tindeq.scrolling.ble

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

object TindeqProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("7e4e1701-1ea6-40c9-9dcc-13d34ffead57")
    val WRITE_UUID: UUID = UUID.fromString("7e4e1703-1ea6-40c9-9dcc-13d34ffead57")
    val NOTIFY_UUID: UUID = UUID.fromString("7e4e1702-1ea6-40c9-9dcc-13d34ffead57")

    val NAME_PREFIXES = listOf("Progressor", "Tindeq", "TINDEQ")

    const val RESPONSE_CMD = 0
    const val RESPONSE_WEIGHT = 1
    const val RESPONSE_LOW_PWR = 4

    const val CMD_TARE_SCALE = 0x64
    const val CMD_START_WEIGHT_MEAS = 0x65
    const val CMD_STOP_WEIGHT_MEAS = 0x66
    const val CMD_SLEEP = 0x6e

    fun packCmd(cmd: Int): ByteArray = byteArrayOf(cmd.toByte(), 0)

    data class WeightSample(val weight: Float, val useconds: Long)

    fun parseNotifyPayload(data: ByteArray): Pair<Int, List<WeightSample>> {
        if (data.size < 2) return 0 to emptyList()
        val kind = data[0].toInt() and 0xff
        val payloadSize = data[1].toInt() and 0xff
        val samples = mutableListOf<WeightSample>()
        val end = minOf(2 + payloadSize, data.size)
        var offset = 2
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        while (offset + 8 <= end) {
            buffer.position(offset)
            val weight = buffer.float
            val useconds = buffer.int.toLong() and 0xffffffffL
            samples.add(WeightSample(weight, useconds))
            offset += 8
        }
        return kind to samples
    }

    fun isProgressorName(name: String?): Boolean {
        if (name.isNullOrBlank()) return false
        return NAME_PREFIXES.any { name.startsWith(it) }
    }
}
