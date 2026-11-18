import XCTest
@testable import Convert

/// The ffmpeg arguments for audio targets. These check the flags that decide the result
/// (codec, sample format, bit depth, rate, channels), not the whole argument list.
final class AudioArgsTests: XCTestCase {
    private let lossless = ["wav", "aiff", "flac", "alac", "wv"]
    private let cdSource = Probe(sampleRate: 44100, hires: false, hasAudio: true, ok: true)
    private let hiResSource = Probe(sampleRate: 96000, hires: true, hasAudio: true, ok: true)

    private func args(_ id: String, source: Probe, bitDepth: Int = 0, sampleRate: Int = 0,
                      channels: Int = 0, bitrate: Int? = nil) throws -> [String] {
        let target = try XCTUnwrap(Targets.byID(id), "no target \(id)")
        var s = ConvSettings()
        s.bitDepth = bitDepth
        s.sampleRate = sampleRate
        s.channels = channels
        s.audioBitrate = bitrate ?? target.defaultBitrate
        return FF.audioArgs(target, s, source)
    }

    /// The value following `flag`, or nil if the flag isn't there.
    private func value(_ flag: String, _ a: [String]) -> String? {
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    private func count(_ flag: String, _ a: [String]) -> Int { a.filter { $0 == flag }.count }

    /// What a lossless target must ask ffmpeg for to write `bits`-bit audio.
    private func assertDepth(_ id: String, _ a: [String], bits: Int, file: StaticString = #filePath, line: UInt = #line) {
        let deep = bits == 24
        switch id {
        case "wav":
            XCTAssertEqual(value("-c:a", a), deep ? "pcm_s24le" : "pcm_s16le", id, file: file, line: line)
        case "aiff":
            XCTAssertEqual(value("-c:a", a), deep ? "pcm_s24be" : "pcm_s16be", id, file: file, line: line)
        case "flac":
            XCTAssertEqual(value("-sample_fmt", a), deep ? "s32" : "s16", id, file: file, line: line)
        case "alac", "wv":
            XCTAssertEqual(value("-sample_fmt", a), deep ? "s32p" : "s16p", id, file: file, line: line)
        default:
            XCTFail("not a lossless target: \(id)", file: file, line: line)
        }
        // 24-bit audio stored in 32-bit samples needs its real depth spelled out (WavPack writes 32-bit otherwise).
        if ["flac", "alac", "wv"].contains(id) {
            XCTAssertEqual(value("-bits_per_raw_sample", a), deep ? "24" : nil, id, file: file, line: line)
        }
    }

    // MARK: Source detection

    func testHiResDetection() {
        // (sample_fmt, bits_per_sample, bits_per_raw_sample) as ffprobe reports them
        let deep: [(String, Int, Int)] = [
            ("s32", 24, 24),    // 24-bit WAV
            ("s32", 32, 32),    // 32-bit integer WAV
            ("flt", 32, 0),     // 32-bit float WAV
            ("dbl", 64, 0),     // 64-bit float WAV
            ("s32", 0, 24),     // 24-bit FLAC
            ("s32p", 0, 24),    // 24-bit ALAC
        ]
        let shallow: [(String, Int, Int)] = [
            ("s16", 16, 0),     // 16-bit WAV
            ("s16", 0, 16),     // 16-bit FLAC
            ("fltp", 0, 0),     // MP3, AAC, Opus: decoded to float, but not high resolution
            ("flt", 0, 0),
            ("", 0, 0),         // nothing known
        ]
        for (fmt, bps, raw) in deep {
            XCTAssertTrue(FF.isHiRes(sampleFormat: fmt, bitsPerSample: bps, bitsPerRawSample: raw), "\(fmt) \(bps) \(raw)")
        }
        for (fmt, bps, raw) in shallow {
            XCTAssertFalse(FF.isHiRes(sampleFormat: fmt, bitsPerSample: bps, bitsPerRawSample: raw), "\(fmt) \(bps) \(raw)")
        }
    }

    // MARK: Bit depth

    func testMatchSourceKeepsSixteenBit() throws {
        for id in lossless { assertDepth(id, try args(id, source: cdSource), bits: 16) }
    }

    func testMatchSourceKeepsHiResAtTwentyFourBit() throws {
        for id in lossless { assertDepth(id, try args(id, source: hiResSource), bits: 24) }
    }

    func testForcedDepthOverridesSource() throws {
        for id in lossless {
            assertDepth(id, try args(id, source: hiResSource, bitDepth: 16), bits: 16)
            assertDepth(id, try args(id, source: cdSource, bitDepth: 24), bits: 24)
        }
    }

    func testLossyTargetsNeverSetBitDepth() throws {
        for id in ["mp3", "m4a", "he-aac", "opus", "ogg", "wma", "ac3", "mp2"] {
            let a = try args(id, source: hiResSource, bitDepth: 24)
            XCTAssertNil(value("-bits_per_raw_sample", a), id)
            XCTAssertNil(value("-sample_fmt", a), id)
        }
    }

    // MARK: Sample rate

    func testLossyTargetsCapHiResSourcesAt48k() throws {
        for id in ["mp3", "m4a", "he-aac", "ogg", "wma", "ac3", "mp2"] {
            XCTAssertEqual(value("-ar", try args(id, source: hiResSource)), "48000", id)
            XCTAssertNil(value("-ar", try args(id, source: cdSource)), id)
        }
        // Opus resamples internally and has no sample-rate setting.
        XCTAssertNil(value("-ar", try args("opus", source: hiResSource)))
    }

    func testLosslessTargetsKeepTheSourceRate() throws {
        for id in lossless { XCTAssertNil(value("-ar", try args(id, source: hiResSource)), id) }
    }

    func testChosenSampleRateWins() throws {
        let flac = try args("flac", source: hiResSource, sampleRate: 48000)
        XCTAssertEqual(value("-ar", flac), "48000")
        let mp3 = try args("mp3", source: hiResSource, sampleRate: 44100)
        XCTAssertEqual(value("-ar", mp3), "44100")
        XCTAssertEqual(count("-ar", mp3), 1)
    }

    func testUnofferedSampleRateIsIgnored() throws {
        // 96 kHz isn't offered for lossy targets: fall back to the 48 kHz cap.
        XCTAssertEqual(value("-ar", try args("mp3", source: hiResSource, sampleRate: 96000)), "48000")
        XCTAssertNil(value("-ar", try args("opus", source: cdSource, sampleRate: 48000)))
    }

    // MARK: Channels and codecs

    func testChannels() throws {
        XCTAssertNil(value("-ac", try args("mp3", source: cdSource)))
        XCTAssertEqual(value("-ac", try args("mp3", source: cdSource, channels: 1)), "1")
        XCTAssertEqual(value("-ac", try args("flac", source: cdSource, channels: 2)), "2")
        // The Vorbis encoder is always stereo; there's no channel setting for it.
        let ogg = try args("ogg", source: cdSource, channels: 1)
        XCTAssertEqual(value("-ac", ogg), "2")
        XCTAssertEqual(count("-ac", ogg), 1)
    }

    func testCodecs() throws {
        let codecs = ["mp3": "libmp3lame", "m4a": "aac_at", "he-aac": "aac_at", "opus": "libopus", "ogg": "vorbis",
                      "wma": "wmav2", "ac3": "ac3", "mp2": "mp2", "flac": "flac", "alac": "alac", "wv": "wavpack"]
        for (id, codec) in codecs { XCTAssertEqual(value("-c:a", try args(id, source: cdSource)), codec, id) }
        XCTAssertEqual(value("-profile:a", try args("he-aac", source: cdSource)), "4")
    }

    func testMP3BitrateModes() throws {
        let vbr = try args("mp3", source: cdSource, bitrate: 0)
        XCTAssertEqual(value("-q:a", vbr), "0")
        XCTAssertNil(value("-b:a", vbr))
        let cbr = try args("mp3", source: cdSource, bitrate: 320)
        XCTAssertEqual(value("-b:a", cbr), "320k")
        XCTAssertNil(value("-q:a", cbr))
    }
}
