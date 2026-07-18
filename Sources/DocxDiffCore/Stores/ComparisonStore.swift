import Foundation
import Observation

@MainActor
@Observable
public final class ComparisonStore {
    public enum Phase: Equatable {
        case empty
        case awaitingSecondDocument
        case comparing
        case ready
        case failed(String)
    }

    public private(set) var originalURL: URL?
    public private(set) var revisedURL: URL?
    public private(set) var result: ComparisonResult?
    public private(set) var phase: Phase = .empty
    public private(set) var inputErrors: [DocumentSide: String] = [:]
    public var filter: ChangeFilter = .all

    private let comparer: any DocumentComparing
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(comparer: any DocumentComparing = DocumentComparisonPipeline()) {
        self.comparer = comparer
    }

    deinit {
        comparisonTask?.cancel()
    }

    public var filteredChanges: [ComparisonChange] {
        let changes = result?.changes ?? []
        switch filter {
        case .all:
            return changes
        case .text:
            return changes.filter {
                if case .text = $0.payload { return true }
                return false
            }
        case .images:
            return changes.filter {
                if case .image = $0.payload { return true }
                return false
            }
        }
    }

    public func setURL(_ url: URL, for side: DocumentSide) {
        if let validationError = validationError(for: url, side: side) {
            inputErrors[side] = validationError
            return
        }

        inputErrors.removeValue(forKey: side)
        switch side {
        case .original:
            originalURL = url
        case .revised:
            revisedURL = url
        }
        restartComparison()
    }

    public func swap() {
        let previousOriginal = originalURL
        originalURL = revisedURL
        revisedURL = previousOriginal
        inputErrors.removeAll()
        restartComparison()
    }

    public func clear() {
        cancelAndAdvanceGeneration()
        originalURL = nil
        revisedURL = nil
        result = nil
        phase = .empty
        inputErrors.removeAll()
        filter = .all
    }

    public func retry() {
        restartComparison()
    }

    private func validationError(for url: URL, side: DocumentSide) -> String? {
        guard url.pathExtension.caseInsensitiveCompare("docx") == .orderedSame else {
            return "\(side.title) file must have a .docx extension."
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return "\(side.title) DOCX file cannot be read."
        }
        return nil
    }

    private func restartComparison() {
        cancelAndAdvanceGeneration()
        result = nil

        guard let originalURL, let revisedURL else {
            phase = originalURL == nil && revisedURL == nil ? .empty : .awaitingSecondDocument
            return
        }

        phase = .comparing
        let comparer = comparer
        let currentGeneration = generation
        comparisonTask = Task { [weak self] in
            do {
                let comparison = try await comparer.compare(
                    original: originalURL,
                    revised: revisedURL
                )
                guard !Task.isCancelled else { return }
                self?.publish(comparison, for: currentGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.publish(error, for: currentGeneration)
            }
        }
    }

    private func cancelAndAdvanceGeneration() {
        comparisonTask?.cancel()
        comparisonTask = nil
        generation &+= 1
    }

    private func publish(_ comparison: ComparisonResult, for completedGeneration: Int) {
        guard generation == completedGeneration, !Task.isCancelled else { return }
        result = comparison
        phase = .ready
        comparisonTask = nil
    }

    private func publish(_ error: Error, for completedGeneration: Int) {
        guard generation == completedGeneration, !Task.isCancelled else { return }
        let localizedDescription = (error as? LocalizedError)?.errorDescription
        result = nil
        phase = .failed(localizedDescription ?? error.localizedDescription)
        comparisonTask = nil
    }
}
