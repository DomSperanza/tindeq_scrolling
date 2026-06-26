package com.tindeq.scrolling

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.tindeq.scrolling.accessibility.InstagramAccessibilityService
import com.tindeq.scrolling.databinding.ActivityMainBinding
import com.tindeq.scrolling.service.TindeqGateService
import kotlinx.coroutines.launch
import kotlin.math.ceil

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var settingsRepository: SettingsRepository
    private var currentUnit: WeightUnit = WeightUnit.LBS
    private var suppressUnitToggle = false

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        if (results.values.all { it }) {
            startBleService()
        } else {
            Toast.makeText(this, R.string.permissions_denied, Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        settingsRepository = (application as TindeqScrollingApp).settingsRepository
        val settings = settingsRepository.load()
        currentUnit = settings.weightUnit
        binding.gateSwitch.isChecked = settings.gateEnabled
        binding.handsFreeSwitch.isChecked = settings.handsFreeOnly
        binding.closeInstagramSwitch.isChecked = settings.closeInstagramWhenBlocked
        applyUnitToggleSelection()
        applySliderRanges()
        loadSlidersFromSettings(settings)

        binding.unitToggle.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked || suppressUnitToggle) return@addOnButtonCheckedListener
            val unit = if (checkedId == R.id.unitLbs) WeightUnit.LBS else WeightUnit.KG
            if (unit == currentUnit) return@addOnButtonCheckedListener
            persistSettings()
            currentUnit = unit
            settingsRepository.setWeightUnit(unit)
            applySliderRanges()
            loadSlidersFromSettings(settingsRepository.load())
            ForceGateController.updateSettings(settingsRepository.load())
        }

        binding.minPullSlider.addOnChangeListener { _, value, _ ->
            binding.minPullValue.text = formatDisplay(value)
            persistSettings()
        }
        binding.scrollPullSlider.addOnChangeListener { _, value, _ ->
            binding.scrollPullValue.text = formatDisplay(value)
            persistSettings()
        }
        binding.gateSwitch.setOnCheckedChangeListener { _, isChecked ->
            settingsRepository.setGateEnabled(isChecked)
            ForceGateController.updateSettings(settingsRepository.load())
            refreshBleSettings()
            refreshUi()
        }
        binding.handsFreeSwitch.setOnCheckedChangeListener { _, _ ->
            persistSettings()
        }
        binding.closeInstagramSwitch.setOnCheckedChangeListener { _, _ ->
            persistSettings()
        }

        binding.connectButton.setOnClickListener {
            if (ForceGateController.state.value.connected) {
                stopService(Intent(this, TindeqGateService::class.java).apply {
                    action = TindeqGateService.ACTION_DISCONNECT
                })
            } else {
                requestBlePermissionsAndConnect()
            }
        }

        binding.accessibilityButton.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        binding.tareButton.setOnClickListener {
            startService(Intent(this, TindeqGateService::class.java).apply {
                action = TindeqGateService.ACTION_TARE
            })
            Toast.makeText(this, R.string.tare_hint, Toast.LENGTH_SHORT).show()
        }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ForceGateController.state.collect { snapshot ->
                    binding.forceValue.text = WeightUnits.format(
                        this@MainActivity,
                        snapshot.weightKg,
                        currentUnit,
                    )
                    binding.statusText.text = statusText(snapshot)
                    binding.connectButton.text = connectButtonText(snapshot)
                    refreshUi()
                }
            }
        }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ForceGateController.connection.collect { phase ->
                    binding.connectButton.text = connectButtonText(ForceGateController.state.value)
                    binding.statusText.text = statusText(ForceGateController.state.value)
                    if (phase == ConnectionPhase.FAILED) {
                        val msg = ForceGateController.connectionError.value
                            ?: getString(R.string.error_connect_failed)
                        Toast.makeText(this@MainActivity, msg, Toast.LENGTH_LONG).show()
                    }
                }
            }
        }

        refreshUi()
    }

    override fun onResume() {
        super.onResume()
        val settings = settingsRepository.load()
        currentUnit = settings.weightUnit
        applyUnitToggleSelection()
        applySliderRanges()
        loadSlidersFromSettings(settings)
        ForceGateController.updateSettings(settings)
        binding.gateSwitch.isChecked = settings.gateEnabled
        binding.handsFreeSwitch.isChecked = settings.handsFreeOnly
        binding.closeInstagramSwitch.isChecked = settings.closeInstagramWhenBlocked
        refreshUi()
    }

    private fun refreshUi() {
        val accessibilityOn = isAccessibilityServiceEnabled()
        binding.accessibilityStatus.text = getString(
            if (accessibilityOn) R.string.accessibility_on else R.string.accessibility_off,
        )
        binding.connectButton.isEnabled = accessibilityOn && binding.gateSwitch.isChecked
        binding.handsFreeSwitch.isEnabled = binding.gateSwitch.isChecked
        binding.handsFreeHint.isVisible = binding.gateSwitch.isChecked
        binding.closeInstagramSwitch.isEnabled = binding.gateSwitch.isChecked
        binding.closeInstagramHint.isVisible = binding.gateSwitch.isChecked
        binding.hintText.isVisible = !accessibilityOn || !binding.gateSwitch.isChecked
    }

    private fun connectButtonText(snapshot: ForceSnapshot): String = when {
        snapshot.connected -> getString(R.string.disconnect)
        ForceGateController.connection.value == ConnectionPhase.SCANNING ->
            getString(R.string.scanning)
        ForceGateController.connection.value == ConnectionPhase.CONNECTING ->
            getString(R.string.connecting)
        else -> getString(R.string.connect)
    }

    private fun statusText(snapshot: ForceSnapshot): String {
        if (!isAccessibilityServiceEnabled()) {
            return getString(R.string.status_need_accessibility)
        }
        if (!snapshot.gateEnabled) {
            return getString(R.string.status_gate_off)
        }
        when (ForceGateController.connection.value) {
            ConnectionPhase.SCANNING -> return getString(R.string.status_scanning)
            ConnectionPhase.CONNECTING -> return getString(R.string.status_connecting)
            ConnectionPhase.FAILED -> return ForceGateController.connectionError.value
                ?: getString(R.string.error_connect_failed)
            else -> Unit
        }
        if (!snapshot.connected) {
            return getString(R.string.status_need_tindeq)
        }
        return when {
            snapshot.mode == GateMode.WARNING -> getString(
                R.string.status_warning,
                graceSeconds(snapshot.graceRemainingMs),
            )
            snapshot.mode == GateMode.BLOCKED -> if (ForceGateController.settings.closeInstagramWhenBlocked) {
                getString(R.string.status_closed)
            } else {
                getString(R.string.status_blocked)
            }
            !snapshot.instagramActive -> getString(R.string.status_waiting_instagram)
            ForceGateController.settings.handsFreeOnly -> getString(R.string.status_holding_hands_free)
            else -> getString(R.string.status_holding)
        }
    }

    private fun graceSeconds(remainingMs: Long): Int =
        ceil(remainingMs / 1000.0).toInt().coerceAtLeast(1)

    private fun applyUnitToggleSelection() {
        val targetId = if (currentUnit == WeightUnit.LBS) R.id.unitLbs else R.id.unitKg
        if (binding.unitToggle.checkedButtonId == targetId) return
        suppressUnitToggle = true
        binding.unitToggle.check(targetId)
        suppressUnitToggle = false
    }

    private fun applySliderRanges() {
        binding.minPullLabel.text = getString(R.string.min_pull_label, currentUnit.abbrev)
        binding.scrollPullLabel.text = getString(R.string.scroll_pull_label, currentUnit.abbrev)
    }

    private fun loadSlidersFromSettings(settings: GateSettings) {
        val minMax = WeightUnits.minSliderMax(currentUnit)
        val scrollMin = WeightUnits.scrollSliderMin(currentUnit)
        val scrollMax = WeightUnits.scrollSliderMax(currentUnit)
        val minVal = WeightUnits.snapToStep(
            WeightUnits.kgToDisplay(settings.minPullKg, currentUnit),
        ).coerceIn(0f, minMax)
        val scrollVal = WeightUnits.snapToStep(
            WeightUnits.kgToDisplay(settings.scrollPullKg, currentUnit),
        ).coerceIn(scrollMin, scrollMax)

        binding.minPullSlider.apply {
            valueFrom = 0f
            stepSize = WeightUnits.SLIDER_STEP
            valueTo = minMax
            value = minVal
        }
        binding.scrollPullSlider.apply {
            valueFrom = 0f
            stepSize = WeightUnits.SLIDER_STEP
            valueTo = scrollMax
            value = scrollVal
            valueFrom = scrollMin
        }
        binding.minPullValue.text = formatDisplay(binding.minPullSlider.value)
        binding.scrollPullValue.text = formatDisplay(binding.scrollPullSlider.value)
    }

    private fun persistSettings() {
        val minKg = WeightUnits.displayToKg(binding.minPullSlider.value, currentUnit)
        var scrollKg = WeightUnits.displayToKg(binding.scrollPullSlider.value, currentUnit)
        val minScrollKg = minKg + WeightUnits.MIN_GAP_KG
        if (scrollKg < minScrollKg) {
            val snapped = WeightUnits.snapToStep(
                WeightUnits.kgToDisplay(minScrollKg, currentUnit),
            ).coerceIn(binding.scrollPullSlider.valueFrom, binding.scrollPullSlider.valueTo)
            binding.scrollPullSlider.value = snapped
            scrollKg = WeightUnits.displayToKg(snapped, currentUnit)
            binding.scrollPullValue.text = formatDisplay(snapped)
        }
        val settings = GateSettings(
            minPullKg = minKg,
            scrollPullKg = scrollKg,
            gateEnabled = binding.gateSwitch.isChecked,
            weightUnit = currentUnit,
            handsFreeOnly = binding.handsFreeSwitch.isChecked,
            closeInstagramWhenBlocked = binding.closeInstagramSwitch.isChecked,
        )
        settingsRepository.save(settings)
        ForceGateController.updateSettings(settings)
        refreshBleSettings()
    }

    private fun refreshBleSettings() {
        if (!ForceGateController.state.value.connected) return
        startService(Intent(this, TindeqGateService::class.java).apply {
            action = TindeqGateService.ACTION_REFRESH_SETTINGS
        })
    }

    private fun requestBlePermissionsAndConnect() {
        val needed = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isEmpty()) {
            startBleService()
        } else {
            permissionLauncher.launch(needed.toTypedArray())
        }
    }

    private fun startBleService() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, TindeqGateService::class.java).apply {
                action = TindeqGateService.ACTION_CONNECT
            },
        )
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabled = manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_GENERIC)
        val target = ComponentName(this, InstagramAccessibilityService::class.java)
        return enabled.any { it.resolveInfo.serviceInfo.let { info ->
            info.packageName == target.packageName && info.name == target.className
        } }
    }

    private fun formatDisplay(displayValue: Float): String {
        val kg = WeightUnits.displayToKg(displayValue, currentUnit)
        return WeightUnits.format(this, kg, currentUnit)
    }
}
