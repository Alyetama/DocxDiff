import DocxDiffCore

struct ComparisonResultPresentation {
    let result: ComparisonResult

    var warningHeading: String? {
        result.warnings.isEmpty ? nil : "Comparison incomplete"
    }

    var accessibleWarningText: String? {
        guard let warningHeading else { return nil }
        return ([warningHeading + "."] + result.warnings).joined(separator: " ")
    }

    var emptyTitle: String {
        result.warnings.isEmpty ? "No content changes" : "No detected content changes"
    }

    var emptyDescription: String {
        if result.warnings.isEmpty {
            return "The documents have the same text and figures."
        }
        return "Some content could not be compared. Review the warnings above before treating these documents as identical."
    }
}
