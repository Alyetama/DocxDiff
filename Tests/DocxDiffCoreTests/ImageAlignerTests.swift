import Foundation
import XCTest
@testable import DocxDiffCore

final class ImageAlignerTests: XCTestCase {
    func testSameDigestAtDifferentOrderProducesNoChange() {
        let old = image(order: 1, digest: "same", anchor: "Figure 1")
        let new = image(order: 8, digest: "same", anchor: "A different location")

        XCTAssertEqual(ImageAligner.changes(original: [old], revised: [new]), [])
    }

    func testDifferentBytesAtSameAnchorAreReplacement() {
        let old = image(order: 3, digest: "old", anchor: "Figure 2. Results")
        let new = image(order: 5, digest: "new", anchor: "Figure 2. Results")

        let changes = ImageAligner.changes(original: [old], revised: [new])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .replaced)
        XCTAssertEqual(changes[0].oldImage, old)
        XCTAssertEqual(changes[0].newImage, new)
    }

    func testSimilarAnchorsAreReplacementAtJaccardThreshold() {
        let old = image(order: 2, digest: "old", anchor: "Figure 2 treatment results")
        let new = image(order: 3, digest: "new", anchor: "Figure 2 revised results")

        let changes = ImageAligner.changes(original: [old], revised: [new])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .replaced)
        XCTAssertEqual(changes[0].oldImage, old)
        XCTAssertEqual(changes[0].newImage, new)
    }

    func testUnmatchedOldImageIsRemoved() {
        let old = image(order: 4, digest: "old", anchor: "Figure 3")

        let changes = ImageAligner.changes(original: [old], revised: [])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .removed)
        XCTAssertEqual(changes[0].oldImage, old)
        XCTAssertNil(changes[0].newImage)
    }

    func testUnmatchedNewImageIsAdded() {
        let new = image(order: 6, digest: "new", anchor: "Figure 4")

        let changes = ImageAligner.changes(original: [], revised: [new])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .added)
        XCTAssertNil(changes[0].oldImage)
        XCTAssertEqual(changes[0].newImage, new)
    }

    func testTextInsertionBeforeUnchangedImageProducesNoImageChange() {
        let old = image(order: 2, digest: "same", anchor: "Figure 5")
        let new = image(order: 3, digest: "same", anchor: "Inserted text before Figure 5")

        XCTAssertEqual(ImageAligner.changes(original: [old], revised: [new]), [])
    }

    func testSingleEmptyAnchorImageAtSameStructuralPositionIsReplacement() {
        let old = image(order: 0, digest: "old", anchor: "")
        let new = image(order: 0, digest: "new", anchor: "")

        let changes = ImageAligner.changes(original: [old], revised: [new])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .replaced)
        XCTAssertEqual(changes.first?.oldImage, old)
        XCTAssertEqual(changes.first?.newImage, new)
    }

    func testDistantGroupsOfEmptyAnchorImagesAreNotOvermatched() {
        let old = [
            image(order: 0, digest: "old-1", anchor: ""),
            image(order: 1, digest: "old-2", anchor: "")
        ]
        let new = [
            image(order: 8, digest: "new-1", anchor: ""),
            image(order: 9, digest: "new-2", anchor: "")
        ]

        let changes = ImageAligner.changes(original: old, revised: new)

        XCTAssertEqual(changes.map(\.kind), [.removed, .removed, .added, .added])
    }

    private func image(order: Int, digest: String, anchor: String) -> ImageBlock {
        ImageBlock(
            order: order,
            data: Data(digest.utf8),
            digest: digest,
            mediaExtension: "png",
            anchor: anchor
        )
    }
}
