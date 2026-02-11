import AppKit

class SetupWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var commandField: NSTextField!
    var directoryField: NSTextField!
    var onSave: ((AppConfig) -> Void)?

    private var existingConfig: AppConfig?

    init(config: AppConfig? = nil, onSave: @escaping (AppConfig) -> Void) {
        self.existingConfig = config
        self.onSave = onSave
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let isFirstRun = existingConfig == nil
        let title = isFirstRun ? "Welcome to ClaudeSidian" : "Settings"

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let padding: CGFloat = 24
        let fieldHeight: CGFloat = 28
        var y: CGFloat = 240

        // Title label
        if isFirstRun {
            let titleLabel = NSTextField(labelWithString: "Configure your terminal command and working directory.")
            titleLabel.font = NSFont.systemFont(ofSize: 13)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.frame = NSRect(x: padding, y: y, width: 520 - padding * 2, height: 20)
            contentView.addSubview(titleLabel)
            y -= 36
        } else {
            y -= 8
        }

        // Command label + field
        let cmdLabel = NSTextField(labelWithString: "Command to run:")
        cmdLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cmdLabel.frame = NSRect(x: padding, y: y, width: 200, height: 20)
        contentView.addSubview(cmdLabel)
        y -= fieldHeight + 4

        commandField = NSTextField(frame: NSRect(x: padding, y: y, width: 520 - padding * 2, height: fieldHeight))
        commandField.placeholderString = "claude --dangerously-skip-permissions"
        commandField.stringValue = existingConfig?.command ?? ""
        commandField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        contentView.addSubview(commandField)
        y -= 32

        // Directory label + field + browse
        let dirLabel = NSTextField(labelWithString: "Working directory:")
        dirLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        dirLabel.frame = NSRect(x: padding, y: y, width: 200, height: 20)
        contentView.addSubview(dirLabel)
        y -= fieldHeight + 4

        let browseWidth: CGFloat = 80
        let gap: CGFloat = 8
        directoryField = NSTextField(frame: NSRect(x: padding, y: y, width: 520 - padding * 2 - browseWidth - gap, height: fieldHeight))
        directoryField.placeholderString = "~/Projects"
        directoryField.stringValue = existingConfig?.workingDirectory ?? ""
        directoryField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        contentView.addSubview(directoryField)

        let browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseDirectory(_:)))
        browseButton.bezelStyle = .rounded
        browseButton.frame = NSRect(x: 520 - padding - browseWidth, y: y - 1, width: browseWidth, height: fieldHeight + 2)
        contentView.addSubview(browseButton)
        y -= 40

        // Save button
        let saveTitle = isFirstRun ? "Save & Launch" : "Save"
        let saveButton = NSButton(title: saveTitle, target: self, action: #selector(saveConfig(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let btnWidth: CGFloat = isFirstRun ? 120 : 80
        saveButton.frame = NSRect(x: 520 - padding - btnWidth, y: y, width: btnWidth, height: 32)
        contentView.addSubview(saveButton)

        // Info text
        let infoLabel = NSTextField(labelWithString: "Settings saved to ~/.config/claudesidian/config.json")
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.frame = NSRect(x: padding, y: 16, width: 520 - padding * 2, height: 16)
        contentView.addSubview(infoLabel)
    }

    @objc func browseDirectory(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if !directoryField.stringValue.isEmpty {
            let expanded = NSString(string: directoryField.stringValue).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url {
                let path = url.path
                let home = NSHomeDirectory()
                if path.hasPrefix(home) {
                    self?.directoryField.stringValue = "~" + path.dropFirst(home.count)
                } else {
                    self?.directoryField.stringValue = path
                }
            }
        }
    }

    @objc func saveConfig(_ sender: Any) {
        let command = commandField.stringValue.trimmingCharacters(in: .whitespaces)
        let directory = directoryField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !command.isEmpty else {
            showAlert("Please enter a command to run.")
            return
        }
        guard !directory.isEmpty else {
            showAlert("Please enter a working directory.")
            return
        }

        let expanded = NSString(string: directory).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            showAlert("The directory \"\(directory)\" does not exist.")
            return
        }

        let config = AppConfig(command: command, workingDirectory: directory)
        do {
            try config.save()
        } catch {
            showAlert("Failed to save config: \(error.localizedDescription)")
            return
        }

        window.close()
        onSave?(config)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // If first-run and user closes without saving, quit
        if existingConfig == nil {
            NSApp.terminate(nil)
        }
    }
}
