import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isTargeted = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.startupError {
                startupErrorView(error)
            } else {
                dropZone
                if !model.jobs.isEmpty { Divider(); jobList }
                Divider()
                settingsSection
                Divider()
                footer
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop audio files here")
                .font(.headline)
            Text("wav · m4a · mp3 · aac · aiff · caf · flac")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Files…") { chooseFiles() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(10)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.enqueue(urls) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK { model.enqueue(panel.urls) }
    }

    // MARK: - Jobs

    private var jobList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.jobs) { job in
                    JobRow(job: job)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Language", selection: $model.settings.language) {
                    ForEach(Settings.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(maxWidth: 300)

                Toggle("Translate into English", isOn: $model.settings.translateToEnglish)

                Toggle("Transcribe quiet stretches too", isOn: $model.settings.transcribeSilence)
                Text(model.settings.transcribeSilence
                     ? "On: quiet stretches are transcribed as well, so speech too soft to detect is not silently dropped. They are marked in the transcript, because quiet is where the model is most likely to invent text."
                     : "Off: quiet stretches are skipped. Faster and tidier, but anything spoken too softly to register will be lost. The gaps are still marked in the transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Keep the intermediate 16 kHz WAV", isOn: $model.settings.keepIntermediateWAV)
                Toggle("Carry text between the model's windows", isOn: $model.settings.carryContext)
                Text("On by default: it produces correct punctuation and consistent spelling. Long recordings are split at pauses anyway, which contains the repetition loops this used to risk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.leading, 4)
        } label: {
            Text("Options").font(.subheadline.weight(.medium))
        }
        .padding(12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline · no network · writes only beside your audio")
                    .font(.caption)
                Text("model \(model.modelDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning {
                Button("Cancel") { model.cancel() }
            } else if model.jobs.contains(where: { $0.status.isFinished }) {
                Button("Clear") { model.clearFinished() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func startupErrorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(.orange)
            Text("Transcribe cannot start").font(.headline)
            ScrollView { Text(error).font(.caption.monospaced()).textSelection(.enabled) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(job.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if case .failed(let message) = job.status {
                    Text(message).font(.caption2).foregroundStyle(.red).lineLimit(3)
                } else if case .done(let out) = job.status {
                    Text(doneDetail(out)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                if let p = job.progress, !job.status.isFinished {
                    ProgressView(value: p).controlSize(.small)
                }
            }
            Spacer()
            if case .done(let out) = job.status {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Duration and chunk shape sit alongside the moving status, so the size of
    /// the job is visible rather than only how far through it is.
    private var detail: String {
        var parts: [String] = []
        if let d = job.audioDuration { parts.append(formatDuration(d)) }
        parts.append(job.status.label)
        return parts.joined(separator: " · ")
    }

    private func doneDetail(_ out: URL) -> String {
        var parts: [String] = []
        if let d = job.audioDuration { parts.append(formatDuration(d)) }
        if let c = job.chunkCount, c > 1 { parts.append("\(c) chunks") }
        parts.append(out.lastPathComponent)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var icon: some View {
        switch job.status {
        case .done:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .queued:    Image(systemName: "clock").foregroundStyle(.secondary)
        case .analysing: Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundStyle(Color.accentColor)
        default:         Image(systemName: "waveform").foregroundStyle(Color.accentColor)
        }
    }
}
