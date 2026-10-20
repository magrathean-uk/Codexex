import SwiftUI
import WebKit

@MainActor enum OpenAIBillingWebsiteData {
    private static let identifier = UUID(uuidString: "0844C977-8F32-48D0-B10E-9E677E93A834")!
    static var store: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: identifier) }
    static func clear() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

/// Only instantiated after the user accepts the unofficial-monitoring disclosure.
struct OpenAIBillingLoginView: View {
    let isAuthorized: @MainActor () -> Bool
    let onSession: @MainActor (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var received = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unofficial OpenAI balance sign-in").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            Text("Not an official or provider-approved method. Account restrictions, suspension or a ban are possible. Your password is handled by OpenAI. Sign-in cookies stay in the app’s own browser storage across retries and restarts; verified monitoring credentials stay in this device’s Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            if isAuthorized() {
                OpenAIBillingBrowser(isAuthorized: isAuthorized) { token, organizationID in
                    guard isAuthorized(), !received else { return }
                    received = true
                    onSession(token, organizationID)
                    dismiss()
                }
            } else {
                Text("Unofficial monitoring is disabled.")
            }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 600)
        #endif
        .onChange(of: isAuthorized()) { _, allowed in
            if !allowed { dismiss() }
        }
    }
}

private struct OpenAIBillingBrowser {
    let isAuthorized: @MainActor () -> Bool
    let onSession: @MainActor (String, String?) -> Void

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let isAuthorized: @MainActor () -> Bool
        let onSession: @MainActor (String, String?) -> Void
        private var delivered = false
        init(isAuthorized: @escaping @MainActor () -> Bool, onSession: @escaping @MainActor (String, String?) -> Void) {
            self.isAuthorized = isAuthorized; self.onSession = onSession
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard isAuthorized(), !delivered, message.name == "billingSession", message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.protocol == "https",
                  message.frameInfo.securityOrigin.host == "platform.openai.com",
                  let body = message.body as? [String: Any], let token = body["token"] as? String,
                  token.hasPrefix("sess-"), (10...4096).contains(token.utf8.count),
                  token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { return }
            let organizationID = body["organizationID"] as? String
            if let organizationID {
                guard organizationID.hasPrefix("org-"), (5...128).contains(organizationID.utf8.count),
                      organizationID.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || $0 == "-" || $0 == "_" }) else { return }
            }
            delivered = true
            onSession(token, organizationID)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            isAuthorized() && action.request.url?.scheme == "https" ? .allow : .cancel
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if isAuthorized(), action.targetFrame == nil, action.request.url?.scheme == "https" {
                webView.load(action.request)
            }
            return nil
        }
    }

    @MainActor func makeBrowser(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        guard isAuthorized() else { return WKWebView(frame: .zero, configuration: configuration) }
        configuration.websiteDataStore = OpenAIBillingWebsiteData.store
        configuration.userContentController.add(context.coordinator, name: "billingSession")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.observer,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = context.coordinator
        browser.uiDelegate = context.coordinator
        browser.load(URLRequest(url: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!))
        return browser
    }

    @MainActor static func deactivate(_ browser: WKWebView) {
        browser.configuration.userContentController.removeScriptMessageHandler(forName: "billingSession")
        browser.configuration.userContentController.removeAllUserScripts()
        browser.evaluateJavaScript("window.__codexexDisableBillingObserver?.()", completionHandler: nil)
        browser.stopLoading()
    }

    // Observes only the page's outgoing billing authorization, never password fields or responses.
    static let observer = #"""
    (() => {
      if (location.origin !== 'https://platform.openai.com') return;
      let delivered = false;
      let disabled = false;
      function billing(url) {
        try {
          const u = new URL(url, location.href);
          return u.origin === 'https://api.openai.com' &&
            /^\/(v1\/)?dashboard\/billing\//.test(u.pathname);
        } catch (_) { return false; }
      }
      function capture(value, organizationID) {
        if (disabled || delivered || typeof value !== 'string' || !value.startsWith('Bearer sess-')) return;
        const token = value.slice(7);
        if (token.length < 10 || token.length > 4096 || /[^\x21-\x7e]/.test(token)) return;
        if (organizationID != null && !/^org-[A-Za-z0-9_-]{1,124}$/.test(organizationID)) return;
        delivered = true;
        window.webkit.messageHandlers.billingSession.postMessage({token, organizationID: organizationID || null});
      }
      const originalFetch = window.fetch;
      window.fetch = function(input, options) {
        try {
          if (billing(typeof input === 'string' || input instanceof URL ? String(input) : input.url)) {
            const headers = new Headers(options && options.headers ? options.headers : input.headers);
            capture(headers.get('Authorization'), headers.get('OpenAI-Organization'));
          }
        } catch (_) {}
        return originalFetch.apply(this, arguments);
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalHeader = XMLHttpRequest.prototype.setRequestHeader;
      const originalSend = XMLHttpRequest.prototype.send;
      const requestHeaders = new WeakMap();
      const eligible = new WeakSet();
      XMLHttpRequest.prototype.open = function(method, url) {
        eligible.delete(this);
        requestHeaders.set(this, {});
        if (billing(url)) eligible.add(this);
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (eligible.has(this)) requestHeaders.get(this)[String(name).toLowerCase()] = String(value);
        return originalHeader.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        if (eligible.has(this)) {
          const headers = requestHeaders.get(this);
          capture(headers.authorization, headers['openai-organization']);
        }
        return originalSend.apply(this, arguments);
      };
      window.__codexexDisableBillingObserver = function() {
        disabled = true;
        window.fetch = originalFetch;
        XMLHttpRequest.prototype.open = originalOpen;
        XMLHttpRequest.prototype.setRequestHeader = originalHeader;
        XMLHttpRequest.prototype.send = originalSend;
      };
    })();
    """#
}

#if os(macOS)
extension OpenAIBillingBrowser: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(isAuthorized: isAuthorized, onSession: onSession) }
    func makeNSView(context: Context) -> WKWebView { makeBrowser(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { if !isAuthorized() { Self.deactivate(view) } }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        Self.deactivate(view)
        view.navigationDelegate = nil; view.uiDelegate = nil
    }
}
#else
extension OpenAIBillingBrowser: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(isAuthorized: isAuthorized, onSession: onSession) }
    func makeUIView(context: Context) -> WKWebView { makeBrowser(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { if !isAuthorized() { Self.deactivate(view) } }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        Self.deactivate(view)
        view.navigationDelegate = nil; view.uiDelegate = nil
    }
}
#endif
