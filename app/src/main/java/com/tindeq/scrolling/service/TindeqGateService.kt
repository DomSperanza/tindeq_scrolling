package com.tindeq.scrolling.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.tindeq.scrolling.ConnectionPhase
import com.tindeq.scrolling.ForceGateController
import com.tindeq.scrolling.MainActivity
import com.tindeq.scrolling.R
import com.tindeq.scrolling.TindeqScrollingApp
import com.tindeq.scrolling.accessibility.InstagramAccessibilityService
import com.tindeq.scrolling.ble.TindeqBleManager
import com.tindeq.scrolling.ble.TindeqClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class TindeqGateService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var connectJob: Job? = null
    private lateinit var ble: TindeqBleManager
    private var client: TindeqClient? = null
    private var deviceAddress: String? = null

    override fun onCreate() {
        super.onCreate()
        ble = TindeqBleManager(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                deviceAddress = intent.getStringExtra(EXTRA_DEVICE_ADDRESS)
                startForegroundCompat()
                connectToDevice()
            }
            ACTION_DISCONNECT -> {
                ForceGateController.setConnectionPhase(ConnectionPhase.IDLE)
                disconnect()
            }
            ACTION_REFRESH_SETTINGS -> {
                val app = application as TindeqScrollingApp
                ForceGateController.updateSettings(app.settingsRepository.load())
            }
            ACTION_TARE -> scope.launch {
                runCatching { client?.tare() }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        disconnect()
        scope.cancel()
        super.onDestroy()
    }

    private fun connectToDevice() {
        connectJob?.cancel()
        connectJob = scope.launch {
            try {
                if (!ble.isBluetoothReady()) {
                    ForceGateController.setConnectionPhase(
                        ConnectionPhase.FAILED,
                        getString(R.string.error_bluetooth_off),
                    )
                    stopSelf()
                    return@launch
                }
                val address = deviceAddress ?: run {
                    ForceGateController.setConnectionPhase(ConnectionPhase.SCANNING)
                    ble.scanForProgressor().address
                }
                deviceAddress = address
                val tindeq = TindeqClient(ble)
                client = tindeq
                tindeq.onWeight = { weight, _ ->
                    val trigger = ForceGateController.onWeight(weight)
                    if (trigger != null) {
                        InstagramAccessibilityService.instance?.performReelSwipe()
                    }
                }
                tindeq.onDisconnected = {
                    ForceGateController.setConnected(false)
                    stopSelf()
                }
                ForceGateController.setConnectionPhase(ConnectionPhase.CONNECTING)
                tindeq.connect(address)
                ForceGateController.setConnected(true)
            } catch (e: Exception) {
                ForceGateController.setConnected(false)
                ForceGateController.setConnectionPhase(
                    ConnectionPhase.FAILED,
                    e.message ?: getString(R.string.error_connect_failed),
                )
                deviceAddress = null
                stopSelf()
            }
        }
    }

    private fun disconnect() {
        connectJob?.cancel()
        scope.launch(Dispatchers.IO) {
            runCatching { client?.disconnect() }
            client = null
            ForceGateController.setConnected(false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "tindeq_gate"
        const val ACTION_CONNECT = "com.tindeq.scrolling.CONNECT"
        const val ACTION_DISCONNECT = "com.tindeq.scrolling.DISCONNECT"
        const val ACTION_REFRESH_SETTINGS = "com.tindeq.scrolling.REFRESH_SETTINGS"
        const val ACTION_TARE = "com.tindeq.scrolling.TARE"
        const val EXTRA_DEVICE_ADDRESS = "device_address"
        private const val NOTIFICATION_ID = 1
    }
}
