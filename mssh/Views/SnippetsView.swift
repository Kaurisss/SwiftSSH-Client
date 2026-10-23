import SwiftUI
import SwiftData

/// CRUD UI for `Snippet` (saved commands). Reachable from Settings and used
/// by the terminal accessory bar / toolbar to push commands to an active
/// session.
struct SnippetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Snippet.lastUsedAt, order: .reverse),
        SortDescriptor(\Snippet.label, comparator: .localizedStandard)
    ]) private var snippets: [Snippet]

    @State private var editingSnippet: Snippet?
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var snippetToDelete: Snippet?

    private var filteredSnippets: [Snippet] {
        Snippet.filtered(snippets, query: searchText)
    }

    var body: some View {
        Group {
            if snippets.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredSnippets) { snippet in
                        Button {
                            editingSnippet = snippet
                        } label: {
                            SnippetRow(snippet: snippet)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppColors.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                snippetToDelete = snippet
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.background)
            }
        }
        .background(AppColors.background)
        .navigationTitle("Snippets")
        .searchable(text: $searchText, prompt: "Search Commands")
        .overlay {
            if !snippets.isEmpty && filteredSnippets.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Commands", systemImage: "magnifyingglass")
                } actions: {
                    Button("Clear Search") { searchText = "" }
                }
            }
        }
        .iOSOnlyNavigationBarTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .accessibilityIdentifier("snippet-add")
            }
        }
        .alert("Delete \(snippetToDelete?.displayLabel ?? "")?", isPresented: .init(
            get: { snippetToDelete != nil }, set: { if !$0 { snippetToDelete = nil } }
        ), presenting: snippetToDelete) { snippet in
            Button("Delete", role: .destructive) {
                modelContext.delete(snippet)
                try? modelContext.save()
                snippetToDelete = nil
            }
            Button("Cancel", role: .cancel) { snippetToDelete = nil }
        } message: { _ in EmptyView() }
        .sheet(isPresented: $showCreateSheet) {
            SnippetEditorView(snippet: nil)
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(snippet: snippet)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textTertiary)
            Text("No Snippets")
                .font(AppFonts.subheading)
                .foregroundStyle(AppColors.textSecondary)
            Button {
                showCreateSheet = true
            } label: {
                Text("Add Snippet")
                    .font(AppFonts.label)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AppColors.onEmphasis)
            .tint(AppColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                AppShape.container
                    .fill(AppColors.accentDim)
                    .frame(width: 36, height: 36)
                Image(systemName: "chevron.right.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.displayLabel)
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                Text(snippet.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if snippet.command.hasSuffix("\n") || snippet.command.hasSuffix("\r") {
                Image(systemName: "return")
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("Runs on Insert")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Editor sheet

struct SnippetEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let snippet: Snippet?

    @State private var label = ""
    @State private var command = ""
    @State private var saveError: String?

    init(snippet: Snippet?) {
        self.snippet = snippet
        _label = State(initialValue: snippet?.label ?? "")
        _command = State(initialValue: snippet?.command ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label, prompt: Text("e.g. Tail syslog").foregroundStyle(AppColors.textTertiary))
                        .iOSOnlyTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("snippet-label")
                } header: {
                    Text("Label")
                }

                Section {
                    TextEditor(text: $command)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .iOSOnlyTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .accessibilityLabel("Command")
                        .accessibilityIdentifier("snippet-command")
                } header: {
                    Text("Command")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle(snippet == nil ? String(localized: "New Snippet") : String(localized: "Edit Snippet"))
            .iOSOnlyNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("snippet-save")
                }
            }
            .alert("Unable to Save Command", isPresented: .init(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("Close", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .appTheme()
    }

    private func save() {
        do {
            try Snippet.save(snippet, label: label, command: command, in: modelContext)
            dismiss()
        } catch {
            saveError = String(localized: "Save failed. Your draft has been kept; try again. \(error.localizedDescription)")
        }
    }
}

// MARK: - Picker (used by terminal toolbar)

/// Quick snippet picker shown as a sheet from the terminal toolbar. Tapping
/// a row dismisses and invokes `onPick` with the snippet.
struct SnippetPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [
        SortDescriptor(\Snippet.lastUsedAt, order: .reverse),
        SortDescriptor(\Snippet.label, comparator: .localizedStandard)
    ]) private var snippets: [Snippet]

    let onPick: (Snippet) -> Void
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var editingSnippet: Snippet?

    private var filteredSnippets: [Snippet] { Snippet.filtered(snippets, query: searchText) }

    var body: some View {
        NavigationStack {
            Group {
                if snippets.isEmpty {
                    ContentUnavailableView {
                        Label("No Snippets", systemImage: "text.badge.plus")
                    } actions: {
                        Button("Add Snippet") { showCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(AppColors.onEmphasis)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background)
                } else {
                    List(filteredSnippets) { snippet in
                        Button {
                            // Bump use stats
                            snippet.useCount += 1
                            snippet.lastUsedAt = Date()
                            try? modelContext.save()
                            onPick(snippet)
                            dismiss()
                        } label: {
                            SnippetRow(snippet: snippet)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppColors.surface)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingSnippet = snippet }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppColors.background)
                }
            }
            .background(AppColors.background)
            .searchable(text: $searchText, prompt: "Search Commands")
            .overlay {
                if !snippets.isEmpty && filteredSnippets.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Commands", systemImage: "magnifyingglass")
                    } actions: {
                        Button("Clear Search") { searchText = "" }
                    }
                }
            }
            .navigationTitle("Snippets")
            .iOSOnlyNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Snippet", systemImage: "plus") { showCreateSheet = true }
                }
            }
            .sheet(isPresented: $showCreateSheet) { SnippetEditorView(snippet: nil) }
            .sheet(item: $editingSnippet) { snippet in SnippetEditorView(snippet: snippet) }
        }
        .appTheme()
    }
}
