import XCTest
@testable import DocxDiffCore

final class ModelSmokeTests: XCTestCase {
    func testComparisonSummaryTotalsImageEvents() {
        let summary = ComparisonSummary(
            addedWords: 3,
            removedWords: 2,
            changedImages: 1
        )
        XCTAssertEqual(summary.totalChanges, 6)
    }
}
