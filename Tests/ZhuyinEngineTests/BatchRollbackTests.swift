import XCTest
@testable import ZhuyinEngine

final class BatchRollbackTests: XCTestCase {
    var tempDirectoryURL: URL!
    var tempLexiconURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        tempLexiconURL = tempDirectoryURL.appendingPathComponent("user_lexicon_batch_test.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        super.tearDown()
    }

    func testArticleIngestionImprovesDecodingAndSupportsExactRollback() {
        let engine = ZhuyinEngine.production(userLexiconURL: tempLexiconURL)
        let syllables = Syllable.parseSequence("ㄔㄣˊ ㄒㄧㄠˇ ㄇㄧㄥˊ")

        // Before ingestion: decoding "ㄔㄣˊ ㄒㄧㄠˇ ㄇㄧㄥˊ" should NOT be "陳小明" (or "陳小明" is not in userWords)
        XCTAssertNil(engine.userLexicon.data.userWords["陳小明"])
        let beforeDecoded = engine.decode(syllables: syllables, topK: 1).bestText

        // Ingest an article where "陳小明" recurs in various contexts
        let article = """
        今天陳小明到學校上課，老師覺得陳小明表現很好。
        昨天陳小明寫了電腦程式，大家都請教陳小明。
        明天陳小明還要去台北參加活動。
        """
        let batch = engine.ingestArticle(text: article, sourceName: "測試文章.txt", mode: .autoImport)

        // Verify batch recorded in history and "陳小明" learned into userWords
        XCTAssertEqual(engine.userLexicon.data.batchHistory.first?.id, batch.id)
        XCTAssertNotNil(engine.userLexicon.data.userWords["陳小明"])

        // Verify recentHomophones MRU was NOT polluted by bulk article import
        XCTAssertTrue(engine.userLexicon.data.recentHomophones.isEmpty, "Bulk article import must not pollute single-character recentHomophones MRU")

        // Verify decoding "ㄔㄣˊ ㄒㄧㄠˇ ㄇㄧㄥˊ" now directly outputs "陳小明"
        let afterDecoded = engine.decode(syllables: syllables, topK: 1).bestText
        XCTAssertEqual(afterDecoded, "陳小明")

        // Rollback the batch
        let rolledBack = engine.rollbackIngestionBatch(id: batch.id)
        XCTAssertTrue(rolledBack)
        XCTAssertTrue(engine.userLexicon.data.batchHistory.isEmpty)
        XCTAssertNil(engine.userLexicon.data.userWords["陳小明"])

        // Verify engine hot-reloaded back to baseline decoding
        let restoredDecoded = engine.decode(syllables: syllables, topK: 1).bestText
        XCTAssertEqual(restoredDecoded, beforeDecoded)
    }

    func testMultipleBatchesIncrementalRollback() {
        let engine = ZhuyinEngine.production(userLexiconURL: tempLexiconURL)

        let article1 = """
        今天陳小明去學校，老師稱讚陳小明很認真，同學也喜歡陳小明。
        """
        let article2 = """
        下午陳小明在台北寫程式，晚上陳小明跟朋友吃飯，大家都找陳小明討論。
        """

        let batch1 = engine.ingestArticle(text: article1, sourceName: "批次一.txt", mode: .autoImport)
        let countAfterBatch1 = engine.userLexicon.data.userWords["陳小明"]?.count ?? 0
        XCTAssertGreaterThan(countAfterBatch1, 0)

        let batch2 = engine.ingestArticle(text: article2, sourceName: "批次二.txt", mode: .autoImport)
        let countAfterBatch2 = engine.userLexicon.data.userWords["陳小明"]?.count ?? 0
        XCTAssertGreaterThan(countAfterBatch2, countAfterBatch1)

        // Rollback only batch2: "陳小明" must remain with batch1's count
        XCTAssertTrue(engine.rollbackIngestionBatch(id: batch2.id))
        XCTAssertEqual(engine.userLexicon.data.userWords["陳小明"]?.count, countAfterBatch1)
        XCTAssertEqual(engine.decode(zhuyin: "ㄔㄣˊ ㄒㄧㄠˇ ㄇㄧㄥˊ", topK: 1).bestText, "陳小明")

        // Rollback batch1: "陳小明" must be completely removed
        XCTAssertTrue(engine.rollbackIngestionBatch(id: batch1.id))
        XCTAssertNil(engine.userLexicon.data.userWords["陳小明"])
    }
}
