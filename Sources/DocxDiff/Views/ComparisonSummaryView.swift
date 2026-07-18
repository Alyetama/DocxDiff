import SwiftUI
import DocxDiffCore

struct ComparisonSummaryView: View {
    let summary: ComparisonSummary
    @Binding var filter: ChangeFilter

    var body: some View {
        HStack(spacing: 12) {
            summaryChip(
                "\(summary.addedWords) added",
                systemImage: "plus",
                color: .green
            )
            summaryChip(
                "\(summary.removedWords) removed",
                systemImage: "minus",
                color: .red
            )
            summaryChip(
                "\(summary.changedImages) figures",
                systemImage: "photo",
                color: .blue
            )

            Spacer(minLength: 12)

            Picker("Changes", selection: $filter) {
                ForEach(ChangeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
    }

    private func summaryChip(
        _ label: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(label, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel(label)
    }
}
