import XCTest

/// Rules about the source itself, read from disk as text with comments removed.
/// The networking rule checks what the code says, not what a process can do:
/// that is scripts/verify-sandbox.sh, and this does not replace it.
final class ArchitectureTests: XCTestCase {

    private struct Rule {
        let name: String
        /// Only files whose path under Sources/ starts with this are checked.
        let scope: String
        let pattern: NSRegularExpression
        /// Printed with every failure, so a failure explains itself.
        let reason: String

        func violations(in code: String) -> [String] {
            let ns = code as NSString
            return pattern.matches(in: code, range: NSRange(location: 0, length: ns.length)).map {
                let line = ns.substring(to: $0.range.location).components(separatedBy: "\n").count
                let text = ns.substring(with: $0.range).trimmingCharacters(in: .whitespaces)
                return "line \(line): `\(text)`"
            }
        }
    }

    private static let coreImportsOnlyFoundation = Rule(
        name: "Core imports only Foundation",
        scope: "Core/",
        // Any import, attributed or of a single symbol, whose module is not Foundation.
        pattern: try! NSRegularExpression(
            pattern: #"^[ \t]*(?:@\w+[ \t]+)*import[ \t]+(?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?(?!Foundation\b)\w+"#,
            options: .anchorsMatchLines),
        reason: "Core is the engine. The app and the CLI depend on it; it depends on nothing that needs a screen.")

    private static let noNetworking = Rule(
        name: "no networking code",
        scope: "",
        pattern: try! NSRegularExpression(pattern: #"URLSession|NWConnection|CFNetwork|\bimport[ \t]+Network"#),
        reason: "CLAUDE.md rule 3: the app contains no networking code. This checks the source. "
            + "The kernel-level check is scripts/verify-sandbox.sh; this test does not replace it.")

    func testCoreImportsOnlyFoundation() throws {
        try check(Self.coreImportsOnlyFoundation)
    }

    func testNoNetworkingCodeAnywhereInSources() throws {
        try check(Self.noNetworking)
    }

    func testTheRulesSeeCodeButNotComments() {
        // A rule that matched nothing would pass forever, so check each one bites.
        XCTAssertFalse(Self.coreImportsOnlyFoundation.violations(in: "import AppKit\n").isEmpty)
        XCTAssertFalse(Self.coreImportsOnlyFoundation.violations(in: "@preconcurrency import SwiftUI\n").isEmpty)
        XCTAssertTrue(Self.coreImportsOnlyFoundation.violations(in: "import Foundation\n").isEmpty)
        XCTAssertFalse(Self.noNetworking.violations(in: "let s = URLSession.shared").isEmpty)
        XCTAssertFalse(Self.noNetworking.violations(in: "import Network\n").isEmpty)

        // A raw string ending in a backslash would swallow the rest of the file
        // if the backslash were read as an escape.
        let stripped = Self.strippingComments("""
            // URLSession, named in prose
            /* outer /* nested */ NWConnection */
            let a = "x // y"; let b = #"a\\"#  // CFNetwork
            let c = 1
            """)
        XCTAssertTrue(Self.noNetworking.violations(in: stripped).isEmpty, stripped)
        XCTAssertTrue(stripped.contains(#""x // y""#), "a // inside a string is not a comment")
        XCTAssertTrue(stripped.contains("let c = 1"), "code after a raw string survives")
        XCTAssertEqual(stripped.components(separatedBy: "\n").count, 4, "line numbers survive")
    }

    // MARK: - Helpers

    /// One assertion per file, naming the file, what was found and why it matters.
    private func check(_ rule: Rule, file: StaticString = #filePath, line: UInt = #line) throws {
        let files = try Self.sourceFiles().filter { $0.path.hasPrefix(rule.scope) }
        XCTAssertFalse(files.isEmpty, "no files found under Sources/\(rule.scope); the test is reading the wrong folder",
                       file: file, line: line)
        for source in files {
            let found = rule.violations(in: source.code)
            XCTAssertTrue(found.isEmpty, """
                Sources/\(source.path) breaks "\(rule.name)": \(found.joined(separator: ", ")).
                Why: \(rule.reason)
                """, file: file, line: line)
        }
    }

    private struct SourceFile { let path: String; let code: String }

    /// Every .swift file under Sources/, comments removed. Found from this file's
    /// location, so it does not matter where the tests are run from.
    private static func sourceFiles() throws -> [SourceFile] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TranscribeCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        return try paths.filter { $0.hasSuffix(".swift") }.sorted().map {
            let text = try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)
            return SourceFile(path: $0, code: strippingComments(text))
        }
    }

    /// Removes `//` and nested `/* */` comments, keeping every newline so line
    /// numbers still match. String literals, including raw (`#"…"#`) and
    /// multi-line ones, are copied untouched, so `//` inside a string stays.
    static func strippingComments(_ source: String) -> String {
        let c = Array(source)
        func at(_ k: Int) -> Character? { k < c.count ? c[k] : nil }
        func starts(_ s: String, _ k: Int) -> Bool {
            s.enumerated().allSatisfy { at(k + $0.offset) == $0.element }
        }
        var out = ""
        var i = 0
        while i < c.count {
            if starts("//", i) {
                while i < c.count && c[i] != "\n" { i += 1 }
                continue
            }
            if starts("/*", i) {
                var depth = 0
                repeat {
                    if starts("/*", i) { depth += 1; i += 2 }
                    else if starts("*/", i) { depth -= 1; i += 2 }
                    else { if c[i] == "\n" { out.append("\n") }; i += 1 }
                } while depth > 0 && i < c.count
                continue
            }
            var j = i
            while at(j) == "#" { j += 1 }
            if at(j) == "\"" {
                let hashes = j - i
                let quotes = starts("\"\"\"", j) ? 3 : 1
                let close = String(repeating: "\"", count: quotes) + String(repeating: "#", count: hashes)
                j += quotes
                while j < c.count && !starts(close, j) {
                    // Raw strings have no backslash escapes.
                    j += (c[j] == "\\" && hashes == 0) ? 2 : 1
                }
                j = min(j + close.count, c.count)
                out.append(contentsOf: c[i..<j])
                i = j
                continue
            }
            out.append(c[i])
            i += 1
        }
        return out
    }
}
