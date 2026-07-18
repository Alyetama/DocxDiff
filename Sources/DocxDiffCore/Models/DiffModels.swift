import Foundation

public enum DiffSegmentKind: Equatable, Sendable {
    case unchanged
    case added
    case removed
}

public struct DiffSegment: Equatable, Sendable {
    public let kind: DiffSegmentKind
    public let text: String

    public init(kind: DiffSegmentKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct TextChange: Equatable, Sendable {
    public let order: Int
    public let oldText: String
    public let newText: String
    public let segments: [DiffSegment]

    public init(order: Int, oldText: String, newText: String, segments: [DiffSegment]) {
        self.order = order
        self.oldText = oldText
        self.newText = newText
        self.segments = segments
    }
}

public enum ImageChangeKind: String, Equatable, Sendable {
    case added
    case removed
    case replaced
}

public struct ImageChange: Equatable, Sendable {
    public let order: Int
    public let kind: ImageChangeKind
    public let oldImage: ImageBlock?
    public let newImage: ImageBlock?
    public let anchor: String

    public init(order: Int, kind: ImageChangeKind, oldImage: ImageBlock?, newImage: ImageBlock?, anchor: String) {
        self.order = order
        self.kind = kind
        self.oldImage = oldImage
        self.newImage = newImage
        self.anchor = anchor
    }
}

public enum ChangePayload: Equatable, Sendable {
    case text(TextChange)
    case image(ImageChange)
}

public struct ComparisonChange: Identifiable, Equatable, Sendable {
    public let id: Int
    public let order: Int
    public let payload: ChangePayload

    public init(id: Int, order: Int, payload: ChangePayload) {
        self.id = id
        self.order = order
        self.payload = payload
    }
}

public struct ComparisonSummary: Equatable, Sendable {
    public let addedWords: Int
    public let removedWords: Int
    public let changedImages: Int

    public init(addedWords: Int, removedWords: Int, changedImages: Int) {
        self.addedWords = addedWords
        self.removedWords = removedWords
        self.changedImages = changedImages
    }

    public var totalChanges: Int { addedWords + removedWords + changedImages }
}

public struct ComparisonResult: Equatable, Sendable {
    public let changes: [ComparisonChange]
    public let summary: ComparisonSummary
    public let warnings: [String]

    public init(changes: [ComparisonChange], summary: ComparisonSummary, warnings: [String]) {
        self.changes = changes
        self.summary = summary
        self.warnings = warnings
    }

    public static let empty = ComparisonResult(
        changes: [],
        summary: ComparisonSummary(addedWords: 0, removedWords: 0, changedImages: 0),
        warnings: []
    )
}

public enum ChangeFilter: String, CaseIterable, Sendable {
    case all = "All"
    case text = "Text"
    case images = "Images"
}
