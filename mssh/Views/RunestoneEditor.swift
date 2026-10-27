import SwiftUI
import Runestone
import TreeSitterBashRunestone
import TreeSitterJSONRunestone
import TreeSitterYAMLRunestone

struct RunestoneEditor: UIViewRepresentable {
    @Binding var text: String
    let fileName: String
    let isEditable: Bool
    let searchRequest: Int

    func makeUIView(context: Context) -> Runestone.TextView {
        let view = Runestone.TextView()
        let language: TreeSitterLanguage?
        switch (fileName as NSString).pathExtension.lowercased() {
        case "json": language = .json
        case "yaml", "yml": language = .yaml
        case "sh", "bash", "zsh": language = .bash
        default: language = nil
        }
        if let language {
            view.setState(TextViewState(text: text, language: language))
        } else {
            view.setState(TextViewState(text: text))
        }
        view.showLineNumbers = true
        view.lineSelectionDisplayType = .line
        view.lineEndings = .lf
        view.isFindInteractionEnabled = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.backgroundColor = .systemBackground
        view.keyboardDismissMode = .interactive
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "sftp-document-editor"
        view.accessibilityLabel = fileName
        view.accessibilityValue = text
        view.editorDelegate = context.coordinator
        view.isEditable = isEditable
        return view
    }

    func updateUIView(_ view: Runestone.TextView, context: Context) {
        context.coordinator.parent = self
        // Only external reloads replace text; ordinary keystrokes retain selection and marked text.
        if view.text != text { view.text = text }
        view.isEditable = isEditable
        view.accessibilityValue = text
        if context.coordinator.searchRequest != searchRequest {
            context.coordinator.searchRequest = searchRequest
            view.findInteraction?.presentFindNavigator(showingReplace: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, TextViewDelegate {
        var parent: RunestoneEditor
        var searchRequest = 0
        init(_ parent: RunestoneEditor) { self.parent = parent }
        func textViewDidChange(_ textView: Runestone.TextView) { parent.text = textView.text }
    }
}
