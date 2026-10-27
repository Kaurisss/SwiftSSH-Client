import SwiftUI
import QuickLook

struct SFTPDocumentView: View {
    @State private var model: SFTPDocumentViewModel
    @State private var confirmClose = false
    @State private var confirmReload = false
    @State private var confirmReplacement = false
    @State private var replacementApproved = false
    @State private var closeAfterSave = false
    @State private var searchRequest = 0
    @State private var exportedDraft: SFTPViewModel.DownloadedFile?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let onDownload: () -> Void

    init(item: SFTPFileItem, service: any SFTPDocumentServicing, onDownload: @escaping () -> Void) {
        self.onDownload = onDownload
        _model = State(initialValue: SFTPDocumentViewModel(item: item, service: service))
    }

    var body: some View {
        NavigationStack {
            content
                .overlay { if model.isSaving { ProgressView() } }
                .navigationTitle(model.item.name)
                .iOSOnlyNavigationBarTitleDisplayMode()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            if model.isDirty { confirmClose = true } else { dismiss() }
                        }
                        .disabled(model.isSaving)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.document != nil {
                            Menu {
                                if !voiceOverEnabled {
                                    Button("Find", systemImage: "magnifyingglass") { searchRequest += 1 }
                                }
                                Button("Reload", systemImage: "arrow.clockwise") { confirmReload = true }
                                Button("Export Draft", systemImage: "square.and.arrow.up") {
                                    do { exportedDraft = .init(url: try model.exportDraft()) }
                                    catch { model.error = error.localizedDescription }
                                }
                            } label: {
                                Label("File Actions", systemImage: "ellipsis.circle")
                            }
                            .disabled(model.isSaving || model.isLoading)
                            Button("Save") { requestSave(closeAfterward: false) }
                                .disabled(!model.canSave)
                                .accessibilityIdentifier("sftp-document-save")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let error = model.error {
                        Text(error)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppColors.surface)
                            .accessibilityIdentifier("sftp-document-error")
                    }
                }
        }
        .interactiveDismissDisabled(model.isDirty || model.isSaving)
        .confirmationDialog("Save changes before closing?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save") {
                replacementApproved = true
                requestSave(closeAfterward: true)
            }
                .disabled(!model.canSave)
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            if !replacementApproved {
                Text("Saving replaces the file. Permissions and ownership are preserved, but ACLs, extended attributes and hard-link relationships may change.")
            }
        }
        .alert("Replace Remote File?", isPresented: $confirmReplacement) {
            Button("Save") {
                replacementApproved = true
                requestSave(closeAfterward: closeAfterSave)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving replaces the file. Permissions and ownership are preserved, but ACLs, extended attributes and hard-link relationships may change.")
        }
        .confirmationDialog("Reload and discard your edits?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Reload", role: .destructive) { Task { await model.load() } }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(item: $exportedDraft) { draft in
            SFTPShareSheet(url: draft.url)
        }
        .task { if model.snapshot == nil { await model.load() } }
        .appTheme()
    }

    private func requestSave(closeAfterward: Bool) {
        closeAfterSave = closeAfterward
        guard replacementApproved else {
            confirmReplacement = true
            return
        }
        Task {
            if await model.save(), closeAfterward { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.document != nil {
            if voiceOverEnabled {
                TextEditor(text: $model.text)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(model.isSaving)
                    .accessibilityLabel(model.item.name)
            } else {
                RunestoneEditor(text: $model.text, fileName: model.item.name,
                                isEditable: !model.isSaving, searchRequest: searchRequest)
            }
        } else if let url = model.previewURL, QLPreviewController.canPreview(url as NSURL) {
            SFTPPreviewView(url: url)
                .accessibilityIdentifier("sftp-document-preview")
        } else {
            ContentUnavailableView {
                Label("Preview Unavailable", systemImage: "doc")
            } actions: {
                Button("Retry") { Task { await model.load() } }
                Button("Download") { onDownload() }
            }
        }
    }
}

private struct SFTPPreviewView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct SFTPShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
