import Foundation

/// Where the app's own pieces live. Two supported shapes:
///
///  1. Bundled  — Transcribe.app/Contents/Resources/{whisper-cli, *.dylib, ggml-large-v3.bin, ...}
///  2. Repo     — <repo>/vendor/whisper.cpp/build/bin/whisper-cli + <repo>/models/*
///
/// Nothing is ever looked up in a hidden application-support or cache directory.
struct Layout {
    let whisperCLI: URL
    let model: URL

    /// whisper.cpp derives the Core ML encoder path from the ggml model path,
    /// so it must sit beside the .bin under this exact name.
    var coreMLEncoder: URL {
        let base = model.deletingPathExtension().lastPathComponent
        return model.deletingLastPathComponent().appendingPathComponent("\(base)-encoder.mlmodelc")
    }

    var hasCoreMLEncoder: Bool {
        FileManager.default.fileExists(atPath: coreMLEncoder.path)
    }

    var modelName: String { model.deletingPathExtension().lastPathComponent }

    enum LayoutError: LocalizedError {
        case notFound(tried: [String])
        var errorDescription: String? {
            switch self {
            case .notFound(let tried):
                return """
                Could not locate whisper-cli and the model. Looked in:
                \(tried.map { "  - \($0)" }.joined(separator: "\n"))
                Run ./setup.sh, or set WHISPER_TRANSCRIPT_HOME.
                """
            }
        }
    }

    static func discover() throws -> Layout {
        var tried: [String] = []
        let fm = FileManager.default

        func candidate(cli: URL, modelDir: URL) -> Layout? {
            tried.append(cli.deletingLastPathComponent().path)
            guard fm.isExecutableFile(atPath: cli.path) else { return nil }
            // Accept whichever large model is present, preferring large-v3.
            let preferred = ["ggml-large-v3.bin", "ggml-large-v3-turbo.bin"]
            let names = (try? fm.contentsOfDirectory(atPath: modelDir.path)) ?? []
            let pick = preferred.first(where: { names.contains($0) })
                ?? names.first(where: { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") })
            guard let pick else { return nil }
            return Layout(cli: cli, model: modelDir.appendingPathComponent(pick))
        }

        // 0. Explicit override.
        if let home = ProcessInfo.processInfo.environment["WHISPER_TRANSCRIPT_HOME"] {
            let root = URL(fileURLWithPath: home)
            if let l = candidate(cli: root.appendingPathComponent("vendor/whisper.cpp/build/bin/whisper-cli"),
                                 modelDir: root.appendingPathComponent("models")) { return l }
            if let l = candidate(cli: root.appendingPathComponent("whisper-cli"), modelDir: root) { return l }
        }

        // 1. Bundled inside the .app.
        if let res = Bundle.main.resourceURL,
           let l = candidate(cli: res.appendingPathComponent("whisper-cli"), modelDir: res) { return l }

        // 2. Beside the executable (CLI copied next to its resources).
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().deletingLastPathComponent()
        if let l = candidate(cli: exeDir.appendingPathComponent("whisper-cli"), modelDir: exeDir) { return l }

        // 3. Development layout: walk up looking for the repo root.
        var dir = exeDir
        for _ in 0..<6 {
            if let l = candidate(cli: dir.appendingPathComponent("vendor/whisper.cpp/build/bin/whisper-cli"),
                                 modelDir: dir.appendingPathComponent("models")) { return l }
            dir = dir.deletingLastPathComponent()
        }

        throw LayoutError.notFound(tried: tried)
    }

    private init(cli: URL, model: URL) {
        self.whisperCLI = cli
        self.model = model
    }
}
