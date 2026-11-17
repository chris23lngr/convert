import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let labelWidth: CGFloat = 104

enum Brand {
    /// The one brand colour, shared with the icon and the website.
    static let sky = Color(red: 0.18, green: 0.66, blue: 1.0)
}

extension Notification.Name {
    static let quickActionChanged = Notification.Name("ConvertQuickActionChanged")
}

struct ContentView: View {
    @ObservedObject var model: ConvertModel
    @State private var dropTargeted = false
    @State private var quickActionInstalled = QuickAction.isInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.files.isEmpty {
                dropZone
            } else if model.groups.isEmpty {
                Label("These files can't be converted together. Pick files of one kind (audio, video, images, documents or PDFs).",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let target = model.target {
                FormRow("Convert to") { formatPicker }
                SettingsView(target: target, s: $model.settings)
                    .disabled(model.phase != .idle)
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460)
        .tint(Brand.sky)
        .background(dropTargeted ? Brand.sky.opacity(0.08) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if let kind = model.primaryKind {
                Image(systemName: kind.symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Brand.sky)
                    .frame(width: 40, height: 40)
                    .background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch model.files.count {
        case 0: "Convert"
        case 1: model.files[0].lastPathComponent
        default: "\(model.files.count) files"
        }
    }

    private var subtitle: String {
        if model.files.isEmpty { return "Drop files here, or right-click files in Finder → Quick Actions → Convert…" }
        var parts: [String] = []
        if model.files.count == 1 {
            let f = model.files[0]
            if let k = MediaKind.of(f) { parts.append(k.noun) }
            if let size = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        } else {
            let names = model.files.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            parts.append(model.files.count > 3 ? "\(names) + \(model.files.count - 3) more" : names)
        }
        if model.skipped > 0 { parts.append("\(model.skipped) unsupported skipped") }
        return parts.joined(separator: " · ")
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Drop audio, video, images, documents or PDFs").foregroundStyle(.secondary)
                Button("Choose Files…") { chooseFiles() }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(dropTargeted ? Brand.sky : Color.secondary.opacity(0.4)))

            if !quickActionInstalled {
                HStack(spacing: 10) {
                    Image(systemName: "contextualmenu.and.cursorarrow").foregroundStyle(Brand.sky)
                    Text("Add “Convert…” to Finder’s right-click menu").font(.callout)
                    Spacer()
                    Button("Install") {
                        NSApp.sendAction(#selector(AppDelegate.installQuickAction(_:)), to: nil, from: nil)
                    }
                }
                .padding(10)
                .background(Brand.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickActionChanged)) { _ in
            quickActionInstalled = QuickAction.isInstalled
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { model.add(panel.urls) }
    }

    // MARK: Format

    private var formatPicker: some View {
        Picker("", selection: $model.targetID) {
            ForEach(model.groups, id: \.0) { group, targets in
                Section(model.groups.count > 1 ? group.rawValue : "") {
                    ForEach(targets) { Text($0.label).tag($0.id) }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(model.phase != .idle)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .idle:
            HStack {
                if model.target?.group == .audio || model.target?.group == .video, Tools.ffmpeg == nil {
                    Label("Needs ffmpeg (brew install ffmpeg)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { model.onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Convert") { model.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.target == nil || model.files.isEmpty)
            }
        case .running:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: model.progress)
                HStack {
                    Text("Converting \(model.currentName)…")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Stop") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        case .done:
            VStack(alignment: .leading, spacing: 8) {
                if !model.outputs.isEmpty {
                    Label("Converted \(model.outputs.count) \(model.outputs.count == 1 ? "file" : "files")",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if model.stopped {
                    Label("Stopped", systemImage: "stop.circle").foregroundStyle(.secondary)
                }
                ForEach(model.errors, id: \.self) { e in
                    Label(e, systemImage: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
                        .disabled(model.outputs.isEmpty)
                    Button("Done") { model.onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

// MARK: - Settings

struct FormRow<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

struct SettingsView: View {
    let target: Target
    @Binding var s: ConvSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch target.group {
            case .audio: audio
            case .video: target.id == "gif" ? AnyView(gif) : AnyView(video)
            case .image: image
            case .document: document
            case .pdfPages: pdf
            }
        }
    }

    private func menu<V: Hashable>(_ selection: Binding<V>, _ options: [(V, String)]) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    // Audio

    @ViewBuilder private var audio: some View {
        if target.isLossyAudio {
            FormRow("Bitrate") {
                menu($s.audioBitrate, target.bitrateOptions.map { ($0, $0 == 0 ? "VBR – best (~245 kbps)" : "\($0) kbps") })
            }
        }
        if target.isLosslessAudio {
            FormRow("Bit depth") {
                menu($s.bitDepth, [(0, "Match source"), (16, "16-bit"), (24, "24-bit")])
            }
        }
        if !target.sampleRates.isEmpty {
            FormRow("Sample rate") {
                menu($s.sampleRate, target.sampleRates.map { ($0, $0 == 0 ? "Same as source" : rateLabel($0)) })
            }
        }
        if target.hasChannelOption {
            FormRow("Channels") {
                menu($s.channels, [(0, "Same as source"), (2, "Stereo"), (1, "Mono")])
            }
        }
    }

    private func rateLabel(_ hz: Int) -> String {
        let k = Double(hz) / 1000
        return k == k.rounded() ? "\(Int(k)) kHz" : String(format: "%.1f kHz", k)
    }

    // Video

    private var video: some View {
        VStack(alignment: .leading, spacing: 10) {
            if target.id != "mov-prores" {
                FormRow("Quality") {
                    Slider(value: $s.videoQuality, in: 0...1) { EmptyView() }
                        minimumValueLabel: { Text("Smaller").font(.caption) }
                        maximumValueLabel: { Text("Better").font(.caption) }
                        .frame(width: 250)
                }
            }
            FormRow("Resolution") {
                menu($s.videoHeight, [(0, "Same as source"), (2160, "4K (2160p)"), (1440, "1440p"),
                                      (1080, "1080p"), (720, "720p"), (480, "480p")])
            }
            FormRow("Frame rate") {
                menu($s.fps, [(0, "Same as source"), (60, "60 fps"), (30, "30 fps"), (25, "25 fps"), (24, "24 fps")])
            }
            FormRow("") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Include audio", isOn: $s.keepAudio)
                    if target.hasHardwareOption {
                        Toggle("Hardware encoding (much faster)", isOn: $s.hardware)
                    }
                }
            }
        }
    }

    private var gif: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormRow("Width") {
                menu($s.gifWidth, [320, 480, 640, 800, 1080].map { ($0, "\($0) px") })
            }
            FormRow("Frame rate") {
                menu($s.gifFps, [10, 12, 15, 20, 25, 30].map { ($0, "\($0) fps") })
            }
        }
    }

    // Image

    @ViewBuilder private var image: some View {
        if target.isLossyImage { qualitySlider }
        FormRow("Max size") {
            menu($s.maxSize, [(0, "Same as source"), (4096, "4096 px"), (2048, "2048 px"), (1920, "1920 px"),
                              (1280, "1280 px"), (1080, "1080 px"), (512, "512 px")])
        }
    }

    private var qualitySlider: some View {
        FormRow("Quality") {
            HStack {
                Slider(value: $s.imageQuality, in: 0.3...1, step: 0.05).frame(width: 200)
                Text("\(Int((s.imageQuality * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // Documents

    @ViewBuilder private var document: some View {
        if target.id == "pdf-doc" {
            FormRow("Paper") { menu($s.paperA4, [(true, "A4"), (false, "US Letter")]) }
        }
    }

    @ViewBuilder private var pdf: some View {
        if target.id != "pdf-txt" {
            FormRow("Resolution") {
                menu($s.pdfDPI, [(72, "72 dpi (screen)"), (150, "150 dpi"), (300, "300 dpi (print)")])
            }
            if target.id == "pdf-jpg" { qualitySlider }
        }
    }
}
