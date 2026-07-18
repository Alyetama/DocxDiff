import SwiftUI
import DocxDiffCore

struct TextChangeCard: View {
    let change: TextChange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Paragraph \(change.order + 1)")
                    .font(.headline)

                Spacer()

                changeLegend
            }

            diffText
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paragraph \(change.order + 1), text changed")
        .accessibilityValue("Original: \(change.oldText). Revised: \(change.newText)")
    }

    private var changeLegend: some View {
        HStack(spacing: 10) {
            Label("Added", systemImage: "plus.circle.fill")
                .foregroundStyle(.green)
            Label("Removed", systemImage: "minus.circle.fill")
                .foregroundStyle(.red)
        }
        .font(.caption.weight(.semibold))
    }

    private var diffText: Text {
        var result = Text("")

        for (index, segment) in change.segments.enumerated() {
            if index > 0,
               TextChangeBoundary.needsVisualSeparator(
                   between: change.segments[index - 1],
                   and: segment
               ) {
                result = result + Text(" ")
            }
            result = result + styled(segment)
        }

        return result
    }

    private func styled(_ segment: DiffSegment) -> Text {
        switch segment.kind {
        case .unchanged:
            return Text(segment.text)
        case .added:
            return Text(segment.text)
                .foregroundColor(.green)
                .bold()
        case .removed:
            return Text(segment.text)
                .foregroundColor(.red)
                .strikethrough()
        }
    }
}

enum TextChangeBoundary {
    static func needsVisualSeparator(
        between previous: DiffSegment,
        and next: DiffSegment
    ) -> Bool {
        guard previous.kind != .unchanged,
              next.kind != .unchanged,
              previous.kind != next.kind,
              let trailingCharacter = previous.text.last,
              let leadingCharacter = next.text.first,
              !trailingCharacter.isWhitespace,
              !leadingCharacter.isWhitespace,
              !trailingCharacter.isPunctuation,
              !leadingCharacter.isPunctuation else {
            return false
        }

        return true
    }
}
