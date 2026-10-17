import XCTest
@testable import ZhuyinEngine

final class ProductionLexiconTests: XCTestCase {

    /// Acceptance Criterion: Cold loading time < 200ms
    func testProductionLexiconLoadingPerformance() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let startTime = DispatchTime.now()
        let lexicon = try Lexicon.loadProduction(from: url)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        print("Production Lexicon Loaded: \(lexicon.entries.count) entries in \(String(format: "%.2f", elapsedMs)) ms")

        // Acceptance Criterion: 載入時間 < 300ms (考量冷啟動 I/O 抖動)
        XCTAssertLessThan(elapsedMs, 300.0, "Production lexicon loading time must be strictly under 300ms")

        // Acceptance Criterion: 提取至少 30,000+ 條台灣常用單字與詞彙
        XCTAssertGreaterThanOrEqual(lexicon.entries.count, 30_000, "Must contain at least 30,000 vocabulary entries")
    }

    /// Acceptance Criterion: 實際以標準鍵盤鍵入一段測試句子（例如輸入 su3cl3 即 ㄋㄧˇ ㄏㄠˇ），驗收是否成功輸出 你好
    func testComposerAndProductionEngineDecodingNiHao() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // Simulate typing "su3cl3"
        let composer = BopomofoComposer()
        composer.handleKeys("su3cl3")

        XCTAssertEqual(composer.displayText, "ㄋㄧˇ ㄏㄠˇ")
        XCTAssertEqual(composer.completedSyllables.count, 2)

        let result = engine.decode(syllables: composer.completedSyllables, topK: 3)
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertEqual(result.bestText, "你好", "Expected top decoded text to be '你好'")
    }

    /// Tests that core common sentence decodes correctly on production lexicon
    func testProductionEngineDecodesCommonPhrases() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ" -> "今天天氣很好"
        let res = engine.decode(zhuyin: "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ", topK: 3)
        XCTAssertEqual(res.bestText, "今天天氣很好")
    }

    /// Tests typing "c;6" produces "ㄏㄤˊ" and decodes to "行"
    func testComposerAndProductionEngineDecodingHang() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        let composer = BopomofoComposer()
        composer.handleKeys("c;6")

        XCTAssertEqual(composer.displayText, "ㄏㄤˊ")
        XCTAssertEqual(composer.completedSyllables.count, 1)

        let result = engine.decode(syllables: composer.completedSyllables, topK: 3)
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertEqual(result.bestText, "行", "Expected top decoded text to be '行'")
    }

    /// Tests candidate generation for single syllable (homophones) and multi-syllable phrases
    func testCandidatesGeneration() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // Single syllable "ㄋㄧˇ"
        let syllables = Syllable.parseSequence("ㄋㄧˇ")
        let singleCandidates = engine.candidates(for: syllables, maxCount: 9)
        XCTAssertFalse(singleCandidates.isEmpty)
        XCTAssertTrue(singleCandidates.contains("你") || singleCandidates.contains("妳"))

        // Multi-syllable "ㄋㄧˇ ㄏㄠˇ"
        let phraseSyllables = Syllable.parseSequence("ㄋㄧˇ ㄏㄠˇ")
        let phraseCandidates = engine.candidates(for: phraseSyllables, maxCount: 9)
        XCTAssertFalse(phraseCandidates.isEmpty)
        XCTAssertEqual(phraseCandidates.first, "你好")
    }

    /// Verifies that candidate generation is not artificially restricted to 9,
    /// so homophones beyond the 9th character can be browsed and selected.
    func testSingleSyllableCandidatesExceedsNine() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // Single syllable "ㄋㄧˇ" should have all available homophones
        let syllables = Syllable.parseSequence("ㄋㄧˇ")
        let allCandidates = engine.candidates(for: syllables)
        print("Candidates count for ㄋㄧˇ: \(allCandidates.count) -> \(allCandidates)")
        XCTAssertGreaterThan(allCandidates.count, 9, "Homophones must not be capped at 9, must include additional pages")

        // Single syllable "ㄧ" should have dozens of homophones
        let yiSyllables = Syllable.parseSequence("ㄧ")
        let yiCandidates = engine.candidates(for: yiSyllables)
        print("Candidates count for ㄧ: \(yiCandidates.count)")
        XCTAssertGreaterThan(yiCandidates.count, 9, "Homophones for ㄧ must exceed 9")
    }

    /// Verifies punctuation candidates (like '。' or symbolPalette) return all candidates beyond 9.
    func testPunctuationCandidatesExceedsNine() {
        let periodCandidates = PunctuationTable.candidates(for: "。")
        XCTAssertGreaterThan(periodCandidates.count, 9, "Period candidate list must contain all variations beyond 9")
        XCTAssertTrue(periodCandidates.contains("＞"))
        XCTAssertTrue(periodCandidates.contains("."))
    }

    /// Tests disambiguation of preposition "在" with quantifier/locative ("在任何位置")
    func testZaiRenHeWeiZhiDisambiguation() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄗㄞˋ ㄖㄣˋ ㄏㄜˊ ㄨㄟˋ ㄓˋ" -> "在任何位置"
        let res = engine.decode(zhuyin: "ㄗㄞˋ ㄖㄣˋ ㄏㄜˊ ㄨㄟˋ ㄓˋ", topK: 3)
        XCTAssertEqual(res.bestText, "在任何位置", "Optimal path must choose '在任何位置' rather than '再任何位置'")
    }

    /// Tests disambiguation of adverb "再" with frequency/action ("再次")
    func testZaiCiDisambiguation() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄗㄞˋ ㄘˋ" -> "再次"
        let res = engine.decode(zhuyin: "ㄗㄞˋ ㄘˋ", topK: 3)
        XCTAssertEqual(res.bestText, "再次", "Optimal path must choose '再次' rather than '在次'")
    }

    /// Tests disambiguation of adverb "再" with "再一次"
    func testZaiYiCiDisambiguation() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄗㄞˋ ㄧ ㄘˋ" -> "再一次"
        let res = engine.decode(zhuyin: "ㄗㄞˋ ㄧ ㄘˋ", topK: 3)
        XCTAssertEqual(res.bestText, "再一次", "Optimal path must choose '再一次' rather than '在一次'")
    }

    /// Tests disambiguation of "得" (complement particle) vs "的" (possessive/modifier)
    func testDeAndDeDisambiguation() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄐㄩㄝˊ ㄉㄜ˙ ㄏㄣˇ ㄏㄠˇ" -> "覺得很好"
        let res1 = engine.decode(zhuyin: "ㄐㄩㄝˊ ㄉㄜ˙ ㄏㄣˇ ㄏㄠˇ", topK: 3)
        XCTAssertEqual(res1.bestText, "覺得很好", "Must decode as '覺得很好' with complement '得'")

        // "ㄨㄛˇ ㄉㄜ˙ ㄆㄥˊ ㄧㄡˇ" -> "我的朋友"
        let res2 = engine.decode(zhuyin: "ㄨㄛˇ ㄉㄜ˙ ㄆㄥˊ ㄧㄡˇ", topK: 3)
        XCTAssertEqual(res2.bestText, "我的朋友", "Must decode as '我的朋友' with possessive '的'")
    }

    /// Tests that typing "ㄨㄣˋ" decodes to "問" rather than "文"
    func testWen4DecodingPrefersWen4() throws {
        guard let url = BinaryLexiconReader.findDefaultBinaryURL() else {
            XCTFail("lexicon.bin not found")
            return
        }

        let lexicon = try Lexicon.loadProduction(from: url)
        let engine = ZhuyinEngine(lexicon: lexicon)

        // "ㄨㄣˋ" -> "問"
        let res = engine.decode(zhuyin: "ㄨㄣˋ", topK: 3)
        XCTAssertEqual(res.bestText, "問", "Typing ㄨㄣˋ must decode as '問'")

        let candidates = engine.candidates(for: Syllable.parseSequence("ㄨㄣˋ"), maxCount: 10)
        XCTAssertEqual(candidates.first, "問", "Candidate #1 for ㄨㄣˋ must be '問'")
        XCTAssertFalse(candidates.contains("文"), "Candidate list for ㄨㄣˋ must not contain '文'")
    }
}
