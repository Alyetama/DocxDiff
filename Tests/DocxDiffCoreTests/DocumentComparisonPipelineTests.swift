import Foundation
import XCTest
@testable import DocxDiffCore

final class DocumentComparisonPipelineTests: XCTestCase {
    func testIdenticalRelevantContentReturnsZeroChanges() async throws {
        let fixture = DOCXFixtureBuilder.DocumentFixture(
            documentXML: DOCXFixtureBuilder.document(paragraphs: [
                "Introduction",
                "The result is unchanged."
            ])
        )
        let pair = try DOCXFixtureBuilder.pair(original: fixture, revised: fixture)
        defer { pair.cleanup() }
        let temporaryPackagesBefore = temporaryPackageNames()

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result, .empty)
        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testInsertedParagraphPreservesLaterEqualParagraphs() async throws {
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(documentXML: DOCXFixtureBuilder.document(paragraphs: [
                "Introduction",
                "Results remain stable.",
                "Conclusion"
            ])),
            revised: .init(documentXML: DOCXFixtureBuilder.document(paragraphs: [
                "Introduction",
                "New supporting context.",
                "Results remain stable.",
                "Conclusion"
            ]))
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary, ComparisonSummary(
            addedWords: 3,
            removedWords: 0,
            changedImages: 0
        ))
        guard result.changes.count == 1 else {
            return XCTFail("Expected one inserted paragraph, got \(result.changes.count)")
        }
        guard case let .text(change) = result.changes[0].payload else {
            return XCTFail("Expected the inserted paragraph to be a text change")
        }
        XCTAssertEqual(change.oldText, "")
        XCTAssertEqual(change.newText, "New supporting context.")
    }

    func testTableCellEditCreatesOneTextChange() async throws {
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(documentXML: DOCXFixtureBuilder.documentWithTableCell("Table result")),
            revised: .init(documentXML: DOCXFixtureBuilder.documentWithTableCell("Table finding"))
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary, ComparisonSummary(
            addedWords: 1,
            removedWords: 1,
            changedImages: 0
        ))
        guard result.changes.count == 1 else {
            return XCTFail("Expected one table-cell text change, got \(result.changes.count)")
        }
        guard case let .text(change) = result.changes[0].payload else {
            return XCTFail("Expected the table-cell edit to be a text change")
        }
        XCTAssertEqual(change.oldText, "Table result")
        XCTAssertEqual(change.newText, "Table finding")
    }

    func testEqualImageBytesUnderDifferentFilenamesProduceNoImageChange() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure 1. Stable result",
                    relationshipID: "rIdOriginal"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdOriginal", "media/original-name.png")
                ]),
                media: ["original-name.png": imageData]
            ),
            revised: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure 1. Stable result",
                    relationshipID: "rIdRevised"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdRevised", "media/renamed-image.jpeg")
                ]),
                media: ["renamed-image.jpeg": imageData]
            )
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary.changedImages, 0)
        XCTAssertEqual(result, .empty)
    }

    func testReplacementImagePreservesOldAndNewData() async throws {
        let oldData = Data("old-image-bytes".utf8)
        let newData = Data("new-image-bytes".utf8)
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure 2. Replacement",
                    relationshipID: "rId1"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rId1", "media/figure.png")
                ]),
                media: ["figure.png": oldData]
            ),
            revised: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure 2. Replacement",
                    relationshipID: "rId9"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rId9", "media/revised.png")
                ]),
                media: ["revised.png": newData]
            )
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary.changedImages, 1)
        guard result.changes.count == 1 else {
            return XCTFail("Expected one replacement image, got \(result.changes.count)")
        }
        guard case let .image(change) = result.changes[0].payload else {
            return XCTFail("Expected the replacement to be an image change")
        }
        XCTAssertEqual(change.kind, .replaced)
        XCTAssertEqual(change.oldImage?.data, oldData)
        XCTAssertEqual(change.newImage?.data, newData)
    }

    func testAlternateContentAndSingleRepresentationCompareWithoutFalseImageRemoval() async throws {
        let imageData = Data([4, 3, 2, 1])
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(
                documentXML: DOCXFixtureBuilder.alternateContentImageDocument(
                    choiceRelationshipID: "rIdChoice",
                    fallbackRelationshipID: "rIdFallback"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdChoice", "media/choice.png"),
                    ("rIdFallback", "media/fallback.png")
                ]),
                media: ["choice.png": imageData, "fallback.png": Data([9])]
            ),
            revised: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "",
                    relationshipID: "rIdSingle"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdSingle", "media/single.png")
                ]),
                media: ["single.png": imageData]
            )
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary.changedImages, 0)
        XCTAssertTrue(result.changes.isEmpty)
    }

    func testAddedAndRemovedImagesRemainDistinct() async throws {
        let removedData = Data("removed-image".utf8)
        let addedData = Data("added-image".utf8)
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure removed",
                    relationshipID: "rIdRemoved"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdRemoved", "media/removed.png")
                ]),
                media: ["removed.png": removedData]
            ),
            revised: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Figure added",
                    relationshipID: "rIdAdded"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdAdded", "media/added.png")
                ]),
                media: ["added.png": addedData]
            )
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )
        let imageChanges = result.changes.compactMap { change -> ImageChange? in
            guard case let .image(imageChange) = change.payload else { return nil }
            return imageChange
        }

        XCTAssertEqual(result.summary.changedImages, 2)
        XCTAssertEqual(imageChanges.map(\.kind), [.removed, .added])
        guard imageChanges.count == 2 else {
            return XCTFail("Expected distinct removed and added image changes")
        }
        XCTAssertEqual(imageChanges[0].oldImage?.data, removedData)
        XCTAssertNil(imageChanges[0].newImage)
        XCTAssertNil(imageChanges[1].oldImage)
        XCTAssertEqual(imageChanges[1].newImage?.data, addedData)
    }

    func testCorruptPackageThrowsPackageErrorAndCleansTemporaryExtraction() async throws {
        let original = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Valid original"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: original) }
        let corrupt = try DOCXFixtureBuilder.corruptPackage()
        defer { try? FileManager.default.removeItem(at: corrupt) }
        let temporaryPackagesBefore = temporaryPackageNames()

        do {
            _ = try await DocumentComparisonPipeline().compare(
                original: original,
                revised: corrupt
            )
            XCTFail("Expected corrupt package comparison to throw")
        } catch let error as DOCXError {
            switch error {
            case .invalidPackage, .missingMainDocument:
                break
            default:
                XCTFail("Expected invalidPackage or missingMainDocument, got \(error)")
            }
        }

        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testMissingImageMediaPreservesTextAndReturnsWarning() async throws {
        let pair = try DOCXFixtureBuilder.pair(
            original: .init(
                documentXML: DOCXFixtureBuilder.document(paragraphs: ["Text survives"])
            ),
            revised: .init(
                documentXML: DOCXFixtureBuilder.documentWithImage(
                    caption: "Text survives revised",
                    relationshipID: "rIdMissing"
                ),
                relationshipsXML: DOCXFixtureBuilder.relationships([
                    ("rIdMissing", "media/not-present.png")
                ])
            )
        )
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary, ComparisonSummary(
            addedWords: 1,
            removedWords: 0,
            changedImages: 0
        ))
        guard result.warnings.count == 1 else {
            return XCTFail("Expected one missing-image warning, got \(result.warnings.count)")
        }
        XCTAssertTrue(result.warnings[0].contains("rIdMissing"))
        guard result.changes.count == 1 else {
            return XCTFail("Expected one preserved text change, got \(result.changes.count)")
        }
        guard case let .text(change) = result.changes[0].payload else {
            return XCTFail("Expected the preserved comparison to be a text change")
        }
        XCTAssertEqual(change.oldText, "Text survives")
        XCTAssertEqual(change.newText, "Text survives revised")
    }

    func testPipelineReturnsTextAndFigureReplacement() async throws {
        let pair = try DOCXFixtureBuilder.revisionPair()
        defer { pair.cleanup() }
        let temporaryPackagesBefore = temporaryPackageNames()

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        XCTAssertEqual(result.summary.addedWords, 1)
        XCTAssertEqual(result.summary.removedWords, 1)
        XCTAssertEqual(result.summary.changedImages, 1)
        guard result.changes.count == 2 else {
            return XCTFail("Expected text and image changes, got \(result.changes.count)")
        }
        XCTAssertEqual(result.changes.map(\.id), [0, 1])
        XCTAssertEqual(result.changes.map(\.order), [0, 2])
        guard case .text = result.changes[0].payload,
              case let .image(imageChange) = result.changes[1].payload else {
            return XCTFail("Expected text before image in document order")
        }
        XCTAssertEqual(imageChange.kind, .replaced)
        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testCancellationAfterBothExtractionsCleansExtractedPackages() async throws {
        let pair = try DOCXFixtureBuilder.revisionPair()
        defer { pair.cleanup() }
        let temporaryPackagesBefore = temporaryPackageNames()
        let parserEntered = expectation(description: "parser entered after extraction")
        let allowParserToReturn = DispatchSemaphore(value: 0)
        let dependencies = DocumentComparisonDependencies(
            extract: { try DOCXExtractor().extract($0) },
            parse: { _ in
                parserEntered.fulfill()
                allowParserToReturn.wait()
                guard !Task.isCancelled else { throw DOCXError.cancelled }
                return ParsedDocument(paragraphs: [], images: [])
            }
        )
        let comparison = Task {
            try await DocumentComparisonPipeline(dependencies: dependencies).compare(
                original: pair.original,
                revised: pair.revised
            )
        }

        await fulfillment(of: [parserEntered], timeout: 5)
        let packagesDuringParsing = temporaryPackageNames()
        XCTAssertEqual(packagesDuringParsing.subtracting(temporaryPackagesBefore).count, 2)

        comparison.cancel()
        allowParserToReturn.signal()

        do {
            _ = try await comparison.value
            XCTFail("Expected comparison cancellation")
        } catch let error as DOCXError {
            XCTAssertEqual(error, .cancelled)
        } catch is CancellationError {
            // CancellationError is also an acceptable structured-concurrency result.
        }
        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testCancellationDuringLongAlignmentPropagatesAsDOCXCancelled() async throws {
        let pair = try DOCXFixtureBuilder.revisionPair()
        defer { pair.cleanup() }
        let temporaryPackagesBefore = temporaryPackageNames()
        let alignmentReady = expectation(description: "both long parsed documents returned")
        let sequence = ParsedDocumentSequence(
            original: ParsedDocument(
                paragraphs: (0..<900).map {
                    ParagraphBlock(order: $0, text: "Original paragraph number \($0)")
                },
                images: []
            ),
            revised: ParsedDocument(
                paragraphs: (0..<900).map {
                    ParagraphBlock(order: $0, text: "Revised paragraph number \($0)")
                },
                images: []
            ),
            secondDocumentReturned: { alignmentReady.fulfill() }
        )
        let dependencies = DocumentComparisonDependencies(
            extract: { try DOCXExtractor().extract($0) },
            parse: { _ in sequence.next() }
        )
        let comparison = Task {
            try await DocumentComparisonPipeline(dependencies: dependencies).compare(
                original: pair.original,
                revised: pair.revised
            )
        }

        await fulfillment(of: [alignmentReady], timeout: 5)
        try await Task.sleep(for: .milliseconds(10))
        comparison.cancel()

        do {
            _ = try await comparison.value
            XCTFail("Expected cancellation during paragraph alignment")
        } catch {
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testParserFailureCleansBothExtractedPackages() async throws {
        let original = try DOCXFixtureBuilder.make(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Valid original"]),
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        let revised = try DOCXFixtureBuilder.make(
            documentXML: "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>",
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: revised)
        }
        let temporaryPackagesBefore = temporaryPackageNames()

        do {
            _ = try await DocumentComparisonPipeline().compare(original: original, revised: revised)
            XCTFail("Expected malformed revised document to fail parsing")
        } catch let error as DOCXError {
            guard case .malformedXML = error else {
                return XCTFail("Expected malformedXML, got \(error)")
            }
        }

        XCTAssertEqual(temporaryPackageNames(), temporaryPackagesBefore)
    }

    func testResultAssemblyPlacesTextBeforeImageWhenOrdersTie() {
        let textChange = TextChange(
            order: 7,
            oldText: "The old result",
            newText: "The new result",
            segments: WordDiff.segments(old: "The old result", new: "The new result")
        )
        let oldImage = image(order: 7, digest: "old", anchor: "Figure 1")
        let newImage = image(order: 7, digest: "new", anchor: "Figure 1")
        let imageChange = ImageChange(
            order: 7,
            kind: .replaced,
            oldImage: oldImage,
            newImage: newImage,
            anchor: "Figure 1"
        )

        let result = ComparisonResultAssembler.make(
            textChanges: [textChange],
            imageChanges: [imageChange],
            warnings: []
        )

        XCTAssertEqual(result.changes.map(\.id), [0, 1])
        XCTAssertEqual(result.changes.map(\.order), [7, 7])
        guard result.changes.count == 2 else {
            return XCTFail("Expected two tied changes, got \(result.changes.count)")
        }
        guard case .text = result.changes[0].payload,
              case .image = result.changes[1].payload else {
            return XCTFail("Expected text before image when order values tie")
        }
    }

    func testPipelineAggregatesWarningsFromBothParsedDocuments() async throws {
        let pair = try DOCXFixtureBuilder.missingImagePair()
        defer { pair.cleanup() }

        let result = try await DocumentComparisonPipeline().compare(
            original: pair.original,
            revised: pair.revised
        )

        guard result.warnings.count == 2 else {
            return XCTFail("Expected two missing-image warnings, got \(result.warnings.count)")
        }
        XCTAssertTrue(result.warnings[0].contains("rIdOriginal"))
        XCTAssertTrue(result.warnings[1].contains("rIdRevised"))
    }

    private func temporaryPackageNames() -> Set<String> {
        try? TemporaryExtractionSession.shared.prepare()
        let directory = TemporaryExtractionSession.shared.rootURL
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(names.map(\.lastPathComponent).filter { !$0.hasPrefix(".") })
    }

    private func image(order: Int, digest: String, anchor: String) -> ImageBlock {
        ImageBlock(
            order: order,
            data: Data(digest.utf8),
            digest: digest,
            mediaExtension: "png",
            anchor: anchor
        )
    }
}

private final class ParsedDocumentSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let original: ParsedDocument
    private let revised: ParsedDocument
    private let secondDocumentReturned: @Sendable () -> Void
    private var count = 0

    init(
        original: ParsedDocument,
        revised: ParsedDocument,
        secondDocumentReturned: @escaping @Sendable () -> Void
    ) {
        self.original = original
        self.revised = revised
        self.secondDocumentReturned = secondDocumentReturned
    }

    func next() -> ParsedDocument {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if count == 2 {
            secondDocumentReturned()
            return revised
        }
        return original
    }
}

private extension DOCXFixtureBuilder {
    static func alternateContentImageDocument(
        choiceRelationshipID: String,
        fallbackRelationshipID: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:v="urn:schemas-microsoft-com:vml"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
          <w:body><w:p><w:r><mc:AlternateContent>
            <mc:Choice Requires="a"><w:drawing><a:blip r:embed="\(choiceRelationshipID)"/></w:drawing></mc:Choice>
            <mc:Fallback><w:pict><v:imagedata r:id="\(fallbackRelationshipID)"/></w:pict></mc:Fallback>
          </mc:AlternateContent></w:r></w:p></w:body>
        </w:document>
        """
    }

    static func revisionPair() throws -> FixturePair {
        let original = try make(
            documentXML: revisionDocument(text: "The result was small.", relationshipID: "rId1"),
            relationshipsXML: relationships([("rId1", "media/figure.png")]),
            media: ["figure.png": Data("old-figure".utf8)]
        )
        do {
            let revised = try make(
                documentXML: revisionDocument(text: "The result was significant.", relationshipID: "rId1"),
                relationshipsXML: relationships([("rId1", "media/figure.png")]),
                media: ["figure.png": Data("new-figure".utf8)]
            )
            return FixturePair(original: original, revised: revised)
        } catch {
            try? FileManager.default.removeItem(at: original)
            throw error
        }
    }

    static func missingImagePair() throws -> FixturePair {
        let original = try make(
            documentXML: missingImageDocument(text: "Original", relationshipID: "rIdOriginal"),
            relationshipsXML: relationships([("rIdOriginal", "media/original-missing.png")]),
            media: [:]
        )
        do {
            let revised = try make(
                documentXML: missingImageDocument(text: "Revised", relationshipID: "rIdRevised"),
                relationshipsXML: relationships([("rIdRevised", "media/revised-missing.png")]),
                media: [:]
            )
            return FixturePair(original: original, revised: revised)
        } catch {
            try? FileManager.default.removeItem(at: original)
            throw error
        }
    }

    static func revisionDocument(text: String, relationshipID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>\(text)</w:t></w:r></w:p>
            <w:p><w:r><w:t>Figure 1. Results</w:t></w:r></w:p>
            <w:p><w:r><w:drawing><a:blip r:embed="\(relationshipID)"/></w:drawing></w:r></w:p>
          </w:body>
        </w:document>
        """
    }

    static func missingImageDocument(text: String, relationshipID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>\(text)</w:t><w:drawing><a:blip r:embed="\(relationshipID)"/></w:drawing></w:r></w:p>
          </w:body>
        </w:document>
        """
    }
}
