#if os(iOS)
import UIKit
import SwiftTerm

/// Custom keyboard accessory bar with terminal-essential keys for iOS.
/// Designed with minimal dark aesthetic matching the app theme.
final class TerminalAccessoryBar: UIView {
    weak var terminal: TerminalView?

    // Key definitions: (label, bytes to send, isSpecial)
    private struct KeyDef {
        let label: String
        let bytes: [UInt8]
        let isModifier: Bool
        let icon: String?

        init(_ label: String, _ bytes: [UInt8], isModifier: Bool = false, icon: String? = nil) {
            self.label = label
            self.bytes = bytes
            self.isModifier = isModifier
            self.icon = icon
        }
    }

    private let keyDefs: [KeyDef] = [
        KeyDef("Esc", [0x1B]),
        KeyDef("Tab", [0x09]),
        KeyDef("Ctrl", [], isModifier: true),
        KeyDef("\u{2191}", [0x1B, 0x5B, 0x41]),  // Up
        KeyDef("\u{2193}", [0x1B, 0x5B, 0x42]),  // Down
        KeyDef("\u{2190}", [0x1B, 0x5B, 0x44]),  // Left
        KeyDef("\u{2192}", [0x1B, 0x5B, 0x43]),  // Right
        KeyDef("Ctrl C", [0x03]),
        KeyDef("Ctrl D", [0x04]),
        KeyDef("|", [0x7C]),
        KeyDef("~", [0x7E]),
        KeyDef("/", [0x2F]),
        KeyDef("-", [0x2D]),
        KeyDef("_", [0x5F]),
        KeyDef(".", [0x2E]),
        KeyDef(":", [0x3A]),
        KeyDef("$", [0x24]),
    ]

    // Lives on the terminal so SwiftTerm applies it to system-keyboard input too.
    private var ctrlActive: Bool { terminal?.controlModifier ?? false }
    private var ctrlButton: UIButton?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    // Colors matching AppColors design system
    private let bgColor = UIColor.secondarySystemBackground
    private let keyColor = UIColor.tertiarySystemBackground
    private let keyTextColor = UIColor.label
    private let accentColor = UIColor(AppColors.accent)
    private let borderColor = UIColor.separator.withAlphaComponent(0.3)

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: terminal.bounds.width, height: 46))
        autoresizingMask = .flexibleWidth
        setupAppearance()
        setupKeys()
        feedbackGenerator.prepare()
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateCtrlAppearance),
            name: .terminalViewControlModifierReset, object: terminal
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupAppearance() {
        backgroundColor = bgColor

        let topBorder = UIView()
        topBorder.backgroundColor = borderColor
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)
        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setupKeys() {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Dismiss keyboard button
        let dismissButton = makeKeyButton(
            title: nil,
            icon: "chevron.down",
            action: #selector(dismissKeyboard)
        )
        dismissButton.accessibilityLabel = String(localized: "Hide Keyboard")
        addSubview(dismissButton)

        // Snippets button — posts a notification that the active terminal view
        // listens to in order to present the SnippetPickerView sheet.
        let snippetButton = makeKeyButton(
            title: nil,
            icon: "text.badge.plus",
            action: #selector(openSnippetPicker)
        )
        snippetButton.tintColor = accentColor
        snippetButton.accessibilityLabel = String(localized: "Snippets")
        addSubview(snippetButton)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -6),

            separator.leadingAnchor.constraint(equalTo: snippetButton.leadingAnchor, constant: -7),
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            snippetButton.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            snippetButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            snippetButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),
            snippetButton.widthAnchor.constraint(equalToConstant: 40),

            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            dismissButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            dismissButton.widthAnchor.constraint(equalToConstant: 40),
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.layoutMargins = UIEdgeInsets(top: 5, left: 6, bottom: 5, right: 12)
        stack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for (index, keyDef) in keyDefs.enumerated() {
            let isArrow = keyDef.label.unicodeScalars.first.map { $0.value >= 0x2190 && $0.value <= 0x2193 } ?? false
            let minWidth: CGFloat = isArrow ? 36 : (keyDef.label.count > 2 ? 44 : 34)

            let button = TerminalAccessoryKeyButton(type: .system)
            button.setTitle(keyDef.label, for: .normal)

            if keyDef.isModifier {
                button.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
            } else if isArrow {
                button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            } else {
                button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            }

            button.tintColor = keyTextColor
            button.tag = index
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            button.backgroundColor = keyColor
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 0.5
            button.layer.borderColor = borderColor.cgColor

            let widthConstraint = button.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth)
            widthConstraint.isActive = true
            var btnConfig = UIButton.Configuration.plain()
            btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            button.configuration = btnConfig

            if keyDef.isModifier {
                ctrlButton = button
            }

            stack.addArrangedSubview(button)
        }
    }

    private func makeKeyButton(title: String?, icon: String?, action: Selector) -> UIButton {
        let button = TerminalAccessoryKeyButton(type: .system)
        if let title = title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        }
        if let icon = icon {
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        }
        button.tintColor = keyTextColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.backgroundColor = keyColor
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.borderColor = borderColor.cgColor
        return button
    }

    @objc private func dismissKeyboard() {
        feedbackGenerator.impactOccurred()
        terminal?.resignFirstResponder()
    }

    @objc private func openSnippetPicker() {
        feedbackGenerator.impactOccurred()
        NotificationCenter.default.post(name: .openSnippetPicker, object: nil)
    }

    @objc private func keyTapped(_ sender: UIButton) {
        feedbackGenerator.impactOccurred()

        let index = sender.tag
        let keyDef = keyDefs[index]

        if keyDef.isModifier {
            terminal?.controlModifier.toggle()
            updateCtrlAppearance()
            return
        }

        guard let terminal else { return }

        if ctrlActive && keyDef.bytes.count == 1 {
            let ctrlByte = keyDef.bytes[0] & 0x1F
            terminal.terminalDelegate?.send(source: terminal, data: ArraySlice([ctrlByte]))
            deactivateCtrl()
        } else {
            terminal.terminalDelegate?.send(source: terminal, data: ArraySlice(keyDef.bytes))
        }
    }

    private func deactivateCtrl() {
        terminal?.controlModifier = false
        updateCtrlAppearance()
    }

    @objc private func updateCtrlAppearance() {
        ctrlButton?.isSelected = ctrlActive
        ctrlButton?.backgroundColor = ctrlActive ? accentColor.withAlphaComponent(0.25) : keyColor
        ctrlButton?.tintColor = ctrlActive ? accentColor : keyTextColor
        ctrlButton?.layer.borderColor = ctrlActive ? accentColor.withAlphaComponent(0.5).cgColor : borderColor.cgColor
    }
}

private final class TerminalAccessoryKeyButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(AppShape.cornerRadius, min(bounds.width, bounds.height) / 2)
    }
}

#endif
