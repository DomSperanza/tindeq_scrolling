package com.tindeq.scrolling.ble

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class TindeqClient(
    private val ble: TindeqBleManager,
) {
    private val mutex = Mutex()
    private var tareValue = 0f

    var onWeight: ((weight: Float, seconds: Double) -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null

    init {
        ble.onNotify = { data ->
            val (kind, samples) = TindeqProtocol.parseNotifyPayload(data)
            if (kind == TindeqProtocol.RESPONSE_WEIGHT) {
                for (sample in samples) {
                    val weight = sample.weight - tareValue
                    onWeight?.invoke(weight, sample.useconds / 1_000_000.0)
                }
            }
        }
        ble.onDisconnected = {
            onDisconnected?.invoke()
        }
    }

    suspend fun connect(deviceAddress: String) {
        ble.connect(deviceAddress)
        send(TindeqProtocol.CMD_START_WEIGHT_MEAS)
    }

    suspend fun disconnect(sleep: Boolean = true) {
        if (sleep) {
            runCatching { send(TindeqProtocol.CMD_SLEEP) }
        }
        ble.disconnect()
    }

    suspend fun tare() {
        send(TindeqProtocol.CMD_TARE_SCALE)
        tareValue = 0f
    }

    private suspend fun send(cmd: Int) {
        mutex.withLock {
            ble.write(TindeqProtocol.packCmd(cmd))
            delay(100)
        }
    }
}
