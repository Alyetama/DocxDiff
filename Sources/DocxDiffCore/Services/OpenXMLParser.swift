import CryptoKit
import Foundation

public struct OpenXMLParser: Sendable {
    public init() {}

    public func parse(packageRoot: URL) throws -> ParsedDocument {
        let wordRoot = packageRoot
            .appendingPathComponent("word", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let documentURL = wordRoot.appendingPathComponent("document.xml")

        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw DOCXError.missingMainDocument
        }

        let relationships = try parseRelationships(
            at: wordRoot.appendingPathComponent("_rels/document.xml.rels")
        )
        let documentData: Data
        do {
            documentData = try Data(contentsOf: documentURL)
        } catch {
            throw DOCXError.missingMainDocument
        }

        let delegate = DocumentDelegate(wordRoot: wordRoot, relationships: relationships)
        try parseXML(documentData, delegate: delegate)
        return ParsedDocument(
            paragraphs: delegate.paragraphs,
            images: delegate.images,
            warnings: delegate.warnings
        )
    }

    private func parseRelationships(at url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DOCXError.malformedXML("Unable to read document relationships: \(error.localizedDescription)")
        }

        let delegate = RelationshipDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.targetsByID
    }

    private func parseXML(_ data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown XML parser error"
            throw DOCXError.malformedXML(message)
        }
    }
}

private final class RelationshipDelegate: NSObject, XMLParserDelegate {
    private(set) var targetsByID: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Relationship",
              OpenXMLNamespace.packageRelationships.contains(namespaceURI ?? ""),
              let id = attributeDict["Id"],
              let type = attributeDict["Type"],
              type.hasSuffix("/image"),
              attributeDict["TargetMode"]?.caseInsensitiveCompare("External") != .orderedSame,
              let target = attributeDict["Target"] else {
            return
        }
        targetsByID[id] = target
    }
}

private final class DocumentDelegate: NSObject, XMLParserDelegate {
    private let wordRoot: URL
    private let relationships: [String: String]
    private var insideParagraph = false
    private var readingText = false
    private var paragraphText = ""
    private var embeddedRelationshipIDs: [String] = []
    private var activeDrawingFallbackIndex: Int?
    private var precedingParagraphText = ""
    private var nextOrder = 0
    private var namespaceURIsByPrefix: [String: [String]] = [:]
    private var alternateContents: [AlternateContentState] = []
    private var branchSelections: [Bool] = []
    private var suppressedBranchCount = 0

    private(set) var paragraphs: [ParagraphBlock] = []
    private(set) var images: [ImageBlock] = []
    private(set) var warnings: [String] = []

    init(wordRoot: URL, relationships: [String: String]) {
        self.wordRoot = wordRoot.resolvingSymlinksInPath().standardizedFileURL
        self.relationships = relationships
    }

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        namespaceURIsByPrefix[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        namespaceURIsByPrefix[prefix]?.removeLast()
        if namespaceURIsByPrefix[prefix]?.isEmpty == true {
            namespaceURIsByPrefix[prefix] = nil
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let namespaceURI = namespaceURI ?? ""
        if OpenXMLNamespace.markupCompatibility.contains(namespaceURI) {
            switch elementName {
            case "AlternateContent":
                alternateContents.append(AlternateContentState())
            case "Choice":
                guard !alternateContents.isEmpty else { return }
                let supported = choiceIsSupported(attributes: attributeDict)
                let selected = supported && !alternateContents[alternateContents.count - 1].selectedBranch
                if selected {
                    alternateContents[alternateContents.count - 1].selectedBranch = true
                }
                branchSelections.append(selected)
                if !selected { suppressedBranchCount += 1 }
            case "Fallback":
                guard !alternateContents.isEmpty else { return }
                let selected = !alternateContents[alternateContents.count - 1].selectedBranch
                if selected {
                    alternateContents[alternateContents.count - 1].selectedBranch = true
                }
                branchSelections.append(selected)
                if !selected { suppressedBranchCount += 1 }
            default:
                break
            }
            return
        }
        guard suppressedBranchCount == 0 else { return }

        switch (elementName, namespaceURI) {
        case ("p", let uri) where OpenXMLNamespace.wordprocessing.contains(uri):
            insideParagraph = true
            readingText = false
            paragraphText = ""
            embeddedRelationshipIDs = []
            activeDrawingFallbackIndex = nil
        case ("t", let uri) where insideParagraph && OpenXMLNamespace.wordprocessing.contains(uri):
            readingText = true
        case ("tab", let uri) where insideParagraph && OpenXMLNamespace.wordprocessing.contains(uri):
            paragraphText.append("\t")
        case ("br", let uri) where insideParagraph && OpenXMLNamespace.wordprocessing.contains(uri):
            paragraphText.append("\n")
        case ("blip", let uri) where insideParagraph && OpenXMLNamespace.drawing.contains(uri):
            if let relationshipID = relationshipID(in: attributeDict, localName: "embed") {
                embeddedRelationshipIDs.append(relationshipID)
                activeDrawingFallbackIndex = embeddedRelationshipIDs.indices.last
            }
        case ("svgBlip", let uri) where insideParagraph && OpenXMLNamespace.svg.contains(uri):
            if let relationshipID = relationshipID(in: attributeDict, localName: "embed") {
                if let fallbackIndex = activeDrawingFallbackIndex,
                   embeddedRelationshipIDs.indices.contains(fallbackIndex) {
                    embeddedRelationshipIDs[fallbackIndex] = relationshipID
                } else {
                    embeddedRelationshipIDs.append(relationshipID)
                }
            }
        case ("imagedata", let uri) where insideParagraph && OpenXMLNamespace.vml.contains(uri):
            if let relationshipID = relationshipID(in: attributeDict, localName: "id") {
                embeddedRelationshipIDs.append(relationshipID)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideParagraph, readingText else { return }
        paragraphText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let namespaceURI = namespaceURI ?? ""
        if OpenXMLNamespace.markupCompatibility.contains(namespaceURI) {
            switch elementName {
            case "Choice", "Fallback":
                if let selected = branchSelections.popLast(), !selected {
                    suppressedBranchCount -= 1
                }
            case "AlternateContent":
                _ = alternateContents.popLast()
            default:
                break
            }
            return
        }
        guard suppressedBranchCount == 0 else { return }

        if elementName == "t", OpenXMLNamespace.wordprocessing.contains(namespaceURI) {
            readingText = false
        } else if elementName == "blip", OpenXMLNamespace.drawing.contains(namespaceURI) {
            activeDrawingFallbackIndex = nil
        } else if elementName == "p",
                  OpenXMLNamespace.wordprocessing.contains(namespaceURI),
                  insideParagraph {
            finishParagraph()
        }
    }

    private func relationshipID(in attributes: [String: String], localName: String) -> String? {
        for (qualifiedName, value) in attributes {
            let components = qualifiedName.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard components.count == 2, components[1] == Substring(localName) else { continue }

            let prefix = String(components[0])
            guard let namespaceURI = namespaceURIsByPrefix[prefix]?.last,
                  OpenXMLNamespace.officeDocumentRelationships.contains(namespaceURI) else {
                continue
            }
            return value
        }
        return nil
    }

    private func choiceIsSupported(attributes: [String: String]) -> Bool {
        guard let requires = attributes["Requires"] else { return false }
        let prefixes = requires.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !prefixes.isEmpty else { return false }
        return prefixes.allSatisfy { prefix in
            guard let namespaceURI = namespaceURIsByPrefix[prefix]?.last else { return false }
            return OpenXMLNamespace.supportedChoiceNamespaces.contains(namespaceURI)
        }
    }

    private func finishParagraph() {
        let normalizedText = paragraphText.docxNormalized
        if !normalizedText.isEmpty {
            paragraphs.append(ParagraphBlock(order: nextOrder, text: normalizedText))
            nextOrder += 1
            precedingParagraphText = normalizedText
        }

        let anchor = normalizedText.isEmpty ? precedingParagraphText : normalizedText
        for relationshipID in embeddedRelationshipIDs {
            resolveImage(relationshipID: relationshipID, anchor: anchor)
        }

        insideParagraph = false
        readingText = false
        paragraphText = ""
        embeddedRelationshipIDs = []
        activeDrawingFallbackIndex = nil
    }

    private func resolveImage(relationshipID: String, anchor: String) {
        guard let target = relationships[relationshipID] else {
            warnings.append(
                "Skipped embedded image \(relationshipID): no internal image relationship was found."
            )
            return
        }

        let decodedTarget = (target.removingPercentEncoding ?? target)
            .replacingOccurrences(of: "\\", with: "/")
        guard !decodedTarget.hasPrefix("/") else {
            warnings.append(
                "Skipped embedded image \(relationshipID): target \(target) escapes the word package directory."
            )
            return
        }

        let unresolvedMediaURL = wordRoot
            .appendingPathComponent(decodedTarget)
            .standardizedFileURL
        let mediaURL = unresolvedMediaURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let wordPathPrefix = wordRoot.path.hasSuffix("/") ? wordRoot.path : wordRoot.path + "/"
        guard mediaURL.path.hasPrefix(wordPathPrefix) else {
            warnings.append(
                "Skipped embedded image \(relationshipID): target \(target) escapes the word package directory."
            )
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: mediaURL)
        } catch {
            warnings.append(
                "Skipped embedded image \(relationshipID): target \(target) could not be read."
            )
            return
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        images.append(
            ImageBlock(
                order: nextOrder,
                data: data,
                digest: digest,
                mediaExtension: mediaURL.pathExtension.lowercased(),
                anchor: anchor
            )
        )
        nextOrder += 1
    }

    private struct AlternateContentState {
        var selectedBranch = false
    }
}

private enum OpenXMLNamespace {
    static let wordprocessing: Set<String> = [
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
        "http://purl.oclc.org/ooxml/wordprocessingml/main"
    ]
    static let drawing: Set<String> = [
        "http://schemas.openxmlformats.org/drawingml/2006/main",
        "http://purl.oclc.org/ooxml/drawingml/main"
    ]
    static let vml: Set<String> = [
        "urn:schemas-microsoft-com:vml"
    ]
    static let svg: Set<String> = [
        "http://schemas.microsoft.com/office/drawing/2016/SVG/main"
    ]
    static let markupCompatibility: Set<String> = [
        "http://schemas.openxmlformats.org/markup-compatibility/2006"
    ]
    static let officeDocumentRelationships: Set<String> = [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "http://purl.oclc.org/ooxml/officeDocument/relationships"
    ]
    static let packageRelationships: Set<String> = [
        "http://schemas.openxmlformats.org/package/2006/relationships",
        "http://purl.oclc.org/ooxml/package/relationships"
    ]
    static let supportedChoiceNamespaces = wordprocessing
        .union(drawing)
        .union(vml)
        .union(svg)
}
