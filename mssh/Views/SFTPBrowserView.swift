import SwiftUI
import Citadel

struct SFTPBrowserView: View {
    struct Connection: Identifiable {
        let id = UUID()
        let client: SSHClient
    }
    @State private var viewModel: SFTPViewModel
    @State private var inspectedFile: SFTPFileItem?
    @Environment(\.dismiss) private var dismiss

    init(client: SSHClient) {
        self.init(viewModel: SFTPViewModel(client: client))
    }

    init(viewModel: SFTPViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                breadcrumbBar.disabled(viewModel.isBusy)
                if let error = viewModel.directoryError {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(AppColors.textPrimary)
                            .textSelection(.enabled)
                        Button("Retry") { Task { await viewModel.retryDirectory() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.lg)
                    .background(AppColors.surface)
                }
                fileList
                    .disabled(viewModel.isBusy)
                    .overlay {
                        if viewModel.isLoading && !viewModel.hasLoadedInitialDirectory {
                            ProgressView().accessibilityLabel("Loading")
                        }
                    }
            }
            .background(AppColors.background)
            .navigationTitle("Files")
            .iOSOnlyNavigationBarTitleDisplayMode()
            .searchable(text: $viewModel.searchText, prompt: "Search Files")
            .toolbar { browserToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isTransferring {
                    SFTPTransferView(fileName: viewModel.transferFileName,
                                     transferType: viewModel.transferType,
                                     isCancelling: viewModel.isCancellingTransfer,
                                     onCancel: viewModel.cancelTransfer)
                }
            }
            .task { await viewModel.loadInitialDirectory() }
            .alert("New Folder", isPresented: $viewModel.showNewFolderAlert) {
                TextField("Folder name", text: $viewModel.newFolderName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { viewModel.newFolderName = "" }
                Button("Create") { Task { await viewModel.createDirectory() } }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("Close", role: .cancel) { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .alert(
                "Delete \(viewModel.itemToDelete?.name ?? "")?",
                isPresented: $viewModel.showDeleteConfirmation,
                presenting: viewModel.itemToDelete
            ) { item in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(item: item) }
                }
                Button("Cancel", role: .cancel) { viewModel.itemToDelete = nil }
            } message: { item in
                Text(item.isDirectory
                     ? String(localized: "This will delete the directory. It must be empty.")
                     : String(localized: "This file will be permanently deleted."))
            }
            .fileImporter(isPresented: $viewModel.showFileImporter,
                          allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { Task { await viewModel.upload(url: url) } }
                case .failure(let error):
                    viewModel.error = String(localized: "File picker error: \(error.localizedDescription)")
                }
            }
            .sheet(item: $viewModel.downloadedFile, onDismiss: viewModel.discardDownload) { file in
                NavigationStack {
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "doc.fill")
                            .font(.largeTitle)
                            .foregroundStyle(AppColors.accent)
                            .accessibilityHidden(true)
                        Text(file.url.lastPathComponent)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                        ShareLink(item: file.url) {
                            Label("Save or Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(AppColors.onEmphasis)
                    }
                    .padding(AppSpacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background)
                    .navigationTitle("Downloaded File")
                    .iOSOnlyNavigationBarTitleDisplayMode()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { viewModel.downloadedFile = nil }
                        }
                    }
                }
            }
            .sheet(item: $inspectedFile) { item in SFTPFileInfoView(item: item) }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .onDisappear { viewModel.cancelTransfer() }
        .appTheme()
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
                .disabled(viewModel.isBusy)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    viewModel.showFileImporter = true
                } label: {
                    Label("Upload File", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.hasLoadedInitialDirectory)
                Button {
                    viewModel.showNewFolderAlert = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(!viewModel.hasLoadedInitialDirectory)
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Toggle("Show Hidden Files", isOn: $viewModel.showsHiddenFiles)
                Picker("Sort By", selection: $viewModel.sortOrder) {
                    ForEach(SFTPFileItem.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label("File Actions", systemImage: "ellipsis.circle")
            }
            .disabled(viewModel.isBusy)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 0) {
            Button {
                Task { await viewModel.goBack() }
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(viewModel.pathHistory.isEmpty)

            ScrollView(.horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.breadcrumbs) { crumb in
                        if crumb.path != "/" {
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .accessibilityHidden(true)
                        }
                        Button {
                            Task { await viewModel.navigate(to: crumb.path) }
                        } label: {
                            Text(crumb.name)
                                .font(.callout.monospaced())
                                .fontWeight(crumb.path == viewModel.currentPath ? .semibold : .regular)
                                .padding(.horizontal, AppSpacing.xs)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel(crumb.path)
                    }
                }
            }
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .opacity(viewModel.hasLoadedInitialDirectory && (viewModel.isLoading || viewModel.isMutating) ? 1 : 0)
                .accessibilityLabel("Loading")
                .accessibilityHidden(!viewModel.hasLoadedInitialDirectory || (!viewModel.isLoading && !viewModel.isMutating))
        }
        .padding(.trailing, AppSpacing.lg)
        .background(AppColors.surface)
    }

    private var fileList: some View {
        List {
            if viewModel.hasLoadedInitialDirectory && viewModel.currentPath != "/" {
                Button {
                    Task { await viewModel.goUp() }
                } label: {
                    Label("Parent Folder", systemImage: "arrow.up")
                }
                .listRowBackground(AppColors.surface)
            }
            ForEach(viewModel.visibleFiles) { item in
                fileRow(item)
                    .contextMenu { fileActions(item) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { fileActions(item) }
                    .listRowBackground(AppColors.surface)
            }
            if viewModel.visibleFiles.isEmpty && !viewModel.isBusy && viewModel.directoryError == nil {
                ContentUnavailableView {
                    Label {
                        if viewModel.files.isEmpty {
                            Text("Empty Directory")
                        } else {
                            Text("No Matching Files")
                        }
                    } icon: {
                        Image(systemName: viewModel.files.isEmpty ? "folder" : "magnifyingglass")
                    }
                } actions: {
                    if !viewModel.searchText.isEmpty || !viewModel.files.isEmpty {
                        Button("Show All Files") {
                            viewModel.searchText = ""
                            viewModel.showsHiddenFiles = true
                        }
                    } else {
                        Button("Upload File") { viewModel.showFileImporter = true }
                    }
                }
                .disabled(!viewModel.hasLoadedInitialDirectory)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private func fileRow(_ item: SFTPFileItem) -> some View {
        if item.isDirectory {
            Button {
                Task { await viewModel.navigate(to: item.path) }
            } label: {
                fileLabel(item)
            }
            .accessibilityHint("Open Folder")
        } else {
            Menu {
                fileActions(item)
            } label: {
                fileLabel(item)
            }
            .accessibilityIdentifier("sftp-file-\(item.name)")
            .accessibilityHint("File Actions")
        }
    }

    private func fileLabel(_ item: SFTPFileItem) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: item.iconName)
                .foregroundStyle(item.iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.name)
                    .font(.body.monospaced())
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                if !item.isDirectory {
                    Text(item.formattedSize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                if let modifiedDate = item.modifiedDate {
                    Text(modifiedDate, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            Image(systemName: item.isDirectory ? "chevron.forward" : "ellipsis")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func fileActions(_ item: SFTPFileItem) -> some View {
        Button("File Details", systemImage: "info.circle") { inspectedFile = item }
        if !item.isDirectory {
            Button {
                Task { await viewModel.download(item: item) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .tint(AppColors.accent)
        }
        Button(role: .destructive) {
            viewModel.itemToDelete = item
            viewModel.showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct SFTPFileInfoView: View {
    let item: SFTPFileItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Name") {
                    Text(item.name).textSelection(.enabled)
                }
                LabeledContent("Path") {
                    Text(item.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                if !item.isDirectory {
                    LabeledContent("Size", value: item.formattedSize)
                }
                if let date = item.modifiedDate {
                    LabeledContent("Date Modified") {
                        Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    }
                }
                LabeledContent("Permissions", value: item.formattedPermissions)
            }
            .navigationTitle("File Details")
            .iOSOnlyNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .appTheme()
    }
}
