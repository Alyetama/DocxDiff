import Foundation
import XCTest
@testable import DocxDiffCore

final class DOCXExtractorTests: XCTestCase {
    func testExtractsMainDocument() throws {
        let docx = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Hello"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: docx) }

        let package = try DOCXExtractor().extract(docx)
        defer { package.cleanup() }

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.rootURL.appendingPathComponent("word/document.xml").path
        ))
    }

    func testCleanupRemovesExtractedDirectory() throws {
        let docx = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Hello"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: docx) }

        let package = try DOCXExtractor().extract(docx)
        let root = package.rootURL

        package.cleanup()
        package.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testRejectsNonDOCXExtension() {
        XCTAssertThrowsError(try DOCXExtractor().extract(URL(fileURLWithPath: "/tmp/file.txt"))) {
            XCTAssertEqual($0 as? DOCXError, .invalidExtension)
        }
    }

    func testMissingMainDocumentDoesNotLeaveExtractionDirectory() throws {
        let docx = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Hello"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: docx) }
        try removeMainDocument(from: docx)
        let directoriesBeforeExtraction = try extractionDirectoryNames()

        XCTAssertThrowsError(try DOCXExtractor().extract(docx)) {
            XCTAssertEqual($0 as? DOCXError, .missingMainDocument)
        }

        XCTAssertEqual(try extractionDirectoryNames(), directoriesBeforeExtraction)
    }

    func testPreCancelledExtractionReturnsCancelledWithoutCreatingDirectory() async throws {
        let docx = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Hello"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: docx) }
        let directoriesBeforeExtraction = try extractionDirectoryNames()

        let task = Task { () throws -> TemporaryDOCXPackage in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                // Continue with a known-cancelled task so extraction observes cancellation itself.
            }
            return try DOCXExtractor().extract(docx)
        }
        task.cancel()

        do {
            let package = try await task.value
            package.cleanup()
            XCTFail("Expected a pre-cancelled extraction to throw DOCXError.cancelled")
        } catch {
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }

        XCTAssertEqual(try extractionDirectoryNames(), directoriesBeforeExtraction)
    }

    func testExtractionAfterSessionShutdownReturnsCancelled() throws {
        let docx = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Hello"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: docx) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DOCXExtractorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TemporaryExtractionSession(
            baseURL: root,
            sessionID: "current",
            processID: 303,
            processIsRunning: { _ in false }
        )
        try session.prepare()
        session.cleanup()

        XCTAssertThrowsError(try DOCXExtractor(session: session).extract(docx)) {
            XCTAssertEqual($0 as? DOCXError, .cancelled)
        }
    }

    private func removeMainDocument(from docx: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-d", docx.path, "word/document.xml"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func extractionDirectoryNames() throws -> Set<String> {
        try TemporaryExtractionSession.shared.prepare()
        let root = TemporaryExtractionSession.shared.rootURL
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true ? url.lastPathComponent : nil
        })
    }
}
