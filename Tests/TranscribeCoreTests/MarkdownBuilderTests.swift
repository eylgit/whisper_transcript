import XCTest
@testable import TranscribeCore

final class MarkdownBuilderTests: XCTestCase {

    private func seg(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> Segment {
        Segment(start: start, end: end, text: text)
    }

    private func result(_ chunks: [TranscribedChunk]) -> TranscriptionResult {
        TranscriptionResult(chunks: chunks, detectedLanguage: "en", audioDuration: 300,
                            modelName: "ggml-large-v3", usedNeuralEngine: false,
                            processingTime: 42, chunkingSummary: nil)
    }

    // MARK: - Paragraphs

    func testAPauseOnlyBreaksAParagraphAtASentenceEnd() {
        // A long gap mid-sentence is a hesitation, not a new thought.
        let mid = MarkdownBuilder.paragraphs(from: [
            seg(0, 1, "I was going to say"), seg(5, 6, "something important."),
        ])
        XCTAssertEqual(mid.count, 1, "a gap mid-sentence must not split the paragraph")

        let end = MarkdownBuilder.paragraphs(from: [
            seg(0, 1, "That is the first point."), seg(5, 6, "Now the second."),
        ])
        XCTAssertEqual(end.count, 2, "a gap after a full stop should split")
    }

    func testAClosingQuoteStillCountsAsASentenceEnd() {
        let paras = MarkdownBuilder.paragraphs(from: [
            seg(0, 1, "\"We are done here.\""), seg(5, 6, "Then everyone left."),
        ])
        XCTAssertEqual(paras.count, 2)
    }

    func testAnEndlessSpeakerIsStillBrokenIntoBlocks() {
        // No pauses and no sentence ends: the hard ceiling has to act anyway.
        let segments = (0..<400).map { seg(Double($0) * 0.1, Double($0) * 0.1 + 0.1, "and then") }
        let paras = MarkdownBuilder.paragraphs(from: segments)
        XCTAssertGreaterThan(paras.count, 1, "a monologue must not become one huge block")
        XCTAssertTrue(paras.allSatisfy { $0.count <= MarkdownBuilder.hardParagraphLength + 32 })
    }

    func testWordsAreSpacedButCJKIsNot() {
        let english = MarkdownBuilder.paragraphs(from: [seg(0, 1, "Hello"), seg(1, 2, "there.")])
        XCTAssertEqual(english.first, "Hello there.")

        let chinese = MarkdownBuilder.paragraphs(from: [seg(0, 1, "你好"), seg(1, 2, "世界")])
        XCTAssertEqual(chinese.first, "你好世界", "inserting spaces would corrupt CJK text")
    }

    // MARK: - The silence markers

    /// "We listened and heard nothing" and "we did not listen" are different
    /// claims, and the transcript must never blur them.
    func testSkippedAndTranscribedSilenceAreLabelledDifferently() {
        let gap = Chunk(kind: .silence, start: 100, end: 120)
        // A real transcript always has speech somewhere: Transcriber throws
        // rather than writing a file in which nothing was transcribed at all.
        let speech = TranscribedChunk(chunk: Chunk(kind: .speech, start: 0, end: 100),
                                      segments: [seg(1, 2, "Real speech.")],
                                      wasTranscribed: true)

        let skipped = MarkdownBuilder.document(
            for: result([speech,
                         TranscribedChunk(chunk: gap, segments: [], wasTranscribed: false)]),
            source: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(skipped.contains("skipped, so any speech here was not captured"))
        XCTAssertFalse(skipped.contains("as a precaution"))

        let listened = MarkdownBuilder.document(
            for: result([speech,
                         TranscribedChunk(chunk: gap,
                                          segments: [seg(101, 102, "Thank you.")],
                                          wasTranscribed: true)]),
            source: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(listened.contains("transcribed separately as a precaution"))
        XCTAssertFalse(listened.contains("was not captured"))
    }

    func testTextFoundInSilenceIsFencedOffAndMarkedUnreliable() {
        let doc = MarkdownBuilder.document(
            for: result([TranscribedChunk(chunk: Chunk(kind: .speech, start: 0, end: 100),
                                          segments: [seg(1, 2, "Real speech.")],
                                          wasTranscribed: true),
                         TranscribedChunk(
                            chunk: Chunk(kind: .silence, start: 100, end: 120),
                            segments: [seg(101, 102, "Thank you.")], wasTranscribed: true)]),
            source: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(doc.contains("> Thank you."), "invented text must stay inside the quote block")
        XCTAssertTrue(doc.contains("Treat anything below as unreliable"))
        XCTAssertTrue(doc.contains("⏹ **End of silence"))
        XCTAssertTrue(doc.contains("_(in silence)_"), "the segment list must mark it too")
    }

    func testSpeechIsNotFenced() {
        let doc = MarkdownBuilder.document(
            for: result([TranscribedChunk(
                chunk: Chunk(kind: .speech, start: 0, end: 100),
                segments: [seg(1, 2, "A real sentence.")], wasTranscribed: true)]),
            source: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(doc.contains("\nA real sentence."))
        XCTAssertFalse(doc.contains("⏸"))
    }

    func testFrontmatterQuotesAreEscaped() {
        let doc = MarkdownBuilder.document(
            for: result([TranscribedChunk(chunk: Chunk(kind: .speech, start: 0, end: 10),
                                          segments: [seg(0, 1, "hi")], wasTranscribed: true)]),
            source: URL(fileURLWithPath: "/tmp/a \"quoted\" name.m4a"))
        XCTAssertTrue(doc.contains(#"source: "a \"quoted\" name.m4a""#),
                      "an unescaped quote would produce invalid YAML frontmatter")
    }

    func testEmptyTranscriptSaysSoRatherThanProducingABlankFile() {
        let doc = MarkdownBuilder.document(
            for: result([]), source: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(doc.contains("No speech was detected"))
    }
}
