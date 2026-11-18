import Foundation

struct Probe {
    var duration = 0.0
    var sampleRate = 0
    var hires = false  // 24/32-bit source
    var hasAudio = false
    var hasVideo = false
    var ok = false
}

enum FF {
    static func probe(_ url: URL) -> Probe {
        var p = Probe()
        guard let fp = Tools.ffprobe,
            let out = try? runSync(
                fp,
                [
                    "-v", "error", "-show_entries",
                    "format=duration:stream=codec_type,sample_rate,sample_fmt,bits_per_raw_sample,disposition",
                    "-of", "json", url.path,
                ]),
            let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        else { return p }
        p.ok = true
        if let f = json["format"] as? [String: Any], let d = f["duration"] as? String { p.duration = Double(d) ?? 0 }
        let streams = json["streams"] as? [[String: Any]] ?? []
        p.hasVideo = streams.contains { s in
            guard s["codec_type"] as? String == "video" else { return false }
            let attached = (s["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0
            return attached == 0  // ignore cover art
        }
        if let a = streams.first(where: { $0["codec_type"] as? String == "audio" }) {
            p.hasAudio = true
            p.sampleRate = Int(a["sample_rate"] as? String ?? "") ?? 0
            let fmt = a["sample_fmt"] as? String ?? ""
            let bits = Int(a["bits_per_raw_sample"] as? String ?? "") ?? 0
            p.hires = fmt.hasPrefix("s32") || bits > 16
        }
        return p
    }

    static let common = ["-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]

    // MARK: Audio

    static func audioArgs(_ t: Target, _ s: ConvSettings, _ p: Probe) -> [String] {
        var a = ["-map", "0:a:0", "-vn", "-map_metadata", "0", "-map_metadata", "0:s:a:0"]
        let br = t.bitrateOptions.contains(s.audioBitrate) ? s.audioBitrate : t.defaultBitrate
        let deep = s.bitDepth == 24 || (s.bitDepth == 0 && p.hires)
        var cap48 = t.isLossyAudio && t.id != "opus" && t.id != "mp3"

        switch t.id {
        case "mp3":
            a += ["-c:a", "libmp3lame"] + (br == 0 ? ["-q:a", "0"] : ["-b:a", "\(br)k"])
            cap48 = true
        case "m4a": a += ["-c:a", "aac_at", "-b:a", "\(br)k"]
        case "he-aac": a += ["-c:a", "aac_at", "-profile:a", "4", "-b:a", "\(br)k"]
        case "opus": a += ["-c:a", "libopus", "-b:a", "\(br)k"]
        case "ogg": a += ["-c:a", "vorbis", "-strict", "experimental", "-ac", "2", "-q:a", vorbisQuality(br)]
        case "wma": a += ["-c:a", "wmav2", "-b:a", "\(br)k"]
        case "ac3": a += ["-c:a", "ac3", "-b:a", "\(br)k"]
        case "mp2": a += ["-c:a", "mp2", "-b:a", "\(br)k"]
        case "wav": a += ["-c:a", deep ? "pcm_s24le" : "pcm_s16le"]
        case "aiff": a += ["-c:a", deep ? "pcm_s24be" : "pcm_s16be"]
        case "flac": a += ["-c:a", "flac", "-sample_fmt", deep ? "s32" : "s16"]
        case "alac": a += ["-c:a", "alac", "-sample_fmt", deep ? "s32p" : "s16p"]
        case "wv": a += ["-c:a", "wavpack", "-sample_fmt", deep ? "s32p" : "s16p"]
        default: break
        }
        if s.sampleRate > 0, t.sampleRates.contains(s.sampleRate) {
            a += ["-ar", "\(s.sampleRate)"]
        } else if cap48, p.sampleRate > 48000 {
            a += ["-ar", "48000"]
        }
        if s.channels > 0, t.hasChannelOption { a += ["-ac", "\(s.channels)"] }
        return a
    }

    private static func vorbisQuality(_ kbps: Int) -> String {
        switch kbps {
        case 320...: "9"
        case 256...: "8"
        case 192...: "6"
        case 160...: "5"
        case 128...: "4"
        default: "2"
        }
    }

    // MARK: Video

    static func videoArgs(_ t: Target, _ s: ConvSettings, _ p: Probe) -> [String] {
        let q = max(0, min(1, s.videoQuality))
        var filters: [String] = []
        var v: [String] = ["-map", "0:v:0", "-map_metadata", "0"]

        if t.id == "gif" {
            let w = s.gifWidth
            let vf =
                "fps=\(s.gifFps),scale=min(iw\\,\(w)):-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a"
            return v + ["-vf", vf, "-loop", "0", "-an"]
        }

        if s.fps > 0 { filters.append("fps=\(s.fps)") }
        if s.videoHeight > 0 { filters.append("scale=-2:min(ih\\,\(s.videoHeight))") }

        var audio = ["-c:a", "aac_at", "-b:a", "192k"]
        switch t.id {
        case "mp4-h264", "mkv":
            if s.hardware {
                v += ["-c:v", "h264_videotoolbox", "-q:v", "\(Int(40 + q * 45))", "-pix_fmt", "yuv420p"]
            } else {
                v += [
                    "-c:v", "libx264", "-preset", "medium", "-crf", "\(Int((30 - q * 12).rounded()))", "-pix_fmt",
                    "yuv420p",
                ]
            }
        case "mp4-hevc":
            if s.hardware {
                v += ["-c:v", "hevc_videotoolbox", "-q:v", "\(Int(40 + q * 45))"]
            } else {
                v += [
                    "-c:v", "libx265", "-preset", "medium", "-crf", "\(Int((32 - q * 12).rounded()))", "-x265-params",
                    "log-level=error",
                ]
            }
            v += ["-tag:v", "hvc1"]
        case "mov-prores":
            v +=
                s.hardware
                ? ["-c:v", "prores_videotoolbox", "-profile:v", "2"]
                : ["-c:v", "prores_ks", "-profile:v", "2"]
            audio = ["-c:a", "pcm_s16le"]
        case "webm":
            v += [
                "-c:v", "libvpx-vp9", "-crf", "\(Int((42 - q * 17).rounded()))", "-b:v", "0",
                "-row-mt", "1", "-deadline", "good", "-cpu-used", "4",
            ]
            audio = ["-c:a", "libopus", "-b:a", "128k"]
        case "mp4-av1":
            v += ["-c:v", "libsvtav1", "-crf", "\(Int((46 - q * 20).rounded()))", "-preset", "8"]
        default: break
        }
        if !filters.isEmpty { v += ["-vf", filters.joined(separator: ",")] }

        if s.keepAudio && p.hasAudio {
            v += ["-map", "0:a:0"] + audio
            if audio[1] == "aac_at", p.sampleRate > 48000 { v += ["-ar", "48000"] }
        } else {
            v += ["-an"]
        }
        if ["mp4", "mov"].contains(t.ext) { v += ["-movflags", "+faststart"] }
        return v
    }
}
