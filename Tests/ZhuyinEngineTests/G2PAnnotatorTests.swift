import XCTest
@testable import ZhuyinEngine

final class G2PAnnotatorTests: XCTestCase {
    func testReverseZhuyinLookupAndPrimaryReadings() {
        let engine = ZhuyinEngine.production()
        let lookup = engine.reverseLookup

        // "今天" must resolve to "ㄐㄧㄣ ㄊㄧㄢ"
        let jinTian = lookup.lookupWord("今天")
        XCTAssertFalse(jinTian.isEmpty)
        XCTAssertEqual(jinTian.first?.displayString, "ㄐㄧㄣ ㄊㄧㄢ")

        // Single character "在" must resolve to "ㄗㄞˋ"
        let zai = lookup.lookupCharacter("在")
        XCTAssertEqual(zai.first?.syllable.raw, "ㄗㄞˋ")
    }

    func testHeterophonyCompoundDisambiguation() {
        let engine = ZhuyinEngine.production()
        let annotator = G2PAnnotator(reverseLookup: engine.reverseLookup)

        // "老銀行" contains known compound "銀行" (ㄧㄣˊ ㄏㄤˊ), so "行" must disambiguate to "ㄏㄤˊ"
        let yinHangAnnotated = annotator.annotate(word: "老銀行", count: 3, isNewWord: true)
        XCTAssertNotNil(yinHangAnnotated)
        XCTAssertEqual(yinHangAnnotated?.selectedSyllables.last?.raw, "ㄏㄤˊ", "Compound '銀行' must disambiguate '行' to ㄏㄤˊ")

        // "新行為" contains known compound "行為" (ㄒㄧㄥˊ ㄨㄟˊ), so "行" must disambiguate to "ㄒㄧㄥˊ"
        let xingWeiAnnotated = annotator.annotate(word: "新行為", count: 3, isNewWord: true)
        XCTAssertNotNil(xingWeiAnnotated)
        if let syls = xingWeiAnnotated?.selectedSyllables, syls.count == 3 {
            XCTAssertEqual(syls[1].raw, "ㄒㄧㄥˊ", "Compound '行為' must disambiguate '行' to ㄒㄧㄥˊ")
        } else {
            XCTFail("Expected 3 syllables for 新行為")
        }
    }
}
