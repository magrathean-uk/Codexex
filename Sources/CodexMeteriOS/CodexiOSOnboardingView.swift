import SwiftUI

struct CodexiOSOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CodexiOSModel
    @State private var path: [Connection] = []
    private enum Connection: Hashable { case subscription, api }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Codexex").font(.title.bold()).accessibilityAddTraits(.isHeader)
                        Text("What would you like to monitor?").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink(value: Connection.subscription) {
                        choice("ChatGPT subscription", detail: "Codex limits and reset times", icon: "gauge.with.dots.needle.bottom.50percent")
                    }.accessibilityIdentifier("ios.onboarding.subscription")
                    NavigationLink(value: Connection.api) {
                        choice("API monitoring", detail: "API access, costs and credits", icon: "chart.bar.xaxis")
                    }.accessibilityIdentifier("ios.onboarding.api")
                }
                Section {
                    Button("Try preview") { model.enablePreviewMode() }
                        .frame(minHeight: 44).accessibilityIdentifier("ios.onboarding.preview")
                } footer: { Text("Explore with sample data.") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Get started").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Connection.self) { connection in
                switch connection {
                case .subscription: CodexiOSSubscriptionConnectionView(model: model)
                case .api: CodexiOSAPIConnectionView(monitor: model.apiMonitor, onContinue: { model.completeOnboarding() })
                }
            }
        }
        .tint(CodexiOSTheme.actionTint)
        .onAppear { if model.hasPendingSignIn { path = [.subscription] } }
        .onChange(of: model.hasPendingSignIn) { _, pending in
            if pending && path.last != .subscription {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { path = [.subscription] }
            }
        }
    }

    private func choice(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8).frame(minHeight: 44)
    }
}

struct CodexiOSOnboardingBackground: View {
    var body: some View { Color(uiColor: .systemGroupedBackground) }
}
