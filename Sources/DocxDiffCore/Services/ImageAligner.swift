import Foundation

public enum ImageAligner {
    public static func changes(original: [ImageBlock], revised: [ImageBlock]) -> [ImageChange] {
        let originalIndices = stableIndices(for: original)
        let revisedIndices = stableIndices(for: revised)
        var matchedOriginal: Set<Int> = []
        var matchedRevised: Set<Int> = []

        for originalIndex in originalIndices {
            guard let revisedIndex = revisedIndices.first(where: {
                !matchedRevised.contains($0) && revised[$0].digest == original[originalIndex].digest
            }) else {
                continue
            }
            matchedOriginal.insert(originalIndex)
            matchedRevised.insert(revisedIndex)
        }

        var candidates: [ReplacementCandidate] = []
        for originalIndex in originalIndices where !matchedOriginal.contains(originalIndex) {
            for revisedIndex in revisedIndices where !matchedRevised.contains(revisedIndex) {
                let score = anchorScore(original[originalIndex].anchor, revised[revisedIndex].anchor)
                let orderDistance = abs(original[originalIndex].order - revised[revisedIndex].order)
                let isNearbyEmptyAnchorPair = original[originalIndex].anchor.docxNormalized.isEmpty
                    && revised[revisedIndex].anchor.docxNormalized.isEmpty
                    && orderDistance <= 1
                if score >= 0.60 || isNearbyEmptyAnchorPair {
                    candidates.append(
                        ReplacementCandidate(
                            originalIndex: originalIndex,
                            revisedIndex: revisedIndex,
                            // Textual anchors remain stronger than structural fallback.
                            score: isNearbyEmptyAnchorPair ? 0.59 : score,
                            orderDistance: orderDistance,
                            originalOrder: original[originalIndex].order,
                            revisedOrder: revised[revisedIndex].order
                        )
                    )
                }
            }
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.orderDistance != $1.orderDistance { return $0.orderDistance < $1.orderDistance }
            if $0.originalOrder != $1.originalOrder { return $0.originalOrder < $1.originalOrder }
            if $0.revisedOrder != $1.revisedOrder { return $0.revisedOrder < $1.revisedOrder }
            if $0.originalIndex != $1.originalIndex { return $0.originalIndex < $1.originalIndex }
            return $0.revisedIndex < $1.revisedIndex
        }

        var events: [ImageChange] = []
        for candidate in candidates {
            guard !matchedOriginal.contains(candidate.originalIndex),
                  !matchedRevised.contains(candidate.revisedIndex) else {
                continue
            }

            let oldImage = original[candidate.originalIndex]
            let newImage = revised[candidate.revisedIndex]
            matchedOriginal.insert(candidate.originalIndex)
            matchedRevised.insert(candidate.revisedIndex)
            events.append(
                ImageChange(
                    order: newImage.order,
                    kind: .replaced,
                    oldImage: oldImage,
                    newImage: newImage,
                    anchor: newImage.anchor
                )
            )
        }

        for index in originalIndices where !matchedOriginal.contains(index) {
            let image = original[index]
            events.append(
                ImageChange(
                    order: image.order,
                    kind: .removed,
                    oldImage: image,
                    newImage: nil,
                    anchor: image.anchor
                )
            )
        }

        for index in revisedIndices where !matchedRevised.contains(index) {
            let image = revised[index]
            events.append(
                ImageChange(
                    order: image.order,
                    kind: .added,
                    oldImage: nil,
                    newImage: image,
                    anchor: image.anchor
                )
            )
        }

        return events.enumerated().sorted {
            if $0.element.order != $1.element.order { return $0.element.order < $1.element.order }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    private static func stableIndices(for images: [ImageBlock]) -> [Int] {
        images.indices.sorted {
            if images[$0].order != images[$1].order { return images[$0].order < images[$1].order }
            return $0 < $1
        }
    }

    private static func anchorScore(_ original: String, _ revised: String) -> Double {
        let normalizedOriginal = original.docxNormalized.lowercased()
        let normalizedRevised = revised.docxNormalized.lowercased()
        if !normalizedOriginal.isEmpty, normalizedOriginal == normalizedRevised {
            return 1
        }

        let originalTokens = wordSet(in: normalizedOriginal)
        let revisedTokens = wordSet(in: normalizedRevised)
        let union = originalTokens.union(revisedTokens)
        guard !union.isEmpty else { return 0 }
        return Double(originalTokens.intersection(revisedTokens).count) / Double(union.count)
    }

    private static func wordSet(in text: String) -> Set<String> {
        Set(WordDiff.tokens(in: text).filter(WordDiff.isWord).map { $0.lowercased() })
    }

    private struct ReplacementCandidate {
        let originalIndex: Int
        let revisedIndex: Int
        let score: Double
        let orderDistance: Int
        let originalOrder: Int
        let revisedOrder: Int
    }
}
