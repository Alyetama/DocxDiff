import XCTest
@testable import DocxDiff
import DocxDiffCore

final class TextChangeBoundaryTests: XCTestCase {
    func testDifferentChangedWordsNeedVisualSeparator() {
        XCTAssertTrue(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "small"),
                and: DiffSegment(kind: .added, text: "statistically significant")
            )
        )
    }

    func testExistingBoundaryWhitespaceNeedsNoVisualSeparator() {
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "small "),
                and: DiffSegment(kind: .added, text: "statistically")
            )
        )
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "small"),
                and: DiffSegment(kind: .added, text: " statistically")
            )
        )
    }

    func testPunctuationBoundaryNeedsNoVisualSeparator() {
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "word"),
                and: DiffSegment(kind: .added, text: ",")
            )
        )
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "("),
                and: DiffSegment(kind: .added, text: "word")
            )
        )
    }

    func testSameKindAndUnchangedBoundariesNeedNoVisualSeparator() {
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .removed, text: "old"),
                and: DiffSegment(kind: .removed, text: "text")
            )
        )
        XCTAssertFalse(
            TextChangeBoundary.needsVisualSeparator(
                between: DiffSegment(kind: .unchanged, text: "same"),
                and: DiffSegment(kind: .added, text: "word")
            )
        )
    }
}
