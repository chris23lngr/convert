import AppKit

/// Test mode: `Convert --cli <target-id> file…` converts with default settings and prints the results.
@MainActor
func runCLI(_ args: [String]) {
    guard args.count >= 2, let target = Targets.byID(args[0]) else {
        print("usage: Convert --cli <target> file…\ntargets: \(Targets.all.map(\.id).joined(separator: " "))")
        exit(2)
    }
    var settings = ConvSettings()
    if let json = ProcessInfo.processInfo.environment["CONVERT_SETTINGS"],
        let s = try? JSONDecoder().decode(ConvSettings.self, from: Data(json.utf8))
    {
        settings = s
    }
    Task {
        var failed = false
        for path in args.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let start = Date()
            do {
                let outs = try await Converter.convert(url, to: target, settings: settings, runner: Runner()) { _ in }
                let secs = String(format: "%.2fs", Date().timeIntervalSince(start))
                print(
                    "OK   \(url.lastPathComponent) → \(outs.map(\.lastPathComponent).joined(separator: ", ")) (\(secs))"
                )
            } catch {
                failed = true
                print("FAIL \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        exit(failed ? 1 : 0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--install-quick-action" || args.first == "--uninstall-quick-action" {
        do {
            if args.first == "--install-quick-action" { try QuickAction.install() } else { try QuickAction.uninstall() }
            print(QuickAction.isInstalled ? "Quick Action installed: \(QuickAction.url.path)" : "Quick Action removed")
            exit(0)
        } catch {
            print("Failed: \(error.localizedDescription)")
            exit(1)
        }
    } else if args.first == "--cli" {
        app.setActivationPolicy(.prohibited)
        runCLI(Array(args.dropFirst()))
        app.run()
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
