import AppKit
import SwiftUI

struct ImagePreviewSelection: Identifiable {
    let id = UUID()
    let title: String
    let data: Data
    let accessibilityDescription: String
}

struct ImagePreviewView: View {
    let selection: ImagePreviewSelection

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selection.title)
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Group {
                if let image = NSImage(data: selection.data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel(selection.accessibilityDescription)
                } else {
                    ContentUnavailableView {
                        Label("Preview unavailable", systemImage: "doc.richtext")
                    } description: {
                        Text("This embedded figure could not be decoded as an image.")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
