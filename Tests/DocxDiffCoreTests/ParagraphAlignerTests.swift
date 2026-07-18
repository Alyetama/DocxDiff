import XCTest
@testable import DocxDiffCore

final class ParagraphAlignerTests: XCTestCase {
    func testEditedParagraphBecomesOneTextChange() {
        let old = [ParagraphBlock(order: 0, text: "Cats prefer the first figure.")]
        let new = [ParagraphBlock(order: 0, text: "Cats prefer the revised figure.")]
        let changes = ParagraphAligner.changes(original: old, revised: new)

        guard changes.count == 1 else {
            return XCTFail("Expected one edited paragraph, got \(changes.count)")
        }
        XCTAssertEqual(changes[0].oldText, old[0].text)
        XCTAssertEqual(changes[0].newText, new[0].text)
    }

    func testOneThirdTokenOverlapPairsShortParagraphAsOneEdit() {
        let old = [ParagraphBlock(order: 0, text: "Table result")]
        let new = [ParagraphBlock(order: 0, text: "Table finding")]

        let changes = ParagraphAligner.changes(original: old, revised: new)

        guard changes.count == 1 else {
            return XCTFail("Expected one short-paragraph edit at the one-third boundary, got \(changes.count)")
        }
        XCTAssertEqual(changes[0].oldText, "Table result")
        XCTAssertEqual(changes[0].newText, "Table finding")
    }

    func testInsertionDoesNotMarkLaterEqualParagraphsChanged() {
        let old = [
            ParagraphBlock(order: 0, text: "Introduction"),
            ParagraphBlock(order: 1, text: "Results")
        ]
        let new = [
            ParagraphBlock(order: 0, text: "Introduction"),
            ParagraphBlock(order: 1, text: "New context"),
            ParagraphBlock(order: 2, text: "Results")
        ]
        let changes = ParagraphAligner.changes(original: old, revised: new)
        XCTAssertEqual(changes.map(\.newText), ["New context"])
    }

    func testUnrelatedParagraphIsRemovedBeforeLaterSimilarParagraphIsPaired() {
        let old = [
            ParagraphBlock(order: 0, text: "Unrelated heading"),
            ParagraphBlock(order: 1, text: "Cats prefer the first figure.")
        ]
        let new = [ParagraphBlock(order: 0, text: "Cats prefer the revised figure.")]

        let changes = ParagraphAligner.changes(original: old, revised: new)

        XCTAssertEqual(changes.map(\.oldText), ["Unrelated heading", "Cats prefer the first figure."])
        XCTAssertEqual(changes.map(\.newText), ["", "Cats prefer the revised figure."])
    }

    func testCanonicallyEquivalentParagraphsProduceNoChange() {
        let old = [ParagraphBlock(order: 0, text: "Cafe\u{301} results")]
        let new = [ParagraphBlock(order: 0, text: "Café results")]

        XCTAssertEqual(ParagraphAligner.changes(original: old, revised: new), [])
    }

    func testCancellationIsCheckedDuringLongParagraphAlignment() {
        let old = (0..<200).map { ParagraphBlock(order: $0, text: "Old paragraph \($0)") }
        let new = (0..<200).map { ParagraphBlock(order: $0, text: "New paragraph \($0)") }
        var checks = 0

        XCTAssertThrowsError(
            try ParagraphAligner.changesCancellable(original: old, revised: new) {
                checks += 1
                if checks == 20 { throw DOCXError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, 20)
    }

    func testRepeatedExactParagraphKeepsFirstMatchAndRemovesTrailingDuplicate() {
        let old = [
            ParagraphBlock(order: 0, text: "Repeated"),
            ParagraphBlock(order: 1, text: "Repeated")
        ]
        let new = [ParagraphBlock(order: 10, text: "Repeated")]

        let changes = ParagraphAligner.changes(original: old, revised: new)

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.order, 1)
        XCTAssertEqual(changes.first?.oldText, "Repeated")
        XCTAssertEqual(changes.first?.newText, "")
    }

    func testMemoryBoundedExactAnchorsMatchLegacyDPForRepeatedParagraphSequences() throws {
        let sequences = paragraphSequences(maximumLength: 5)
        for original in sequences {
            for revised in sequences {
                XCTAssertEqual(
                    try ParagraphAligner.exactAnchorPairs(
                        original: blocks(original),
                        revised: blocks(revised),
                        cancellationCheck: {}
                    ).map { Pair($0.0, $0.1) },
                    legacyExactAnchorPairs(original: original, revised: revised).map { Pair($0.0, $0.1) },
                    "Legacy paragraph anchors differ for original=\(original), revised=\(revised)"
                )
            }
        }
    }

    func testCancellationIsCheckedInsideSingleParagraphBaseCaseScan() {
        let original = [ParagraphBlock(order: 0, text: "Needle")]
        let revised = (0..<200).map { ParagraphBlock(order: $0, text: "Other \($0)") }
        var checks = 0

        XCTAssertThrowsError(
            try ParagraphAligner.exactAnchorPairs(
                original: original,
                revised: revised,
                cancellationCheck: {
                    checks += 1
                    if checks == 5 { throw DOCXError.cancelled }
                }
            )
        ) { error in
            XCTAssertEqual(error as? DOCXError, .cancelled)
        }
        XCTAssertEqual(checks, 5)
    }

    private func paragraphSequences(maximumLength: Int) -> [[String]] {
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

    private func blocks(_ values: [String]) -> [ParagraphBlock] {
        values.enumerated().map { ParagraphBlock(order: $0.offset, text: $0.element) }
    }

    private func legacyExactAnchorPairs(
        original: [String],
        revised: [String]
    ) -> [(Int, Int)] {
        var matrix = Array(
            repeating: Array(repeating: 0, count: revised.count + 1),
            count: original.count + 1
        )
        for originalIndex in original.indices.reversed() {
            for revisedIndex in revised.indices.reversed() {
                if original[originalIndex].docxNormalized == revised[revisedIndex].docxNormalized {
                    matrix[originalIndex][revisedIndex] = matrix[originalIndex + 1][revisedIndex + 1] + 1
                } else {
                    matrix[originalIndex][revisedIndex] = max(
                        matrix[originalIndex + 1][revisedIndex],
                        matrix[originalIndex][revisedIndex + 1]
                    )
                }
            }
        }

        var pairs: [(Int, Int)] = []
        var originalIndex = 0
        var revisedIndex = 0
        while originalIndex < original.count, revisedIndex < revised.count {
            if original[originalIndex].docxNormalized == revised[revisedIndex].docxNormalized {
                pairs.append((originalIndex, revisedIndex))
                originalIndex += 1
                revisedIndex += 1
            } else if matrix[originalIndex + 1][revisedIndex]
                        >= matrix[originalIndex][revisedIndex + 1] {
                originalIndex += 1
            } else {
                revisedIndex += 1
            }
        }
        return pairs
    }

    private struct Pair: Equatable {
        let original: Int
        let revised: Int

        init(_ original: Int, _ revised: Int) {
            self.original = original
            self.revised = revised
        }
    }
}
