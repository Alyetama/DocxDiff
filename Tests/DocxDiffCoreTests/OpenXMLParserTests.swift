import Foundation
import XCTest
@testable import DocxDiffCore

final class OpenXMLParserTests: XCTestCase {
    func testParsesParagraphTableTextAndImageInOrder() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: DOCXFixtureBuilder.documentWithTableAndImage(),
            relationshipsXML: DOCXFixtureBuilder.relationships([
                ("rId5", "media/figure.png")
            ]),
            media: ["figure.png": Data([1, 2, 3])]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.paragraphs.map(\.text), [
            "Introduction", "Table result", "Conclusion"
        ])
        XCTAssertEqual(parsed.paragraphs.map(\.order), [0, 2, 3])
        XCTAssertEqual(parsed.images.count, 1)
        XCTAssertEqual(parsed.images[0].order, 1)
        XCTAssertEqual(parsed.images[0].anchor, "Introduction")
        XCTAssertEqual(parsed.images[0].mediaExtension, "png")
        XCTAssertEqual(parsed.images[0].data, Data([1, 2, 3]))
        XCTAssertEqual(
            parsed.images[0].digest,
            "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81"
        )
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testNormalizesSplitRunsTabsAndBreaksAndIgnoresDeletedText() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body><w:p>
                <w:r><w:t>Split</w:t><w:tab/><w:t>run</w:t><w:br/><w:t> text </w:t></w:r>
                <w:del><w:r><w:delText>deleted words</w:delText></w:r></w:del>
              </w:p></w:body>
            </w:document>
            """,
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.paragraphs, [ParagraphBlock(order: 0, text: "Split run text")])
        XCTAssertTrue(parsed.images.isEmpty)
    }

    func testImageUsesCurrentParagraphAsAnchor() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
              <w:body><w:p><w:r><w:t>Figure caption</w:t><w:drawing><a:blip r:embed="rId2"/></w:drawing></w:r></w:p></w:body>
            </w:document>
            """,
            relationshipsXML: DOCXFixtureBuilder.relationships([("rId2", "media/photo.JPEG")]),
            media: ["photo.JPEG": Data([4, 5])]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.paragraphs.map(\.order), [0])
        XCTAssertEqual(parsed.images.map(\.order), [1])
        XCTAssertEqual(parsed.images.map(\.anchor), ["Figure caption"])
        XCTAssertEqual(parsed.images.map(\.mediaExtension), ["jpeg"])
    }

    func testMissingImageTargetPreservesTextAndAddsWarning() throws {
        let root = try DOCXFixtureBuilder.packageWithMissingImage()
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.paragraphs.map(\.text), ["Text survives"])
        XCTAssertEqual(parsed.images, [])
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings[0].contains("rId7"))
    }

    func testEscapingAndExternalImageTargetsAddWarnings() throws {
        let relationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../outside.png"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="https://example.com/image.png" TargetMode="External"/>
        </Relationships>
        """
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: documentWithImages(["rId1", "rId2"]),
            relationshipsXML: relationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertTrue(parsed.images.isEmpty)
        XCTAssertEqual(parsed.warnings.count, 2)
        XCTAssertTrue(parsed.warnings.contains { $0.contains("rId1") })
        XCTAssertTrue(parsed.warnings.contains { $0.contains("rId2") })
    }

    func testSymlinkedImageTargetOutsideWordDirectoryAddsWarning() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: documentWithImages(["rId3"]),
            relationshipsXML: DOCXFixtureBuilder.relationships([("rId3", "media/link.png")]),
            media: [:]
        )
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffTests-outside-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideURL)
        }
        try Data([9, 8, 7]).write(to: outsideURL)
        let mediaDirectory = root.appendingPathComponent("word/media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: mediaDirectory.appendingPathComponent("link.png"),
            withDestinationURL: outsideURL
        )

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertTrue(parsed.images.isEmpty)
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings.first?.contains("rId3") == true)
    }

    func testParsesRemappedOpenXMLPrefixesAndIgnoresUnrelatedEmbedAttribute() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:document xmlns:x="http://purl.oclc.org/ooxml/wordprocessingml/main"
                        xmlns:pic="http://purl.oclc.org/ooxml/drawingml/main"
                        xmlns:rel="http://purl.oclc.org/ooxml/officeDocument/relationships"
                        xmlns:fake="urn:not-openxml-relationships">
              <x:body><x:p><x:r><x:t>Remapped prefixes</x:t><x:drawing>
                <pic:blip fake:embed="rIdWrong" rel:embed="rId8"/>
              </x:drawing></x:r></x:p></x:body>
            </x:document>
            """,
            relationshipsXML: DOCXFixtureBuilder.relationships([("rId8", "media/remapped.png")]),
            media: ["remapped.png": Data([6, 7, 8])]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.paragraphs.map(\.text), ["Remapped prefixes"])
        XCTAssertEqual(parsed.images.map(\.data), [Data([6, 7, 8])])
        XCTAssertEqual(parsed.images.map(\.anchor), ["Remapped prefixes"])
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testParsesLegacyVMLImageDataUsingNamespaceAwareRelationshipID() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:v="urn:schemas-microsoft-com:vml"
                        xmlns:rel="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                        xmlns:fake="urn:not-openxml-relationships">
              <w:body><w:p><w:r><w:t>Legacy figure</w:t><w:pict>
                <v:imagedata fake:id="rIdWrong" rel:id="rIdVML"/>
              </w:pict></w:r></w:p></w:body>
            </w:document>
            """,
            relationshipsXML: DOCXFixtureBuilder.relationships([("rIdVML", "media/legacy.png")]),
            media: ["legacy.png": Data([7, 7, 7])]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.images.map(\.data), [Data([7, 7, 7])])
        XCTAssertEqual(parsed.images.map(\.anchor), ["Legacy figure"])
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testModernSVGReferenceSupersedesDrawingFallbackImage() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                        xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <w:body><w:p><w:r><w:drawing><a:blip r:embed="rIdPNG">
                <a:extLst><a:ext><asvg:svgBlip r:embed="rIdSVG"/></a:ext></a:extLst>
              </a:blip></w:drawing></w:r></w:p></w:body>
            </w:document>
            """,
            relationshipsXML: DOCXFixtureBuilder.relationships([
                ("rIdPNG", "media/fallback.png"),
                ("rIdSVG", "media/vector.svg")
            ]),
            media: [
                "fallback.png": Data([1]),
                "vector.svg": Data("<svg/>".utf8)
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.images.count, 1)
        XCTAssertEqual(parsed.images.first?.mediaExtension, "svg")
        XCTAssertEqual(parsed.images.first?.data, Data("<svg/>".utf8))
    }

    func testAlternateContentSelectsSupportedChoiceAndSuppressesVMLFallback() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: alternateContentDocument(
                choiceRelationshipID: "rIdChoice",
                fallbackRelationshipID: "rIdFallback"
            ),
            relationshipsXML: DOCXFixtureBuilder.relationships([
                ("rIdChoice", "media/choice.png"),
                ("rIdFallback", "media/fallback.png")
            ]),
            media: [
                "choice.png": Data([1, 2, 3]),
                "fallback.png": Data([9, 9, 9])
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.images.count, 1)
        XCTAssertEqual(parsed.images.first?.data, Data([1, 2, 3]))
    }

    func testAlternateContentUsesVMLFallbackWhenChoiceRequirementIsUnsupported() throws {
        let xml = alternateContentDocument(
            choiceRelationshipID: "rIdChoice",
            fallbackRelationshipID: "rIdFallback"
        ).replacingOccurrences(of: "Requires=\"a\"", with: "Requires=\"future\"")
            .replacingOccurrences(
                of: "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"",
                with: "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:future=\"urn:unsupported-feature\""
            )
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: xml,
            relationshipsXML: DOCXFixtureBuilder.relationships([
                ("rIdChoice", "media/choice.png"),
                ("rIdFallback", "media/fallback.png")
            ]),
            media: [
                "choice.png": Data([1, 2, 3]),
                "fallback.png": Data([9, 9, 9])
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let parsed = try OpenXMLParser().parse(packageRoot: root)

        XCTAssertEqual(parsed.images.count, 1)
        XCTAssertEqual(parsed.images.first?.data, Data([9, 9, 9]))
    }

    func testMalformedDocumentXMLThrowsMalformedXMLError() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: "<w:document xmlns:w=\"urn:test\"><w:body><w:p>",
            relationshipsXML: DOCXFixtureBuilder.emptyRelationships,
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try OpenXMLParser().parse(packageRoot: root)) { error in
            guard case .malformedXML = error as? DOCXError else {
                return XCTFail("Expected DOCXError.malformedXML, got \(error)")
            }
        }
    }

    func testMalformedRelationshipsXMLThrowsMalformedXMLError() throws {
        let root = try DOCXFixtureBuilder.expandedPackage(
            documentXML: DOCXFixtureBuilder.document(paragraphs: ["Text"]),
            relationshipsXML: "<Relationships><Relationship",
            media: [:]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try OpenXMLParser().parse(packageRoot: root)) { error in
            guard case .malformedXML = error as? DOCXError else {
                return XCTFail("Expected DOCXError.malformedXML, got \(error)")
            }
        }
    }

    private func documentWithImages(_ relationshipIDs: [String]) -> String {
        let images = relationshipIDs.map { "<w:p><w:r><w:drawing><a:blip r:embed=\"\($0)\"/></w:drawing></w:r></w:p>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>\(images)</w:body>
        </w:document>
        """
    }

    private func alternateContentDocument(
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
}
