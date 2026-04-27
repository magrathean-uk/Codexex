import SwiftUI

struct CodexiOSOnboardingView: View {
    @Bindable var model: CodexiOSModel
    @State private var step: Step = .welcome

    private enum Step: Int {
        case welcome
        case login
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CodexiOSOnboardingBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header

                        Group {
                            switch step {
                            case .welcome:
                                welcomeStep
                            case .login:
                                loginStep
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 34)
                    .padding(.bottom, 120)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: step)
        .onChange(of: model.isSignedIn) { _, isSignedIn in
            if isSignedIn, model.previewModeEnabled == false {
                model.completeOnboarding()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                progressDot(active: true)
                progressDot(active: step == .login)
                Text(step == .welcome ? "Step 1 of 2" : "Step 2 of 2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(step == .welcome ? "Welcome to Codexex" : "Sign in with ChatGPT")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text(step == .welcome ? "Track Codex quota from this device. No server, no Mac bridge, no browser cookies." : "Approve the device code in Safari. When you return, Codexex checks status automatically.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard

            onboardingCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose how to start")
                        .font(.title2.weight(.bold))

                    Text("Preview mode uses local sample data so anyone can test the layout before signing in.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        model.enablePreviewMode()
                    } label: {
                        Text("Try Preview Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CodexiOSOnboardingPrimaryButtonStyle())

                    Button {
                        withAnimation { step = .login }
                    } label: {
                        Text("Continue to Login")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CodexiOSOnboardingSecondaryButtonStyle())
                }
            }
        }
    }

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect account")
                        .font(.title2.weight(.bold))

                    Text(loginMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let code = model.deviceCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device code")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(code)
                                .font(.system(.title2, design: .monospaced, weight: .bold))
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    FlowLayout(spacing: 10) {
                        if model.deviceCode == nil {
                            Button(model.isSigningIn ? "Starting" : "Sign In") {
                                model.beginSignIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isSigningIn)
                        } else {
                            Button("Open Safari") { model.openSignInPage() }
                                .buttonStyle(.borderedProminent)
                            Button("Copy Code") { model.copyCode() }
                                .buttonStyle(.bordered)
                            Button("Check Status") { model.checkSignIn() }
                                .buttonStyle(.bordered)
                                .disabled(model.isSigningIn)
                        }
                    }
                }
            }

            Button {
                withAnimation { step = .welcome }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
        }
    }

    private var heroCard: some View {
        onboardingCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.cyan.opacity(0.18))
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quota, readable")
                        .font(.title2.weight(.bold))
                    Text("Codex and Spark cards, reset times, and preview data in the same layout as the real app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var loginMessage: String {
        if model.deviceCode != nil {
            return model.statusMessage
        }
        if let error = model.errorMessage {
            return error
        }
        return "Start device login. Safari opens, then Codexex finishes when you return."
    }

    private func progressDot(active: Bool) -> some View {
        Capsule()
            .fill(active ? .cyan : .white.opacity(0.16))
            .frame(width: active ? 28 : 10, height: 10)
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 24, y: 14)
    }
}

struct CodexiOSOnboardingBackground: View {
    var body: some View {
        ZStack {
            CodexiOSTheme.background
            GeometryReader { proxy in
                Circle()
                    .fill(.cyan.opacity(0.12))
                    .frame(width: proxy.size.width * 0.90, height: proxy.size.width * 0.90)
                    .blur(radius: 48)
                    .offset(x: -proxy.size.width * 0.34, y: -proxy.size.height * 0.14)

                Circle()
                    .fill(.orange.opacity(0.08))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.width * 0.78)
                    .blur(radius: 52)
                    .offset(x: proxy.size.width * 0.40, y: proxy.size.height * 0.42)
            }
        }
    }
}

struct CodexiOSOnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .background((isEnabled ? Color.cyan : Color.cyan.opacity(0.45)).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CodexiOSOnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 15)
            .background(.white.opacity(configuration.isPressed ? 0.05 : 0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }
}
