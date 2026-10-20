import SwiftUI
import TindeqCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = model.sessionEndedMessage {
                        SessionEndedBanner(message: message) { model.sessionEndedMessage = nil }
                    }
                    ProgressorCard()
                    ThresholdsCard()
                    OptionsCard()
                    InstagramCard()
                    #if DEBUG
                    DebugCard()
                    #endif
                }
                .padding(16)
            }
            .navigationTitle("Tindeq Scrolling")
            .safeAreaInset(edge: .bottom) { StartButton() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.sessionActive },
            set: { if !$0 { model.endSession() } }
        )) {
            SessionView()
        }
    }
}

private struct SessionEndedBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.blocked)
            Text(message).font(.subheadline)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.blocked.opacity(0.15)))
    }
}

private struct ProgressorCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unit = model.settings.weightUnit
        Card(title: "Progressor") {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                Spacer()
                if model.isConnected && !model.simulatedProgressor {
                    Button("Tare") { model.tare() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text(WeightUnits.format(model.weightKg, unit))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            ForceMeter(
                weightKg: model.weightKg,
                minKg: model.settings.minPullKg,
                scrollKg: model.settings.scrollPullKg
            )
            if !model.simulatedProgressor {
                connectButton
            }
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        if model.connection.isConnected || model.connection.isBusy {
            Button(role: .destructive) { model.disconnect() } label: {
                HStack {
                    if model.connection.isBusy { ProgressView().controlSize(.small) }
                    Text(model.connection.isBusy ? "Cancel" : "Disconnect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button { model.connect() } label: {
                Label("Connect Progressor", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusText: String {
        if model.simulatedProgressor { return "Simulated Progressor (debug)" }
        switch model.connection {
        case .idle: return "Not connected"
        case .scanning: return "Scanning. Pull on the Progressor to wake it."
        case .connecting: return "Connecting…"
        case .connected(let name): return "Connected to \(name)"
        case .failed(let message): return message
        }
    }

    private var statusIcon: String {
        switch model.connection {
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: model.simulatedProgressor ? "ladybug.fill" : "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: Theme.holding
        case .failed: Theme.warning
        default: .secondary
        }
    }
}

private struct ThresholdsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let unit = model.settings.weightUnit
        Card(title: "Thresholds") {
            Picker("Unit", selection: $model.settings.weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { Text($0.abbrev).tag($0) }
            }
            .pickerStyle(.segmented)

            thresholdRow(
                title: "Minimum pull",
                kg: model.settings.minPullKg,
                caption: "Hold at least this much to keep reels playing.",
                value: displayBinding(\.minPullKg),
                range: 0...WeightUnits.minSliderMax(unit)
            )
            thresholdRow(
                title: "Next reel pull",
                kg: model.settings.scrollPullKg,
                caption: "Spike to this to jump to the next reel.",
                value: displayBinding(\.scrollPullKg),
                range: WeightUnits.scrollSliderMin(unit)...WeightUnits.scrollSliderMax(unit)
            )
        }
    }

    private func thresholdRow(
        title: String,
        kg: Float,
        caption: String,
        value: Binding<Float>,
        range: ClosedRange<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(WeightUnits.format(kg, model.settings.weightUnit))
                    .font(.headline)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: WeightUnits.sliderStep)
            Caption(caption)
        }
    }

    /// Slider binding in the display unit, stored in kg (like the Android sliders).
    private func displayBinding(_ keyPath: WritableKeyPath<GateSettings, Float>) -> Binding<Float> {
        Binding(
            get: {
                WeightUnits.snapToStep(
                    WeightUnits.kgToDisplay(model.settings[keyPath: keyPath], model.settings.weightUnit)
                )
            },
            set: { display in
                var updated = model.settings
                updated[keyPath: keyPath] = WeightUnits.displayToKg(display, updated.weightUnit)
                model.settings = updated.normalized()
            }
        )
    }
}

private struct OptionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card(title: "Options") {
            Toggle("Hands-free scrolling only", isOn: $model.settings.handsFreeOnly)
            Caption("Taps still work, but finger swipes between reels are blocked. Pull to advance.")

            Divider()

            Text("When you drop below minimum pull").font(.headline)
            Picker("When you drop below minimum pull", selection: $model.settings.blockedAction) {
                Text("Lock the feed").tag(BlockedAction.lockFeed)
                Text("End the session").tag(BlockedAction.endSession)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Caption(blockedCaption(model.settings.blockedAction))
        }
    }

    private func blockedCaption(_ action: BlockedAction) -> String {
        let grace = Int(ForceGate.graceDuration)
        switch action {
        case .lockFeed:
            return "After a \(grace)-second warning, video pauses and the feed is covered until you pull again."
        case .endSession:
            return "After a \(grace)-second warning, the session closes and you return here."
        }
    }
}

private struct InstagramCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingSignOut = false

    var body: some View {
        Card(title: "Instagram") {
            switch model.instagramSignedIn {
            case .none:
                Label("Checking…", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            case .some(true):
                Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.holding)
                Button("Sign out of Instagram", role: .destructive) { confirmingSignOut = true }
                    .buttonStyle(.bordered)
            case .some(false):
                Label("Not signed in", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Caption("You'll log in on Instagram's own page when you start. "
                    + "The pull gate doesn't apply until Reels load.")
            }
        }
        .confirmationDialog("Sign out of Instagram?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await model.signOutOfInstagram() }
            }
        } message: {
            Text("This clears Instagram's login and site data from this app.")
        }
    }
}

private struct StartButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Button { model.startSession() } label: {
                Label("Start Reels", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isConnected)
            if !model.isConnected {
                Caption("Connect your Progressor to start.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

#if DEBUG
private struct DebugCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card(title: "Debug") {
            Toggle("Simulated Progressor", isOn: $model.simulatedProgressor)
            Caption("Feeds force from a slider instead of Bluetooth (for the simulator). "
                + "A slider also appears during the session.")
            if model.simulatedProgressor {
                Slider(value: $model.simulatedWeightKg, in: 0...max(model.settings.scrollPullKg * 1.3, 10))
            }
        }
    }
}
#endif
