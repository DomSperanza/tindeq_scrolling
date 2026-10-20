import CoreBluetooth
import Foundation
import TindeqCore

enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected(name: String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isBusy: Bool {
        self == .scanning || self == .connecting
    }
}

/// CoreBluetooth client for the Tindeq Progressor. Same flow as the Android
/// `TindeqBleManager` + `TindeqClient`: scan for the first device whose name
/// matches, subscribe to the data characteristic, send START_WEIGHT_MEAS, and
/// stream weight samples.
@MainActor
final class ProgressorBLE: NSObject {
    var onStateChange: (@MainActor (ConnectionState) -> Void)?
    var onWeight: (@MainActor (Float) -> Void)?

    private(set) var state: ConnectionState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private static let serviceUUID = CBUUID(string: TindeqProtocol.serviceUUID)
    private static let writeUUID = CBUUID(string: TindeqProtocol.writeUUID)
    private static let notifyUUID = CBUUID(string: TindeqProtocol.notifyUUID)
    private static let scanTimeout: Duration = .seconds(12)
    private static let commandSpacing: Duration = .milliseconds(100)

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var wantsConnection = false
    private var userDisconnecting = false
    private var scanTimeoutTask: Task<Void, Never>?
    private var commandQueue: [UInt8] = []
    private var drainingCommands = false

    func connect() {
        wantsConnection = true
        userDisconnecting = false
        // Created lazily so the Bluetooth permission prompt appears on the first
        // Connect tap rather than at launch. The delegate fires
        // centralManagerDidUpdateState once the state is known.
        guard let central else {
            state = .scanning
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        startIfReady(central)
    }

    func disconnect() {
        wantsConnection = false
        scanTimeoutTask?.cancel()
        central?.stopScan()
        guard let peripheral else {
            state = .idle
            return
        }
        userDisconnecting = true
        if writeCharacteristic != nil {
            // Put the Progressor to sleep before dropping the link, like Android.
            enqueue(TindeqProtocol.cmdSleep)
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                self.central?.cancelPeripheralConnection(peripheral)
            }
        } else {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    func tare() {
        enqueue(TindeqProtocol.cmdTareScale)
    }

    // MARK: - Connection flow

    private func startIfReady(_ central: CBCentralManager) {
        guard wantsConnection, !state.isConnected else { return }
        switch central.state {
        case .poweredOn:
            startScan(central)
        case .unknown, .resetting:
            state = .scanning
        case .poweredOff:
            fail("Turn on Bluetooth, then try again")
        case .unauthorized:
            fail("Bluetooth access is off. Enable it in Settings → Tindeq Scrolling.")
        case .unsupported:
            fail("This device doesn't support Bluetooth LE")
        @unknown default:
            fail("Bluetooth unavailable")
        }
    }

    private func startScan(_ central: CBCentralManager) {
        state = .scanning
        // No service filter: the Progressor isn't guaranteed to advertise its
        // service UUID, so match on name like the Android app does.
        central.scanForPeripherals(withServices: nil, options: nil)
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(for: Self.scanTimeout)
            guard !Task.isCancelled, self.state == .scanning else { return }
            self.central?.stopScan()
            self.fail("No Progressor found. Pull on it to wake it, then retry.")
        }
    }

    private func fail(_ message: String) {
        wantsConnection = false
        scanTimeoutTask?.cancel()
        central?.stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetLink()
        state = .failed(message)
    }

    private func resetLink() {
        peripheral = nil
        writeCharacteristic = nil
        commandQueue.removeAll()
    }

    // MARK: - Commands

    private func enqueue(_ cmd: UInt8) {
        commandQueue.append(cmd)
        guard !drainingCommands else { return }
        drainingCommands = true
        Task {
            while !self.commandQueue.isEmpty {
                let next = self.commandQueue.removeFirst()
                self.write(next)
                try? await Task.sleep(for: Self.commandSpacing)
            }
            self.drainingCommands = false
        }
    }

    private func write(_ cmd: UInt8) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(TindeqProtocol.packCmd(cmd), for: characteristic, type: type)
    }
}

// MARK: - CBCentralManagerDelegate

extension ProgressorBLE: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startIfReady(central)
        } else if wantsConnection || state.isConnected {
            if state.isConnected {
                resetLink()
                state = .failed("Bluetooth turned off")
            } else {
                startIfReady(central)
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard state == .scanning, self.peripheral == nil else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard TindeqProtocol.isProgressorName(name) else { return }
        central.stopScan()
        scanTimeoutTask?.cancel()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail(error?.localizedDescription ?? "Could not connect. Wake the Progressor and retry.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral == self.peripheral else { return }
        let wasUser = userDisconnecting
        userDisconnecting = false
        wantsConnection = false
        resetLink()
        state = wasUser ? .idle : .failed("Progressor disconnected")
    }
}

// MARK: - CBPeripheralDelegate

extension ProgressorBLE: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("Progressor service not found")
            return
        }
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let characteristics = service.characteristics ?? []
        guard let notify = characteristics.first(where: { $0.uuid == Self.notifyUUID }),
              let write = characteristics.first(where: { $0.uuid == Self.writeUUID }) else {
            fail("Progressor characteristics not found")
            return
        }
        writeCharacteristic = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.notifyUUID else { return }
        if let error {
            fail("Couldn't subscribe to force data: \(error.localizedDescription)")
            return
        }
        state = .connected(name: peripheral.name ?? "Progressor")
        enqueue(TindeqProtocol.cmdStartWeightMeas)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.notifyUUID, let data = characteristic.value else { return }
        let (kind, samples) = TindeqProtocol.parseNotifyPayload(data)
        guard kind == TindeqProtocol.responseWeight else { return }
        for sample in samples {
            onWeight?(sample.weight)
        }
    }
}
