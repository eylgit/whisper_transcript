import Foundation

/// Wraps a child process in an OS-enforced sandbox.
///
/// The profile is a *deny-list* on purpose. An allow-list would cut off the IOKit
/// accelerator access Metal needs, silently dropping us back to far slower CPU
/// inference. So we start from `(allow default)` and remove exactly two things:
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

    /// Fully resolves a path. The sandbox matches on resolved paths, so a rule
    /// naming /var/folders/... never fires because the kernel sees
    /// /private/var/folders/... . URL.resolvingSymlinksInPath does not resolve
    /// the /var firmlink, so use realpath(3) directly.
    static func realPath(_ path: String) -> String? {
        guard let raw = realpath(path, nil) else { return nil }
        defer { free(raw) }
        return String(cString: raw)
    }

    /// A write rule is only safe if it names a genuinely nested directory.
    /// Granting "/" or "/private" would quietly void the whole restriction.
    private static func isSafeWritableRoot(_ resolved: String) -> Bool {
        let parts = resolved.split(separator: "/")
        return resolved.hasPrefix("/") && parts.count >= 2
    }

    /// The single directory the OS needs for its compiled-GPU-shader cache.
    ///
    /// Measured: with this allowed, a run takes ~3s; with nothing writable,
    /// Metal recompiles all 20 shader libraries every time and the same run
    /// takes ~19s. Testing showed ~/Library/Caches and the darwin temp
    /// directory are *not* needed, so neither is granted.
    ///
    /// This directory holds compiled shader code, never audio or transcripts.
    static func systemCacheDirs() -> [URL] {
        var buf = [CChar](repeating: 0, count: 1024)
        let n = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count)
        guard n > 0, n <= buf.count else { return [] }
        let path = String(cString: buf)
        return path.isEmpty ? [] : [URL(fileURLWithPath: path)]
    }

    static func profile(writableDirs: [URL], allowSystemCaches: Bool = true) -> String {
        var writable = writableDirs
        if allowSystemCaches { writable += systemCacheDirs() }

        var lines = [
            "(version 1)",
            ";; Permissive base so Metal keeps its IOKit GPU access.",
            "(allow default)",
            ";; The offline guarantee, enforced by the kernel rather than by convention.",
            "(deny network*)",
            ";; Nothing may be written anywhere...",
            "(deny file-write*)",
            ";; ...except beside the user's own audio file (and the GPU shader cache).",
        ]
        var seen = Set<String>()
        for dir in writable {
            guard let p = realPath(dir.path) ?? realPath(dir.deletingLastPathComponent().path)
                    .map({ $0 + "/" + dir.lastPathComponent }) else { continue }
            guard isSafeWritableRoot(p), seen.insert(p).inserted else { continue }
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
