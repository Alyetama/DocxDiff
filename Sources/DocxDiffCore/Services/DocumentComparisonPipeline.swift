import Foundation

public protocol DocumentComparing: Sendable {
    func compare(original: URL, revised: URL) async throws -> ComparisonResult
}

struct DocumentComparisonDependencies: Sendable {
    let extract: @Sendable (URL) throws -> TemporaryDOCXPackage
    let parse: @Sendable (URL) throws -> ParsedDocument

    static let live = DocumentComparisonDependencies(
        extract: { try DOCXExtractor().extract($0) },
        parse: { try OpenXMLParser().parse(packageRoot: $0) }
    )
}

public struct DocumentComparisonPipeline: DocumentComparing, Sendable {
    private let dependencies: DocumentComparisonDependencies

    public init() {
        dependencies = .live
    }

    init(dependencies: DocumentComparisonDependencies) {
        self.dependencies = dependencies
    }

    public func compare(original: URL, revised: URL) async throws -> ComparisonResult {
        let dependencies = dependencies
        let worker = Task.detached(priority: .userInitiated) {
            try Self.compareSynchronously(
                original: original,
                revised: revised,
                dependencies: dependencies
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func compareSynchronously(
        original: URL,
        revised: URL,
        dependencies: DocumentComparisonDependencies
    ) throws -> ComparisonResult {
        try checkCancellation()

        let originalPackage = try dependencies.extract(original)
        defer { originalPackage.cleanup() }
        try checkCancellation()

        let revisedPackage = try dependencies.extract(revised)
        defer { revisedPackage.cleanup() }
        try checkCancellation()

        let originalDocument = try dependencies.parse(originalPackage.rootURL)
        try checkCancellation()
        let revisedDocument = try dependencies.parse(revisedPackage.rootURL)
        try checkCancellation()

        let textChanges = try ParagraphAligner.changesCancellable(
            original: originalDocument.paragraphs,
            revised: revisedDocument.paragraphs
        )
        try checkCancellation()
        let imageChanges = ImageAligner.changes(
            original: originalDocument.images,
            revised: revisedDocument.images
        )
        try checkCancellation()

        let result = ComparisonResultAssembler.make(
            textChanges: textChanges,
            imageChanges: imageChanges,
            warnings: originalDocument.warnings + revisedDocument.warnings
        )
        try checkCancellation()

        return result
    }

    private static func checkCancellation() throws {
        guard !Task.isCancelled else { throw DOCXError.cancelled }
    }
}

enum ComparisonResultAssembler {
    static func make(
        textChanges: [TextChange],
        imageChanges: [ImageChange],
        warnings: [String]
    ) -> ComparisonResult {
        ComparisonResult(
            changes: mergedChanges(text: textChanges, images: imageChanges),
            summary: summary(text: textChanges, images: imageChanges),
            warnings: warnings
        )
    }

    private static func mergedChanges(
        text textChanges: [TextChange],
        images imageChanges: [ImageChange]
    ) -> [ComparisonChange] {
        var sortable: [SortableChange] = []
        sortable.reserveCapacity(textChanges.count + imageChanges.count)

        for change in textChanges {
            sortable.append(
                SortableChange(
                    order: change.order,
                    kindOrder: 0,
                    insertionOrder: sortable.count,
                    payload: .text(change)
                )
            )
        }
        for change in imageChanges {
            sortable.append(
                SortableChange(
                    order: change.order,
                    kindOrder: 1,
                    insertionOrder: sortable.count,
                    payload: .image(change)
                )
            )
        }

        sortable.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.kindOrder != $1.kindOrder { return $0.kindOrder < $1.kindOrder }
            return $0.insertionOrder < $1.insertionOrder
        }

        return sortable.enumerated().map { id, change in
            ComparisonChange(id: id, order: change.order, payload: change.payload)
        }
    }

    private static func summary(
        text textChanges: [TextChange],
        images imageChanges: [ImageChange]
    ) -> ComparisonSummary {
        var addedWords = 0
        var removedWords = 0
        for change in textChanges {
            let counts = WordDiff.changedWordCounts(in: change.segments)
            addedWords += counts.added
            removedWords += counts.removed
        }
        return ComparisonSummary(
            addedWords: addedWords,
            removedWords: removedWords,
            changedImages: imageChanges.count
        )
    }

    private struct SortableChange {
        let order: Int
        let kindOrder: Int
        let insertionOrder: Int
        let payload: ChangePayload
    }
}
