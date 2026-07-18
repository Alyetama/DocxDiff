import SwiftUI
import DocxDiffCore

struct ChangeListView: View {
    let store: ComparisonStore
    let onPreview: (ImagePreviewSelection) -> Void

    var body: some View {
        if store.filteredChanges.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Choose another filter to see the remaining changes.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.filteredChanges) { change in
                        switch change.payload {
                        case .text(let textChange):
                            TextChangeCard(change: textChange)
                        case .image(let imageChange):
                            ImageChangeCard(change: imageChange, onPreview: onPreview)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyTitle: String {
        switch store.filter {
        case .all:
            "No content changes"
        case .text:
            "No text changes"
        case .images:
            "No image changes"
        }
    }
}
