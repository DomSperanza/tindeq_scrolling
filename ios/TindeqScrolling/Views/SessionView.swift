import SwiftUI
import TindeqCore

/// Full-screen reels session: Instagram's web reels with our HUD and gate overlays on top.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var showScrollFlash = false
    @State private var diagnostics: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let web = model.web {
                ReelsWebView(controller: web)
                    .ignoresSafeArea(edges: .bottom)
            }

            GateOverlay()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if model.route == .auth {
                    authBanner
                }
                #if DEBUG
                if model.simulatedProgressor {
                    simulatedForceSlider
                }
                #endif
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.scrollCount) {
            showScrollFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                showScrollFlash = false
            }
        }
        #if DEBUG
        .alert("Reels diagnostics", isPresented: Binding(
            get: { diagnostics != nil },
            set: { if !$0 { diagnostics = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(diagnostics ?? "")
        }
        #endif
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            ForceHUD(showScrollFlash: showScrollFlash)
                #if DEBUG
                .onLongPressGesture {
                    Task { diagnostics = await model.diagnoseReels() }
                }
                #endif
            Spacer()
            #if DEBUG
            Button {
                model.debugNextReel()
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .accessibilityLabel("Next reel (debug)")
            #endif
            Button {
                model.endSession()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .accessibilityLabel("End session")
        }
        .padding(.top, 4)
    }

    private var authBanner: some View {
        Label("Log in to Instagram. The pull gate starts once Reels load.", systemImage: "person.badge.key.fill")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }

    #if DEBUG
    private var simulatedForceSlider: some View {
        @Bindable var model = model
        return HStack {
            Image(systemName: "ladybug.fill")
            Slider(value: $model.simulatedWeightKg, in: 0...max(model.settings.scrollPullKg * 1.3, 10))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
    #endif
}

/// Compact live-force pill shown over the reels (the iOS version of the Android HUD).
private struct ForceHUD: View {
    @Environment(AppModel.self) private var model
    let showScrollFlash: Bool

    var body: some View {
        let unit = model.settings.weightUnit
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(WeightUnits.format(model.weightKg, unit))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("min \(WeightUnits.format(model.settings.minPullKg, unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showScrollFlash {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.scroll)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            ForceMeter(
                weightKg: model.weightKg,
                minKg: model.settings.minPullKg,
                scrollKg: model.settings.scrollPullKg,
                height: 6
            )
            .frame(width: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .animation(.spring(duration: 0.25), value: showScrollFlash)
    }

    private var accent: Color {
        model.gateActive ? Theme.color(for: model.gateMode) : .white
    }
}
