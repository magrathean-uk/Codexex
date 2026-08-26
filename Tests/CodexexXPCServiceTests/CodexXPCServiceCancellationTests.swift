import Foundation
import XCTest
import CodexMeterCore

@MainActor
final class CodexXPCServiceCancellationTests: XCTestCase {
    func testPersistedDeviceAuthCancellationUsesTypedHelperRequest() async {
        let helper = CancelRecordingHelperSession()
        let service = CodexXPCService(helper: helper)
        let cancelled = expectation(description: "persisted flow cancelled")
        let flowID = "abcdefghijklmnopqrstuvwxyzABCDEFGH123456789"

        service.cancelChatGPTSignIn(flowID: flowID) { error in
            XCTAssertNil(error)
            cancelled.fulfill()
        }

        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(helper.request?.method, .cancelDeviceAuth)
        XCTAssertEqual(helper.request?.flowID, flowID)
    }

    func testCancelInterruptsBlockedSendDrainsBeforeNextSendAndKeepsSessionReusable() async throws {
        let helper = BlockingHelperSession()
        let service = CodexXPCService(helper: helper)
        let events = LockedEvents()
        let firstReply = expectation(description: "blocked send interrupted")
        let cancelDrained = expectation(description: "cancel drain barrier")
        let secondReply = expectation(description: "next send succeeds")

        service.fetchSnapshot { data, error in
            XCTAssertNil(data)
            XCTAssertNotNil(error)
            events.append("first reply")
            firstReply.fulfill()
        }
        XCTAssertTrue(helper.waitUntilFirstSendStarts(timeout: 1))

        service.cancelPendingOperations {
            events.append("cancel drained")
            cancelDrained.fulfill()
        }
        service.fetchSnapshot { data, error in
            XCTAssertNil(error)
            do {
                let data = try XCTUnwrap(data)
                let response = try JSONDecoder().decode(CodexServiceSnapshotResponse.self, from: data)
                XCTAssertEqual(response, BlockingHelperSession.successfulResponse)
            } catch {
                XCTFail("Could not decode next response: \(error)")
            }
            events.append("second reply")
            secondReply.fulfill()
        }

        await fulfillment(of: [firstReply, cancelDrained, secondReply], timeout: 3)

        XCTAssertEqual(events.values, ["first reply", "cancel drained", "second reply"])
        XCTAssertEqual(helper.counts.send, 2)
        XCTAssertEqual(helper.counts.reset, 1)
    }

    func testRapidSecondCancelInterruptsNewSendAndKeepsFollowingSendReusable() async throws {
        let helper = BlockingHelperSession(blockedSendCount: 2)
        let service = CodexXPCService(helper: helper)
        let events = LockedEvents()
        let firstReply = expectation(description: "first send interrupted")
        let firstDrain = expectation(description: "first cancel drained")

        service.fetchSnapshot { _, error in
            XCTAssertNotNil(error)
            events.append("first reply")
            firstReply.fulfill()
        }
        XCTAssertTrue(helper.waitUntilSendStarts(1, timeout: 1))
        service.cancelPendingOperations {
            events.append("first drain")
            firstDrain.fulfill()
        }
        await fulfillment(of: [firstReply, firstDrain], timeout: 3)

        let secondReply = expectation(description: "second send interrupted")
        let secondDrain = expectation(description: "second cancel drained")
        let thirdReply = expectation(description: "third send succeeds")
        service.fetchSnapshot { _, error in
            XCTAssertNotNil(error)
            events.append("second reply")
            secondReply.fulfill()
        }
        XCTAssertTrue(helper.waitUntilSendStarts(2, timeout: 1))
        service.cancelPendingOperations {
            events.append("second drain")
            secondDrain.fulfill()
        }
        service.fetchSnapshot { data, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            events.append("third reply")
            thirdReply.fulfill()
        }

        await fulfillment(of: [secondReply, secondDrain, thirdReply], timeout: 3)

        XCTAssertEqual(
            events.values,
            ["first reply", "first drain", "second reply", "second drain", "third reply"]
        )
        XCTAssertEqual(helper.counts.send, 3)
        XCTAssertEqual(helper.counts.reset, 2)
    }

    func testResetDuringLaunchCancelsUnpublishedProcessAndNextSendSucceeds() async throws {
        let launchGate = FirstLaunchGate()
        let process = CodexHelperProcess(
            helperURLProvider: { URL(fileURLWithPath: "/bin/cat") },
            beforePublishingLaunch: { launchGate.pauseFirstLaunch() }
        )
        let outcome = LockedSendOutcome()
        let firstSendFinished = expectation(description: "launch-raced send finishes")

        DispatchQueue.global().async {
            do {
                outcome.record(value: try process.send("first"))
            } catch {
                outcome.record(error: error)
            }
            firstSendFinished.fulfill()
        }
        XCTAssertEqual(launchGate.waitUntilPaused(timeout: 1), .success)

        process.reset()
        launchGate.resume()
        await fulfillment(of: [firstSendFinished], timeout: 3)

        XCTAssertNil(outcome.value)
        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(try process.send("second"), "second")
        process.reset()
    }
}

private final class CancelRecordingHelperSession: CodexHelperSession {
    private let lock = NSLock()
    private var storedRequest: CodexHelperRequest?

    func send(_ request: CodexHelperRequest) throws -> CodexHelperResponseEnvelope {
        lock.lock()
        storedRequest = request
        lock.unlock()
        return CodexHelperResponseEnvelope(
            requestID: request.requestID,
            type: .deviceAuthCancelled
        )
    }

    func reset() {}

    var request: CodexHelperRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }
}

private final class BlockingHelperSession: CodexHelperSession {
    static let successfulResponse = CodexServiceSnapshotResponse(
        authMode: .chatGPT,
        snapshot: nil,
        errorMessage: "test response"
    )

    private let condition = NSCondition()
    private var sendCount = 0
    private var resetCount = 0
    private var firstSendStarted = false
    private let blockedSendCount: Int

    init(blockedSendCount: Int = 1) {
        self.blockedSendCount = blockedSendCount
    }

    func send(_ request: CodexHelperRequest) throws -> CodexHelperResponseEnvelope {
        condition.lock()
        sendCount += 1
        let currentSend = sendCount
        if currentSend <= blockedSendCount {
            if currentSend == 1 { firstSendStarted = true }
            condition.broadcast()
            let deadline = Date().addingTimeInterval(2)
            while resetCount < currentSend, condition.wait(until: deadline) {}
            let wasReset = resetCount >= currentSend
            condition.unlock()
            guard wasReset else { throw FakeHelperError.timedOut }
            throw FakeHelperError.cancelled
        }
        condition.unlock()

        let payload = try JSONEncoder().encode(Self.successfulResponse)
        return CodexHelperResponseEnvelope(
            requestID: request.requestID,
            type: .snapshot,
            payloadJSON: String(decoding: payload, as: UTF8.self)
        )
    }

    func reset() {
        condition.lock()
        resetCount += 1
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilFirstSendStarts(timeout: TimeInterval) -> Bool {
        waitUntilSendStarts(1, timeout: timeout)
    }

    func waitUntilSendStarts(_ expectedCount: Int, timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while sendCount < expectedCount {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    var counts: (send: Int, reset: Int) {
        condition.lock()
        defer { condition.unlock() }
        return (sendCount, resetCount)
    }
}

private final class FirstLaunchGate: @unchecked Sendable {
    private let lock = NSLock()
    private let paused = DispatchSemaphore(value: 0)
    private let resumed = DispatchSemaphore(value: 0)
    private var launchCount = 0

    func pauseFirstLaunch() {
        lock.lock()
        launchCount += 1
        let shouldPause = launchCount == 1
        lock.unlock()
        guard shouldPause else { return }
        paused.signal()
        resumed.wait()
    }

    func waitUntilPaused(timeout: TimeInterval) -> DispatchTimeoutResult {
        paused.wait(timeout: .now() + timeout)
    }

    func resume() {
        resumed.signal()
    }
}

private final class LockedSendOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: String?
    private var storedError: Error?

    func record(value: String) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func record(error: Error) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

private enum FakeHelperError: Error {
    case cancelled
    case timedOut
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
