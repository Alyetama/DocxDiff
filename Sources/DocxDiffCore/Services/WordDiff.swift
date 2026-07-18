import Foundation

public enum WordDiff {
    public static func segments(old: String, new: String) -> [DiffSegment] {
        // Compatibility entry point for synchronous callers that do not participate in
        // structured cancellation. The pipeline uses the throwing variant below.
        try! segmentsCancellable(old: old, new: new, cancellationCheck: {})
    }

    public static func segmentsCancellable(old: String, new: String) throws -> [DiffSegment] {
        try segmentsCancellable(old: old, new: new, cancellationCheck: checkTaskCancellation)
    }

    static func segmentsCancellable(
        old: String,
        new: String,
        cancellationCheck: () throws -> Void
    ) throws -> [DiffSegment] {
        let oldTokens = try cancellableTokens(in: old, cancellationCheck: cancellationCheck)
        let newTokens = try cancellableTokens(in: new, cancellationCheck: cancellationCheck)
        let matches = try CanonicalLCS.pairs(
            original: oldTokens,
            revised: newTokens,
            areEqual: { $0.key == $1.key },
            cancellationCheck: cancellationCheck
        )

        var result = SegmentAccumulator()
        var oldIndex = 0
        var newIndex = 0
        for (matchedOld, matchedNew) in matches {
            try cancellationCheck()
            while oldIndex < matchedOld {
                try cancellationCheck()
                result.append(.removed, text: oldTokens[oldIndex].display)
                oldIndex += 1
            }
            while newIndex < matchedNew {
                try cancellationCheck()
                result.append(.added, text: newTokens[newIndex].display)
                newIndex += 1
            }
            result.append(.unchanged, text: oldTokens[matchedOld].display)
            oldIndex = matchedOld + 1
            newIndex = matchedNew + 1
        }
        while oldIndex < oldTokens.count {
            try cancellationCheck()
            result.append(.removed, text: oldTokens[oldIndex].display)
            oldIndex += 1
        }
        while newIndex < newTokens.count {
            try cancellationCheck()
            result.append(.added, text: newTokens[newIndex].display)
            newIndex += 1
        }
        try cancellationCheck()
        return result.segments
    }

    public static func changedWordCounts(in segments: [DiffSegment]) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0

        for segment in segments {
            switch segment.kind {
            case .added:
                added += tokens(in: segment.text).count(where: isWord)
            case .removed:
                removed += tokens(in: segment.text).count(where: isWord)
            case .unchanged:
                continue
            }
        }

        return (added, removed)
    }

    static func tokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return tokenExpression.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static let tokenExpression = try! NSRegularExpression(
        pattern: "\\s+|[\\p{L}\\p{M}\\p{N}_]+|[^\\s\\p{L}\\p{M}\\p{N}_]"
    )

    private static func cancellableTokens(
        in text: String,
        cancellationCheck: () throws -> Void
    ) throws -> [Token] {
        let displays = try tokenStringsCancellable(
            in: text,
            cancellationCheck: cancellationCheck
        )
        var result: [Token] = []
        result.reserveCapacity(displays.count)
        for display in displays {
            try cancellationCheck()
            result.append(Token(display))
        }
        return result
    }

    /// Cancellation-aware equivalent of `tokenExpression`. It scans Unicode scalars so
    /// even one extremely long word or whitespace run has deterministic checkpoints.
    static func tokenStringsCancellable(
        in text: String,
        cancellationCheck: () throws -> Void
    ) throws -> [String] {
        try cancellationCheck()
        let scalars = text.unicodeScalars
        var result: [String] = []
        var tokenStart = scalars.startIndex
        var currentClass: TokenClass?
        var index = scalars.startIndex

        while index < scalars.endIndex {
            try cancellationCheck()
            let nextClass = tokenClass(for: scalars[index])
            if let currentClass,
               currentClass != nextClass || currentClass == .symbol {
                result.append(String(scalars[tokenStart..<index]))
                tokenStart = index
            }
            currentClass = nextClass
            index = scalars.index(after: index)
        }
        if currentClass != nil {
            result.append(String(scalars[tokenStart..<scalars.endIndex]))
        }
        return result
    }

    static func isWord(_ token: String) -> Bool {
        token.unicodeScalars.contains { scalar in
            if CharacterSet.letters.contains(scalar) {
                return true
            }

            switch scalar.properties.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber:
                return true
            default:
                return false
            }
        }
    }

    private static func checkTaskCancellation() throws {
        guard !Task.isCancelled else { throw DOCXError.cancelled }
    }

    private struct Token {
        let display: String
        let key: String

        init(_ display: String) {
            self.display = display
            key = display.precomposedStringWithCanonicalMapping
        }
    }

    private static func tokenClass(for scalar: Unicode.Scalar) -> TokenClass {
        if scalar.properties.isWhitespace { return .whitespace }
        if scalar == "_" { return .word }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return .word
        default:
            return .symbol
        }
    }

    private enum TokenClass {
        case whitespace
        case word
        case symbol
    }

    private struct SegmentAccumulator {
        private var groups: [Group] = []

        mutating func append(_ kind: DiffSegmentKind, text: String) {
            guard !text.isEmpty else { return }
            if groups.last?.kind == kind {
                groups[groups.count - 1].pieces.append(text)
            } else {
                groups.append(Group(kind: kind, pieces: [text]))
            }
        }

        var segments: [DiffSegment] {
            groups.map { group in
                DiffSegment(kind: group.kind, text: group.pieces.joined())
            }
        }

        private struct Group {
            let kind: DiffSegmentKind
            var pieces: [String]
        }
    }
}
