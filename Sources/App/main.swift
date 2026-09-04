import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Transcribe"
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.setFrameAutosaveName("")   // no preferences file
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Files dropped on the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        model.enqueue(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A transcription is still running."
        alert.informativeText = "Quitting now will stop it. The partly written intermediate WAV is left beside your audio file."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Working")
        if alert.runModal() == .alertFirstButtonReturn {
            model.cancel()
            return .terminateNow
        }
        return .terminateCancel
    }

    /// A minimal menu bar, mostly so the standard shortcuts (⌘Q, ⌘W) work.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Transcribe", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Transcribe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Transcribe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Transcribe"
        alert.informativeText = """
            Offline audio transcription using whisper.cpp and the \
            \(model.modelDescription) model.

            Audio never leaves this machine. Every step runs in a sandbox with no \
            network access that can only write into the folder holding your audio \
            file. The only files created are the Markdown transcript and, for \
            non-WAV input, a temporary 16 kHz WAV beside the original that is \
            removed once the transcript is written.
            """
        alert.runModal()
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
