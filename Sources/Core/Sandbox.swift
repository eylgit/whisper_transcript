import Foundation

/// Wraps a child process in an OS-enforced sandbox.
///
/// The profile is a *deny-list* on purpose. An allow-list would cut off the IOKit
/// accelerator access Metal needs and the mach lookup Core ML needs to reach the
/// Neural Engine, silently dropping us back to slow CPU inference. So we start from
/// `(allow default)` and remove exactly two things:
///
///   * all network access — the offline guarantee, enforced by the kernel
///   * all filesystem writes except the directory holding the user's audio
///
/// The profile is passed inline with `-p`, so no profile file is ever written to disk.
enum Sandbox {
    static let execURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: execURL.path)
    }

    /// Quote a path for the sandbox profile language.
    private static func quote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Directories the OS itself needs to write to for GPU/ANE shader and model
    /// caches. These hold compiled model/shader code, never audio or transcripts.
    static func systemCacheDirs() -> [URL] {
        var dirs: [URL] = []
        if let c = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            dirs.append(c)
        }
        // Per-user darwin temp/cache root (/private/var/folders/xx/...).
        dirs.append(URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent())
        return dirs
    }

    static func profile(writableDirs: [URL], allowSystemCaches: Bool = true) -> String {
        var writable = writableDirs
        if allowSystemCaches { writable += systemCacheDirs() }

        var lines = [
            "(version 1)",
            ";; Permissive base so Metal (IOKit) and Core ML (ANE mach service) keep working.",
            "(allow default)",
            ";; The offline guarantee, enforced by the kernel rather than by convention.",
            "(deny network*)",
            ";; Nothing may be written anywhere...",
            "(deny file-write*)",
            ";; ...except beside the user's own audio file (and OS shader/model caches).",
        ]
        var seen = Set<String>()
        for dir in writable {
            let p = dir.resolvingSymlinksInPath().path
            guard seen.insert(p).inserted else { continue }
            lines.append("(allow file-write* (subpath \(quote(p))))")
        }
        return lines.joined(separator: "\n")
    }

    /// Rewrites (executable, args) so the command runs under the sandbox.
    static func wrap(executable: URL, arguments: [String], writableDirs: [URL])
        -> (executable: URL, arguments: [String])
    {
        let p = profile(writableDirs: writableDirs)
        return (execURL, ["-p", p, executable.path] + arguments)
    }
}
