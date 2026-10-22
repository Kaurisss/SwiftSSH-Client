import SwiftUI
import UniformTypeIdentifiers

struct KeyImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSource: KeyImportSource?
    @State private var label = ""
    @State private var pemText = ""
    @State private var fileName = ""
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        sourceLabel("Import from File", icon: "doc.badge.arrow.up", selected: selectedSource == .files)
                    }
                    .accessibilityIdentifier("key-import-files")

                    Button {
                        if selectedSource != .clipboard {
                            pemText = ""
                            fileName = ""
                        }
                        selectedSource = .clipboard
                    } label: {
                        sourceLabel("Paste Key", icon: "doc.on.clipboard", selected: selectedSource == .clipboard)
                    }
                    .accessibilityIdentifier("key-import-paste")
                }
                .buttonStyle(.plain)

                if selectedSource == .files {
                    Section("Preview Keys") {
                        let preview = SSHKeyImporter.preview(text: pemText, fileName: fileName)
                        Label(fileName, systemImage: "key.fill")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(preview.displayType)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(preview.fingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if selectedSource == .clipboard {
                    Section {
                        TextEditor(text: $pemText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                            .iOSOnlyTextInputAutocapitalization()
                            .autocorrectionDisabled()
                            .accessibilityLabel("Private Key (PEM)")
                            .accessibilityIdentifier("key-import-private-key")
                    } header: {
                        Text("Private Key (PEM)")
                    }
                }

                if selectedSource != nil {
                    Section {
                        TextField("Label", text: $label)
                            .font(.body)
                            .iOSOnlyTextInputAutocapitalization()
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("key-import-name")
                    } header: {
                        Text("Key Name")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Import SSH Keys")
            .iOSOnlyNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectedSource != nil {
                    Button(action: importKey) {
                        Label("Import", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppColors.onEmphasis)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("key-import-save")
                    .padding(AppSpacing.lg)
                    .background(AppColors.background)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    guard url.startAccessingSecurityScopedResource() else {
                        throw SSHKeyImportError.fileReadFailed(url.lastPathComponent)
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    try validateKey(text)
                    pemText = text
                    fileName = url.lastPathComponent
                    selectedSource = .files
                    if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        label = url.deletingPathExtension().lastPathComponent
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text((errorMessage ?? "") + "\n\n" + String(localized: "Choose an unencrypted SSH private key and try again."))
            }
        }
        .appTheme()
    }

    private func sourceLabel(_ title: LocalizedStringKey, icon: String, selected: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppColors.accent)
                .frame(width: 32)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.sm)
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(selected ? AppColors.accent : AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func validateKey(_ text: String) throws {
        guard SSHKeyImporter.detectFormat(text) != .unknown else {
            throw SSHKeyImportError.notAPrivateKey
        }
        guard !SSHKeyImporter.isEncrypted(text) else {
            throw SSHKeyImportError.encryptedKeyNeedsPassphrase
        }
    }

    private func importKey() {
        do {
            try validateKey(pemText)
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try KeyManagementService.importKey(
                label: name.isEmpty ? String(localized: "Imported Key") : name,
                pemText: pemText,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
