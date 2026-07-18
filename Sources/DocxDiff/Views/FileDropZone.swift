import SwiftUI
import UniformTypeIdentifiers
import DocxDiffCore

struct FileDropZone: View {
    let side: DocumentSide
    let store: ComparisonStore
    let onChoose: () -> Void

    @State private var isDropTargeted = false

    private var url: URL? {
        switch side {
        case .original:
            store.originalURL
        case .revised:
            store.revisedURL
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(side.title)
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: url == nil ? "doc.badge.plus" : "doc.fill")
                    .font(.title2)
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url?.lastPathComponent ?? "Drop DOCX here")
                        .fontWeight(url == nil ? .regular : .medium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(url == nil ? "Microsoft Word document" : "Drop another file to replace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Choose File…", action: onChoose)
            }

            if let error = store.inputErrors[side] {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(side.title) file error: \(error)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: acceptDrop)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(side.title) document, \(url?.lastPathComponent ?? "no file selected")")
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.canLoadObject(ofClass: NSURL.self)
        }) else {
            return false
        }

        provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL else { return }
            Task { @MainActor in
                store.setURL(url, for: side)
            }
        }
        return true
    }
}
