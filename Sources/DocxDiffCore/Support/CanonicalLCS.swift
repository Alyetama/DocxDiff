import Foundation

/// Reconstructs the same canonical LCS path as the former suffix matrix:
/// diagonal when equal, otherwise original-removal on equal scores. Checkpointed
/// rows avoid retaining the full O(n*m) matrix while keeping exact tie semantics.
enum CanonicalLCS {
    static func pairs<Element>(
        original: [Element],
        revised: [Element],
        areEqual: (Element, Element) -> Bool,
        cancellationCheck: () throws -> Void
    ) throws -> [(Int, Int)] {
        try cancellationCheck()
        guard !original.isEmpty, !revised.isEmpty else { return [] }

        if original.count == 1 {
            for revisedIndex in revised.indices {
                try cancellationCheck()
                if areEqual(original[0], revised[revisedIndex]) { return [(0, revisedIndex)] }
            }
            return []
        }
        if revised.count == 1 {
            for originalIndex in original.indices {
                try cancellationCheck()
                if areEqual(original[originalIndex], revised[0]) { return [(originalIndex, 0)] }
            }
            return []
        }

        let blockSize = max(1, Int(Double(original.count).squareRoot().rounded(.up)))
        let checkpoints = try suffixCheckpoints(
            original: original,
            revised: revised,
            blockSize: blockSize,
            areEqual: areEqual,
            cancellationCheck: cancellationCheck
        )

        var pairs: [(Int, Int)] = []
        pairs.reserveCapacity(min(original.count, revised.count))
        var originalIndex = 0
        var revisedIndex = 0
        while originalIndex < original.count, revisedIndex < revised.count {
            try cancellationCheck()
            let blockStart = originalIndex
            let blockEnd = min(
                ((blockStart / blockSize) + 1) * blockSize,
                original.count
            )
            guard let boundary = checkpoints[blockEnd] else { preconditionFailure("Missing LCS checkpoint") }
            let rows = try blockRows(
                original: original,
                revised: revised,
                range: blockStart..<blockEnd,
                boundary: boundary,
                areEqual: areEqual,
                cancellationCheck: cancellationCheck
            )

            while originalIndex < blockEnd, revisedIndex < revised.count {
                if revisedIndex & 0xFF == 0 { try cancellationCheck() }
                let localRow = originalIndex - blockStart
                if areEqual(original[originalIndex], revised[revisedIndex]) {
                    pairs.append((originalIndex, revisedIndex))
                    originalIndex += 1
                    revisedIndex += 1
                } else if rows[localRow + 1][revisedIndex] >= rows[localRow][revisedIndex + 1] {
                    originalIndex += 1
                } else {
                    revisedIndex += 1
                }
            }
        }
        return pairs
    }

    private static func suffixCheckpoints<Element>(
        original: [Element],
        revised: [Element],
        blockSize: Int,
        areEqual: (Element, Element) -> Bool,
        cancellationCheck: () throws -> Void
    ) throws -> [Int: [Int]] {
        var checkpoints: [Int: [Int]] = [
            original.count: Array(repeating: 0, count: revised.count + 1)
        ]
        var next = Array(repeating: 0, count: revised.count + 1)
        var current = next
        for originalIndex in original.indices.reversed() {
            try cancellationCheck()
            current[revised.count] = 0
            for revisedIndex in revised.indices.reversed() {
                if revisedIndex & 0xFF == 0 { try cancellationCheck() }
                if areEqual(original[originalIndex], revised[revisedIndex]) {
                    current[revisedIndex] = next[revisedIndex + 1] + 1
                } else {
                    current[revisedIndex] = max(next[revisedIndex], current[revisedIndex + 1])
                }
            }
            swap(&next, &current)
            if originalIndex % blockSize == 0 {
                checkpoints[originalIndex] = next
            }
        }
        return checkpoints
    }

    private static func blockRows<Element>(
        original: [Element],
        revised: [Element],
        range: Range<Int>,
        boundary: [Int],
        areEqual: (Element, Element) -> Bool,
        cancellationCheck: () throws -> Void
    ) throws -> [[Int]] {
        var rows = Array(
            repeating: Array(repeating: 0, count: revised.count + 1),
            count: range.count + 1
        )
        rows[range.count] = boundary
        for originalIndex in range.reversed() {
            try cancellationCheck()
            let localRow = originalIndex - range.lowerBound
            rows[localRow][revised.count] = 0
            for revisedIndex in revised.indices.reversed() {
                if revisedIndex & 0xFF == 0 { try cancellationCheck() }
                if areEqual(original[originalIndex], revised[revisedIndex]) {
                    rows[localRow][revisedIndex] = rows[localRow + 1][revisedIndex + 1] + 1
                } else {
                    rows[localRow][revisedIndex] = max(
                        rows[localRow + 1][revisedIndex],
                        rows[localRow][revisedIndex + 1]
                    )
                }
            }
        }
        return rows
    }
}
