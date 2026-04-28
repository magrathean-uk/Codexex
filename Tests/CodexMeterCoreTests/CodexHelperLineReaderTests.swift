import Foundation
import XCTest
@testable import CodexMeterCore

final class CodexHelperLineReaderTests: XCTestCase {
    func testReadLineTimesOutWhenHelperDoesNotEmitNewline() throws {
        let pipe = Pipe()
        defer {
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
        }

        XCTAssertThrowsError(
            try CodexHelperLineReader.readLine(
                from: pipe.fileHandleForReading,
                timeout: 0.05,
                maxBytes: 32
            )
        ) { error in
            XCTAssertEqual(error as? CodexHelperLineReaderError, .timeout)
        }
    }

    func testReadLineRejectsOversizedHelperOutput() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data("abcdef\n".utf8))
        pipe.fileHandleForWriting.closeFile()
        defer {
            pipe.fileHandleForReading.closeFile()
        }

        XCTAssertThrowsError(
            try CodexHelperLineReader.readLine(
                from: pipe.fileHandleForReading,
                timeout: 1,
                maxBytes: 4
            )
        ) { error in
            XCTAssertEqual(error as? CodexHelperLineReaderError, .responseTooLarge)
        }
    }
}
