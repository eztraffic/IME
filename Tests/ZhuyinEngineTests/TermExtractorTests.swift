import XCTest
@testable import ZhuyinEngine

final class TermExtractorTests: XCTestCase {
    func testMinimumCostWordSegmentation() {
        let engine = ZhuyinEngine.production()
        let extractor = TermExtractor(lexicon: engine.lexicon, reverseLookup: engine.reverseLookup)

        let segmented = extractor.segmentClause("今天天氣很好")
        XCTAssertEqual(segmented, ["今天", "天氣", "很好"])
    }

    func testOOVNewWordDiscoveryViaPMIAndEntropy() {
        let engine = ZhuyinEngine.production()
        let extractor = TermExtractor(lexicon: engine.lexicon, reverseLookup: engine.reverseLookup)

        // "陳小明" appears across diverse left and right contexts
        let article = """
        今天陳小明去學校上課，老師誇獎陳小明很認真。
        昨天陳小明完成程式作業，大家覺得陳小明非常厲害。
        明天陳小明也要參加比賽。
        """
        let clauses = TextSanitizer.extractClauses(article)
        let stats = extractor.extract(from: clauses)

        let discoveredWords = stats.discoveredNewWords.map { $0.word }
        XCTAssertTrue(discoveredWords.contains("陳小明"), "Recurring OOV name '陳小明' with diverse boundaries must be discovered: got \(discoveredWords)")

        // Ensure functional stop-character boundaries like "的陳小明" or "陳小明很" are rejected
        XCTAssertFalse(discoveredWords.contains("的陳小明"))
        XCTAssertFalse(discoveredWords.contains("陳小明很"))

        // Verify bigram transitions involving the newly segmented term are also captured
        XCTAssertGreaterThanOrEqual(stats.bigramCounts["今天|陳小明"] ?? 0, 1)
    }
}
