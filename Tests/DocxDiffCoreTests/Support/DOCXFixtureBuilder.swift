import Foundation
import XCTest

enum DOCXFixtureBuilder {
    struct DocumentFixture {
        let documentXML: String
        let relationshipsXML: String
        let media: [String: Data]

        init(
            documentXML: String,
            relationshipsXML: String = DOCXFixtureBuilder.emptyRelationships,
            media: [String: Data] = [:]
        ) {
            self.documentXML = documentXML
            self.relationshipsXML = relationshipsXML
            self.media = media
        }
    }

    struct FixturePair {
        let original: URL
        let revised: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: revised)
        }
    }

    static let emptyRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    """

    static func document(paragraphs: [String]) -> String {
        let body = paragraphs.map { paragraph in
            "<w:p><w:r><w:t>\(escapedXML(paragraph))</w:t></w:r></w:p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
        """
    }

    static func pair(original: DocumentFixture, revised: DocumentFixture) throws -> FixturePair {
        let originalURL = try make(
            documentXML: original.documentXML,
            relationshipsXML: original.relationshipsXML,
            media: original.media
        )
        do {
            let revisedURL = try make(
                documentXML: revised.documentXML,
                relationshipsXML: revised.relationshipsXML,
                media: revised.media
            )
            return FixturePair(original: originalURL, revised: revisedURL)
        } catch {
            try? FileManager.default.removeItem(at: originalURL)
            throw error
        }
    }

    static func corruptPackage() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxDiffTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).docx")
        try Data("not a ZIP archive".utf8).write(to: url)
        return url
    }

    static func make(
        documentXML: String,
        relationshipsXML: String,
        media: [String: Data]
    ) throws -> URL {
        let fileManager = FileManager.default
        let packageRoot = fileManager.temporaryDirectory
            .appendingPathComponent("DocxDiffTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = packageRoot.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).docx")
        defer { try? fileManager.removeItem(at: packageRoot) }

        try fileManager.createDirectory(
            at: packageRoot.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: packageRoot.appendingPathComponent("word/_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        if !media.isEmpty {
            try fileManager.createDirectory(
                at: packageRoot.appendingPathComponent("word/media", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try contentTypesXML.write(
            to: packageRoot.appendingPathComponent("[Content_Types].xml"),
            atomically: true,
            encoding: .utf8
        )
        try rootRelationshipsXML.write(
            to: packageRoot.appendingPathComponent("_rels/.rels"),
            atomically: true,
            encoding: .utf8
        )
        try documentXML.write(
            to: packageRoot.appendingPathComponent("word/document.xml"),
            atomically: true,
            encoding: .utf8
        )
        try relationshipsXML.write(
            to: packageRoot.appendingPathComponent("word/_rels/document.xml.rels"),
            atomically: true,
            encoding: .utf8
        )
        for name in media.keys.sorted() {
            guard let data = media[name] else { continue }
            try data.write(to: packageRoot.appendingPathComponent("word/media/\(name)"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = packageRoot
        process.arguments = ["-q", "-r", outputURL.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        return outputURL
    }

    static func expandedPackage(
        documentXML: String,
        relationshipsXML: String,
        media: [String: Data]
    ) throws -> URL {
        let fileManager = FileManager.default
        let packageRoot = fileManager.temporaryDirectory
            .appendingPathComponent("DocxDiffTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wordRoot = packageRoot.appendingPathComponent("word", isDirectory: true)
        var removePartialPackage = true
        defer {
            if removePartialPackage {
                try? fileManager.removeItem(at: packageRoot)
            }
        }

        try fileManager.createDirectory(
            at: wordRoot.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        if !media.isEmpty {
            try fileManager.createDirectory(
                at: wordRoot.appendingPathComponent("media", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try documentXML.write(
            to: wordRoot.appendingPathComponent("document.xml"),
            atomically: true,
            encoding: .utf8
        )
        try relationshipsXML.write(
            to: wordRoot.appendingPathComponent("_rels/document.xml.rels"),
            atomically: true,
            encoding: .utf8
        )
        for name in media.keys.sorted() {
            guard let data = media[name] else { continue }
            try data.write(to: wordRoot.appendingPathComponent("media/").appendingPathComponent(name))
        }
        removePartialPackage = false
        return packageRoot
    }

    static func relationships(_ relationships: [(id: String, target: String)]) -> String {
        let elements = relationships.map { relationship in
            "<Relationship Id=\"\(relationship.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(relationship.target)\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(elements)</Relationships>
        """
    }

    static func documentWithTableAndImage() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Introduction</w:t></w:r></w:p>
            <w:p><w:r><w:drawing><a:blip r:embed="rId5"/></w:drawing></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table </w:t></w:r><w:r><w:t>result</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:r><w:t>Conclusion</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
    }

    static func documentWithTableCell(_ text: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Introduction</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>\(escapedXML(text))</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:r><w:t>Conclusion</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
    }

    static func documentWithImage(caption: String, relationshipID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>\(escapedXML(caption))</w:t></w:r></w:p>
            <w:p><w:r><w:drawing><a:blip r:embed="\(relationshipID)"/></w:drawing></w:r></w:p>
          </w:body>
        </w:document>
        """
    }

    static func packageWithMissingImage() throws -> URL {
        try expandedPackage(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
              <w:body><w:p><w:r><w:t>Text survives</w:t><w:drawing><a:blip r:embed="rId7"/></w:drawing></w:r></w:p></w:body>
            </w:document>
            """,
            relationshipsXML: relationships([("rId7", "media/missing.png")]),
            media: [:]
        )
    }

    private static func escapedXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """
}
