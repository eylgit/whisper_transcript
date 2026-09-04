import Foundation
import Combine
import UniformTypeIdentifiers

enum JobStatus: Equatable {
    case queued
    case reading
    case converting
    case transcribing(Double)
    case writing
    case done(URL)
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .done, .failed, .cancelled: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .queued: return "Waiting"
        case .reading: return "Reading audio"
        case .converting: return "Converting to 16 kHz"
        case .transcribing(let p): return "Transcribing \(Int(p * 100))%"
        case .writing: return "Writing Markdown"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct Job: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var status: JobStatus = .queued

    var progress: Double? {
        switch status {
        case .queued: return 0
        case .reading, .converting: return 0.02
        case .transcribing(let p): return max(p, 0.02)
        case .writing: return 0.99
        case .done: return 1
        case .failed, .cancelled: return nil
        }
    }
}

/// Settings live in memory for the session only. Persisting them would mean
/// writing a preferences file, and this app deliberately creates no files
/// outside the folder holding your audio.
struct Settings {
    var language = "auto"
    var translateToEnglish = false
    var keepIntermediateWAV = false
    var carryContext = true

    static let languages: [(code: String, name: String)] = [
        ("auto", "Detect automatically"), ("en", "English"), ("zh", "Chinese"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("ru", "Russian"), ("ja", "Japanese"),
        ("ko", "Korean"), ("ar", "Arabic"), ("hi", "Hindi"), ("nl", "Dutch"),
        ("pl", "Polish"), ("tr", "Turkish"), ("vi", "Vietnamese"),
    ]
}

final class AppModel: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var isRunning = false
    @Published private(set) var startupError: String?
    @Published var settings = Settings()

    private var layout: Layout?
    private let worker = DispatchQueue(label: "app.transcribe.worker", qos: .userInitiated)
    private var currentProcess: RunningProcess?
    private var cancelRequested = false
    /// Work queue owned by the worker thread. `jobs` exists purely to drive the
    /// UI; the worker never reads it, so it never has to block on the main queue.
    private var pending: [Job] = []
    private let lock = NSLock()

    var modelDescription: String {
        guard let layout else { return "no model found" }
        return layout.modelName
    }

    init() {
        do {
            layout = try Layout.discover()
        } catch {
            startupError = error.localizedDescription
        }
        if !Sandbox.isAvailable {
            startupError = "/usr/bin/sandbox-exec is unavailable, so the offline guarantee cannot be enforced."
        }
    }

    // MARK: - Input

    static func isSupportedAudio(_ url: URL) -> Bool {
        // Skip our own intermediate files so re-dropping a folder is harmless.
        if url.lastPathComponent.hasSuffix(Transcriber.intermediateSuffix) { return false }
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .audio) || type.conforms(to: .movie) {
            return true
        }
        let fallback = ["wav", "m4a", "mp3", "aac", "aif", "aiff", "caf", "flac", "mp4", "mov"]
        return fallback.contains(url.pathExtension.lowercased())
    }

    func enqueue(_ urls: [URL]) {
        let accepted = urls.filter { Self.isSupportedAudio($0) }
        guard !accepted.isEmpty else { return }
        let newJobs = accepted.map { Job(url: $0) }
        jobs.append(contentsOf: newJobs)
        lock.lock(); pending.append(contentsOf: newJobs); lock.unlock()
        startIfIdle()
    }

    func clearFinished() {
        jobs.removeAll { $0.status.isFinished }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let p = currentProcess
        let dropped = pending
        pending.removeAll()
        lock.unlock()
        p?.cancel()
        for job in dropped { update(job.id, .cancelled) }
    }

    // MARK: - Work loop

    private func update(_ id: UUID, _ status: JobStatus) {
        DispatchQueue.main.async {
            guard let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            self.jobs[i].status = status
        }
    }

    private func startIfIdle() {
        guard !isRunning, let layout else { return }
        isRunning = true
        lock.lock(); cancelRequested = false; lock.unlock()

        worker.async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let job = self.pending.isEmpty ? nil : self.pending.removeFirst()
                let stop = self.cancelRequested
                self.lock.unlock()

                guard let job else { break }
                if stop { self.update(job.id, .cancelled); continue }

                var request = TranscriptionRequest(source: job.url)
                request.options.language = self.settings.language
                request.options.translateToEnglish = self.settings.translateToEnglish
                request.options.carryContext = self.settings.carryContext
                request.keepIntermediateWAV = self.settings.keepIntermediateWAV

                do {
                    let out = try Transcriber.run(
                        request, layout: layout,
                        onStage: { stage in
                            switch stage {
                            case .inspecting: self.update(job.id, .reading)
                            case .converting: self.update(job.id, .converting)
                            case .transcribing(let p): self.update(job.id, .transcribing(p))
                            case .writing: self.update(job.id, .writing)
                            }
                        },
                        registerHandle: { handle in
                            self.lock.lock(); self.currentProcess = handle; self.lock.unlock()
                        })
                    self.update(job.id, .done(out))
                } catch {
                    self.lock.lock(); let wasCancelled = self.cancelRequested; self.lock.unlock()
                    self.update(job.id, wasCancelled ? .cancelled : .failed(error.localizedDescription))
                }
                self.lock.lock(); self.currentProcess = nil; self.lock.unlock()
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}
