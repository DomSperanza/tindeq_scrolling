import Observation
import SwiftUI
import TindeqCore

/// App-wide state: Progressor connection, gate settings, and the reels session.
/// Plays the role of Android's `ForceGateController` + `TindeqGateService`.
@MainActor
@Observable
final class AppModel {
    // MARK: Settings

    var settings: GateSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            gate.settings = settings
            web?.setHandsFree(settings.handsFreeOnly)
        }
    }

    // MARK: Progressor

    private(set) var connection: ConnectionState = .idle
    private(set) var weightKg: Float = 0
    /// Debug builds can feed force from an on-screen slider (the simulator has no Bluetooth).
    var simulatedProgressor = false {
        didSet { simulatedProgressorChanged() }
    }
    var simulatedWeightKg: Float = 0

    var isConnected: Bool { simulatedProgressor || connection.isConnected }

    // MARK: Session

    var sessionActive = false
    private(set) var web: ReelsWebController?
    private(set) var route: InstagramRoutes.Route = .external
    private(set) var gateMode: GateMode = .idle
    private(set) var graceRemaining: TimeInterval = 0
    /// Bumped on every pull-triggered scroll, so views can animate.
    private(set) var scrollCount = 0
    private(set) var lastScrollResult: String?
    /// Set when a session ends because of the gate, shown on the home screen.
    var sessionEndedMessage: String?

    var instagramSignedIn: Bool?

    /// True when the pull gate is enforcing: in a session, on a reels page.
    var gateActive: Bool { sessionActive && route == .reels }

    /// On reels but no Progressor: treated like blocked.
    var progressorLost: Bool { gateActive && !isConnected }

    // MARK: Private

    @ObservationIgnored private let settingsStore = SettingsStore()
    @ObservationIgnored private let ble: ProgressorBLE
    @ObservationIgnored private var gate: ForceGate
    @ObservationIgnored private var feedLocked = false
    @ObservationIgnored private var simulationTask: Task<Void, Never>?

    init() {
        let loaded = settingsStore.load()
        settings = loaded
        gate = ForceGate(settings: loaded)
        ble = ProgressorBLE()
        ble.onStateChange = { [weak self] state in self?.connectionChanged(state) }
        ble.onWeight = { [weak self] weight in self?.ingest(weightKg: weight) }
    }

    // MARK: - Progressor actions

    func connect() {
        ble.connect()
    }

    func disconnect() {
        ble.disconnect()
    }

    func tare() {
        ble.tare()
    }

    private func connectionChanged(_ state: ConnectionState) {
        connection = state
        if !state.isConnected && !simulatedProgressor {
            weightKg = 0
            gate.reset()
            gateMode = .idle
            graceRemaining = 0
        }
        syncFeedLock()
    }

    private func simulatedProgressorChanged() {
        simulationTask?.cancel()
        simulationTask = nil
        if simulatedProgressor {
            // Feed samples at ~50 Hz so grace timing works without slider movement.
            simulationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.ingest(weightKg: self.simulatedWeightKg)
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        } else {
            connectionChanged(connection)
        }
    }

    // MARK: - Force samples

    private func ingest(weightKg weight: Float) {
        weightKg = weight
        guard gateActive, isConnected else {
            if gateMode != .idle {
                gate.reset()
                gateMode = .idle
                graceRemaining = 0
                syncFeedLock()
            }
            return
        }

        let output = gate.process(weightKg: weight, now: ProcessInfo.processInfo.systemUptime)
        graceRemaining = output.graceRemaining
        if output.mode != gateMode {
            gateMode = output.mode
            if gateMode == .blocked && settings.blockedAction == .endSession {
                endSession(message: "Session ended: you stayed below your minimum pull for "
                    + "\(Int(ForceGate.graceDuration)) seconds.")
                return
            }
            syncFeedLock()
        }
        if output.scrollTriggered {
            nextReel()
        }
    }

    private func nextReel() {
        guard let web else { return }
        scrollCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let result = await web.nextReel()
            lastScrollResult = result
            #if DEBUG
            print("[nextReel]", result)
            #endif
        }
    }

    /// Pauses video in the page whenever the feed is covered (blocked or Progressor lost).
    /// `force` re-sends the state even if unchanged, e.g. after the page reloaded.
    private func syncFeedLock(force: Bool = false) {
        let shouldLock = gateActive && (gateMode == .blocked || !isConnected)
        guard force || shouldLock != feedLocked else { return }
        feedLocked = shouldLock
        web?.setLocked(shouldLock)
    }

    // MARK: - Session

    func startSession() {
        guard !sessionActive else { return }
        sessionEndedMessage = nil
        let controller = ReelsWebController()
        controller.onRouteChange = { [weak self] route in self?.routeChanged(route) }
        controller.onBridgeReady = { [weak self] in self?.bridgeReady() }
        web = controller
        route = .external
        gate.reset()
        gateMode = .idle
        feedLocked = false
        sessionActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        controller.loadReels()
    }

    func endSession(message: String? = nil) {
        guard sessionActive else { return }
        web?.setLocked(true)
        web?.tearDown()
        web = nil
        sessionActive = false
        route = .external
        gate.reset()
        gateMode = .idle
        feedLocked = false
        sessionEndedMessage = message
        UIApplication.shared.isIdleTimerDisabled = false
        Task { await refreshInstagramStatus() }
    }

    private func routeChanged(_ newRoute: InstagramRoutes.Route) {
        route = newRoute
        // Login time never counts against the user: restart the gate fresh when
        // reels (re)appear.
        gate.reset()
        gateMode = .idle
        graceRemaining = 0
        syncFeedLock(force: true)
    }

    /// ReelsBridge.js is re-injected on every full page load and starts unlocked
    /// with hands-free off, so push the current state into it.
    private func bridgeReady() {
        web?.setHandsFree(settings.handsFreeOnly)
        syncFeedLock(force: true)
    }

    // MARK: - Instagram account

    func refreshInstagramStatus() async {
        instagramSignedIn = await InstagramAccount.isSignedIn()
    }

    func signOutOfInstagram() async {
        await InstagramAccount.signOut()
        await refreshInstagramStatus()
    }

    #if DEBUG
    /// Scroll without a pull, for testing ReelsBridge.js in the simulator.
    func debugNextReel() {
        nextReel()
    }

    func diagnoseReels() async -> String {
        guard let web else { return "No session" }
        let dom = await web.diagnose()
        return "route: \(route)\nlast scroll: \(lastScrollResult ?? "none")\n\(dom)"
    }
    #endif
}
