import Foundation

public enum DOCXError: Error, Equatable, LocalizedError, Sendable {
    case invalidExtension
    case unreadableFile
    case encryptedDocument
    case invalidPackage
    case missingMainDocument
    case malformedXML(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidExtension:
            "The file must have a .docx extension."
        case .unreadableFile:
            "The DOCX file cannot be read."
        case .encryptedDocument:
            "Encrypted DOCX files are not supported."
        case .invalidPackage:
            "The file is not a valid DOCX package."
        case .missingMainDocument:
            "The DOCX package is missing word/document.xml."
        case let .malformedXML(message):
            "The DOCX contains malformed XML: \(message)"
        case .cancelled:
            "The operation was cancelled."
        }
    }
}

public final class TemporaryDOCXPackage: @unchecked Sendable {
    public let rootURL: URL
    private let lock = NSLock()
    private var cleaned = false

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        guard !cleaned else { return }
        try? FileManager.default.removeItem(at: rootURL)
        cleaned = true
    }

    deinit { cleanup() }
}

public struct DOCXExtractor: Sendable {
    private let session: TemporaryExtractionSession

    public init() {
        session = .shared
    }

    init(session: TemporaryExtractionSession) {
        self.session = session
    }

    public func extract(_ sourceURL: URL) throws -> TemporaryDOCXPackage {
        guard sourceURL.pathExtension.caseInsensitiveCompare("docx") == .orderedSame else {
            throw DOCXError.invalidExtension
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw DOCXError.unreadableFile
        }

        let fileManager = FileManager.default
        let destinationURL: URL
        do {
            destinationURL = try session.makeExtractionDestination()
        } catch let error as DOCXError {
            throw error
        } catch {
            throw DOCXError.invalidPackage
        }
        let extractionBaseURL = destinationURL.deletingLastPathComponent()
        var shouldCleanUp = true
        defer {
            if shouldCleanUp {
                try? fileManager.removeItem(at: destinationURL)
            }
        }

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        } catch {
            if session.isShuttingDown { throw DOCXError.cancelled }
            throw DOCXError.invalidPackage
        }

        guard !Task.isCancelled else {
            throw DOCXError.cancelled
        }

        let standardErrorURL = extractionBaseURL
            .appendingPathComponent(".\(UUID().uuidString).stderr")
        guard fileManager.createFile(atPath: standardErrorURL.path, contents: nil) else {
            throw DOCXError.invalidPackage
        }
        defer { try? fileManager.removeItem(at: standardErrorURL) }

        let standardErrorFileHandle: FileHandle
        do {
            standardErrorFileHandle = try FileHandle(forWritingTo: standardErrorURL)
        } catch {
            throw DOCXError.invalidPackage
        }
        defer { try? standardErrorFileHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", sourceURL.path, destinationURL.path]
        process.standardError = standardErrorFileHandle

        do {
            try session.start(process)
        } catch let error as DOCXError {
            throw error
        } catch {
            throw DOCXError.invalidPackage
        }
        defer { session.finish(process) }

        while process.isRunning {
            if Task.isCancelled {
                session.stopAndWaitForExit(process)
                throw DOCXError.cancelled
            }
            if session.isShuttingDown {
                // Session cleanup owns terminate/wait ordering for registered children.
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard !Task.isCancelled, !session.isShuttingDown else {
            throw DOCXError.cancelled
        }

        try? standardErrorFileHandle.close()

        guard process.terminationStatus == 0 else {
            let errorOutput = String(
                decoding: (try? Data(contentsOf: standardErrorURL)) ?? Data(),
                as: UTF8.self
            ).lowercased()
            if errorOutput.contains("password") || errorOutput.contains("encrypt") {
                throw DOCXError.encryptedDocument
            }
            throw DOCXError.invalidPackage
        }

        guard fileManager.fileExists(
            atPath: destinationURL.appendingPathComponent("word/document.xml").path
        ) else {
            throw DOCXError.missingMainDocument
        }

        shouldCleanUp = false
        return TemporaryDOCXPackage(rootURL: destinationURL)
    }
}
