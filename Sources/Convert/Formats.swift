import Foundation
import UniformTypeIdentifiers

// MARK: - Input kinds

enum MediaKind: String, CaseIterable {
    case audio, video, image, pdf, document

    private static let videoExts: Set<String> = [
        "mkv", "webm", "avi", "flv", "wmv", "ts", "mts", "m2ts", "3gp", "ogv", "mxf", "vob",
    ]
    private static let audioExts: Set<String> = [
        "mka", "opus", "ape", "wv", "tta", "dsf", "dff", "ac3", "dts", "amr", "mp2", "caf",
    ]

    private static let documentTypes: [UTType] =
        [.rtf, .rtfd, .plainText, .html, .webArchive]
        + [
            "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
            "org.oasis-open.opendocument.text", "net.daringfireball.markdown",
        ].compactMap { UTType($0) }

    static func of(_ url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if ext == "md" || ext == "markdown" { return .document }
        guard let t = UTType(filenameExtension: ext) else { return nil }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .audiovisualContent) { return .video }
        if documentTypes.contains(where: { t.conforms(to: $0) }) { return .document }
        return nil
    }

    var outputGroups: Set<OutGroup> {
        switch self {
        case .audio: [.audio]
        case .video: [.video, .audio]
        case .image: [.image]
        case .pdf: [.pdfPages]
        case .document: [.document]
        }
    }

    var symbol: String {
        switch self {
        case .audio: "waveform"
        case .video: "film"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        }
    }

    var noun: String {
        switch self {
        case .audio: "Audio"
        case .video: "Video"
        case .image: "Image"
        case .pdf: "PDF"
        case .document: "Document"
        }
    }
}

// MARK: - Output targets

enum OutGroup: String, CaseIterable {
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    case document = "Document"
    case pdfPages = "From PDF"
}

struct Target: Identifiable, Hashable {
    let id: String
    let label: String
    let ext: String
    let group: OutGroup
}

enum Targets {
    static let all: [Target] = {
        func t(_ g: OutGroup, _ list: [(String, String, String)]) -> [Target] {
            list.map { Target(id: $0.0, label: $0.1, ext: $0.2, group: g) }
        }
        var webp: [(String, String, String)] = []
        if Tools.cwebp != nil { webp = [("webp", "WebP", "webp")] }
        return t(
            .video,
            [
                ("mp4-h264", "MP4 (H.264)", "mp4"),
                ("mp4-hevc", "MP4 (HEVC / H.265)", "mp4"),
                ("mov-prores", "MOV (ProRes 422)", "mov"),
                ("webm", "WebM (VP9)", "webm"),
                ("mkv", "MKV (H.264)", "mkv"),
                ("mp4-av1", "MP4 (AV1)", "mp4"),
                ("gif", "GIF (animated)", "gif"),
            ])
            + t(
                .audio,
                [
                    ("mp3", "MP3", "mp3"),
                    ("m4a", "M4A (AAC)", "m4a"),
                    ("he-aac", "M4A (HE-AAC, small)", "m4a"),
                    ("wav", "WAV", "wav"),
                    ("aiff", "AIFF", "aiff"),
                    ("flac", "FLAC", "flac"),
                    ("alac", "ALAC (Apple Lossless)", "m4a"),
                    ("opus", "Opus", "opus"),
                    ("ogg", "OGG (Vorbis)", "ogg"),
                    ("wma", "WMA", "wma"),
                    ("ac3", "AC3 (Dolby Digital)", "ac3"),
                    ("wv", "WavPack", "wv"),
                    ("mp2", "MP2", "mp2"),
                ])
            + t(
                .image,
                [
                    ("jpg", "JPEG", "jpg"),
                    ("png", "PNG", "png"),
                    ("heic", "HEIC", "heic"),
                    ("avif", "AVIF", "avif"),
                ] + webp + [
                    ("tiff", "TIFF", "tiff"),
                    ("gif-img", "GIF", "gif"),
                    ("bmp", "BMP", "bmp"),
                    ("pdf-img", "PDF", "pdf"),
                ])
            + t(
                .document,
                [
                    ("pdf-doc", "PDF", "pdf"),
                    ("docx", "Word (DOCX)", "docx"),
                    ("doc", "Word 97–2004 (DOC)", "doc"),
                    ("odt", "OpenDocument (ODT)", "odt"),
                    ("rtf", "Rich Text (RTF)", "rtf"),
                    ("txt", "Plain Text", "txt"),
                    ("html", "HTML", "html"),
                ])
            + t(
                .pdfPages,
                [
                    ("pdf-png", "PNG (one per page)", "png"),
                    ("pdf-jpg", "JPEG (one per page)", "jpg"),
                    ("pdf-txt", "Plain Text", "txt"),
                ])
    }()

    static func byID(_ id: String) -> Target? { all.first { $0.id == id } }

    /// Output groups valid for every selected file.
    static func groups(for kinds: Set<MediaKind>) -> [(OutGroup, [Target])] {
        guard !kinds.isEmpty else { return [] }
        var allowed = Set(OutGroup.allCases)
        for k in kinds { allowed.formIntersection(k.outputGroups) }
        return OutGroup.allCases.filter(allowed.contains).map { g in (g, all.filter { $0.group == g }) }
    }

    /// Sensible first choice for a selection, skipping the format the files are already in.
    static func preferred(for kinds: Set<MediaKind>, sourceExts: Set<String>, among available: [Target]) -> Target? {
        let order: [String]
        switch kinds.count == 1 ? kinds.first : (kinds == [.audio, .video] ? .audio : nil) {
        case .audio: order = ["mp3", "wav", "m4a"]
        case .video: order = ["mp4-h264", "mov-prores"]
        case .image: order = ["jpg", "png"]
        case .pdf: order = ["pdf-png"]
        case .document: order = ["pdf-doc", "docx"]
        default: order = []
        }
        for id in order {
            if let t = available.first(where: { $0.id == id }), !sourceExts.contains(t.ext) { return t }
        }
        return available.first { !sourceExts.contains($0.ext) } ?? available.first
    }
}

// MARK: - Per-target options

extension Target {
    var isLossyAudio: Bool { ["mp3", "m4a", "he-aac", "opus", "ogg", "wma", "ac3", "mp2"].contains(id) }
    var isLosslessAudio: Bool { ["wav", "aiff", "flac", "alac", "wv"].contains(id) }
    var isLossyImage: Bool { ["jpg", "heic", "avif", "webp"].contains(id) }
    var hasHardwareOption: Bool { ["mp4-h264", "mp4-hevc", "mov-prores", "mkv"].contains(id) }

    var bitrateOptions: [Int] {
        switch id {
        case "mp3": [0, 320, 256, 192, 160, 128, 96, 64]
        case "m4a": [320, 256, 192, 160, 128, 96]
        case "he-aac": [96, 80, 64, 48, 32]
        case "opus": [256, 192, 160, 128, 96, 64, 48, 32]
        case "ogg": [320, 256, 192, 160, 128, 96]
        case "wma": [256, 192, 160, 128, 96]
        case "ac3": [640, 448, 384, 256, 192]
        case "mp2": [384, 320, 256, 192, 128]
        default: []
        }
    }

    var defaultBitrate: Int {
        switch id {
        case "m4a": 256
        case "he-aac": 64
        case "opus": 160
        case "ogg", "wma": 192
        case "ac3": 448
        case "mp2": 256
        default: 0
        }
    }

    var sampleRates: [Int] {
        if id == "opus" { return [] }
        return isLossyAudio ? [0, 44100, 48000] : [0, 44100, 48000, 88200, 96000]
    }

    var hasChannelOption: Bool { id != "ogg" }

    /// Whether the panel has anything to show under "Advanced" for this format.
    var hasSettings: Bool { !(group == .document && id != "pdf-doc") && id != "pdf-txt" }
}

struct ConvSettings: Codable, Equatable {
    // Audio
    var audioBitrate = 0  // kbps; 0 = MP3 VBR best
    var sampleRate = 0  // 0 = same as source
    var channels = 0  // 0 = same, 1 = mono, 2 = stereo
    var bitDepth = 0  // 0 = auto (match source), 16, 24
    // Video
    var videoQuality = 0.65  // 0 = smallest … 1 = best
    var videoHeight = 0  // 0 = same as source
    var fps = 0  // 0 = same as source
    var keepAudio = true
    var hardware = true
    var gifWidth = 480
    var gifFps = 15
    // Image
    var imageQuality = 0.85
    var maxSize = 0  // longest edge in px; 0 = same as source
    // Documents / PDF
    var paperA4 = true
    var pdfDPI = 150
}
