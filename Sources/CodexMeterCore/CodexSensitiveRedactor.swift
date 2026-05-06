import Foundation

public enum CodexSensitiveRedactor: Sendable {
    public static func redacted(_ value: String) -> String {
        guard value.isEmpty == false else { return value }
        var output = value
        for rule in rules {
            output = rule.apply(to: output)
        }
        return output
    }

    public static func redactedOptional(_ value: String?) -> String? {
        value.map(redacted(_:))
    }

    public static func safeErrorDescription(_ error: Error) -> String {
        redacted(error.localizedDescription)
    }

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String

        init(_ pattern: String, replacement: String, options: NSRegularExpression.Options = []) {
            do {
                self.regex = try NSRegularExpression(pattern: pattern, options: options)
                self.replacement = replacement
            } catch {
                preconditionFailure("Invalid sensitive redaction regex: \(pattern)")
            }
        }

        func apply(to input: String) -> String {
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
        }
    }

    private static let sensitiveJSONKey = #"(?i)([\"']?(?:access_token|refresh_token|id_token|authorization_code|code_verifier|device_auth_id|account_id|chatgpt_account_id|user_code|flow_id)[\"']?\s*[:=]\s*[\"']?)[^\"'\s,&}]+"#
    private static let sensitiveQueryValue = #"(?i)([?&](?:access_token|refresh_token|id_token|authorization_code|code|code_verifier|device_auth_id|account_id|chatgpt_account_id|user_code|flow_id)=)[^&#\s]+"#

    private static let rules: [Rule] = [
        Rule(#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}"#, replacement: "Bearer <redacted>"),
        Rule(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#, replacement: "<jwt>"),
        Rule(sensitiveJSONKey, replacement: "$1<redacted>"),
        Rule(sensitiveQueryValue, replacement: "$1<redacted>"),
        Rule(#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, replacement: "<email>"),
        Rule(#"\b(?:acc|acct|account|org|user)_[A-Za-z0-9_-]{8,}\b"#, replacement: "<account-id>"),
        Rule(#"\b[A-Z0-9]{4,8}-[A-Z0-9]{4,8}\b"#, replacement: "<device-code>")
    ]
}
