import SwiftUI
import TindeqCore

/// Warning / locked / disconnected overlays over the reels (the iOS version of
/// the Android accessibility overlay).
struct GateOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.progressorLost {
                ProgressorLostOverlay()
            } else if model.gateActive && model.gateMode == .blocked {
                LockedOverlay()
            } else if model.gateActive && model.gateMode == .warning {
                WarningOverlay()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.gateMode)
        .animation(.easeInOut(duration: 0.2), value: model.progressorLost)
    }
}

private struct WarningOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unit = model.settings.weightUnit
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Pull harder")
                    .font(.title2.weight(.bold))
                Text("\(max(1, Int(model.graceRemaining.rounded(.up))))")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.warning)
                    .contentTransition(.numericText(countsDown: true))
                Text("\(WeightUnits.format(model.weightKg, unit)) · need \(WeightUnits.format(model.settings.minPullKg, unit))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }
}

private struct LockedOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unit = model.settings.weightUnit
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.blocked)
                Text("Feed locked")
                    .font(.title.weight(.bold))
                Text("Pull to \(WeightUnits.format(model.settings.minPullKg, unit)) to keep watching")
                    .foregroundStyle(.secondary)
                Text(WeightUnits.format(model.weightKg, unit))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ForceMeter(
                    weightKg: model.weightKg,
                    minKg: model.settings.minPullKg,
                    scrollKg: model.settings.scrollPullKg
                )
                .frame(maxWidth: 260)
                Button("End session") { model.endSession() }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
            }
            .padding(32)
        }
        .transition(.opacity)
    }
}

private struct ProgressorLostOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.warning)
                Text("Progressor disconnected")
                    .font(.title2.weight(.bold))
                if case .failed(let message) = model.connection {
                    Text(message).foregroundStyle(.secondary)
                }
                Button { model.connect() } label: {
                    HStack {
                        if model.connection.isBusy { ProgressView().controlSize(.small) }
                        Text(model.connection.isBusy ? "Reconnecting…" : "Reconnect")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.connection.isBusy)
                Button("End session") { model.endSession() }
                    .buttonStyle(.bordered)
            }
            .multilineTextAlignment(.center)
            .padding(32)
        }
        .transition(.opacity)
    }
}
