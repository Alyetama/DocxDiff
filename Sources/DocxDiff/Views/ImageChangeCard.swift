import AppKit
import SwiftUI
import DocxDiffCore

struct ImageChangeCard: View {
    let change: ImageChange
    let onPreview: (ImagePreviewSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle)
                    .font(.headline)

                if !change.anchor.isEmpty {
                    Text(change.anchor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            switch change.kind {
            case .added:
                if let image = change.newImage {
                    previewButton(image: image, side: .revised)
                }
            case .removed:
                if let image = change.oldImage {
                    previewButton(image: image, side: .original)
                }
            case .replaced:
                HStack(alignment: .center, spacing: 12) {
                    if let image = change.oldImage {
                        previewButton(image: image, side: .original)
                    }

                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    if let image = change.newImage {
                        previewButton(image: image, side: .revised)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .accessibilityElement(children: .contain)
    }

    private var cardTitle: String {
        switch change.kind {
        case .added:
            "Figure added"
        case .removed:
            "Figure removed"
        case .replaced:
            "Figure replaced"
        }
    }

    private func previewButton(image: ImageBlock, side: DocumentSide) -> some View {
        Button {
            onPreview(
                ImagePreviewSelection(
                    title: "\(side.title) figure",
                    data: image.data,
                    accessibilityDescription: "\(side.title) preview for \(cardTitle.lowercased())"
                )
            )
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(side.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                imageContent(for: image.data)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open enlarged \(side.title.lowercased()) figure preview")
        .help("Open enlarged \(side.title.lowercased()) preview")
    }

    @ViewBuilder
    private func imageContent(for data: Data) -> some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.largeTitle)
                Text("Preview unavailable")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
