package com.tindeq.scrolling.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@SuppressLint("MissingPermission")
class TindeqBleManager(context: Context) {
    private val appContext = context.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter

    private var gatt: BluetoothGatt? = null
    private var writeChar: BluetoothGattCharacteristic? = null

    var onNotify: ((ByteArray) -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null

    fun isBluetoothReady(): Boolean = adapter?.isEnabled == true

    suspend fun scanForProgressor(timeoutMs: Long = 12_000): BluetoothDevice {
        val bluetooth = adapter ?: throw IllegalStateException("Bluetooth unavailable")
        val found = CompletableDeferred<BluetoothDevice>()
        val seen = mutableSetOf<String>()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                val name = device.name ?: result.scanRecord?.deviceName
                if (!TindeqProtocol.isProgressorName(name)) return
                if (!seen.add(device.address)) return
                found.complete(device)
            }

            override fun onScanFailed(errorCode: Int) {
                if (!found.isCompleted) {
                    found.completeExceptionally(IllegalStateException("BLE scan failed: $errorCode"))
                }
            }
        }

        bluetooth.bluetoothLeScanner.startScan(callback)
        try {
            return kotlinx.coroutines.withTimeout(timeoutMs) { found.await() }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            throw IllegalStateException("No Progressor found nearby", e)
        } finally {
            bluetooth.bluetoothLeScanner.stopScan(callback)
        }
    }

    suspend fun connect(address: String) {
        disconnect()
        val device = adapter?.getRemoteDevice(address)
            ?: throw IllegalStateException("Bluetooth unavailable")
        val notifyReady = CompletableDeferred<Unit>()

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> gatt.discoverServices()
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        if (!notifyReady.isCompleted) {
                            notifyReady.completeExceptionally(IllegalStateException("GATT disconnected"))
                        }
                        teardown(gatt)
                        onDisconnected?.invoke()
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    notifyReady.completeExceptionally(IllegalStateException("Service discovery failed"))
                    return
                }
                val service = gatt.getService(TindeqProtocol.SERVICE_UUID)
                val notify = service?.getCharacteristic(TindeqProtocol.NOTIFY_UUID)
                val write = service?.getCharacteristic(TindeqProtocol.WRITE_UUID)
                if (notify == null || write == null) {
                    notifyReady.completeExceptionally(IllegalStateException("Progressor service not found"))
                    return
                }
                writeChar = write
                gatt.setCharacteristicNotification(notify, true)
                val cccd = notify.getDescriptor(CLIENT_CONFIG_UUID)
                if (cccd == null) {
                    notifyReady.completeExceptionally(IllegalStateException("CCCD missing"))
                    return
                }
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(cccd)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                if (
                    descriptor.uuid == CLIENT_CONFIG_UUID &&
                    status == BluetoothGatt.GATT_SUCCESS &&
                    !notifyReady.isCompleted
                ) {
                    notifyReady.complete(Unit)
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                if (characteristic.uuid == TindeqProtocol.NOTIFY_UUID) {
                    onNotify?.invoke(value)
                }
            }

            @Deprecated("Deprecated in API 33")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                @Suppress("DEPRECATION")
                val value = characteristic.value ?: return
                if (characteristic.uuid == TindeqProtocol.NOTIFY_UUID) {
                    onNotify?.invoke(value)
                }
            }
        }

        gatt = device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
        notifyReady.await()
    }

    suspend fun write(data: ByteArray) = suspendCancellableCoroutine { cont ->
        val g = gatt ?: run {
            cont.resumeWithException(IllegalStateException("Not connected"))
            return@suspendCancellableCoroutine
        }
        val characteristic = writeChar ?: run {
            cont.resumeWithException(IllegalStateException("Write characteristic missing"))
            return@suspendCancellableCoroutine
        }
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = data
        if (!g.writeCharacteristic(characteristic)) {
            cont.resumeWithException(IllegalStateException("GATT write failed"))
        } else {
            cont.resume(Unit)
        }
    }

    fun disconnect() {
        gatt?.let { teardown(it) }
    }

    private fun teardown(gatt: BluetoothGatt) {
        runCatching { gatt.close() }
        if (this.gatt == gatt) {
            this.gatt = null
            writeChar = null
        }
    }

    companion object {
        private val CLIENT_CONFIG_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
