import Foundation

struct AudioInfo {
    let duration: TimeInterval
    let sampleRate: Int
    let channels: Int
    let isSignedPCM16LE: Bool

    /// whisper-cli accepts 16-bit WAV only; anything else needs a conversion pass.
    var isWhisperReady: Bool { sampleRate == 16_000 && channels == 1 && isSignedPCM16LE }
}

enum AudioError: LocalizedError {
    case unreadable(URL, String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url, let detail):
            return "Could not read audio from \(url.lastPathComponent).\n\(detail)"
        case .conversionFailed(let detail):
            return "Audio conversion failed.\n\(detail)"
        }
    }
}

/// Audio handling via Apple's own CoreAudio command line tools. No ffmpeg, no
/// third-party codec libraries — the only things that ever touch the audio are
/// /usr/bin/afinfo, /usr/bin/afconvert and whisper.cpp.
enum AudioConverter {
    static let afinfo = URL(fileURLWithPath: "/usr/bin/afinfo")
    static let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")

    /// Whisper's required input format: 16 kHz, mono, signed 16-bit little-endian PCM.
    static let targetSampleRate = 16_000

    static func inspect(_ url: URL) throws -> AudioInfo {
        var out = "", err = ""
        let (exe, args) = Sandbox.wrap(executable: afinfo, arguments: [url.path], writableDirs: [])
        let status = try ProcessRunner.run(
            executable: exe, arguments: args,
            onStdoutLine: { out += $0 + "\n" },
            onStderrLine: { err += $0 + "\n" })

        guard status == 0 else {
            throw AudioError.unreadable(url, err.isEmpty ? out : err)
        }

        func firstMatch(_ pattern: String, in s: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }

        // afinfo prints e.g.:
        //   Data format:     1 ch,  16000 Hz, 'lpcm' ... 16-bit little-endian signed integer
        //   estimated duration: 11.000000 sec
        let duration = Double(firstMatch(#"estimated duration:\s*([0-9.]+)"#, in: out) ?? "") ?? 0
        let channels = Int(firstMatch(#"([0-9]+)\s+ch\b"#, in: out) ?? "") ?? 0
        let rate = Int(Double(firstMatch(#"([0-9.]+)\s+Hz"#, in: out) ?? "") ?? 0)
        // afinfo describes 16-bit PCM two different ways depending on container:
        //   "1 ch,  16000 Hz, Int16"                                    (plain WAV)
        //   "1 ch,  16000 Hz, 'lpcm' (...) 16-bit little-endian signed integer"
        // Big-endian variants print as BEI16 and must not be accepted.
        let isWAVE = out.contains("File type ID:") && out.contains("WAVE")
        let shortForm = out.contains("Int16") && !out.contains("BEI16")
        let longForm = out.contains("'lpcm'") && out.contains("16-bit")
            && out.contains("little-endian") && out.contains("signed integer")
        let pcm16 = isWAVE && (shortForm || longForm)

        guard duration > 0 || channels > 0 else {
            throw AudioError.unreadable(url, "afinfo reported no decodable audio track.\n\(out)")
        }
        return AudioInfo(duration: duration, sampleRate: rate, channels: channels,
                         isSignedPCM16LE: pcm16)
    }

    /// Converts to whisper's required format. The destination is chosen by the
    /// caller and always sits beside the source file.
    static func convert(_ source: URL, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        let (exe, args) = Sandbox.wrap(
            executable: afconvert,
            arguments: ["-f", "WAVE", "-d", "LEI16@\(targetSampleRate)", "-c", "1",
                        source.path, destination.path],
            writableDirs: [dir])

        var err = ""
        let status = try ProcessRunner.run(
            executable: exe, arguments: args,
            onStdoutLine: { err += $0 + "\n" },
            onStderrLine: { err += $0 + "\n" })

        guard status == 0, FileManager.default.fileExists(atPath: destination.path) else {
            throw AudioError.conversionFailed(err)
        }
    }
}
