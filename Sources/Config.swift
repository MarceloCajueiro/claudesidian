import Foundation

struct AppConfig: Codable {
    var command: String
    var workingDirectory: String

    static let configDir = NSString(string: "~/.config/claudesidian").expandingTildeInPath
    static let configPath = (configDir as NSString).appendingPathComponent("config.json")

    static func load() -> AppConfig? {
        let url = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save() throws {
        let dir = AppConfig.configDir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: AppConfig.configPath))
    }

    func expandedWorkingDirectory() -> String {
        NSString(string: workingDirectory).expandingTildeInPath
    }

    /// Parse command string into (executable, args) for shell execution.
    /// Uses the user's login shell with -l -c to ensure PATH and env are loaded.
    func shellCommand() -> (executable: String, args: [String]) {
        let shell = AppConfig.userShell()
        return (shell, ["-l", "-c", "exec \(command)"])
    }

    static func userShell() -> String {
        let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
        guard bufsize != -1 else { return "/bin/zsh" }
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
        defer { buffer.deallocate() }
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        if getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) != 0 {
            return "/bin/zsh"
        }
        return String(cString: pwd.pw_shell)
    }
}
