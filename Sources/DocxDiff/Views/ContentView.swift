import SwiftUI
import UniformTypeIdentifiers
import DocxDiffCore

struct ContentView: View {
    @State private var store: ComparisonStore
    @State private var isImporterPresented = false
    @State private var importingSide: DocumentSide?
    @State private var preview: ImagePreviewSelection?

    private let docxType = UTType(filenameExtension: "docx", conformingTo: .zip) ?? .zip

    init(store: ComparisonStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            inputSurface

            Divider()

            comparisonContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.swap()
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.originalURL == nil || store.revisedURL == nil)
                .help("Swap Original and Revised (Command-Shift-S)")

                Button {
                    store.clear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(store.originalURL == nil && store.revisedURL == nil)
                .help("Clear both documents (Command-Delete)")
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [docxType],
            allowsMultipleSelection: false
        ) { result in
            let side = importingSide
            importingSide = nil

            switch result {
            case .success(let urls):
                guard let side, let url = urls.first else { return }
                store.setURL(url, for: side)
            case .failure(let error):
                guard !isCancellation(error) else { return }
            }
        }
        .sheet(item: $preview) { selection in
            ImagePreviewView(selection: selection)
        }
    }

    private var inputSurface: some View {
        HStack(alignment: .top, spacing: 16) {
            FileDropZone(side: .original, store: store) {
                presentImporter(for: .original)
            }
            FileDropZone(side: .revised, store: store) {
                presentImporter(for: .revised)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var comparisonContent: some View {
        switch store.phase {
        case .empty:
            ContentUnavailableView {
                Label("Choose two documents", systemImage: "doc.on.doc")
            } description: {
                Text("Compared locally. Files never leave this Mac.")
            }
        case .awaitingSecondDocument:
            ContentUnavailableView {
                Label("Choose the second document", systemImage: "doc.badge.plus")
            } description: {
                Text("Add the missing Original or Revised DOCX to begin comparing.")
            }
        case .comparing:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Comparing documents…")
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            failureView(message: message)
        case .ready:
            readyView
        }
    }

    private func failureView(message: String) -> some View {
        ContentUnavailableView {
            Label("Comparison failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            HStack {
                Button("Retry") {
                    store.retry()
                }
                .keyboardShortcut(.defaultAction)

                Button("Replace Original…") {
                    presentImporter(for: .original)
                }

                Button("Replace Revised…") {
                    presentImporter(for: .revised)
                }
            }
        }
    }

    @ViewBuilder
    private var readyView: some View {
        if let result = store.result {
            let presentation = ComparisonResultPresentation(result: result)
            VStack(spacing: 0) {
                @Bindable var bindableStore = store
                ComparisonSummaryView(summary: result.summary, filter: $bindableStore.filter)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                Divider()

                if let warningHeading = presentation.warningHeading,
                   let accessibleWarningText = presentation.accessibleWarningText {
                    comparisonWarningBanner(
                        heading: warningHeading,
                        warnings: result.warnings,
                        accessibleText: accessibleWarningText
                    )
                    Divider()
                }

                if result.changes.isEmpty {
                    ContentUnavailableView {
                        Label(
                            presentation.emptyTitle,
                            systemImage: result.warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                    } description: {
                        Text(presentation.emptyDescription)
                    }
                } else {
                    ChangeListView(store: store) { selection in
                        preview = selection
                    }
                }
            }
        }
    }

    private func comparisonWarningBanner(
        heading: String,
        warnings: [String],
        accessibleText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(heading, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleText)
    }

    private func presentImporter(for side: DocumentSide) {
        importingSide = side
        isImporterPresented = true
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}
