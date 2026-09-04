import Foundation

let toolName = "transcribe"

func usage() -> String {
    """
    \(toolName) — offline audio → Markdown, powered by whisper.cpp

    USAGE
      \(toolName) [options] <audio-file>...

    OPTIONS
      -l, --language CODE   Spoken language, or "auto" to detect (default: auto)
      -tr, --translate      Translate the transcript into English
      -t, --threads N       Worker threads (default: 4, the performance cores)
      -c, --carry-context   Carry text between chunks (better proper-noun
                            consistency, but risks repetition loops)
      -k, --keep-wav        Keep the intermediate 16 kHz WAV beside the source
      -f, --force           Overwrite an existing .md instead of numbering a new one
      -q, --quiet           Only print the path of each file written
      -h, --help            Show this message

    PRIVACY
      Runs fully offline. Every child process is sandboxed with no network access
      and may write only into the folder holding the audio file. The only files
      created are <name>.md and, for non-WAV input, a temporary <name>.whisper-tmp.wav
      beside the original that is removed once the transcript is written.
    """
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

// MARK: - Argument parsing

var request = TranscriptionRequest(source: URL(fileURLWithPath: "/"))
var options = WhisperOptions()
var keepWAV = false, force = false, quiet = false
var inputs: [URL] = []

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    func value(_ flag: String) -> String {
        guard !args.isEmpty else { fail("\(flag) requires a value") }
        return args.removeFirst()
    }
    switch arg {
    case "-h", "--help":
        print(usage()); exit(0)
    case "-l", "--language":
        options.language = value(arg)
    case "-tr", "--translate":
        options.translateToEnglish = true
    case "-t", "--threads":
        guard let n = Int(value(arg)), n > 0 else { fail("--threads needs a positive integer") }
        options.threads = n
    case "-c", "--carry-context":
        options.carryContext = true
    case "-k", "--keep-wav":
        keepWAV = true
    case "-f", "--force":
        force = true
    case "-q", "--quiet":
        quiet = true
    case "--print-sandbox-profile":
        // Lets scripts/verify-sandbox.sh test the exact profile the app applies,
        // rather than a hand-copied approximation that could drift.
        let dir = args.isEmpty ? FileManager.default.currentDirectoryPath : args.removeFirst()
        print(Sandbox.profile(writableDirs: [URL(fileURLWithPath: dir)]))
        exit(0)
    default:
        if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n\(usage())") }
        inputs.append(URL(fileURLWithPath: arg))
    }
}

guard !inputs.isEmpty else {
    print(usage())
    exit(1)
}

// MARK: - Run

let layout: Layout
do {
    layout = try Layout.discover()
} catch {
    fail(error.localizedDescription)
}

if !Sandbox.isAvailable {
    fail("/usr/bin/sandbox-exec is unavailable, so the offline guarantee cannot be enforced.")
}

func note(_ s: String) {
    guard !quiet else { return }
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

note("model: \(layout.modelName)\(layout.hasCoreMLEncoder ? " (Core ML encoder present)" : "")")

var failures = 0
for input in inputs {
    guard FileManager.default.fileExists(atPath: input.path) else {
        FileHandle.standardError.write(Data("error: no such file: \(input.path)\n".utf8))
        failures += 1
        continue
    }

    var req = TranscriptionRequest(source: input)
    req.options = options
    req.keepIntermediateWAV = keepWAV
    req.overwrite = force

    var lastPercent = -1
    do {
        let out = try Transcriber.run(req, layout: layout, onStage: { stage in
            switch stage {
            case .inspecting:   note("\(input.lastPathComponent): reading audio")
            case .converting:   note("\(input.lastPathComponent): converting to 16 kHz mono WAV")
            case .transcribing(let p):
                let pct = Int(p * 100)
                if pct != lastPercent && !quiet {
                    lastPercent = pct
                    FileHandle.standardError.write(Data("\r\(input.lastPathComponent): transcribing \(pct)%   ".utf8))
                }
            case .writing:
                if !quiet { FileHandle.standardError.write(Data("\r".utf8)) }
                note("\(input.lastPathComponent): writing Markdown")
            }
        })
        print(out.path)
    } catch {
        if !quiet { FileHandle.standardError.write(Data("\r".utf8)) }
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
