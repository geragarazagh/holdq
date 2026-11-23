// Command line interface for HoldQ: inspect quit-protection status and active ⌘Q keycode.
// Run as holdq-cli (symlink to HoldQ.app/Contents/MacOS/HoldQ) or as HoldQ with subcommands:
//
//   holdq-cli status [--json]
//   holdq-cli --keycode
//   holdq-cli --version | --help

import AppKit
import ServiceManagement

private let holdqCliName = "holdq-cli"

private let hqAppBundle: Bundle = {
    let real = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let appURL = real.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return Bundle(url: appURL) ?? .main
}()

private func holdqAnswersForItself() -> Bool {
    typealias Lookup = @convention(c) (pid_t) -> pid_t
    let me = getpid()
    if let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
        let r = unsafeBitCast(f, to: Lookup.self)(me)
        if r > 0 { return r == me }
    }
    return getppid() == 1
}

private func hqFail(_ s: String) -> Never {
    FileHandle.standardError.write(Data((s + "\n").utf8))
    exit(1)
}

private func hqJSON(_ obj: Any) -> Never {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { hqFail("Could not encode JSON.") }
    print(text)
    exit(0)
}

private func hqRunning() -> Bool {
    guard let id = hqAppBundle.bundleIdentifier else { return false }
    return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != getpid() }
}

@MainActor func runHoldQCLI(_ rawArgs: [String]) -> Bool {
    let exe = hqAppBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "HoldQ"
    let named = URL(fileURLWithPath: rawArgs[0]).lastPathComponent != exe
    let rest = Array(rawArgs.dropFirst())
    let usage = """
    Usage: \(holdqCliName) status [--json]      prints version, running state, hold duration and mapped ⌘Q keycode
           \(holdqCliName) --keycode            prints the virtual keycode for ⌘Q in the current layout
           \(holdqCliName) --version | --help
    """
    let guiFlags: Set<String> = ["--login", "--background", "--dark"]
    guard let cmd = rest.first else {
        if named { print(usage); exit(0) }
        return false
    }
    switch cmd {
    case "--help", "-h":
        print(usage); exit(0)
    case "--version", "-V":
        let v = hqAppBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        print("HoldQ \(v)"); exit(0)
    case "--keycode":
        guard rest.count == 1 else { hqFail(usage) }
        print(quitKeyCode()); exit(0)
    case "status":
        break
    default:
        if named || (cmd.hasPrefix("--") && !guiFlags.contains(cmd)) { hqFail(usage) }
        return false
    }
    if holdqAnswersForItself() {
        hqFail("\(holdqCliName) runs from a terminal or script, not launched as an app or launchd job.")
    }
    let tail = Array(rest.dropFirst())
    let json = tail == ["--json"]
    guard tail.isEmpty || json else { hqFail(usage) }
    let version = hqAppBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let running = hqRunning()
    let code = quitKeyCode()
    let login = SMAppService.agent(plistName: "\(hqAppBundle.bundleIdentifier ?? "com.geragaraza.holdq").login.plist").status == .enabled
    if json {
        hqJSON([
            "version": version,
            "running": running,
            "holdSeconds": holdTime,
            "quitKeyCode": code,
            "openAtLogin": login,
        ])
    }
    print("version: \(version)")
    print("running: \(running ? "yes" : "no")")
    print("holdSeconds: \(holdTime)")
    print("quitKeyCode: \(code)")
    print("openAtLogin: \(login ? "yes" : "no")")
    exit(0)
}
