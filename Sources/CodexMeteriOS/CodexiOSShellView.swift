import SwiftUI

struct CodexiOSShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheckSignInOnReturn = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var refreshIntervalSeconds = 300
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.hasCompletedOnboarding) private var storedHasCompletedOnboarding = false
    @Bindable var model: CodexiOSModel

    var body: some View {
        Group {
            if model.isCheckingSavedAccount {
                CodexiOSLaunchLoadingView(message: model.statusMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if hasCompletedOnboarding {
                CodexiOSRootView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 1.02))
                    ))
            } else {
                CodexiOSOnboardingView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.98))
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: hasCompletedOnboarding)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: model.isCheckingSavedAccount)
        .task {
            await model.start()
        }
        .task(id: refreshTaskID) {
            await runAutoRefreshLoop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await model.handleSceneDidBecomeActive(
                    autoCheckSignInOnReturn: autoCheckSignInOnReturn,
                    refreshWhenActive: refreshWhenActive
                )
            }
        }
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    private var hasCompletedOnboarding: Bool {
        model.hasCompletedOnboarding || storedHasCompletedOnboarding
    }

    private var refreshTaskID: String {
        "\(refreshWhenActive)-\(max(refreshIntervalSeconds, 300))"
    }

    private func runAutoRefreshLoop() async {
        guard refreshWhenActive else { return }
        while Task.isCancelled == false {
            try? await Task.sleep(for: .seconds(Double(max(refreshIntervalSeconds, 300))))
            guard Task.isCancelled == false else { return }
            if scenePhase == .active, model.canAutoRefresh {
                await model.refresh()
            }
        }
    }
}

private struct CodexiOSLaunchLoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            CodexiOSTheme.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        CodexiOSLoadingPulse(tint: CodexiOSTheme.secondary)

                        Text("Codexex")
                            .font(.system(size: 38, weight: .bold))
                            .lineLimit(1)
                    }

                    Text(message)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                CodexiOSLoadingBar(tint: CodexiOSTheme.secondary)
                    .accessibilityLabel("Loading quota")
            }
            .padding(22)
            .frame(maxWidth: 520, alignment: .leading)
        }
    }
}

struct CodexiOSLoadingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.20), lineWidth: 2)

            Circle()
                .trim(from: 0.0, to: 0.34)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(isActive && reduceMotion == false ? 360 : 0))

            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .offset(y: -16)
                .opacity(isActive && reduceMotion == false ? 0.55 : 1)
        }
        .frame(width: 36, height: 36)
        .onAppear {
            guard reduceMotion == false else { return }
            isActive = true
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false),
            value: isActive
        )
        .accessibilityHidden(true)
    }
}

struct CodexiOSLoadingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let segmentWidth = max(54, width * 0.28)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CodexiOSTheme.inset)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CodexiOSTheme.primaryGradient)
                    .frame(width: segmentWidth)
                    .offset(x: reduceMotion ? 0 : (isActive ? width - segmentWidth : 0))
                    .opacity(reduceMotion ? 0.75 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 8)
        .onAppear {
            guard reduceMotion == false else { return }
            isActive = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
            value: isActive
        )
    }
}

struct CodexiOSRefreshingIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(isActive && reduceMotion == false ? 360 : 0))
            .onAppear {
                guard reduceMotion == false else { return }
                isActive = true
            }
            .animation(
                reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: isActive
            )
            .accessibilityHidden(true)
    }
}
