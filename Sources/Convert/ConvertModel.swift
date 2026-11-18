import Foundation
import SwiftUI

@MainActor
final class ConvertModel: ObservableObject {
    enum Phase { case idle, running, done }

    @Published private(set) var files: [URL] = []
    @Published private(set) var skipped = 0
    @Published var targetID = "" { didSet { if oldValue != targetID { loadSettings() } } }
    @Published var settings = ConvSettings() { didSet { if !loading { saveSettings() } } }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var currentName = ""
    @Published private(set) var outputs: [URL] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var stopped = false
    @Published private(set) var trashed = 0
    /// Move each original to the Trash once its conversion succeeded (remembered).
    @Published var trashOriginals = UserDefaults.standard.bool(forKey: "trashOriginals") {
        didSet { UserDefaults.standard.set(trashOriginals, forKey: "trashOriginals") }
    }

    var onClose: () -> Void = {}
    private var loading = false
    private let runner = Runner()

    init(files: [URL]) {
        add(files)
        loadSettings()
    }

    var kinds: Set<MediaKind> { Set(files.compactMap(MediaKind.of)) }
    var groups: [(OutGroup, [Target])] { Targets.groups(for: kinds) }
    var target: Target? { Targets.byID(targetID) }
    var primaryKind: MediaKind? { kinds.count == 1 ? kinds.first : nil }
    private var groupKey: String { kinds.map(\.rawValue).sorted().joined(separator: "+") }

    func add(_ urls: [URL]) {
        guard phase != .running else { return }
        if phase == .done { reset() }
        for u in urls where !files.contains(u) {
            if MediaKind.of(u) != nil { files.append(u) } else { skipped += 1 }
        }
        chooseTarget()
    }

    func remove(_ url: URL) {
        guard phase == .idle else { return }
        files.removeAll { $0 == url }
        chooseTarget()
    }

    private func reset() {
        phase = .idle
        outputs = []
        errors = []
        progress = 0
        stopped = false
        trashed = 0
    }

    private func chooseTarget() {
        let available = groups.flatMap(\.1)
        guard !available.isEmpty else {
            targetID = ""
            return
        }
        if available.contains(where: { $0.id == targetID }) { return }
        let last = UserDefaults.standard.string(forKey: "lastTarget.\(groupKey)")
        let exts = Set(files.map { $0.pathExtension.lowercased() })
        targetID =
            available.first(where: { $0.id == last })?.id
            ?? Targets.preferred(for: kinds, sourceExts: exts, among: available)?.id
            ?? available[0].id
    }

    private func loadSettings() {
        guard let t = target else { return }
        UserDefaults.standard.set(t.id, forKey: "lastTarget.\(groupKey)")
        var s = ConvSettings()
        if let data = UserDefaults.standard.data(forKey: "settings.\(t.id)"),
            let saved = try? JSONDecoder().decode(ConvSettings.self, from: data)
        {
            s = saved
        }
        if !t.bitrateOptions.isEmpty, !t.bitrateOptions.contains(s.audioBitrate) { s.audioBitrate = t.defaultBitrate }
        if !t.sampleRates.contains(s.sampleRate) { s.sampleRate = 0 }
        loading = true
        settings = s
        loading = false
    }

    private func saveSettings() {
        guard let t = target, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "settings.\(t.id)")
    }

    func start() {
        guard let t = target, phase == .idle, !files.isEmpty else { return }
        reset()
        phase = .running
        let list = files
        let s = settings
        let runner = runner
        let trash = trashOriginals
        Task {
            let n = Double(list.count)
            for (i, file) in list.enumerated() {
                if stopped { break }
                currentName = file.lastPathComponent
                progress = Double(i) / n
                let report: @Sendable (Double) -> Void = { [weak self] p in
                    Task { @MainActor in
                        guard let self, self.phase == .running else { return }
                        self.progress = (Double(i) + p) / n
                    }
                }
                do {
                    let made = try await Converter.convert(file, to: t, settings: s, runner: runner, progress: report)
                    outputs += made
                    // Only after a finished, separate output exists on disk; the Trash keeps it recoverable.
                    if trash, !stopped, !made.isEmpty, !made.contains(file),
                        made.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
                    {
                        do {
                            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                            trashed += 1
                        } catch {
                            errors.append("\(file.lastPathComponent): converted, but couldn't move it to the Trash")
                        }
                    }
                } catch {
                    if !stopped { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                }
            }
            progress = 1
            phase = .done
        }
    }

    func cancel() {
        guard phase == .running else { return }
        stopped = true
        runner.cancel()
    }
}
