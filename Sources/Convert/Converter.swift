import Foundation

enum Converter {
    /// Converts one file and returns what was written (files, or a folder for multi-page PDFs).
    static func convert(
        _ input: URL, to t: Target, settings s: ConvSettings, runner: Runner,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        switch t.group {
        case .audio, .video:
            guard let ff = Tools.ffmpeg else {
                throw ConvertError("ffmpeg isn't installed. Install it with: brew install ffmpeg")
            }
            let p = await Task.detached { FF.probe(input) }.value
            if p.ok, t.group == .audio, !p.hasAudio { throw ConvertError("This file has no audio track") }
            if p.ok, t.group == .video, !p.hasVideo { throw ConvertError("This file has no video track") }
            let out = uniqueOutput(for: input, ext: t.ext)
            let codec = t.group == .audio ? FF.audioArgs(t, s, p) : FF.videoArgs(t, s, p)
            let args = FF.common + ["-i", input.path] + codec + [out.path]
            do {
                try await runner.run(ff, args, duration: p.duration, progress: progress)
            } catch {
                try? FileManager.default.removeItem(at: out)
                throw error
            }
            return [out]

        case .image:
            return [try await Task.detached { try ImageConv.convert(input, t, s) }.value]

        case .document:
            if t.id == "pdf-doc" {
                let out = uniqueOutput(for: input, ext: "pdf")
                try await MainActor.run { try DocConv.toPDF(input, out, a4: s.paperA4) }
                return [out]
            }
            return [try await Task.detached { try DocConv.textutil(input, t) }.value]

        case .pdfPages:
            return try await Task.detached { try PDFConv.convert(input, t, s, progress: progress) }.value
        }
    }
}
