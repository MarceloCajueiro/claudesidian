import AppKit
import SwiftTerm

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var terminalView: LocalProcessTerminalView!
    var terminalDelegate: TerminalHandler!
    var setupController: SetupWindowController?
    var currentConfig: AppConfig?

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

        terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        terminalView.caretColor = NSColor(red: 0.91, green: 0.59, blue: 0.41, alpha: 1.0)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
        terminalView.optionAsMetaKey = true

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
