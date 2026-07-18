import Darwin
import Foundation

protocol ExtractionChildProcess: AnyObject {
    var isRunning: Bool { get }
    func run() throws
    func terminate()
    func waitUntilExit()
}

extension Process: ExtractionChildProcess {}

/// Owns one process session under the app's temporary root. Extracted packages live
/// below this directory so a normal quit can clean them together and a later launch
/// can safely sweep sessions whose owner process is no longer running.
public final class TemporaryExtractionSession: @unchecked Sendable {
    public static let shared = TemporaryExtractionSession()

    public let rootURL: URL

    private let sessionsURL: URL
    private let sessionID: String
    private let processID: Int32
    private let processIsRunning: @Sendable (Int32) -> Bool
    private let fileManager: FileManager
    private let lifecycle = NSCondition()
    private var isPrepared = false
    private var state = State.active
    private var activeProcesses: [ObjectIdentifier: ChildRecord] = [:]

    private convenience init() {
        self.init(
            baseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("DocxDiff", isDirectory: true),
            sessionID: UUID().uuidString,
            processID: getpid(),
            processIsRunning: Self.liveProcessCheck
        )
    }

    init(
        baseURL: URL,
        sessionID: String,
        processID: Int32,
        processIsRunning: @escaping @Sendable (Int32) -> Bool,
        fileManager: FileManager = .default
    ) {
        let sessionsURL = baseURL.appendingPathComponent("sessions", isDirectory: true)
        self.sessionsURL = sessionsURL
        self.sessionID = sessionID
        self.processID = processID
        self.processIsRunning = processIsRunning
        self.fileManager = fileManager
        rootURL = sessionsURL.appendingPathComponent(sessionID, isDirectory: true)
    }

    public func prepare() throws {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        guard state == .active else { throw DOCXError.cancelled }
        guard !isPrepared else { return }

        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        try sweepStaleSessions()

        if !fileManager.fileExists(atPath: rootURL.path) {
            // Hidden staging avoids a concurrent launch sweeping a directory before
            // its ownership marker is durable.
            let stagingURL = sessionsURL.appendingPathComponent(
                ".creating-\(sessionID)-\(UUID().uuidString)",
                isDirectory: true
            )
            do {
                try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
                try Data(String(processID).utf8).write(
                    to: stagingURL.appendingPathComponent(".owner-pid"),
                    options: .atomic
                )
                try fileManager.moveItem(at: stagingURL, to: rootURL)
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
        }
        isPrepared = true
    }

    func makeExtractionDestination() throws -> URL {
        try prepare()
        return rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func start(_ process: any ExtractionChildProcess) throws {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        guard state == .active else { throw DOCXError.cancelled }

        // Launch while holding the lifecycle lock. Cleanup cannot take its child
        // snapshot between process launch and registration.
        try process.run()
        activeProcesses[ObjectIdentifier(process)] = ChildRecord(process: process)
    }

    func finish(_ process: any ExtractionChildProcess) {
        lifecycle.lock()
        activeProcesses[ObjectIdentifier(process)] = nil
        lifecycle.unlock()
    }

    func stopAndWaitForExit(_ process: any ExtractionChildProcess) {
        lifecycle.lock()
        let record = activeProcesses[ObjectIdentifier(process)]
        lifecycle.unlock()
        record?.requestTermination()
        record?.waitUntilExit()
    }

    var isShuttingDown: Bool {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        return state != .active
    }

    public func cleanup() {
        lifecycle.lock()
        while state == .shuttingDown {
            lifecycle.wait()
        }
        guard state != .finished else {
            lifecycle.unlock()
            return
        }
        state = .shuttingDown
        let processes = Array(activeProcesses.values)
        lifecycle.unlock()

        // Stop every child before waiting for any child. Only after all waits
        // complete is it safe to remove paths a child may still be writing.
        for process in processes {
            process.requestTermination()
        }
        for process in processes {
            process.waitUntilExit()
        }
        try? fileManager.removeItem(at: rootURL)

        lifecycle.lock()
        activeProcesses.removeAll()
        isPrepared = false
        state = .finished
        lifecycle.broadcast()
        lifecycle.unlock()
    }

    private func sweepStaleSessions() throws {
        let sessionURLs = try fileManager.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for candidate in sessionURLs where candidate.lastPathComponent != sessionID {
            let ownerURL = candidate.appendingPathComponent(".owner-pid")
            let ownerPID = (try? String(contentsOf: ownerURL, encoding: .utf8))
                .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let ownerPID, ownerPID > 0, processIsRunning(ownerPID) {
                continue
            }
            try? fileManager.removeItem(at: candidate)
        }
    }

    private static func defaultProcessIsRunning(_ processID: Int32) -> Bool {
        guard processID > 0 else { return false }
        if kill(processID, 0) == 0 { return true }
        return errno == EPERM
    }

    private static let liveProcessCheck: @Sendable (Int32) -> Bool = { processID in
        defaultProcessIsRunning(processID)
    }

    private enum State {
        case active
        case shuttingDown
        case finished
    }

    private final class ChildRecord: @unchecked Sendable {
        private let process: any ExtractionChildProcess
        private let condition = NSCondition()
        private var terminationRequested = false
        private var isWaiting = false
        private var didWait = false

        init(process: any ExtractionChildProcess) {
            self.process = process
        }

        func requestTermination() {
            condition.lock()
            defer { condition.unlock() }
            guard !terminationRequested else { return }
            terminationRequested = true
            if process.isRunning { process.terminate() }
        }

        func waitUntilExit() {
            condition.lock()
            while isWaiting, !didWait {
                condition.wait()
            }
            guard !didWait else {
                condition.unlock()
                return
            }
            isWaiting = true
            condition.unlock()

            process.waitUntilExit()

            condition.lock()
            didWait = true
            isWaiting = false
            condition.broadcast()
            condition.unlock()
        }
    }
}
