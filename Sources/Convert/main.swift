import AppKit

/// Test mode: `Convert --cli <target-id> file…` converts with default settings and prints the results.
///
/// `CONVERT_SETTINGS` (JSON) overrides individual settings, e.g. `{"hardware": false}`.
/// `Convert --cli --targets file…` lists the target IDs the window would offer for those files.
@MainActor
func runCLI(_ args: [String]) {
    if args.first == "--targets", args.count >= 2 {
        listTargets(for: args.dropFirst().map { URL(fileURLWithPath: $0) })
    }
    guard args.count >= 2, let target = Targets.byID(args[0]) else {
        print(
            """
            usage: Convert --cli <target> file…
                   Convert --cli --targets file…
            targets: \(Targets.all.map(\.id).joined(separator: " "))
            """)
        exit(2)
    }
    var settings = ConvSettings()
    if let json = ProcessInfo.processInfo.environment["CONVERT_SETTINGS"] {
        do {
            settings = try settingsWithOverrides(json)
        } catch {
            print("CONVERT_SETTINGS is not valid: \(error.localizedDescription)")
            exit(2)
        }
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

/// Prints one target ID per line, the same choices the window offers for these files.
@MainActor
func listTargets(for urls: [URL]) -> Never {
    var kinds = Set<MediaKind>()
    for url in urls {
        guard let kind = MediaKind.of(url) else {
            print("unsupported file: \(url.lastPathComponent)")
            exit(1)
        }
        kinds.insert(kind)
    }
    for (_, targets) in Targets.groups(for: kinds) {
        for target in targets { print(target.id) }
    }
    exit(0)
}

/// The default settings with the keys from a JSON object replaced, so callers only name what they change.
func settingsWithOverrides(_ json: String) throws -> ConvSettings {
    let defaults = try JSONEncoder().encode(ConvSettings())
    guard var merged = try JSONSerialization.jsonObject(with: defaults) as? [String: Any],
        let overrides = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    else { throw ConvertError("expected a JSON object such as {\"hardware\": false}") }
    for key in overrides.keys.sorted() where merged[key] == nil {
        throw ConvertError("unknown setting \"\(key)\"; known: \(merged.keys.sorted().joined(separator: ", "))")
    }
    merged.merge(overrides) { _, new in new }
    return try JSONDecoder().decode(ConvSettings.self, from: JSONSerialization.data(withJSONObject: merged))
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
