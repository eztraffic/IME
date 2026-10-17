import XCTest
@testable import ZhuyinEngine

final class SpatialViterbiTests: XCTestCase {
    var engine: ZhuyinEngine!

    override func setUp() {
        super.setUp()
        // Use production engine (or lightweight default fallback)
        engine = ZhuyinEngine.production()
    }

    func testTypoCorrectionJinTianWeatherWithAdjacentKeyE() {
        // Correct syllables: ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ (今天天氣很好)
        // User typed: w was slipped to e on syllable 1 -> ㄍㄧㄢ
        // Typed syllables: ㄐㄧㄣ ㄍㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ
        let typoZhuyin = "ㄐㄧㄣ ㄍㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ"
        let syllables = Syllable.parseSequence(typoZhuyin)

        // 1. With spatial tolerance enabled (default)
        engine.isSpatialToleranceEnabled = true
        let correctedResult = engine.decode(syllables: syllables, topK: 3)
        XCTAssertEqual(correctedResult.bestText, "今天天氣很好", "Viterbi should automatically correct adjacent-key typo 'ㄍㄧㄢ' to '今天天氣很好'")

        // 2. With spatial tolerance disabled
        engine.isSpatialToleranceEnabled = false
        let uncorrectedResult = engine.decode(syllables: syllables, topK: 3)
        XCTAssertNotEqual(uncorrectedResult.bestText, "今天天氣很好", "Without spatial model, 'ㄍㄧㄢ' should remain uncorrected OOV fallback")
    }

    func testExactInputPreservedWithoutFalseCorrection() {
        // User cleanly typed "今天天氣很好"
        let exactZhuyin = "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ"
        let syllables = Syllable.parseSequence(exactZhuyin)

        engine.isSpatialToleranceEnabled = true
        let result = engine.decode(syllables: syllables, topK: 1)
        XCTAssertEqual(result.bestText, "今天天氣很好")
    }

    func testTypoCorrectionAdjacentKeyRForFInWeather() {
        // 'f' (ㄑ) and 'r' (ㄐ) are physical neighbors on macOS keyboard (dist 1.0)
        // Correct: ㄊㄧㄢ ㄑㄧˋ (天氣, keys: w u 0 + f u 4)
        // Slipped: ㄊㄧㄢ ㄐㄧˋ (keys: w u 0 + r u 4)
        let typoWeather = "ㄊㄧㄢ ㄐㄧˋ"
        let syllables = Syllable.parseSequence(typoWeather)

        engine.isSpatialToleranceEnabled = true
        let result = engine.decode(syllables: syllables, topK: 3)
        // The candidate list should include "天氣"
        let candidates = result.candidates.map { $0.text }
        XCTAssertTrue(candidates.contains("天氣"), "Candidates should include '天氣' via adjacent key r -> f correction")
    }

    func testLongSentenceStabilizedNoFlipFlop() {
        // "如何修正鄰近的字是否會造成更多的錯誤" with typo ㄈㄡˋ (4th tone) instead of ㄈㄡˇ (3rd tone) on "否"
        let fullZhuyin = "ㄖㄨˊ ㄏㄜˊ ㄒㄧㄡ ㄓㄥˋ ㄌㄧㄣˊ ㄐㄧㄣˋ ˙ㄉㄜ ㄗˋ ㄕˋ ㄈㄡˋ ㄏㄨㄟˋ ㄗㄠˋ ㄔㄥˊ ㄍㄥˋ ㄉㄨㄛ ˙ㄉㄜ ㄘㄨㄛˋ ㄨˋ"
        let syllables = Syllable.parseSequence(fullZhuyin)
        XCTAssertEqual(syllables.count, 18)

        engine.isSpatialToleranceEnabled = true
        engine.resetStabilizedHistory()

        // 1. Simulate progressive typing from syllable 1 to 18
        var currentText = ""
        for len in 1...syllables.count {
            let prefix = Array(syllables.prefix(len))
            let res = engine.decode(syllables: prefix, topK: 1)
            currentText = res.bestText
            if len == 11 {
                // At length 11 ("如何修正鄰近的字是否會"), "是否會" should be formed via spatial tolerance
                XCTAssertTrue(currentText.hasSuffix("是否會"), "Expected text ending in '是否會' at length 11, got: \(currentText)")
            }
        }

        // At end of sentence (length 18), '是否' must NOT flip-flop to '是復'!
        XCTAssertEqual(currentText, "如何修正鄰近的字是否會造成更多的錯誤", "Sentence must retain '是否' and not flip to '是復' when typing reaches the end")

        // 2. Also verify one-shot batch decode achieves the same correct result
        engine.resetStabilizedHistory()
        let batchResult = engine.decode(syllables: syllables, topK: 1)
        XCTAssertEqual(batchResult.bestText, "如何修正鄰近的字是否會造成更多的錯誤")
    }

    func testNoRarePhantomReadingsInSpatial() {
        // When typing ㄈㄡˇ (as in 否, 3rd tone), its adjacent 4th tone ㄈㄡˋ
        // should NOT introduce the archaic phantom reading "復" (cost 14.5) into spatial candidates.
        let single = Syllable.parseSequence("ㄈㄡˇ")
        engine.isSpatialToleranceEnabled = true
        let candidates = engine.candidates(for: single)
        XCTAssertFalse(candidates.contains("復"), "Rare reading '復' (ㄈㄡˋ) must not appear in spatial candidates of 'ㄈㄡˇ'")

        // Also test phrase: typing ㄕˋ ㄈㄡˋ (typo for 是否)
        // Spatial tolerance should correctly produce "是否" and NOT produce "是復"
        let phraseSyllables = Syllable.parseSequence("ㄕˋ ㄈㄡˋ")
        let decoded = engine.decode(syllables: phraseSyllables, topK: 3)
        XCTAssertEqual(decoded.bestText, "是否")
        XCTAssertFalse(decoded.candidates.map { $0.text }.contains("是復"))
    }

    func testSingleGuoTypingSimulation() {
        let composer = BopomofoComposer()
        composer.handleKey(character: "e")
        composer.handleKey(character: "j")
        composer.handleKey(character: "i")
        composer.handleKey(character: "6")

        XCTAssertEqual(composer.items.count, 1)
        guard case .syllable(let syl) = composer.items[0] else {
            XCTFail("Expected syllable item")
            return
        }
        XCTAssertEqual(syl.raw, "ㄍㄨㄛˊ")

        // 1. Without spatial tolerance
        engine.isSpatialToleranceEnabled = false
        let resWithout = engine.decode(syllables: [syl], topK: 5)
        print(">>> Without spatial tolerance: bestText=\(resWithout.bestText)")
        for c in resWithout.candidates {
            print(">>> cand: \(c.text) cost=\(c.totalCost)")
        }
        XCTAssertEqual(resWithout.bestText, "國")

        // 2. With spatial tolerance
        engine.isSpatialToleranceEnabled = true
        let resWith = engine.decode(syllables: [syl], topK: 5)
        print(">>> With spatial tolerance: bestText=\(resWith.bestText)")
        for c in resWith.candidates {
            print(">>> cand: \(c.text) cost=\(c.totalCost)")
        }
        XCTAssertEqual(resWith.bestText, "國")
    }

    func testExactGuoNotReplacedByGuo() {
        // Typing single ㄍㄨㄛˊ (e j i 6)
        let syllables = Syllable.parseSequence("ㄍㄨㄛˊ")
        engine.isSpatialToleranceEnabled = true
        let result = engine.decode(syllables: syllables, topK: 3)
        XCTAssertEqual(result.bestText, "國")
        XCTAssertFalse(result.candidates.map(\.text).contains("過"))
    }

    func testGuoFollowedByUnrelatedWord() {
        // Typing ㄍㄨㄛˊ ㄐㄧㄚ (國家) must decode as 國家, never falsely turning 國 into 過
        let syllables = Syllable.parseSequence("ㄍㄨㄛˊ ㄐㄧㄚ")
        engine.isSpatialToleranceEnabled = true
        let result = engine.decode(syllables: syllables, topK: 3)
        XCTAssertEqual(result.bestText, "國家")
    }
}
