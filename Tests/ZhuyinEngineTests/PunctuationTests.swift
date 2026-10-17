import XCTest
@testable import ZhuyinEngine

final class PunctuationTests: XCTestCase {
    // MARK: - Shift Punctuation Lookups

    func testShiftPunctuationLookups() {
        // Shift + , (<) -> ，
        let comma = PunctuationTable.lookup(keyCode: 0x2B, character: "<", isShift: true, isOption: false)
        XCTAssertEqual(comma?.primary, "，")
        XCTAssertTrue(comma?.candidates.contains("、") ?? false)
        XCTAssertTrue(comma?.candidates.contains("《") ?? false)

        // Shift + . (>) -> 。
        let period = PunctuationTable.lookup(keyCode: 0x2F, character: ">", isShift: true, isOption: false)
        XCTAssertEqual(period?.primary, "。")
        XCTAssertTrue(period?.candidates.contains("……") ?? false)
        XCTAssertTrue(period?.candidates.contains("⋯⋯") ?? false)

        // Shift + / (?) -> ？
        let question = PunctuationTable.lookup(keyCode: 0x2C, character: "?", isShift: true, isOption: false)
        XCTAssertEqual(question?.primary, "？")

        // Shift + ; (:) -> ：
        let colon = PunctuationTable.lookup(keyCode: 0x29, character: ":", isShift: true, isOption: false)
        XCTAssertEqual(colon?.primary, "：")

        // Shift + ' (") -> ”
        let doubleQuote = PunctuationTable.lookup(keyCode: 0x27, character: "\"", isShift: true, isOption: false)
        XCTAssertEqual(doubleQuote?.primary, "”")

        // Shift + 1 (!) -> ！
        let exclamation = PunctuationTable.lookup(keyCode: 0x12, character: "!", isShift: true, isOption: false)
        XCTAssertEqual(exclamation?.primary, "！")

        // Shift + 9 ( () -> （
        let leftParen = PunctuationTable.lookup(keyCode: 0x19, character: "(", isShift: true, isOption: false)
        XCTAssertEqual(leftParen?.primary, "（")

        // Shift + 0 ( )) -> ）
        let rightParen = PunctuationTable.lookup(keyCode: 0x1D, character: ")", isShift: true, isOption: false)
        XCTAssertEqual(rightParen?.primary, "）")

        // Shift + - (_) -> ——
        let dash = PunctuationTable.lookup(keyCode: 0x1B, character: "_", isShift: true, isOption: false)
        XCTAssertEqual(dash?.primary, "——")
        XCTAssertTrue(dash?.candidates.contains("—") ?? false)

        // Shift + 6 (^) -> ……
        let ellipsis = PunctuationTable.lookup(keyCode: 0x16, character: "^", isShift: true, isOption: false)
        XCTAssertEqual(ellipsis?.primary, "……")
        XCTAssertTrue(ellipsis?.candidates.contains("⋯⋯") ?? false)

        // Shift + ` (~) -> ～
        let tilde = PunctuationTable.lookup(keyCode: 0x32, character: "~", isShift: true, isOption: false)
        XCTAssertEqual(tilde?.primary, "～")

        // Shift + [ ({) -> 『
        let leftDoubleQuote = PunctuationTable.lookup(keyCode: 0x21, character: "{", isShift: true, isOption: false)
        XCTAssertEqual(leftDoubleQuote?.primary, "『")

        // Shift + ] (}) -> 』
        let rightDoubleQuote = PunctuationTable.lookup(keyCode: 0x1E, character: "}", isShift: true, isOption: false)
        XCTAssertEqual(rightDoubleQuote?.primary, "』")

        // Shift + \ (|) -> ｜
        let pipe = PunctuationTable.lookup(keyCode: 0x2A, character: "|", isShift: true, isOption: false)
        XCTAssertEqual(pipe?.primary, "｜")

        // Shift + = (+) -> ＋
        let plus = PunctuationTable.lookup(keyCode: 0x18, character: "+", isShift: true, isOption: false)
        XCTAssertEqual(plus?.primary, "＋")
    }

    // MARK: - Option Combinations

    func testOptionPunctuationLookups() {
        // Option + ; -> ； (Semicolon)
        let semicolon = PunctuationTable.lookup(keyCode: 0x29, character: ";", isShift: false, isOption: true)
        XCTAssertEqual(semicolon?.primary, "；")

        // Option + - -> — (Dash)
        let optionDash = PunctuationTable.lookup(keyCode: 0x1B, character: "-", isShift: false, isOption: true)
        XCTAssertEqual(optionDash?.primary, "—")

        // Option + [ -> 「
        let leftQuote = PunctuationTable.lookup(keyCode: 0x21, character: "[", isShift: false, isOption: true)
        XCTAssertEqual(leftQuote?.primary, "「")

        // Option + ] -> 」
        let rightQuote = PunctuationTable.lookup(keyCode: 0x1E, character: "]", isShift: false, isOption: true)
        XCTAssertEqual(rightQuote?.primary, "」")

        // Option + , -> 《
        let bookLeft = PunctuationTable.lookup(keyCode: 0x2B, character: ",", isShift: false, isOption: true)
        XCTAssertEqual(bookLeft?.primary, "《")

        // Option + . -> 》
        let bookRight = PunctuationTable.lookup(keyCode: 0x2F, character: ".", isShift: false, isOption: true)
        XCTAssertEqual(bookRight?.primary, "》")
    }

    // MARK: - Unshifted Punctuation Keys

    func testUnshiftedPunctuationLookups() {
        // [ -> 「
        let leftBracket = PunctuationTable.lookup(keyCode: 0x21, character: "[", isShift: false, isOption: false)
        XCTAssertEqual(leftBracket?.primary, "「")
        XCTAssertTrue(leftBracket?.candidates.contains("『") ?? false)
        XCTAssertTrue(leftBracket?.candidates.contains("【") ?? false)

        // ] -> 」
        let rightBracket = PunctuationTable.lookup(keyCode: 0x1E, character: "]", isShift: false, isOption: false)
        XCTAssertEqual(rightBracket?.primary, "」")
        XCTAssertTrue(rightBracket?.candidates.contains("』") ?? false)
        XCTAssertTrue(rightBracket?.candidates.contains("】") ?? false)

        // \ -> 、 (Dunhao)
        let backslash = PunctuationTable.lookup(keyCode: 0x2A, character: "\\", isShift: false, isOption: false)
        XCTAssertEqual(backslash?.primary, "、")
        XCTAssertTrue(backslash?.candidates.contains("＼") ?? false)

        // ' -> ’ (Single quote)
        let singleQuote = PunctuationTable.lookup(keyCode: 0x27, character: "'", isShift: false, isOption: false)
        XCTAssertEqual(singleQuote?.primary, "’")
        XCTAssertTrue(singleQuote?.candidates.contains("‘") ?? false)

        // ` -> · (Interpunct)
        let grave = PunctuationTable.lookup(keyCode: 0x32, character: "`", isShift: false, isOption: false)
        XCTAssertEqual(grave?.primary, "·")

        // = -> ＝ (Fullwidth equal)
        let equal = PunctuationTable.lookup(keyCode: 0x18, character: "=", isShift: false, isOption: false)
        XCTAssertEqual(equal?.primary, "＝")
    }

    // MARK: - Shift + Option Combinations

    func testShiftOptionCombinations() {
        // Shift + Option + B -> Symbol Palette
        let palette = PunctuationTable.lookup(keyCode: 0x0B, character: "b", isShift: true, isOption: true)
        XCTAssertNotNil(palette)
        XCTAssertEqual(palette?.candidates, PunctuationTable.symbolPalette)
        XCTAssertEqual(PunctuationTable.symbolPalette.count, 18)
        XCTAssertTrue(PunctuationTable.symbolPalette.contains("「"))
        XCTAssertTrue(PunctuationTable.symbolPalette.contains("」"))
        XCTAssertTrue(PunctuationTable.symbolPalette.contains("——"))

        // Shift + Option + Space -> Fullwidth Space
        let space = PunctuationTable.lookup(keyCode: 0x31, character: " ", isShift: true, isOption: true)
        XCTAssertEqual(space?.primary, "　")

        // Shift + Option + , -> 《
        let bookLeft = PunctuationTable.lookup(keyCode: 0x2B, character: "<", isShift: true, isOption: true)
        XCTAssertEqual(bookLeft?.primary, "《")

        // Shift + Option + . -> 》
        let bookRight = PunctuationTable.lookup(keyCode: 0x2F, character: ">", isShift: true, isOption: true)
        XCTAssertEqual(bookRight?.primary, "》")
    }

    // MARK: - Composer Integration with Punctuation

    func testComposerPunctuationHandling() {
        let composer = BopomofoComposer()

        // 1. Enter syllable: ㄋㄧˇ (su3)
        composer.handleKeys("su3")
        XCTAssertEqual(composer.items.count, 1)
        XCTAssertEqual(composer.completedSyllables.count, 1)

        // 2. Insert punctuation: ，
        composer.appendPunctuation("，")
        XCTAssertEqual(composer.items.count, 2)
        XCTAssertEqual(composer.items[1], .punctuation("，"))
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ ，")

        // 3. Enter second syllable: ㄏㄠˇ (cl3)
        composer.handleKeys("cl3")
        XCTAssertEqual(composer.items.count, 3)
        XCTAssertEqual(composer.items[2].syllable?.raw, "ㄏㄠˇ")
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ ， ㄏㄠˇ")

        // 4. Backspace removes last syllable
        let res1 = composer.handleBackspace()
        XCTAssertEqual(res1, .backspaced(displayText: "ㄋㄧˇ ，"))
        XCTAssertEqual(composer.items.count, 2)

        // 5. Backspace removes punctuation
        let res2 = composer.handleBackspace()
        XCTAssertEqual(res2, .backspaced(displayText: "ㄋㄧˇ"))
        XCTAssertEqual(composer.items.count, 1)

        // 6. Backspace removes first syllable
        let res3 = composer.handleBackspace()
        XCTAssertEqual(res3, .backspaced(displayText: ""))
        XCTAssertTrue(composer.isEmpty)
    }

    // MARK: - Sentence Decoding with Punctuation

    func testSentenceDecodingWithPunctuation() {
        let engine = ZhuyinEngine.production()

        // Decode "su3cl3" (你好)
        let s1 = Syllable(parsing: "ㄋㄧˇ")!
        let s2 = Syllable(parsing: "ㄏㄠˇ")!
        let res1 = engine.decode(syllables: [s1, s2], topK: 1)
        XCTAssertEqual(res1.bestText, "你好")

        // Verify punctuation candidate lookup
        let punctCandidates = PunctuationTable.candidates(for: "，")
        XCTAssertTrue(punctCandidates.contains("、"))
        XCTAssertTrue(punctCandidates.contains("《"))
    }
}
