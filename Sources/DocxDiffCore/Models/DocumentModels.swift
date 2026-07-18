import Foundation

public enum DocumentSide: String, CaseIterable, Sendable {
    case original
    case revised

    public var title: String { rawValue.capitalized }
}

public struct ParagraphBlock: Equatable, Sendable {
    public let order: Int
    public let text: String

    public init(order: Int, text: String) {
        self.order = order
        self.text = text
    }
}

public struct ImageBlock: Equatable, Sendable {
    public let order: Int
    public let data: Data
    public let digest: String
    public let mediaExtension: String
    public let anchor: String

    public init(order: Int, data: Data, digest: String, mediaExtension: String, anchor: String) {
        self.order = order
        self.data = data
        self.digest = digest
        self.mediaExtension = mediaExtension
        self.anchor = anchor
    }
}

public struct ParsedDocument: Equatable, Sendable {
    public let paragraphs: [ParagraphBlock]
    public let images: [ImageBlock]
    public let warnings: [String]

    public init(paragraphs: [ParagraphBlock], images: [ImageBlock], warnings: [String] = []) {
        self.paragraphs = paragraphs
        self.images = images
        self.warnings = warnings
    }
}
