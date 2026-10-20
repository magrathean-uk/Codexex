import SwiftUI
import CodexMeterCore

struct CodexiOSSubscriptionConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CodexiOSModel
    @State private var returnedFromSafari = false

    static func status(for model: CodexiOSModel) -> String {
        if model.previewModeEnabled { return "Preview" }
        if model.isSigningIn || model.isCheckingSavedAccount { return "Checking" }
        if model.hasPendingSignIn { return "Waiting" }
        if model.isSignedIn { return "Connected" }
        if model.liveAccountState == .authExpired { return "Sign in again" }
        if model.liveAccountState == .unavailable { return "Unavailable" }
        return "Not connected"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: Self.status(for: model))
                if model.isSignedIn, let plan = model.snapshot?.account.displayPlan { LabeledContent("Plan", value: plan) }
            } footer: { Text("View Codex limits and reset times.") }
            if model.previewModeEnabled {
                Section { Text("Turn off Preview mode in Settings to connect an account.").foregroundStyle(.secondary) }
            } else if model.isSigningIn || model.isCheckingSavedAccount {
                Section { ProgressView(model.hasPendingSignIn ? "Checking approval…" : "Connecting…").frame(minHeight: 44) }
                    .transition(.opacity)
            } else if model.hasPendingSignIn {
                Section {
                    if let code = model.deviceCode {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Device code").font(.subheadline).foregroundStyle(.secondary)
                            Text(code).font(.title2.monospaced().bold()).textSelection(.enabled)
                                .accessibilityIdentifier("ios.signIn.deviceCode")
                            Button("Copy code", systemImage: "doc.on.doc") { model.copyCode() }
                                .frame(minHeight: 44).accessibilityIdentifier("ios.signIn.copyCode")
                        }.padding(.vertical, 8)
                    }
                } footer: { Text("Enter this code in Safari, then return here.") }
                    .transition(.opacity)
                Section {
                    Button(returnedFromSafari ? "Check status" : "Open Safari") {
                        Task { if returnedFromSafari { await model.checkSignIn() } else { await model.openSignInPage() } }
                    }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44)
                    .tint(CodexiOSTheme.prominentTint).foregroundStyle(.white)
                    .accessibilityIdentifier("ios.signIn.primaryAction")
                    Button(returnedFromSafari ? "Open Safari again" : "Check status") {
                        Task { if returnedFromSafari { await model.openSignInPage() } else { await model.checkSignIn() } }
                    }.frame(minHeight: 44)
                    Button("Start over") { Task { await model.restartSignIn() } }
                    Button("Cancel sign-in", role: .destructive) { Task { await model.cancelSignIn() } }
                }
            } else if model.isSignedIn {
                Section {
                    Button("Refresh quota") { Task { await model.refresh() } }.disabled(model.isRefreshing)
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                }
            } else {
                Section {
                    Button(model.liveAccountState == .unavailable ? "Try again" : "Sign in with ChatGPT") {
                        Task { if model.liveAccountState == .unavailable { await model.refresh() } else { await model.beginSignIn() } }
                    }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44)
                    .tint(CodexiOSTheme.prominentTint).foregroundStyle(.white)
                    .accessibilityIdentifier("ios.signIn.primaryAction")
                    if model.liveAccountState == .unavailable {
                        Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    }
                } footer: { Text(model.liveAccountState == .unavailable ? "Retry your saved connection." : "Safari opens to approve the connection.") }
                    .transition(.opacity)
            }
            if let error = model.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.primary).font(.callout).fixedSize(horizontal: false, vertical: true) }
            } else if !model.previewModeEnabled, let feedback = signInFeedback {
                Section { Text(feedback).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("ChatGPT").navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.hasPendingSignIn)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.isSigningIn)
        .onChange(of: scenePhase) { _, value in if value == .active && model.hasPendingSignIn { returnedFromSafari = true } }
        .onAppear { returnedFromSafari = model.hasPendingSignIn }
    }

    private var signInFeedback: String? {
        if model.statusMessage == "Code copied. Paste it in Safari." { return "Code copied." }
        if model.statusMessage == CodexiOSError.signInExpired.localizedDescription { return "Code expired. Start again." }
        if model.statusMessage.hasPrefix("Could not open Safari.") {
            return "Safari could not open. Copy the code and open auth.openai.com/codex/device."
        }
        if model.statusMessage.hasPrefix("Try again ") { return model.statusMessage }
        return nil
    }
}

struct CodexiOSAPIConnectionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let monitor: OpenAIMonitorModel
    var preview = false
    var onContinue: (() -> Void)?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: preview ? "Preview" : monitor.isRefreshing ? "Checking" : monitor.isValidated ? "Connected" : monitor.hasKey ? "Saved" : "Not connected")
                NavigationLink("API key") { CodexiOSAPIKeySetupView(monitor: monitor, preview: preview) }
                    .accessibilityIdentifier("ios.api.keySetup")
                NavigationLink {
                    CodexiOSPrepaidBalanceView(monitor: monitor, preview: preview)
                } label: {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Text("Prepaid balance")
                            .fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Text(monitor.balance.map { $0.remainingUSD.formatted(.currency(code: "USD")) } ?? (monitor.unofficialBalanceEnabled ? "Unavailable" : "Off"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }.accessibilityIdentifier("ios.api.balanceSetup")
                NavigationLink("Usage and costs") { CodexiOSAPIReportView(monitor: monitor, preview: preview) }
                    .accessibilityIdentifier("ios.api.reports")
            } footer: { Text("API billing is separate from your ChatGPT subscription.") }
            if let error = monitor.error { Section { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) } }
        }
        .navigationTitle("OpenAI API").navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
        .toolbar {
            if let onContinue {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onContinue).disabled(!monitor.isValidated)
                        .accessibilityIdentifier("ios.api.continue")
                }
            }
        }
        .onAppear { if !preview { monitor.refresh() } }
    }
}

private struct CodexiOSAPIKeySetupView: View {
    let monitor: OpenAIMonitorModel
    let preview: Bool
    @State private var key = ""
    @State private var kind: OpenAIAPIKeyKind = .regular
    @FocusState private var keyFocused: Bool
    #if DEBUG
    init(monitor: OpenAIMonitorModel, preview: Bool, initialKey: String = "") {
        self.monitor = monitor
        self.preview = preview
        _key = State(initialValue: initialKey)
    }
    #endif
    var body: some View {
        Form {
            Section {
                Picker("Key type", selection: $kind) {
                    Text("Standard").tag(OpenAIAPIKeyKind.regular)
                    Text("Admin").tag(OpenAIAPIKeyKind.admin)
                    if monitor.unofficialBalanceEnabled { Text("Billing session").tag(OpenAIAPIKeyKind.billingSession) }
                }
                SecureField(kind == .billingSession ? "Billing session token" : "API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($keyFocused).submitLabel(.done).onSubmit(saveKey)
                    .disabled(preview || monitor.isRefreshing)
                    .privacySensitive().accessibilityIdentifier("ios.api.key")
                Button("Save and verify", action: saveKey)
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44)
                    .tint(CodexiOSTheme.prominentTint)
                    .foregroundStyle(canSaveKey ? Color.white : Color.secondary)
                    .disabled(!canSaveKey)
                    .accessibilityIdentifier("ios.api.saveKey")
                if monitor.isRefreshing { ProgressView("Verifying…") }
                else if monitor.isValidated { Label("Connected", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            } footer: { Text(kind == .admin ? "Use an Admin key for organization reports." : "Credentials stay in this device’s Keychain.") }
            if let error = monitor.error { Section {
                Label(error == OpenAIAPIError.invalidKey.localizedDescription ? "Enter a valid OpenAI key." : error,
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.primary).font(.callout).fixedSize(horizontal: false, vertical: true)
            } }
            if monitor.hasKey || monitor.deletionPending {
                Section {
                    Button(monitor.deletionPending ? "Retry key removal" : "Disconnect monitoring", role: .destructive) {
                        monitor.setUnofficialBalanceEnabled(false)
                        monitor.disconnect()
                        Task { await OpenAIBillingWebsiteData.clear() }
                    }.disabled(preview)
                }
            }
        }
        .navigationTitle("API key").navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyFocused = false }
            }
        }
        .onAppear { kind = monitor.keyKind == .billingSession && !monitor.unofficialBalanceEnabled ? .regular : monitor.keyKind }
        .onChange(of: monitor.isRefreshing) { _, refreshing in
            if !refreshing && monitor.isValidated && monitor.error == nil { key = "" }
        }
    }

    private var canSaveKey: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !monitor.isRefreshing && !preview
    }

    private func saveKey() {
        guard canSaveKey else { return }
        monitor.saveKey(key, kind: kind)
        if monitor.isRefreshing { keyFocused = false }
    }
}

private struct CodexiOSPrepaidBalanceView: View {
    let monitor: OpenAIMonitorModel
    let preview: Bool
    @State private var showingWarning = false
    @State private var showingLogin = false
    var body: some View {
        Form {
            Section {
                LabeledContent("Remaining") {
                    Text(monitor.balance.map { $0.remainingUSD.formatted(.currency(code: "USD")) } ?? "Unavailable").monospacedDigit()
                }
                if let balance = monitor.balance { LabeledContent("Updated", value: balance.fetchedAt.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Automatic balance", value: monitor.unofficialBalanceEnabled ? "On" : "Off")
            } footer: { Text("Uses a separate billing sign-in.") }
            Section {
                Button("Connect billing account") {
                    if monitor.unofficialBalanceEnabled { showingLogin = true }
                    else { showingWarning = true }
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44).disabled(preview)
                .tint(CodexiOSTheme.prominentTint).foregroundStyle(.white)
                .accessibilityIdentifier("ios.api.billingSignIn")
                if monitor.unofficialBalanceEnabled {
                    Button("Refresh balance") { monitor.refresh() }.disabled(monitor.isRefreshing || preview)
                    if monitor.isRefreshing { ProgressView("Refreshing…") }
                    Button("Disable automatic balance", role: .destructive) { showingLogin = false; monitor.setUnofficialBalanceEnabled(false) }.disabled(preview)
                }
                if !monitor.hasKey && !monitor.deletionPending {
                    Button("Remove saved browser sign-in", role: .destructive) {
                        showingLogin = false
                        monitor.setUnofficialBalanceEnabled(false)
                        Task { await OpenAIBillingWebsiteData.clear() }
                    }.disabled(preview)
                }
            }
            if let error = monitor.error ?? monitor.balanceError { Section { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) } }
            Section { Link("Open API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!) }
        }
        .navigationTitle("Prepaid balance").navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
        .alert("Enable unofficial balance access?", isPresented: $showingWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Enable unofficial balance") { monitor.setUnofficialBalanceEnabled(true); if monitor.unofficialBalanceEnabled { showingLogin = true } }
        } message: {
            Text("This is not an official or provider-approved method. It uses an undocumented billing endpoint and may breach account terms, resulting in account restrictions, suspension or a ban. Sign-in cookies persist in the app’s own browser storage across retries and restarts. Verified monitoring credentials stay in this device’s Keychain. Disable stops monitoring; Disconnect, Remove saved browser sign-in or Reset App also clears the browser login. Private endpoints may change or stop working. Enable only if you accept these risks.")
        }
        .sheet(isPresented: $showingLogin) {
            if monitor.unofficialBalanceEnabled && !preview {
                OpenAIBillingLoginView(isAuthorized: { monitor.unofficialBalanceEnabled && !preview }) { session, organization in
                    guard monitor.unofficialBalanceEnabled else { return }
                    monitor.saveKey(session, kind: .billingSession, organizationID: organization)
                }
            }
        }
        .onChange(of: monitor.unofficialBalanceEnabled) { _, enabled in if !enabled { showingLogin = false } }
    }
}

private struct CodexiOSAPIReportView: View {
    let monitor: OpenAIMonitorModel
    let preview: Bool
    var body: some View {
        Form {
            if let report = monitor.report {
                Section {
                    LabeledContent("Requests", value: report.usage.requests.formatted())
                    LabeledContent("Input tokens", value: report.usage.inputTokens.formatted())
                    LabeledContent("Cached input tokens", value: report.usage.cachedInputTokens.formatted())
                    LabeledContent("Output tokens", value: report.usage.outputTokens.formatted())
                } header: { Text("Usage") } footer: {
                    Text("\(report.usageStart.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted)). Input includes cached tokens.")
                }
                if !report.usage.byModel.isEmpty {
                    Section("Requests by model") {
                        ForEach(report.usage.byModel.keys.sorted(), id: \.self) { name in
                            LabeledContent(name, value: report.usage.byModel[name, default: 0].formatted())
                        }
                    }
                }
                Section {
                    if report.costsByCurrency.isEmpty { Text("No cost entries reported.").foregroundStyle(.secondary) }
                    ForEach(report.costsByCurrency.keys.sorted(), id: \.self) { currency in
                        LabeledContent("Cost (\(currency))", value: report.costsByCurrency[currency, default: 0].formatted(.currency(code: currency)))
                    }
                    LabeledContent("Updated", value: report.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                } header: { Text("Costs") } footer: {
                    Text("\(report.costStart.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted)). Reported spending may be delayed.")
                }
            } else {
                Section { Text("Connect an organization Admin key to view usage and cost reports.").foregroundStyle(.secondary) }
            }
            Section {
                Button("Refresh reports") { monitor.refresh() }.disabled(!monitor.hasKey || monitor.isRefreshing || preview)
                if monitor.isRefreshing { ProgressView("Refreshing…") }
                Link("Open API usage", destination: URL(string: "https://platform.openai.com/usage")!)
            }
            if let error = monitor.error { Section { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) } }
        }
        .navigationTitle("Usage and costs").navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
    }
}

#if DEBUG
/// Native render-test entry points; authentication and monitor behavior remain injected by the caller.
@MainActor enum CodexiOSConnectionDesignFixtures {
    static func key(monitor: OpenAIMonitorModel, initialKey: String = "") -> some View {
        CodexiOSAPIKeySetupView(monitor: monitor, preview: false, initialKey: initialKey)
    }

    static func balance(monitor: OpenAIMonitorModel) -> some View {
        CodexiOSPrepaidBalanceView(monitor: monitor, preview: false)
    }

    static func reports(monitor: OpenAIMonitorModel) -> some View {
        CodexiOSAPIReportView(monitor: monitor, preview: false)
    }
}
#endif
