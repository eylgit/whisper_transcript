import Foundation

struct ProcessError: LocalizedError {
    let executable: String
    let exitCode: Int32
    let stderrTail: String
    var errorDescription: String? {
        var msg = "\(executable) failed (exit \(exitCode))"
        if !stderrTail.isEmpty { msg += ":\n\(stderrTail)" }
        return msg
    }
}

/// Thread-safe accumulator that turns a byte stream into whole lines.
private final class LineBuffer {
    private var pending = Data()
    private let lock = NSLock()
    private let emit: (String) -> Void

    init(emit: @escaping (String) -> Void) { self.emit = emit }

    func feed(_ data: Data) {
        lock.lock()
        pending.append(data)
        // whisper-cli separates progress updates with \r as well as \n.
        var lines: [String] = []
        while let idx = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending[pending.startIndex..<idx]
            pending.removeSubrange(pending.startIndex...idx)
            if let s = String(data: Data(lineData), encoding: .utf8) { lines.append(s) }
        }
        lock.unlock()
        for l in lines { emit(l) }
    }

    /// Flush any trailing partial line once the stream closes.
    func finish() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()
        if !rest.isEmpty, let s = String(data: rest, encoding: .utf8), !s.isEmpty { emit(s) }
    }
}

/// Handle to a running child process so a GUI can cancel it.
public final class RunningProcess {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false

    init(_ p: Process) { process = p }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }

    var wasCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

enum ProcessRunner {
    /// Runs `executable`, streaming stdout/stderr back line-by-line as they arrive.
    /// Returns the exit status; throws only if the process could not be launched.
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil,
        registerHandle: ((RunningProcess) -> Void)? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Deliberately minimal environment: no DYLD_* injection, nothing inherited
        // that could redirect the child somewhere unexpected.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outBuf = LineBuffer { onStdoutLine?($0) }
        let errBuf = LineBuffer { onStderrLine?($0) }
        let group = DispatchGroup()

        for (pipe, buf) in [(outPipe, outBuf), (errPipe, errBuf)] {
            group.enter()
            var done = false
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    guard !done else { return }
                    done = true
                    handle.readabilityHandler = nil
                    buf.finish()
                    group.leave()
                } else {
                    buf.feed(data)
                }
            }
        }

        try process.run()
        registerHandle?(RunningProcess(process))
        // The child inherited the write ends; the parent must drop its own copies
        // or the readers never see EOF and we stall until the drain timeout.
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        process.waitUntilExit()
        // EOF is now reliable, so this returns immediately; the bound is only a
        // guard against a wedged reader.
        _ = group.wait(timeout: .now() + 5)
        return process.terminationStatus
    }
}
