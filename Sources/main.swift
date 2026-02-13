import AppKit
import SwiftTerm

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var terminalView: LocalProcessTerminalView!
    var terminalDelegate: TerminalHandler!
    var setupController: SetupWindowController?
    var currentConfig: AppConfig?
    var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if let config = AppConfig.load() {
            currentConfig = config
            setupMenuBar()
            setupWindow()
            setupTerminal(with: config)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(terminalView)
        } else {
            setupMenuBar()
            showSetup(config: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminateChildProcess()
        return .terminateNow
    }

    func windowWillClose(_ notification: Notification) {
        terminateChildProcess()
    }

    private func terminateChildProcess() {
        guard let tv = terminalView else { return }
        let pid = tv.process.shellPid
        guard pid != 0, tv.process.running else { return }

        tv.terminate()

        // Fallback: if still alive after 2s, SIGKILL
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ClaudeSidian", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ClaudeSidian", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ClaudeSidian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (for copy/paste)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu (font size)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Bigger", action: #selector(biggerFont(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Smaller", action: #selector(smallerFont(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(resetFont(_:)), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Settings

    @objc func openSettings(_ sender: Any) {
        let config = currentConfig ?? AppConfig.load()
        setupController = SetupWindowController(config: config) { _ in
            let alert = NSAlert()
            alert.messageText = "Settings saved"
            alert.informativeText = "Restart ClaudeSidian for changes to take effect."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        setupController?.showWindow()
    }

    private func showSetup(config: AppConfig?) {
        setupController = SetupWindowController(config: config) { [weak self] config in
            self?.currentConfig = config
            self?.setupWindow()
            self?.setupTerminal(with: config)
            NSApp.activate(ignoringOtherApps: true)
            self?.window.makeKeyAndOrderFront(nil)
            self?.window.makeFirstResponder(self?.terminalView)
        }
        setupController?.showWindow()
    }

    // MARK: - Window

    func setupWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth: CGFloat = min(1000, screenFrame.width * 0.7)
        let windowHeight: CGFloat = min(700, screenFrame.height * 0.7)
        let windowX = screenFrame.midX - windowWidth / 2
        let windowY = screenFrame.midY - windowHeight / 2

        let contentRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeSidian"
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        window.delegate = self
    }

    // MARK: - Terminal

    func setupTerminal(with config: AppConfig) {
        guard let contentView = window.contentView else { return }

        let padding: CGFloat = 12

        terminalView = DroppableTerminalView(frame: .zero)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        terminalView.caretColor = NSColor(red: 0.91, green: 0.59, blue: 0.41, alpha: 1.0)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
        terminalView.optionAsMetaKey = false

        // Delegate
        terminalDelegate = TerminalHandler(window: window, app: self)
        terminalView.processDelegate = terminalDelegate

        contentView.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
            terminalView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding),
            terminalView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            terminalView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
        ])

        let env = buildEnvironment()
        let (executable, args) = config.shellCommand()
        let workDir = config.expandedWorkingDirectory()
        let shell = AppConfig.userShell()

        terminalView.startProcess(
            executable: executable,
            args: args,
            environment: env,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: workDir
        )

        // Intercept Shift+Enter → send \n for Claude Code multiline input
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let tv = self?.terminalView else { return event }
            if event.modifierFlags.contains(.shift) && event.keyCode == 36 {
                tv.send(txt: "\n")
                return nil
            }
            return event
        }
    }

    func buildEnvironment() -> [String] {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")

        let currentEnv = ProcessInfo.processInfo.environment
        let homePath = currentEnv["HOME"] ?? NSHomeDirectory()

        var pathComponents: [String] = []
        pathComponents.append("\(homePath)/.local/bin")
        pathComponents.append("\(homePath)/.nvm/versions/node/current/bin")
        pathComponents.append("/opt/homebrew/bin")
        pathComponents.append("/opt/homebrew/sbin")
        pathComponents.append("/usr/local/bin")
        pathComponents.append("/usr/local/sbin")

        if let systemPath = currentEnv["PATH"] {
            pathComponents.append(systemPath)
        } else {
            pathComponents.append("/usr/bin:/bin:/usr/sbin:/sbin")
        }

        env.append("PATH=\(pathComponents.joined(separator: ":"))")

        for key in ["SHELL", "SSH_AUTH_SOCK", "TMPDIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "EDITOR"] {
            if let val = currentEnv[key] {
                env.append("\(key)=\(val)")
            }
        }

        // Enable OSC 8 hyperlink support (clickable file paths in Claude Code)
        env.append("FORCE_HYPERLINK=1")

        return env
    }

    // MARK: - Font Actions

    @objc func biggerFont(_ sender: Any) {
        guard let tv = terminalView else { return }
        let size = tv.font.pointSize
        guard size < 72 else { return }
        tv.font = NSFont.monospacedSystemFont(ofSize: size + 1, weight: .regular)
    }

    @objc func smallerFont(_ sender: Any) {
        guard let tv = terminalView else { return }
        let size = tv.font.pointSize
        guard size > 8 else { return }
        tv.font = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }

    @objc func resetFont(_ sender: Any) {
        terminalView?.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }
}

// MARK: - Cursor Overlay

/// Transparent view placed above the terminal to override SwiftTerm's iBeam cursor.
/// AppKit's cursor rect system uses the topmost visible view — when this overlay is
/// unhidden, its pointingHand cursor rect takes precedence over the terminal's iBeam.
/// All mouse, keyboard, and scroll events are forwarded to the terminal underneath.
class CursorOverlayView: NSView {
    weak var targetView: NSView?

    init(target: NSView) {
        self.targetView = target
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // Forward all input events to the terminal view
    override func mouseDown(with event: NSEvent) { targetView?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { targetView?.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { targetView?.mouseDragged(with: event) }
    override func rightMouseDown(with event: NSEvent) { targetView?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { targetView?.rightMouseUp(with: event) }
    override func otherMouseDown(with event: NSEvent) { targetView?.otherMouseDown(with: event) }
    override func otherMouseUp(with event: NSEvent) { targetView?.otherMouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) { targetView?.scrollWheel(with: event) }
    override func keyDown(with event: NSEvent) { targetView?.keyDown(with: event) }
    override func keyUp(with event: NSEvent) { targetView?.keyUp(with: event) }
    override func flagsChanged(with event: NSEvent) { targetView?.flagsChanged(with: event) }
}

// MARK: - Drag & Drop Terminal View

class DroppableTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setupFileClickMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        setupFileClickMonitor()
    }

    // MARK: - Cmd+Click file path detection

    private var clickMonitor: Any?
    private var cursorMonitor: Any?
    private var flagsMonitor: Any?
    private var showingPointingHand = false

    func setupFileClickMonitor() {
        // Cmd+Click to open file paths
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self,
                  event.modifierFlags.contains(.command),
                  let window = event.window,
                  window === self.window else {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }

            let (col, row) = self.cellPosition(from: point)

            // Skip if this cell has an OSC 8 payload (super already handles it)
            if let cd = self.terminal.getCharData(col: col, row: row), cd.getPayload() != nil {
                return event
            }

            if let path = self.resolveFilePath(displayRow: row, col: col) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return nil
            }

            return event
        }

        // Cursor change on Cmd+hover over file paths
        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else { return event }
            self.updateCursorIfNeeded(for: event)
            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.command) {
                self.updateCursorIfNeeded(for: event)
            } else {
                self.resetCursorIfNeeded()
            }
            return event
        }
    }

    private var cursorOverlay: CursorOverlayView?

    private func ensureOverlay() {
        guard cursorOverlay == nil, let sv = superview else { return }
        let overlay = CursorOverlayView(target: self)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        sv.addSubview(overlay, positioned: .above, relativeTo: self)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        cursorOverlay = overlay
    }

    private func updateCursorIfNeeded(for event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              let window = self.window else {
            resetCursorIfNeeded()
            return
        }

        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let point = convert(mouseLocation, from: nil)
        guard bounds.contains(point) else {
            resetCursorIfNeeded()
            return
        }

        let (col, row) = cellPosition(from: point)

        let hasLink: Bool
        if let cd = terminal.getCharData(col: col, row: row), cd.getPayload() != nil {
            hasLink = true
        } else {
            hasLink = resolveFilePath(displayRow: row, col: col) != nil
        }

        if hasLink {
            if !showingPointingHand {
                showingPointingHand = true
                ensureOverlay()
                cursorOverlay?.isHidden = false
                window.invalidateCursorRects(for: cursorOverlay!)
            }
        } else {
            resetCursorIfNeeded()
        }
    }

    private func resetCursorIfNeeded() {
        guard showingPointingHand else { return }
        showingPointingHand = false
        if let overlay = cursorOverlay {
            overlay.isHidden = true
            window?.invalidateCursorRects(for: overlay)
        }
        window?.invalidateCursorRects(for: self)
    }

    private func cellPosition(from point: CGPoint) -> (col: Int, row: Int) {
        let cellWidth = frame.width / CGFloat(terminal.cols)
        let cellHeight = frame.height / CGFloat(terminal.rows)
        let col = min(max(0, Int(point.x / cellWidth)), terminal.cols - 1)
        let row = min(max(0, Int((frame.height - point.y) / cellHeight)), terminal.rows - 1)
        return (col, row)
    }

    /// Returns the expanded, validated file path if one exists under the cursor, or nil.
    private func resolveFilePath(displayRow: Int, col: Int) -> String? {
        guard let path = extractFilePath(displayRow: displayRow, col: col) else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
    }

    deinit {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        if let m = cursorMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
    }

    private func extractFilePath(displayRow: Int, col: Int) -> String? {
        let cols = terminal.cols

        // Read all characters from this line
        var chars: [Character] = []
        for c in 0..<cols {
            if let ch = terminal.getCharacter(col: c, row: displayRow) {
                chars.append(ch)
            } else {
                chars.append(" ")
            }
        }

        let lineStr = String(chars)
        let stopChars = CharacterSet(charactersIn: "\"'`<>|;(){}[]")

        // Find all potential path starts (/ or ~/) on this line
        // and check if the clicked column falls within a valid path
        var candidates: [(start: Int, path: String)] = []

        for i in 0..<cols {
            let ch = chars[i]
            let isPathStart: Bool
            if ch == "/" {
                isPathStart = true
            } else if ch == "~" && i + 1 < cols && chars[i + 1] == "/" {
                isPathStart = true
            } else if ch == "." && i + 1 < cols && chars[i + 1] == "/" {
                isPathStart = true
            } else {
                isPathStart = false
            }

            guard isPathStart else { continue }

            // Scan right from this start, allowing spaces but stopping at delimiters
            var end = i
            for j in i..<cols {
                let c = chars[j]
                // Stop at hard delimiters
                if c.unicodeScalars.contains(where: { stopChars.contains($0) }) {
                    break
                }
                // Stop at control characters / null
                if c == "\0" || c.asciiValue.map({ $0 < 32 }) == true {
                    break
                }
                end = j
            }

            if end >= i + 1 { // at least 2 chars
                let startIdx = lineStr.index(lineStr.startIndex, offsetBy: i)
                let endIdx = lineStr.index(lineStr.startIndex, offsetBy: end + 1)
                var token = String(lineStr[startIdx..<endIdx])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",:"))

                // Strip trailing :lineNumber
                if let range = token.range(of: #":\d+$"#, options: .regularExpression) {
                    token = String(token[token.startIndex..<range.lowerBound])
                }

                candidates.append((start: i, path: token))
            }
        }

        // Find the longest candidate whose range includes the clicked column
        // Prefer longer matches (more specific paths)
        var bestMatch: String? = nil
        for candidate in candidates {
            let expanded = (candidate.path as NSString).expandingTildeInPath
            let pathLen = candidate.path.count
            let rangeEnd = candidate.start + pathLen - 1

            if col >= candidate.start && col <= rangeEnd {
                if bestMatch == nil || candidate.path.count > bestMatch!.count {
                    if FileManager.default.fileExists(atPath: expanded) {
                        bestMatch = candidate.path
                    }
                }
            }
        }

        return bestMatch
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }

        let paths = urls.map { shellEscape($0.path) }
        let text = paths.joined(separator: " ")
        send(txt: text)
        return true
    }

    private func shellEscape(_ path: String) -> String {
        if path.rangeOfCharacter(from: .init(charactersIn: " \t'\"\\!$`#&|;(){}[]<>?*~")) != nil {
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return path
    }
}

// MARK: - Terminal Handler

class TerminalHandler: LocalProcessTerminalViewDelegate {
    weak var window: NSWindow?
    weak var app: AppDelegate?

    init(window: NSWindow, app: AppDelegate) {
        self.window = window
        self.app = app
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Launch

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
