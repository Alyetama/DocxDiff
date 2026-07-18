import XCTest
@testable import DocxDiff
import DocxDiffCore

final class ComparisonPresentationTests: XCTestCase {
    func testWarningOnlyResultUsesIncompleteComparisonEmptyState() {
        let result = ComparisonResult(
            changes: [],
            summary: ComparisonSummary(addedWords: 0, removedWords: 0, changedImages: 0),
            warnings: ["Skipped embedded image rId7."]
        )

        let presentation = ComparisonResultPresentation(result: result)

        XCTAssertEqual(presentation.emptyTitle, "No detected content changes")
        XCTAssertTrue(presentation.emptyDescription.contains("could not be compared"))
        XCTAssertFalse(presentation.emptyDescription.contains("same text and figures"))
        XCTAssertEqual(presentation.warningHeading, "Comparison incomplete")
        XCTAssertEqual(presentation.accessibleWarningText, "Comparison incomplete. Skipped embedded image rId7.")
    }

    func testCleanNoChangeResultKeepsReassuringEmptyState() {
        let presentation = ComparisonResultPresentation(result: .empty)

        XCTAssertEqual(presentation.emptyTitle, "No content changes")
        XCTAssertEqual(presentation.emptyDescription, "The documents have the same text and figures.")
        XCTAssertNil(presentation.warningHeading)
    }
}
