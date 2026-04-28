import Foundation
import CodexMeterCore

protocol CodexHelperSession: AnyObject {
    func send(_ request: CodexHelperRequest) throws -> CodexHelperResponseEnvelope
    func reset()
}

final class CodexHelperProcessSession: CodexHelperSession {
    private let process: CodexHelperProcess
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(process: CodexHelperProcess = CodexHelperProcess()) {
        self.process = process
    }

    func send(_ request: CodexHelperRequest) throws -> CodexHelperResponseEnvelope {
        let data = try encoder.encode(request)
        let line = String(decoding: data, as: UTF8.self)
        let response = try process.send(line)
        do {
            return try decoder
                .decode(CodexHelperResponseEnvelope.self, from: Data(response.utf8))
                .validated(against: request)
        } catch {
            process.reset()
            throw error
        }
    }

    func reset() {
        process.reset()
    }
}
