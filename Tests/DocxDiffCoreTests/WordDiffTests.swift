import XCTest
@testable import DocxDiffCore

final class WordDiffTests: XCTestCase {
    func testReplacementPreservesSpacesAndPunctuation() {
        let result = WordDiff.segments(
            old: "The result was small.",
            new: "The result was statistically significant."
        )
        XCTAssertEqual(result, [
            DiffSegment(kind: .unchanged, text: "The result was "),
            DiffSegment(kind: .removed, text: "small"),
            DiffSegment(kind: .added, text: "statistically significant"),
            DiffSegment(kind: .unchanged, text: ".")
        ])
        XCTAssertEqual(result.map(\.text).joined(), "The result was smallstatistically significant.")
        XCTAssertEqual(WordDiff.changedWordCounts(in: result).added, 2)
        XCTAssertEqual(WordDiff.changedWordCounts(in: result).removed, 1)
    }

    func testEqualTextProducesOneUnchangedSegment() {
        XCTAssertEqual(
            WordDiff.segments(old: "same text", new: "same text"),
            [DiffSegment(kind: .unchanged, text: "same text")]
        )
    }

    func testChangedWordCountsIncludeAllUnicodeNumberCategories() {
        let result = WordDiff.segments(old: "Ⅻ", new: "½")

        XCTAssertEqual(WordDiff.changedWordCounts(in: result).added, 1)
        XCTAssertEqual(WordDiff.changedWordCounts(in: result).removed, 1)
    }

    func testCanonicallyEquivalentWordsRemainUnchangedAndPreserveOriginalDisplayText() {
        let decomposed = "Cafe\u{301}"

        let result = WordDiff.segments(old: decomposed, new: "Café")

        XCTAssertEqual(result, [DiffSegment(kind: .unchanged, text: decomposed)])
        XCTAssertEqual(WordDiff.changedWordCounts(in: result).added, 0)
        XCTAssertEqual(WordDiff.changedWordCounts(in: result).removed, 0)
    }

    func testCancellationIsCheckedDuringLongMemoryBoundedAlignment() {
        let old = (0..<300).map { "old\($0)" }.joined(separator: " ")
        let new = (0..<300).map { "new\($0)" }.joined(separator: " ")
        let cancellationTarget = tokenizationCheckCount(old: old, new: new) + 20
        var checks = 0

        XCTAssertThrowsError(
            try WordDiff.segmentsCancellable(old: old, new: new) {
                checks += 1
                if checks == cancellationTarget { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, cancellationTarget)
    }

    func testRepeatedTokenTieKeepsFirstMatchLikeLegacyDP() {
        XCTAssertEqual(
            WordDiff.segments(old: "A A", new: "A"),
            [
                DiffSegment(kind: .unchanged, text: "A"),
                DiffSegment(kind: .removed, text: " A")
            ]
        )
    }

    func testMemoryBoundedReconstructionMatchesLegacyDPForRepeatedWordSequences() {
        let sequences = wordSequences(maximumLength: 4)
        for oldWords in sequences {
            for newWords in sequences {
                let old = oldWords.joined(separator: " ")
                let new = newWords.joined(separator: " ")
                XCTAssertEqual(
                    WordDiff.segments(old: old, new: new),
                    legacySegments(old: old, new: new),
                    "Legacy DP mismatch for old=\(oldWords), new=\(newWords)"
                )
            }
        }
    }

    func testCancellationIsCheckedInsideSingleTokenBaseCaseScan() {
        let revised = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let cancellationTarget = tokenizationCheckCount(old: "needle", new: revised) + 6
        var checks = 0

        XCTAssertThrowsError(
            try WordDiff.segmentsCancellable(old: "needle", new: revised) {
                checks += 1
                if checks == cancellationTarget { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, cancellationTarget)
    }

    func testCancellationDuringHugeAddedParagraphStopsBeforeAllTokensAreProcessed() {
        let revised = (0..<4_096).map { "word\($0)" }.joined(separator: " ")
        var checks = 0

        XCTAssertThrowsError(
            try WordDiff.segmentsCancellable(old: "", new: revised) {
                checks += 1
                if checks == 20 { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, 20)
    }

    func testCancellationDuringOneHugeAddedTokenStopsBeforeScanningItAll() {
        let revised = String(repeating: "a", count: 100_000)
        var checks = 0

        XCTAssertThrowsError(
            try WordDiff.segmentsCancellable(old: "", new: revised) {
                checks += 1
                if checks == 20 { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, 20)
    }

    func testEmptySideStillCoalescesAllTokensIntoOneExactSegment() {
        let paragraph = (0..<1_024).map { "word\($0)" }.joined(separator: " ")

        XCTAssertEqual(
            WordDiff.segments(old: "", new: paragraph),
            [DiffSegment(kind: .added, text: paragraph)]
        )
        XCTAssertEqual(
            WordDiff.segments(old: paragraph, new: ""),
            [DiffSegment(kind: .removed, text: paragraph)]
        )
    }

    func testCancellationAwareTokenizerMatchesLegacyRegexAcrossUnicodeBoundaries() throws {
        let fragments = [
            "A", "e\u{301}", "Ⅻ", "½", "_", " ", "\r\n", "\u{00A0}",
            ",", "🙂", "\u{200D}", "\u{FE0F}"
        ]
        let samples = fragments + fragments.flatMap { left in
            fragments.map { right in left + right }
        }

        for sample in samples {
            XCTAssertEqual(
                try WordDiff.tokenStringsCancellable(in: sample, cancellationCheck: {}),
                WordDiff.tokens(in: sample),
                "Tokenizer mismatch for \(sample.debugDescription)"
            )
        }
    }

    func testCancellationIsCheckedInsideHugeAddedTailReconstruction() {
        let revised = (0..<2_048).map { "word\($0)" }.joined(separator: " ")
        let cancellationTarget = tokenizationCheckCount(old: "", new: revised) + 21
        var checks = 0

        XCTAssertThrowsError(
            try WordDiff.segmentsCancellable(old: "", new: revised) {
                checks += 1
                if checks == cancellationTarget { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, cancellationTarget)
    }

    private func wordSequences(maximumLength: Int) -> [[String]] {
        var result: [[String]] = [[]]
        for length in 1...maximumLength {
            var level: [[String]] = [[]]
            for _ in 0..<length {
                level = level.flatMap { prefix in ["A", "B"].map { prefix + [$0] } }
            }
            result += level
        }
        return result
    }

    private func tokenizationCheckCount(old: String, new: String) -> Int {
        2
            + old.unicodeScalars.count
            + new.unicodeScalars.count
            + WordDiff.tokens(in: old).count
            + WordDiff.tokens(in: new).count
    }

    private func legacySegments(old: String, new: String) -> [DiffSegment] {
        let oldTokens = WordDiff.tokens(in: old)
        let newTokens = WordDiff.tokens(in: new)
        var matrix = Array(
            repeating: Array(repeating: 0, count: newTokens.count + 1),
            count: oldTokens.count + 1
        )
        for oldIndex in oldTokens.indices.reversed() {
            for newIndex in newTokens.indices.reversed() {
                if oldTokens[oldIndex].precomposedStringWithCanonicalMapping
                    == newTokens[newIndex].precomposedStringWithCanonicalMapping {
                    matrix[oldIndex][newIndex] = matrix[oldIndex + 1][newIndex + 1] + 1
                } else {
                    matrix[oldIndex][newIndex] = max(
                        matrix[oldIndex + 1][newIndex],
                        matrix[oldIndex][newIndex + 1]
                    )
                }
            }
        }

        var result: [DiffSegment] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldTokens.count || newIndex < newTokens.count {
            if oldIndex < oldTokens.count,
               newIndex < newTokens.count,
               oldTokens[oldIndex].precomposedStringWithCanonicalMapping
                == newTokens[newIndex].precomposedStringWithCanonicalMapping {
                appendLegacy(.unchanged, oldTokens[oldIndex], to: &result)
                oldIndex += 1
                newIndex += 1
            } else if oldIndex < oldTokens.count,
                      newIndex == newTokens.count
                        || matrix[oldIndex + 1][newIndex] >= matrix[oldIndex][newIndex + 1] {
                appendLegacy(.removed, oldTokens[oldIndex], to: &result)
                oldIndex += 1
            } else {
                appendLegacy(.added, newTokens[newIndex], to: &result)
                newIndex += 1
            }
        }
        return result
    }

    private func appendLegacy(
        _ kind: DiffSegmentKind,
        _ text: String,
        to segments: inout [DiffSegment]
    ) {
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = DiffSegment(kind: kind, text: last.text + text)
        } else {
            segments.append(DiffSegment(kind: kind, text: text))
        }
    }
}
