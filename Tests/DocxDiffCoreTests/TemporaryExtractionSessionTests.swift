import Foundation
import XCTest
@testable import DocxDiffCore

final class TemporaryExtractionSessionTests: XCTestCase {
    func testLaunchSweepRemovesStaleSessionAndPreservesAnotherLiveProcess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let stale = sessions.appendingPathComponent("stale", isDirectory: true)
        let active = sessions.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try Data("101".utf8).write(to: stale.appendingPathComponent(".owner-pid"))
        try Data("202".utf8).write(to: active.appendingPathComponent(".owner-pid"))

        let session = TemporaryExtractionSession(
            baseURL: root,
            sessionID: "current",
            processID: 303,
            processIsRunning: { $0 == 202 }
        )
        try session.prepare()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.rootURL.path))

        session.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
    }

    func testExtractionDestinationsBelongToCurrentSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TemporaryExtractionSession(
            baseURL: root,
            sessionID: "current",
            processID: 303,
            processIsRunning: { _ in false }
        )

        let destination = try session.makeExtractionDestination()

        XCTAssertEqual(destination.deletingLastPathComponent(), session.rootURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testShutdownTerminatesThenWaitsForChildrenBeforeRemovingSessionRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TemporaryExtractionSession(
            baseURL: root,
            sessionID: "current",
            processID: 303,
            processIsRunning: { _ in false }
        )
        try session.prepare()
        let process = ControllableExtractionProcess(sessionRoot: session.rootURL)
        try session.start(process)

        session.cleanup()

        XCTAssertEqual(process.events, ["run", "terminate", "wait"])
        XCTAssertFalse(process.isRunning)
        XCTAssertTrue(process.rootExistedWhileWaiting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.rootURL.path))
        XCTAssertThrowsError(try session.start(ControllableExtractionProcess(sessionRoot: session.rootURL))) {
            XCTAssertEqual($0 as? DOCXError, .cancelled)
        }
    }

    func testShutdownLeavesNoRealChildProcessRunning() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TemporaryExtractionSession(
            baseURL: root,
            sessionID: "current",
            processID: 303,
            processIsRunning: { _ in false }
        )
        try session.prepare()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try session.start(process)
        XCTAssertTrue(process.isRunning)

        session.cleanup()

        XCTAssertFalse(process.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.rootURL.path))
    }
}

private final class ControllableExtractionProcess: ExtractionChildProcess, @unchecked Sendable {
    private let sessionRoot: URL
    private(set) var events: [String] = []
    private(set) var isRunning = false
    private(set) var rootExistedWhileWaiting = false
    var terminationStatus: Int32 { isRunning ? -1 : 0 }

    init(sessionRoot: URL) {
        self.sessionRoot = sessionRoot
    }

    func run() throws {
        events.append("run")
        isRunning = true
    }

    func terminate() {
        events.append("terminate")
    }

    func waitUntilExit() {
        events.append("wait")
        rootExistedWhileWaiting = FileManager.default.fileExists(atPath: sessionRoot.path)
        isRunning = false
    }
}
