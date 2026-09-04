import XCTest
@testable import TranscribeCore

/// The sandbox profile is the offline guarantee. A silent mistake here would
/// not break anything visibly — it would just quietly stop protecting anyone.
final class SandboxTests: XCTestCase {

    func testProfileDeniesNetworkAndWrites() {
        let p = Sandbox.profile(writableDirs: [], allowSystemCaches: false)
        XCTAssertTrue(p.contains("(deny network*)"))
        XCTAssertTrue(p.contains("(deny file-write*)"))
        XCTAssertTrue(p.contains("(allow default)"), "Metal needs its IOKit access")
    }

    func testDenyRulesPrecedeAllowRules() {
        // sandbox profiles are last-match-wins, so an allow that appeared before
        // the deny would be silently overridden and the directory unwritable.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let p = Sandbox.profile(writableDirs: [dir], allowSystemCaches: false)
        let deny = p.range(of: "(deny file-write*)")
        let allow = p.range(of: "(allow file-write*")
        XCTAssertNotNil(deny); XCTAssertNotNil(allow)
        XCTAssertTrue(deny!.upperBound < allow!.lowerBound,
                      "an allow rule before the blanket deny would be overridden")
    }

    func testTheAudioDirectoryBecomesWritable() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let resolved = Sandbox.realPath(dir.path)!
        let p = Sandbox.profile(writableDirs: [dir], allowSystemCaches: false)
        XCTAssertTrue(p.contains("(allow file-write* (subpath \"\(resolved)\"))"))
    }

    func testRootIsNeverGrantedAsAWritableRoot() {
        // Granting "/" or "/private" would void the entire restriction while
        // still looking like a working profile.
        for dangerous in ["/", "/private"] {
            let p = Sandbox.profile(writableDirs: [URL(fileURLWithPath: dangerous)],
                                    allowSystemCaches: false)
            XCTAssertFalse(p.contains("(allow file-write* (subpath \"/\"))"),
                           "granted / from \(dangerous)")
            XCTAssertFalse(p.contains("(allow file-write* (subpath \"/private\"))"),
                           "granted /private from \(dangerous)")
        }
    }

    func testPathsAreQuotedSoASpaceCannotSplitARule() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("a folder with spaces")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = Sandbox.profile(writableDirs: [dir], allowSystemCaches: false)
        XCTAssertTrue(p.contains("a folder with spaces\"))"),
                      "the path must sit inside quotes")
    }

    func testDuplicateDirectoriesProduceOneRule() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let p = Sandbox.profile(writableDirs: [dir, dir, dir], allowSystemCaches: false)
        XCTAssertEqual(p.components(separatedBy: "(allow file-write*").count - 1, 1)
    }

    /// The profile is only worth anything if the kernel agrees. This runs the
    /// real thing rather than inspecting the text.
    func testTheKernelActuallyRefusesAWriteOutsideTheAllowedDirectory() throws {
        guard Sandbox.isAvailable else { throw XCTSkip("sandbox-exec unavailable") }
        let allowed = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandbox-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: allowed) }

        let forbidden = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandbox-test-outside-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: forbidden) }

        func touch(_ target: URL) throws -> Int32 {
            let (exe, args) = Sandbox.wrap(
                executable: URL(fileURLWithPath: "/usr/bin/touch"),
                arguments: [target.path], writableDirs: [allowed])
            return try ProcessRunner.run(executable: exe, arguments: args)
        }

        XCTAssertEqual(try touch(allowed.appendingPathComponent("inside.txt")), 0,
                       "a write beside the audio must still work")
        XCTAssertNotEqual(try touch(forbidden), 0,
                          "a write outside the audio's folder must be refused")
        XCTAssertFalse(FileManager.default.fileExists(atPath: forbidden.path))
    }
}
