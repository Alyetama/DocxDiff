import Foundation

public enum ParagraphAligner {
    public static func changes(original: [ParagraphBlock], revised: [ParagraphBlock]) -> [TextChange] {
        try! changesCancellable(original: original, revised: revised, cancellationCheck: {})
    }

    public static func changesCancellable(
        original: [ParagraphBlock],
        revised: [ParagraphBlock]
    ) throws -> [TextChange] {
        try changesCancellable(
            original: original,
            revised: revised,
            cancellationCheck: checkTaskCancellation
        )
    }

    static func changesCancellable(
        original: [ParagraphBlock],
        revised: [ParagraphBlock],
        cancellationCheck: () throws -> Void
    ) throws -> [TextChange] {
        let anchors = try exactAnchorPairs(
            original: original,
            revised: revised,
            cancellationCheck: cancellationCheck
        )
        var changes: [TextChange] = []
        var originalStart = 0
        var revisedStart = 0

        for (originalIndex, revisedIndex) in anchors {
            try appendChanges(
                original: Array(original[originalStart..<originalIndex]),
                revised: Array(revised[revisedStart..<revisedIndex]),
                to: &changes,
                cancellationCheck: cancellationCheck
            )
            originalStart = originalIndex + 1
            revisedStart = revisedIndex + 1
        }

        try appendChanges(
            original: Array(original[originalStart..<original.count]),
            revised: Array(revised[revisedStart..<revised.count]),
            to: &changes,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
        return changes
    }

    static func exactAnchorPairs(
        original: [ParagraphBlock],
        revised: [ParagraphBlock],
        cancellationCheck: () throws -> Void
    ) throws -> [(Int, Int)] {
        let originalText = original.map { $0.text.docxNormalized }
        let revisedText = revised.map { $0.text.docxNormalized }
        return try CanonicalLCS.pairs(
            original: originalText,
            revised: revisedText,
            areEqual: ==,
            cancellationCheck: cancellationCheck
        )
    }

    private static func appendChanges(
        original: [ParagraphBlock],
        revised: [ParagraphBlock],
        to changes: inout [TextChange],
        cancellationCheck: () throws -> Void
    ) throws {
        let pairs = try similarPairs(original, revised, cancellationCheck: cancellationCheck)
        var originalIndex = 0
        var revisedIndex = 0

        for (pairedOriginal, pairedRevised) in pairs {
            while originalIndex < pairedOriginal {
                try appendRemoved(original[originalIndex], to: &changes, cancellationCheck: cancellationCheck)
                originalIndex += 1
            }
            while revisedIndex < pairedRevised {
                try appendAdded(revised[revisedIndex], to: &changes, cancellationCheck: cancellationCheck)
                revisedIndex += 1
            }

            let old = original[pairedOriginal]
            let new = revised[pairedRevised]
            if old.text.docxNormalized != new.text.docxNormalized {
                changes.append(
                    TextChange(
                        order: new.order,
                        oldText: old.text,
                        newText: new.text,
                        segments: try WordDiff.segmentsCancellable(
                            old: old.text,
                            new: new.text,
                            cancellationCheck: cancellationCheck
                        )
                    )
                )
            }
            originalIndex = pairedOriginal + 1
            revisedIndex = pairedRevised + 1
        }

        while originalIndex < original.count {
            try appendRemoved(original[originalIndex], to: &changes, cancellationCheck: cancellationCheck)
            originalIndex += 1
        }
        while revisedIndex < revised.count {
            try appendAdded(revised[revisedIndex], to: &changes, cancellationCheck: cancellationCheck)
            revisedIndex += 1
        }
    }

    private static func appendRemoved(
        _ paragraph: ParagraphBlock,
        to changes: inout [TextChange],
        cancellationCheck: () throws -> Void
    ) throws {
        changes.append(
            TextChange(
                order: paragraph.order,
                oldText: paragraph.text,
                newText: "",
                segments: try WordDiff.segmentsCancellable(
                    old: paragraph.text,
                    new: "",
                    cancellationCheck: cancellationCheck
                )
            )
        )
    }

    private static func appendAdded(
        _ paragraph: ParagraphBlock,
        to changes: inout [TextChange],
        cancellationCheck: () throws -> Void
    ) throws {
        changes.append(
            TextChange(
                order: paragraph.order,
                oldText: "",
                newText: paragraph.text,
                segments: try WordDiff.segmentsCancellable(
                    old: "",
                    new: paragraph.text,
                    cancellationCheck: cancellationCheck
                )
            )
        )
    }

    private static func similarPairs(
        _ original: [ParagraphBlock],
        _ revised: [ParagraphBlock],
        cancellationCheck: () throws -> Void
    ) throws -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        pairs.reserveCapacity(min(original.count, revised.count))
        try appendSimilarPairs(
            original,
            originalRange: 0..<original.count,
            revised,
            revisedRange: 0..<revised.count,
            to: &pairs,
            cancellationCheck: cancellationCheck
        )
        return pairs
    }

    /// Hirschberg reconstruction for the weighted, ordered paragraph pairing.
    private static func appendSimilarPairs(
        _ original: [ParagraphBlock],
        originalRange: Range<Int>,
        _ revised: [ParagraphBlock],
        revisedRange: Range<Int>,
        to pairs: inout [(Int, Int)],
        cancellationCheck: () throws -> Void
    ) throws {
        try cancellationCheck()
        guard !originalRange.isEmpty, !revisedRange.isEmpty else { return }
        if originalRange.count == 1 {
            let originalIndex = originalRange.lowerBound
            var bestIndex: Int?
            var bestSimilarity = -1.0
            for revisedIndex in revisedRange {
                try cancellationCheck()
                let similarity = jaccardSimilarity(
                    original[originalIndex].text,
                    revised[revisedIndex].text
                )
                if similarity >= 1.0 / 3.0, similarity > bestSimilarity {
                    bestIndex = revisedIndex
                    bestSimilarity = similarity
                }
            }
            if let bestIndex { pairs.append((originalIndex, bestIndex)) }
            return
        }

        let originalMiddle = originalRange.lowerBound + originalRange.count / 2
        let splitOffset = try similaritySplitOffset(
            original,
            originalMiddle: originalMiddle,
            originalRange: originalRange,
            revised,
            revisedRange: revisedRange,
            cancellationCheck: cancellationCheck
        )
        let revisedMiddle = revisedRange.lowerBound + splitOffset
        try appendSimilarPairs(
            original,
            originalRange: originalRange.lowerBound..<originalMiddle,
            revised,
            revisedRange: revisedRange.lowerBound..<revisedMiddle,
            to: &pairs,
            cancellationCheck: cancellationCheck
        )
        try appendSimilarPairs(
            original,
            originalRange: originalMiddle..<originalRange.upperBound,
            revised,
            revisedRange: revisedMiddle..<revisedRange.upperBound,
            to: &pairs,
            cancellationCheck: cancellationCheck
        )
    }

    private static func similaritySplitOffset(
        _ original: [ParagraphBlock],
        originalMiddle: Int,
        originalRange: Range<Int>,
        _ revised: [ParagraphBlock],
        revisedRange: Range<Int>,
        cancellationCheck: () throws -> Void
    ) throws -> Int {
        let forward = try similarityPrefixScores(
            original,
            originalRange: originalRange.lowerBound..<originalMiddle,
            revised,
            revisedRange: revisedRange,
            reversed: false,
            cancellationCheck: cancellationCheck
        )
        let backward = try similarityPrefixScores(
            original,
            originalRange: originalMiddle..<originalRange.upperBound,
            revised,
            revisedRange: revisedRange,
            reversed: true,
            cancellationCheck: cancellationCheck
        )
        var splitOffset = 0
        var best = AlignmentScore.invalid
        for offset in 0...revisedRange.count {
            let score = forward[offset] + backward[revisedRange.count - offset]
            if score.isBetter(than: best) {
                best = score
                splitOffset = offset
            }
        }
        return splitOffset
    }

    private static func similarityPrefixScores(
        _ original: [ParagraphBlock],
        originalRange: Range<Int>,
        _ revised: [ParagraphBlock],
        revisedRange: Range<Int>,
        reversed: Bool,
        cancellationCheck: () throws -> Void
    ) throws -> [AlignmentScore] {
        var previous = Array(repeating: AlignmentScore.zero, count: revisedRange.count + 1)
        var current = previous
        let originalIndices = reversed ? Array(originalRange.reversed()) : Array(originalRange)
        let revisedIndices = reversed ? Array(revisedRange.reversed()) : Array(revisedRange)
        for originalIndex in originalIndices {
            try cancellationCheck()
            current[0] = .zero
            for (offset, revisedIndex) in revisedIndices.enumerated() {
                if offset & 0x3F == 0 { try cancellationCheck() }
                let remove = previous[offset + 1]
                let add = current[offset]
                var best = remove.isAtLeast(asGoodAs: add) ? remove : add
                let similarity = jaccardSimilarity(
                    original[originalIndex].text,
                    revised[revisedIndex].text
                )
                if similarity >= 1.0 / 3.0 {
                    let pair = previous[offset].adding(similarity: similarity)
                    if pair.isAtLeast(asGoodAs: best) { best = pair }
                }
                current[offset + 1] = best
            }
            swap(&previous, &current)
        }
        return previous
    }

    private static func jaccardSimilarity(_ old: String, _ new: String) -> Double {
        let oldTokens = wordSet(in: old)
        let newTokens = wordSet(in: new)
        let union = oldTokens.union(newTokens)
        guard !union.isEmpty else { return old.docxNormalized == new.docxNormalized ? 1 : 0 }
        return Double(oldTokens.intersection(newTokens).count) / Double(union.count)
    }

    private static func wordSet(in text: String) -> Set<String> {
        Set(WordDiff.tokens(in: text).compactMap {
            WordDiff.isWord($0) ? $0.docxNormalized.lowercased() : nil
        })
    }

    private static func checkTaskCancellation() throws {
        guard !Task.isCancelled else { throw DOCXError.cancelled }
    }

    private struct AlignmentScore {
        let pairCount: Int
        let similarity: Double

        static let zero = AlignmentScore(pairCount: 0, similarity: 0)
        static let invalid = AlignmentScore(pairCount: -1, similarity: -.infinity)

        static func + (left: AlignmentScore, right: AlignmentScore) -> AlignmentScore {
            AlignmentScore(
                pairCount: left.pairCount + right.pairCount,
                similarity: left.similarity + right.similarity
            )
        }

        func adding(similarity: Double) -> AlignmentScore {
            AlignmentScore(pairCount: pairCount + 1, similarity: self.similarity + similarity)
        }

        func isAtLeast(asGoodAs other: AlignmentScore) -> Bool {
            pairCount > other.pairCount || (pairCount == other.pairCount && similarity >= other.similarity)
        }

        func isBetter(than other: AlignmentScore) -> Bool {
            pairCount > other.pairCount || (pairCount == other.pairCount && similarity > other.similarity)
        }
    }
}
