import SwiftUI

struct CodexiOSShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .transition(.opacity)
            } else if hasCompletedOnboarding {
                CodexiOSRootView(model: model)
                    .transition(.opacity)
            } else {
                CodexiOSOnboardingView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hasCompletedOnboarding)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.isCheckingSavedAccount)
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
        .onOpenURL { url in
            #if DEBUG
            if url.scheme == "codexex", url.host == "background-test" {
                Task { await runBackgroundTest() }
                return
            }
            #endif
            guard url.scheme == "codexex", url.host == "refresh" else { return }
            Task { await model.refresh() }
        }
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    private var hasCompletedOnboarding: Bool {
        model.hasCompletedOnboarding || storedHasCompletedOnboarding
    }

    private var refreshTaskID: String {
        "\(refreshWhenActive)-\(max(refreshIntervalSeconds, 300))"
    }

    #if DEBUG
    private func runBackgroundTest() async {
        let push = codexiOSSharedPushRegistrationManager
        push.recordDebugTestPhase("waiting-for-startup")
        let startupDeadline = Date().addingTimeInterval(10)
        while model.isCheckingSavedAccount || model.isRefreshing || model.isSigningIn || model.isLiveActivityTransitioning {
            guard !Task.isCancelled, Date() < startupDeadline else {
                push.recordDebugTestPhase("startup-not-ready")
                return
            }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
        push.recordDebugTestPhase("refreshing-quota")
        await model.refresh()
        guard !Task.isCancelled, !model.previewModeEnabled, model.isSignedIn, model.snapshot != nil else {
            push.recordDebugTestPhase("signed-in-quota-unavailable")
            return
        }
        if !model.isLiveActivityRunning {
            push.recordDebugTestPhase("starting-activity")
            await model.startLiveActivity()
        }
        guard !Task.isCancelled, model.isLiveActivityRunning else {
            push.recordDebugTestPhase("activity-unavailable")
            return
        }
        push.recordDebugTestPhase("waiting-for-registration")
        let registrationDeadline = Date().addingTimeInterval(10)
        while push.registrationState != .registered {
            guard !Task.isCancelled, Date() < registrationDeadline else {
                push.recordDebugTestPhase("registration-not-ready")
                return
            }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
        guard !push.isTestWakeCoolingDown else {
            push.recordDebugTestPhase("test-cooldown")
            return
        }
        push.recordDebugTestPhase("requesting-wake")
        await push.requestTestWake()
        push.recordDebugTestPhase(push.testWakeStatus?.hasPrefix("Requested") == true ? "wake-requested" : "wake-request-failed")
    }
    #endif

    private func runAutoRefreshLoop() async {
        guard refreshWhenActive else { return }
        while Task.isCancelled == false {
            try? await Task.sleep(for: .seconds(Double(max(refreshIntervalSeconds, 300))))
            guard Task.isCancelled == false else { return }
            if scenePhase == .active, model.canAutoRefresh || model.apiMonitor.hasKey {
                await model.refresh()
            }
        }
    }
}

private struct CodexiOSLaunchLoadingView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Codexex").font(.largeTitle.bold())
            Text(message).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
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
