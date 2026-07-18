import Foundation
import XCTest
@testable import DocxDiffCore

private typealias StoreComparisonResult = DocxDiffCore.ComparisonResult

@MainActor
final class ComparisonStoreTests: XCTestCase {
    func testValidOriginalAndRevisedURLsTriggerOneComparison() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)

        store.setURL(urls[0], for: .original)
        XCTAssertEqual(store.phase, .awaitingSecondDocument)
        store.setURL(urls[1], for: .revised)

        await waitForCallCount(1, on: comparer)
        let calls = await comparer.recordedCalls()
        XCTAssertEqual(calls, [.init(original: urls[0], revised: urls[1])])
        XCTAssertEqual(store.phase, .comparing)

        await comparer.finishLatest(with: .empty)
        await waitForPhase(.ready, on: store)
        XCTAssertEqual(store.result, .empty)
    }

    func testNonDOCXURLSetsOriginalSpecificErrorWithoutCallingComparer() async throws {
        let urls = try readableURLs(named: ["notes.txt"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)

        store.setURL(urls[0], for: .original)

        XCTAssertNil(store.originalURL)
        XCTAssertEqual(store.phase, .empty)
        XCTAssertTrue(store.inputErrors[.original]?.contains("Original") == true)
        XCTAssertTrue(store.inputErrors[.original]?.contains(".docx") == true)
        let calls = await comparer.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testUnreadableReplacementKeepsExistingURLAndOnlyClearsChangedSlotError() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.txt"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        let missingOriginal = urls[0]
            .deletingLastPathComponent()
            .appendingPathComponent("missing.docx")

        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        store.setURL(missingOriginal, for: .original)

        XCTAssertEqual(store.originalURL, urls[0])
        XCTAssertTrue(store.inputErrors[.original]?.contains("Original") == true)
        XCTAssertTrue(store.inputErrors[.original]?.contains("read") == true)
        XCTAssertTrue(store.inputErrors[.revised]?.contains("Revised") == true)

        store.setURL(urls[0], for: .original)

        XCTAssertNil(store.inputErrors[.original])
        XCTAssertNotNil(store.inputErrors[.revised])
        let calls = await comparer.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testSwapReversesURLsAndRerunsComparison() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)
        await comparer.finishLatest(with: .empty)
        await waitForPhase(.ready, on: store)

        store.swap()

        await waitForCallCount(2, on: comparer)
        XCTAssertEqual(store.originalURL, urls[1])
        XCTAssertEqual(store.revisedURL, urls[0])
        let calls = await comparer.recordedCalls()
        XCTAssertEqual(calls[1], .init(original: urls[1], revised: urls[0]))
        XCTAssertEqual(store.phase, .comparing)
        await comparer.finishLatest(with: .empty)
        await waitForPhase(.ready, on: store)
    }

    func testClearCancelsWorkAndResetsWindowState() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)

        store.clear()

        await waitForCancellationCount(1, on: comparer)

        XCTAssertNil(store.originalURL)
        XCTAssertNil(store.revisedURL)
        XCTAssertNil(store.result)
        XCTAssertEqual(store.phase, .empty)
        XCTAssertTrue(store.inputErrors.isEmpty)
        XCTAssertEqual(store.filter, .all)
    }

    func testSecondRevisionCancelsOldComparisonAndNewestResultWins() async throws {
        let urls = try readableURLs(named: [
            "original.docx",
            "revision-a.docx",
            "revision-b.docx"
        ])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        let newestResult = resultWithText(id: 2)
        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)

        store.setURL(urls[2], for: .revised)
        await waitForCancellationCount(1, on: comparer)
        await waitForCallCount(2, on: comparer)
        await comparer.finishLatest(with: newestResult)
        await waitForPhase(.ready, on: store)

        XCTAssertEqual(store.revisedURL, urls[2])
        XCTAssertEqual(store.result, newestResult)
        XCTAssertEqual(store.phase, .ready)
    }

    func testDeinitializationCancelsActiveComparisonWithoutTaskRetainingStore() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        weak var weakStore: ComparisonStore?
        var store: ComparisonStore? = ComparisonStore(comparer: comparer)
        weakStore = store
        store?.setURL(urls[0], for: .original)
        store?.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)

        store = nil

        XCTAssertNil(weakStore)
        await waitForCancellationCount(1, on: comparer)
    }

    func testAllTextAndImagesFiltersReturnMatchingPayloadKinds() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        let mixedResult = resultWithTextAndImage()
        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)
        await comparer.finishLatest(with: mixedResult)
        await waitForPhase(.ready, on: store)

        store.filter = .all
        XCTAssertEqual(store.filteredChanges, mixedResult.changes)

        store.filter = .text
        XCTAssertEqual(store.filteredChanges.map(\.id), [10])
        XCTAssertTrue(store.filteredChanges.allSatisfy {
            if case .text = $0.payload { return true }
            return false
        })

        store.filter = .images
        XCTAssertEqual(store.filteredChanges.map(\.id), [20])
        XCTAssertTrue(store.filteredChanges.allSatisfy {
            if case .image = $0.payload { return true }
            return false
        })
    }

    func testLocalizedFailureKeepsURLsAndRetryStartsNewComparison() async throws {
        let urls = try readableURLs(named: ["original.docx", "revised.docx"])
        defer { removeTemporaryURLs(urls) }
        let comparer = ControlledComparer()
        let store = ComparisonStore(comparer: comparer)
        store.setURL(urls[0], for: .original)
        store.setURL(urls[1], for: .revised)
        await waitForCallCount(1, on: comparer)

        await comparer.failLatest(with: SampleComparisonError())
        await waitForPhase(.failed("The selected documents could not be compared."), on: store)

        XCTAssertEqual(store.originalURL, urls[0])
        XCTAssertEqual(store.revisedURL, urls[1])
        XCTAssertNil(store.result)

        store.retry()

        await waitForCallCount(2, on: comparer)
        XCTAssertEqual(store.phase, .comparing)
        await comparer.finishLatest(with: .empty)
        await waitForPhase(.ready, on: store)
    }

    func testReadableURLsRemovesPartialDirectoryWhenSetupThrows() {
        let directoriesBefore = comparisonStoreFixtureDirectories()

        XCTAssertThrowsError(
            try readableURLs(named: ["created.docx", "missing/child.docx"])
        )

        XCTAssertEqual(comparisonStoreFixtureDirectories(), directoriesBefore)
    }

    private func waitForCallCount(
        _ expectedCount: Int,
        on comparer: ControlledComparer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil(
            "\(expectedCount) comparison calls",
            file: file,
            line: line,
            condition: { await comparer.recordedCalls().count == expectedCount }
        )
    }

    private func waitForCancellationCount(
        _ expectedCount: Int,
        on comparer: ControlledComparer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil(
            "\(expectedCount) cancelled comparison calls",
            file: file,
            line: line,
            condition: { await comparer.cancelledCalls().count == expectedCount }
        )
    }

    private func waitForPhase(
        _ expectedPhase: ComparisonStore.Phase,
        on store: ComparisonStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil(
            "phase \(expectedPhase)",
            file: file,
            line: line,
            condition: { store.phase == expectedPhase }
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await clock.sleep(for: .milliseconds(1))
        }
        XCTFail(
            "Timed out waiting for \(description)",
            file: file,
            line: line
        )
    }

    private func readableURLs(named names: [String]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComparisonStoreTests-\(UUID().uuidString)", isDirectory: true)
        var shouldRemoveDirectory = true
        defer {
            if shouldRemoveDirectory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let urls = try names.map { name in
            let url = directory.appendingPathComponent(name)
            try Data("test".utf8).write(to: url)
            return url
        }
        shouldRemoveDirectory = false
        return urls
    }

    private func removeTemporaryURLs(_ urls: [URL]) {
        guard let directory = urls.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func comparisonStoreFixtureDirectories() -> Set<String> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(
            urls.map(\.lastPathComponent)
                .filter { $0.hasPrefix("ComparisonStoreTests-") }
        )
    }

    private func resultWithText(id: Int) -> StoreComparisonResult {
        let text = TextChange(
            order: id,
            oldText: "old",
            newText: "new",
            segments: [DiffSegment(kind: .removed, text: "old")]
        )
        return StoreComparisonResult(
            changes: [ComparisonChange(id: id, order: id, payload: .text(text))],
            summary: ComparisonSummary(addedWords: 0, removedWords: 1, changedImages: 0),
            warnings: []
        )
    }

    private func resultWithTextAndImage() -> StoreComparisonResult {
        let text = TextChange(
            order: 1,
            oldText: "old",
            newText: "new",
            segments: [DiffSegment(kind: .added, text: "new")]
        )
        let imageBlock = ImageBlock(
            order: 2,
            data: Data([1, 2, 3]),
            digest: "image",
            mediaExtension: "png",
            anchor: "Figure 1"
        )
        let image = ImageChange(
            order: 2,
            kind: .added,
            oldImage: nil,
            newImage: imageBlock,
            anchor: "Figure 1"
        )
        return StoreComparisonResult(
            changes: [
                ComparisonChange(id: 10, order: 1, payload: .text(text)),
                ComparisonChange(id: 20, order: 2, payload: .image(image))
            ],
            summary: ComparisonSummary(addedWords: 1, removedWords: 0, changedImages: 1),
            warnings: []
        )
    }
}

private actor ControlledComparer: DocumentComparing {
    struct Call: Equatable {
        let original: URL
        let revised: URL
    }

    private struct PendingComparison {
        let id: Int
        let continuation: CheckedContinuation<StoreComparisonResult, Error>
    }

    private var nextID = 0
    private var calls: [Call] = []
    private var cancellations: [Call] = []
    private var cancelledIDs: Set<Int> = []
    private var pending: [PendingComparison] = []

    func compare(original: URL, revised: URL) async throws -> StoreComparisonResult {
        let id = nextID
        nextID += 1
        let call = Call(original: original, revised: revised)
        calls.append(call)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancelledIDs.contains(id) {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending.append(PendingComparison(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id, call: call) }
        }
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func cancelledCalls() -> [Call] {
        cancellations
    }

    func finishLatest(with result: StoreComparisonResult) {
        pending.removeLast().continuation.resume(returning: result)
    }

    func failLatest(with error: Error) {
        pending.removeLast().continuation.resume(throwing: error)
    }

    private func cancel(id: Int, call: Call) {
        guard cancelledIDs.insert(id).inserted else { return }
        cancellations.append(call)
        guard let pendingIndex = pending.firstIndex(where: { $0.id == id }) else { return }
        let continuation = pending.remove(at: pendingIndex).continuation
        continuation.resume(throwing: CancellationError())
    }
}

private struct SampleComparisonError: LocalizedError {
    var errorDescription: String? {
        "The selected documents could not be compared."
    }
}
