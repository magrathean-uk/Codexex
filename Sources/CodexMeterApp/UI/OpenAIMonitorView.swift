import SwiftUI
import CodexMeterCore

struct OpenAIMonitorView: View {
    let monitor: OpenAIMonitorModel
    var configuration = true
    var preview = false
    @State private var key = ""
    @State private var kind: OpenAIAPIKeyKind = .regular
    @State private var showingUnofficialWarning = false
    @State private var showingBillingLogin = false
    @State private var openLoginAfterConsent = false

    var body: some View {
        Group {
            if configuration { expandedContent }
            else { compactContent }
        }
        .buttonStyle(OpenAIActionButtonStyle())
        .onAppear { if !preview { kind = monitor.keyKind == .billingSession && !monitor.unofficialBalanceEnabled ? .regular : monitor.keyKind; monitor.refresh() } }
        .onChange(of: monitor.unofficialBalanceEnabled) { _, enabled in
            if !enabled { showingBillingLogin = false; if kind == .billingSession { kind = .regular } }
        }
        .alert("Enable unofficial balance access?", isPresented: $showingUnofficialWarning) {
            Button("Cancel", role: .cancel) { openLoginAfterConsent = false }
            Button("Enable unofficial balance") {
                monitor.setUnofficialBalanceEnabled(true)
                guard monitor.unofficialBalanceEnabled else { return }
                if openLoginAfterConsent { showingBillingLogin = true }
                else { monitor.refresh() }
                openLoginAfterConsent = false
            }
        } message: {
            Text("This is not an official or provider-approved method. It uses an undocumented billing endpoint and may breach account terms, resulting in account restrictions, suspension or a ban. Sign-in cookies persist in the app’s own browser storage across retries and restarts. Verified monitoring credentials stay in this device’s Keychain. Disable stops monitoring; Disconnect, Remove saved browser sign-in or Reset App also clears the browser login. Private endpoints may change or stop working. Enable only if you accept these risks.")
        }
        .sheet(isPresented: $showingBillingLogin) {
            if monitor.unofficialBalanceEnabled && !preview {
                OpenAIBillingLoginView(isAuthorized: { monitor.unofficialBalanceEnabled && !preview }) { session, organizationID in
                    guard monitor.unofficialBalanceEnabled else { return }
                    kind = .billingSession
                    monitor.saveKey(session, kind: .billingSession, organizationID: organizationID)
                }
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("OpenAI API", systemImage: "chart.bar.xaxis").font(.system(size: 16, weight: .semibold))
            Text("API billing is separate from your ChatGPT / Codex subscription. Monitoring sends read-only requests and never generates content.")
                .font(.caption).foregroundStyle(.secondary)
            if preview {
                Text("Preview — no API requests or credential changes.").font(.caption)
            } else {
                if monitor.hasKey {
                    VStack(alignment: .leading, spacing: 4) {
                        if let balance = monitor.balance {
                            Text(balance.remainingUSD.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))))
                                .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("remaining · unofficial balance source").font(.subheadline).foregroundStyle(.secondary)
                            Text("Checked \(balance.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            Text(monitor.organizationID.map { "Organization: \($0)" } ?? "Default billing organization").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("$ —").font(.system(size: 32, weight: .semibold, design: .rounded))
                            Text("remaining · balance unavailable").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let error = monitor.balanceError { Text(error).font(.caption).foregroundStyle(.secondary) }
                    if configuration {
                    Label(monitor.isValidated ? (monitor.keyKind == .billingSession ? "Unofficial billing connection verified" : "Read-only API connection verified") : "Credential saved; connection not verified", systemImage: monitor.isValidated ? "checkmark.shield" : "key")
                    if let date = monitor.validatedAt { Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let report = monitor.report {
                        Text("Organization text-generation usage").font(.subheadline.bold())
                        Text("Last successful report: \(report.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text("\(report.usageStart.formatted(date: .abbreviated, time: .shortened)) – \(report.end.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        LabeledContent("Requests", value: report.usage.requests.formatted())
                        LabeledContent("Input tokens (includes cached)", value: report.usage.inputTokens.formatted())
                        LabeledContent("Cached input tokens", value: report.usage.cachedInputTokens.formatted())
                        LabeledContent("Output tokens", value: report.usage.outputTokens.formatted())
                        ForEach(report.usage.byModel.keys.sorted(), id: \.self) { model in
                            LabeledContent("\(model) requests", value: report.usage.byModel[model, default: 0].formatted())
                        }
                        Text("Organization costs: \(report.costStart.formatted(date: .abbreviated, time: .shortened)) – \(report.end.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        if report.costsByCurrency.isEmpty { Text("No cost entries reported for this period.").font(.caption) }
                        ForEach(report.costsByCurrency.keys.sorted(), id: \.self) { currency in
                            LabeledContent("Reported cost (\(currency))", value: report.costsByCurrency[currency, default: 0].formatted(.currency(code: currency)))
                        }
                        Text("Reports may be delayed. Reported costs are spending, not dollars remaining.").font(.caption).foregroundStyle(.secondary)
                    } else if configuration {
                        Text("Organization usage and cost reports need an Admin API key. Public API access does not establish a credit balance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(monitor.isRefreshing ? "Checking…" : "Refresh") { monitor.refresh() }.disabled(monitor.isRefreshing)
                }
                if let error = monitor.error { Text(error).font(.caption).foregroundStyle(.red) }
                Divider()
                if monitor.unofficialBalanceEnabled {
                    Label("Unofficial balance access enabled", systemImage: "exclamationmark.triangle").font(.subheadline)
                    Text("Not an official or provider-approved method. Account restrictions, suspension or a ban are possible. Private billing endpoints can change.").font(.caption).foregroundStyle(.secondary)
                    Button("Sign in for $ remaining") { showingBillingLogin = true }
                    Button("Disable unofficial balance", role: .destructive) {
                        showingBillingLogin = false
                        monitor.setUnofficialBalanceEnabled(false)
                        if kind == .billingSession { kind = .regular }
                    }
                } else {
                    Text("$ remaining — unofficial monitoring off").font(.title3.weight(.semibold))
                    Button("Review unofficial balance option") { openLoginAfterConsent = true; showingUnofficialWarning = true }
                    Text("Off by default. Review the account-risk warning before enabling this option.").font(.caption).foregroundStyle(.secondary)
                }
                if configuration {
                    Divider()
                    Picker("Key type", selection: $kind) {
                        Text("Standard API key").tag(OpenAIAPIKeyKind.regular)
                        Text("Organization Admin key").tag(OpenAIAPIKeyKind.admin)
                        if monitor.unofficialBalanceEnabled { Text("Billing session token").tag(OpenAIAPIKeyKind.billingSession) }
                    }
                    Text(kind == .billingSession ? "Use your OpenAI billing session token (sess-). It grants account access, stays in this device’s Keychain, and may expire. This balance route is unofficial." : "Standard keys verify Models access. Select Admin only for an organization Admin API key with reporting permission. Balance requests run only after explicit consent to unofficial access.").font(.caption).foregroundStyle(.secondary)
                    SecureField(kind == .billingSession ? "Billing session token" : "API key", text: $key)
                    HStack {
                        Button("Save and verify") { monitor.saveKey(key, kind: kind); key = "" }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if monitor.hasKey || monitor.deletionPending { Button(monitor.deletionPending ? "Retry key removal" : "Disconnect", role: .destructive) {
                            showingBillingLogin = false
                            monitor.setUnofficialBalanceEnabled(false)
                            monitor.disconnect()
                            Task { await OpenAIBillingWebsiteData.clear() }
                        } }
                    }
                    Text("API credentials stay in this device’s Keychain. Billing sign-in cookies stay in the app’s own browser storage. Neither is synced or sent to Magrathean.").font(.caption).foregroundStyle(.secondary)
                    if !monitor.hasKey && !monitor.deletionPending {
                        Button("Remove saved browser sign-in", role: .destructive) {
                            showingBillingLogin = false
                            monitor.setUnofficialBalanceEnabled(false)
                            Task { await OpenAIBillingWebsiteData.clear() }
                        }
                    }
                }
            }
            Link("Open API usage dashboard", destination: URL(string: "https://platform.openai.com/usage")!)
                .font(.caption).buttonStyle(.plain)
            Link("Open API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                .font(.caption).buttonStyle(.plain)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OpenAI API", systemImage: "chart.bar.xaxis")
                .font(.system(size: 16, weight: .semibold))
            Text(monitor.balance.map { $0.remainingUSD.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) + " remaining" } ?? "Balance unavailable")
                .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(compactStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactStatus: String {
        let source = monitor.unofficialBalanceEnabled ? " · Unofficial" : ""
        if monitor.isRefreshing { return "Checking…" + source }
        if monitor.error != nil || (monitor.unofficialBalanceEnabled && monitor.balanceError != nil) { return "Update failed · see Settings" + source }
        if let date = monitor.balance?.fetchedAt ?? monitor.validatedAt {
            return "Updated " + date.formatted(date: .omitted, time: .shortened) + source
        }
        return "Connection details in Settings" + source
    }
}

private struct OpenAIActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            #if os(macOS)
            .frame(minHeight: 30)
            #else
            .frame(minHeight: 44)
            #endif
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
    }
}
