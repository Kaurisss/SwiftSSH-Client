import SwiftUI
import SwiftTerm

/// DECSCUSR cursor-shape escape sequence for the user's preference.
/// `\e[N q` where N is 1-6 (block/underline/bar × blink/steady).
/// Lives at file scope so iOS and macOS wrappers share one source of truth.
private func decscusrEscape(style: AppPreferences.CursorStyle, blink: Bool) -> [UInt8] {
    let code: Int
    switch (style, blink) {
    case (.block, true):      code = 1
    case (.block, false):     code = 2
    case (.underline, true):  code = 3
    case (.underline, false): code = 4
    case (.bar, true):        code = 5
    case (.bar, false):       code = 6
    }
    return Array("\u{1B}[\(code) q".utf8)
}

#if os(iOS)
/// Observe the terminal's own layout, including font changes that don't resize its parent.
final class LayoutReportingTerminalView: TerminalView {
    var onLayout: ((TerminalView, Bool) -> Void)?
    private var layoutReportPending = false
    private var hasReportedLayout = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, !layoutReportPending else { return }
        layoutReportPending = true
        // Read after the current Auto Layout pass, without capturing its intermediate grid.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutReportPending = false
            guard self.bounds.width > 0, self.bounds.height > 0 else { return }
            let firstLayout = !self.hasReportedLayout
            self.hasReportedLayout = true
            self.onLayout?(self, firstLayout)
        }
    }
}

/// Padding belongs outside SwiftTerm so its grid is computed from the drawable width.
final class TerminalContainerView: UIView {
    let terminal: TerminalView
    var onLayout: ((TerminalView) -> Void)?

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        backgroundColor = terminal.nativeBackgroundColor
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard terminal.bounds.width > 0, terminal.bounds.height > 0 else { return }
        terminal.layoutIfNeeded()
        // SwiftTerm may not emit sizeChanged if the initial grid already fits.
        onLayout?(terminal)
    }
}

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView (iOS)
struct TerminalViewWrapper: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var bridge: SSHTerminalBridge
    var isFocused = true
    @AppStorage(AppPreferences.Key.terminalThemeName)
    private var themeName = AppPreferences.Default.terminalThemeName
    @AppStorage(AppPreferences.Key.terminalFontFamily)
    private var fontFamily = AppPreferences.Default.terminalFontFamily
    @AppStorage(AppPreferences.Key.terminalFontSize)
    private var fontSize = AppPreferences.Default.terminalFontSize
    @AppStorage(AppPreferences.Key.terminalCursorStyle)
    private var cursorStyleRaw = AppPreferences.Default.terminalCursorStyle
    @AppStorage(AppPreferences.Key.terminalBlinkCursor)
    private var blinkCursor = AppPreferences.Default.terminalBlinkCursor

    private var theme: TerminalTheme { TerminalTheme.named(themeName) }

    private var resolvedFont: UIFont {
        let pt = CGFloat(fontSize)
        if fontFamily != "System", let f = UIFont(name: fontFamily, size: pt) {
            return f
        }
        return UIFont.monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    private func resolvedColor(_ color: SwiftUI.Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        ))
    }

    func makeUIView(context: Context) -> TerminalContainerView {
        context.coordinator.wantsFocus = isFocused
        let terminal = Self.makeTerminalView(backgroundColor: resolvedColor(theme.background))
        terminal.terminalDelegate = context.coordinator
        context.coordinator.applyFontPreference(resolvedFont, to: terminal)
        applyTheme(to: terminal, coordinator: context.coordinator)
        terminal.inputAccessoryView = TerminalAccessoryBar(terminal: terminal)
        bridge.terminalView = terminal

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        terminal.addGestureRecognizer(pinch)

        let container = TerminalContainerView(terminal: terminal)
        container.onLayout = { [weak coordinator = context.coordinator] terminal in
            coordinator?.synchronizeSize(of: terminal)
        }
        (terminal as? LayoutReportingTerminalView)?.onLayout = { [weak coordinator = context.coordinator] terminal, firstLayout in
            coordinator?.synchronizeSize(of: terminal, force: firstLayout)
        }

        applyCursorStyle(to: terminal)

        if bridge.isConnected && isFocused {
            Self.focusWithRetry(terminal, coordinator: context.coordinator)
        }

        return container
    }

    static func makeTerminalView(backgroundColor: UIColor) -> TerminalView {
        let terminal = LayoutReportingTerminalView()
        terminal.nativeBackgroundColor = backgroundColor
        terminal.backgroundColor = backgroundColor
        // Redraw at the new size; keep cached glyphs unscaled during the keyboard animation.
        terminal.contentMode = .topLeft
        terminal.layer.needsDisplayOnBoundsChange = true
        return terminal
    }

    func updateUIView(_ container: TerminalContainerView, context: Context) {
        let uiView = container.terminal
        context.coordinator.wantsFocus = isFocused
        applyTheme(to: uiView, coordinator: context.coordinator)
        container.backgroundColor = uiView.nativeBackgroundColor
        context.coordinator.applyFontPreference(resolvedFont, to: uiView)

        applyCursorStyle(to: uiView)

        if bridge.isConnected && isFocused && !uiView.isFirstResponder {
            Self.focusWithRetry(uiView, coordinator: context.coordinator)
        }
    }

    private func applyTheme(to terminal: TerminalView, coordinator: Coordinator) {
        terminal.nativeBackgroundColor = resolvedColor(theme.background)
        terminal.backgroundColor = terminal.nativeBackgroundColor
        terminal.nativeForegroundColor = resolvedColor(theme.foreground)
        // The other bundled terminal themes have dark backgrounds even in light app chrome.
        coordinator.applyPalette(to: terminal, light: theme == .default && colorScheme == .light)
    }

    /// Apply the user's cursor preference. `feed(byteArray:)` is public on
    /// both platforms; SwiftTerm's `terminal` property is internal on iOS.
    private func applyCursorStyle(to terminal: TerminalView) {
        let style = AppPreferences.CursorStyle(rawValue: cursorStyleRaw) ?? .block
        terminal.feed(byteArray: ArraySlice(decscusrEscape(style: style, blink: blinkCursor)))
    }

    private static func focusWithRetry(_ view: TerminalView, coordinator: Coordinator, attempt: Int = 0) {
        let maxAttempts = 4
        let delays: [TimeInterval] = [0.1, 0.3, 0.6, 1.0]
        let delay = attempt < delays.count ? delays[attempt] : 1.0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.wantsFocus, view.window != nil else { return }
            if !view.isFirstResponder {
                let success = view.becomeFirstResponder()
                if !success && attempt + 1 < maxAttempts {
                    focusWithRetry(view, coordinator: coordinator, attempt: attempt + 1)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    final class Coordinator: NSObject, TerminalViewDelegate, UIGestureRecognizerDelegate {
        let bridge: SSHTerminalBridge
        var wantsFocus = true
        private var preferredFont: UIFont?
        private var pinchStartSize: CGFloat = 14
        private var usesLightPalette: Bool?

        init(bridge: SSHTerminalBridge) {
            self.bridge = bridge
        }

        func applyFontPreference(_ font: UIFont, to terminal: TerminalView) {
            // Preserve session zoom across unrelated SwiftUI updates; explicit settings still win.
            guard preferredFont?.fontName != font.fontName
                || preferredFont?.pointSize != font.pointSize else { return }
            preferredFont = font
            terminal.font = font
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let terminal = gesture.view as? TerminalView else { return }
            switch gesture.state {
            case .began:
                pinchStartSize = terminal.font.pointSize
            case .changed, .ended:
                let size = min(24, max(8, pinchStartSize * gesture.scale))
                guard abs(terminal.font.pointSize - size) > 0.01 else { return }
                terminal.font = terminal.font.withSize(size)
                synchronizeSize(of: terminal)
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // SwiftTerm is a UIScrollView; its pan recognizer must not swallow the pinch.
            guard gestureRecognizer is UIPinchGestureRecognizer,
                  let terminal = gestureRecognizer.view as? TerminalView else { return false }
            return other === terminal.panGestureRecognizer
        }

        func applyPalette(to terminal: TerminalView, light: Bool) {
            guard usesLightPalette != light else { return }
            if light {
                terminal.installColors(TerminalTheme.lightANSIColors)
            } else if usesLightPalette == true {
                terminal.installColors(TerminalTheme.darkANSIColors)
            }
            usesLightPalette = light
        }

        func synchronizeSize(of terminal: TerminalView, force: Bool = false) {
            guard terminal.bounds.width > 0, terminal.bounds.height > 0 else { return }
            let grid = terminal.getTerminal()
            bridge.resizeTerminal(cols: grid.cols, rows: grid.rows, force: force)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            bridge.sendToSSH(data: data)
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard source.bounds.width > 0, source.bounds.height > 0 else { return }
            bridge.resizeTerminal(cols: newCols, rows: newRows)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = text
            }
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

#elseif os(macOS)
/// NSViewRepresentable wrapper for SwiftTerm's TerminalView (macOS)
struct TerminalViewWrapper: NSViewRepresentable {
    @ObservedObject var bridge: SSHTerminalBridge
    @AppStorage(AppPreferences.Key.terminalThemeName)
    private var themeName = AppPreferences.Default.terminalThemeName
    @AppStorage(AppPreferences.Key.terminalFontFamily)
    private var fontFamily = AppPreferences.Default.terminalFontFamily
    @AppStorage(AppPreferences.Key.terminalFontSize)
    private var fontSize = AppPreferences.Default.terminalFontSize
    @AppStorage(AppPreferences.Key.terminalCursorStyle)
    private var cursorStyleRaw = AppPreferences.Default.terminalCursorStyle
    @AppStorage(AppPreferences.Key.terminalBlinkCursor)
    private var blinkCursor = AppPreferences.Default.terminalBlinkCursor

    private var theme: TerminalTheme { TerminalTheme.named(themeName) }

    private var resolvedFont: NSFont {
        let pt = CGFloat(fontSize)
        if fontFamily != "System", let f = NSFont(name: fontFamily, size: pt) {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminal = TerminalView()
        terminal.terminalDelegate = context.coordinator
        terminal.nativeBackgroundColor = NSColor(theme.background)
        terminal.nativeForegroundColor = NSColor(theme.foreground)
        terminal.font = resolvedFont
        bridge.terminalView = terminal

        applyCursorStyle(to: terminal)

        if bridge.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                terminal.window?.makeFirstResponder(terminal)
            }
        }

        return terminal
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        nsView.nativeBackgroundColor = NSColor(theme.background)
        nsView.nativeForegroundColor = NSColor(theme.foreground)

        let target = resolvedFont
        if nsView.font.fontName != target.fontName
            || abs(nsView.font.pointSize - target.pointSize) > 0.5 {
            nsView.font = target
        }

        applyCursorStyle(to: nsView)

        if bridge.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if nsView.window?.firstResponder !== nsView {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }

    /// Apply cursor style via DECSCUSR (shared with iOS).
    private func applyCursorStyle(to terminal: TerminalView) {
        let style = AppPreferences.CursorStyle(rawValue: cursorStyleRaw) ?? .block
        terminal.feed(byteArray: ArraySlice(decscusrEscape(style: style, blink: blinkCursor)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let bridge: SSHTerminalBridge

        init(bridge: SSHTerminalBridge) {
            self.bridge = bridge
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            bridge.sendToSSH(data: data)
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            bridge.resizeTerminal(cols: newCols, rows: newRows)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
#endif
