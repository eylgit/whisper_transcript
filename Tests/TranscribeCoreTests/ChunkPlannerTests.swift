import XCTest
@testable import TranscribeCore

/// The planner is the whole defence against a runaway decoder, so what is
/// tested here is mostly one property: it must never lose audio.
final class ChunkPlannerTests: XCTestCase {

    private func assertCoversEverything(
        _ chunks: [Chunk], duration: TimeInterval,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(chunks.isEmpty, "a recording must always produce work", file: file, line: line)
        // Walk the chunks in start order; each must begin at or before the point
        // the previous one reached, or there is a hole in the coverage.
        var reached: TimeInterval = 0
        for chunk in chunks.sorted(by: { $0.start < $1.start }) {
            XCTAssertLessThanOrEqual(
                chunk.start, reached + 1e-9,
                "gap in coverage: nothing covers \(reached)s to \(chunk.start)s",
                file: file, line: line)
            reached = max(reached, chunk.end)
        }
        XCTAssertEqual(reached, duration, accuracy: 1e-6,
                       "coverage stops short of the end", file: file, line: line)
    }

    func testShortRecordingIsNotChunked() {
        let duration = Tuning.minimumDurationToChunkSeconds - 1
        let chunks = ChunkPlanner.plan(
            duration: duration,
            silences: [SilenceRegion(start: 10, end: 20)])
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .speech)
        assertCoversEverything(chunks, duration: duration)
    }

    func testNoSilencesMeansOnePass() {
        let chunks = ChunkPlanner.plan(duration: 600, silences: [])
        XCTAssertEqual(chunks.count, 1)
        assertCoversEverything(chunks, duration: 600)
    }

    func testSilenceBecomesItsOwnChunkBetweenTwoSpeechChunks() {
        let chunks = ChunkPlanner.plan(
            duration: 300, silences: [SilenceRegion(start: 100, end: 110)])
        XCTAssertEqual(chunks.map(\.kind), [.speech, .silence, .speech])
        // The speech chunks reach into the pause by the buffer, so no word sits
        // on a hard cut at a chunk edge.
        XCTAssertEqual(chunks[0].end, 100 + Tuning.silenceBufferSeconds, accuracy: 1e-9)
        XCTAssertEqual(chunks[1].start, 100, accuracy: 1e-9)
        XCTAssertEqual(chunks[1].end, 110, accuracy: 1e-9)
        XCTAssertEqual(chunks[2].start, 110 - Tuning.silenceBufferSeconds, accuracy: 1e-9)
        assertCoversEverything(chunks, duration: 300)
    }

    func testSilenceAtTheVeryStartDoesNotProduceAZeroWidthChunk() {
        let chunks = ChunkPlanner.plan(
            duration: 300, silences: [SilenceRegion(start: 0, end: 8)])
        XCTAssertFalse(chunks.contains { $0.duration <= 0 })
        XCTAssertEqual(chunks.first?.kind, .silence, "nothing precedes a pause at t=0")
        assertCoversEverything(chunks, duration: 300)
    }

    func testSilenceRunningToTheEndDoesNotProduceAZeroWidthChunk() {
        let chunks = ChunkPlanner.plan(
            duration: 300, silences: [SilenceRegion(start: 290, end: 300)])
        XCTAssertFalse(chunks.contains { $0.duration <= 0 })
        assertCoversEverything(chunks, duration: 300)
    }

    func testUnsortedSilencesAreHandled() {
        let ordered = ChunkPlanner.plan(duration: 600, silences: [
            SilenceRegion(start: 100, end: 110), SilenceRegion(start: 300, end: 310),
        ])
        let shuffled = ChunkPlanner.plan(duration: 600, silences: [
            SilenceRegion(start: 300, end: 310), SilenceRegion(start: 100, end: 110),
        ])
        XCTAssertEqual(ordered.map(\.start), shuffled.map(\.start))
        assertCoversEverything(shuffled, duration: 600)
    }

    func testPauseSwallowedByThePreviousBufferIsSkippedNotDuplicated() {
        // Two pauses closer together than the buffer: the second falls inside
        // the first one's trailing buffer and must not reopen a chunk backwards.
        let chunks = ChunkPlanner.plan(duration: 600, silences: [
            SilenceRegion(start: 100, end: 110),
            SilenceRegion(start: 110.5, end: 114),
        ])
        assertCoversEverything(chunks, duration: 600)
        XCTAssertTrue(chunks.allSatisfy { $0.end > $0.start }, "no reversed chunk")
    }

    /// The invariant that actually matters, over many shapes of recording:
    /// losing speech is the worst thing this tool could do, so coverage must
    /// hold no matter where the pauses fall.
    func testCoverageHoldsAcrossManyRandomRecordings() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let duration = Double.random(in: 1...3600, using: &rng)
            let count = Int.random(in: 0...12, using: &rng)
            var silences: [SilenceRegion] = []
            for _ in 0..<count {
                let start = Double.random(in: 0...duration, using: &rng)
                let end = min(duration, start + Double.random(in: 0.1...30, using: &rng))
                if end > start { silences.append(SilenceRegion(start: start, end: end)) }
            }
            assertCoversEverything(
                ChunkPlanner.plan(duration: duration, silences: silences),
                duration: duration)
        }
    }
}
