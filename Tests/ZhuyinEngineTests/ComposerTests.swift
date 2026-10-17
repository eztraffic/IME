import XCTest
@testable import ZhuyinEngine

final class ComposerTests: XCTestCase {
    var composer: BopomofoComposer!

    override func setUp() {
        super.setUp()
        composer = BopomofoComposer()
    }

    /// Acceptance Criterion: 按鍵序列 ["r", "u", "4"] 正確組出 ㄐㄧˋ
    func testRu4ProducesJi4() {
        composer.handleKey(character: "r")
        XCTAssertEqual(composer.currentInitial, "ㄐ")
        XCTAssertEqual(composer.displayText, "ㄐ")

        composer.handleKey(character: "u")
        XCTAssertEqual(composer.currentMedial, "ㄧ")
        XCTAssertEqual(composer.displayText, "ㄐㄧ")

        let result = composer.handleKey(character: "4")
        XCTAssertEqual(composer.completedSyllables.count, 1)
        let syllable = composer.completedSyllables[0]
        XCTAssertEqual(syllable.initial, "ㄐ")
        XCTAssertEqual(syllable.medial, "ㄧ")
        XCTAssertNil(syllable.rhyme)
        XCTAssertEqual(syllable.tone, .fourth)
        XCTAssertEqual(syllable.raw, "ㄐㄧˋ")
        XCTAssertEqual(composer.displayText, "ㄐㄧˋ")
        XCTAssertEqual(result, .syllableCompleted(syllable, displayText: "ㄐㄧˋ"))
    }

    /// Acceptance Criterion: 重複聲母覆蓋邏輯（輸入 1 再輸入 q，緩衝區應只留 ㄆ）
    func testInitialOverwrite() {
        composer.handleKey(character: "1") // ㄅ
        XCTAssertEqual(composer.currentInitial, "ㄅ")
        XCTAssertEqual(composer.currentComposingZhuyin, "ㄅ")

        composer.handleKey(character: "q") // ㄆ
        XCTAssertEqual(composer.currentInitial, "ㄆ")
        XCTAssertEqual(composer.currentComposingZhuyin, "ㄆ")
        XCTAssertEqual(composer.displayText, "ㄆ")
    }

    /// Tests medial and rhyme overwrite logic
    func testMedialAndRhymeOverwrite() {
        // Medial overwrite
        composer.handleKey(character: "u") // ㄧ
        XCTAssertEqual(composer.currentMedial, "ㄧ")
        composer.handleKey(character: "j") // ㄨ
        XCTAssertEqual(composer.currentMedial, "ㄨ")

        // Rhyme overwrite
        composer.handleKey(character: "8") // ㄚ
        XCTAssertEqual(composer.currentRhyme, "ㄚ")
        composer.handleKey(character: "o") // ㄟ
        XCTAssertEqual(composer.currentRhyme, "ㄟ")

        XCTAssertEqual(composer.currentComposingZhuyin, "ㄨㄟ")
    }

    /// Acceptance Criterion: Backspace 退格行為：優先刪除未完成音節的最後一個符號；若當前音節為空，則刪除上一個已完成的音節。
    func testBackspaceBehavior() {
        // Compose first syllable: ㄐㄧˋ
        composer.handleKeys("ru4")
        XCTAssertEqual(composer.completedSyllables.count, 1)
        XCTAssertEqual(composer.displayText, "ㄐㄧˋ")

        // Start typing second syllable: ㄊ (w) + ㄧ (u)
        composer.handleKey(character: "w")
        composer.handleKey(character: "u")
        XCTAssertEqual(composer.displayText, "ㄐㄧˋ ㄊㄧ")

        // 1. Backspace: should delete last uncompleted component (ㄧ)
        let res1 = composer.handleBackspace()
        XCTAssertEqual(res1, .backspaced(displayText: "ㄐㄧˋ ㄊ"))
        XCTAssertEqual(composer.currentInitial, "ㄊ")
        XCTAssertNil(composer.currentMedial)
        XCTAssertEqual(composer.completedSyllables.count, 1)

        // 2. Backspace: should delete remaining initial (ㄊ)
        let res2 = composer.handleBackspace()
        XCTAssertEqual(res2, .backspaced(displayText: "ㄐㄧˋ"))
        XCTAssertNil(composer.currentInitial)
        XCTAssertFalse(composer.hasComposingComponents)
        XCTAssertEqual(composer.completedSyllables.count, 1)

        // 3. Backspace: in-flight is now empty, should delete previous completed syllable (ㄐㄧˋ)
        let res3 = composer.handleBackspace()
        XCTAssertEqual(res3, .backspaced(displayText: ""))
        XCTAssertTrue(composer.completedSyllables.isEmpty)

        // 4. Backspace on empty composer
        let res4 = composer.handleBackspace()
        XCTAssertEqual(res4, .empty)
    }

    /// Acceptance Criterion: su3cl3 組出 ㄋㄧˇ ㄏㄠˇ
    func testSu3Cl3ProducesNiHao() {
        composer.handleKeys("su3cl3")
        XCTAssertEqual(composer.completedSyllables.count, 2)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄋㄧˇ")
        XCTAssertEqual(composer.completedSyllables[1].raw, "ㄏㄠˇ")
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ ㄏㄠˇ")
    }

    /// Test tone 1 (space) completion
    func testSpaceToneCompletion() {
        composer.handleKey(character: "r") // ㄐ
        composer.handleKey(character: "u") // ㄧ
        composer.handleKey(character: "0") // ㄢ
        let res = composer.handleKey(character: " ") // first tone
        XCTAssertEqual(composer.completedSyllables.count, 1)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄐㄧㄢ")
        XCTAssertEqual(composer.completedSyllables[0].tone, .first)
        XCTAssertEqual(res, .syllableCompleted(composer.completedSyllables[0], displayText: "ㄐㄧㄢ"))
    }

    /// Test case insensitivity (uppercase keys like R, U, 4)
    func testCaseInsensitivity() {
        composer.handleKeys("RU4")
        XCTAssertEqual(composer.completedSyllables.count, 1)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄐㄧˋ")
    }

    /// Test inserting and removing syllables at arbitrary indices (for inline internal text modification)
    func testIndexBasedSyllableOperations() {
        composer.handleKeys("su3cl3") // ㄋㄧˇ ㄏㄠˇ (2 syllables)
        XCTAssertEqual(composer.completedSyllables.count, 2)

        // Remove first syllable
        let removed = composer.removeCompletedSyllable(at: 0)
        XCTAssertEqual(removed?.raw, "ㄋㄧˇ")
        XCTAssertEqual(composer.completedSyllables.count, 1)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄏㄠˇ")

        // Insert at beginning
        let newSyllable = Syllable(initial: "ㄐ", medial: "ㄧ", rhyme: "ㄣ", tone: .first)
        composer.insertCompletedSyllable(newSyllable, at: 0)
        XCTAssertEqual(composer.completedSyllables.count, 2)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄐㄧㄣ")
        XCTAssertEqual(composer.completedSyllables[1].raw, "ㄏㄠˇ")
    }

    /// Tests that ANSI escape sequences for arrow keys (Left \u{1b}[D, Right \u{1b}[C, Up \u{1b}[A, Down \u{1b}[B)
    /// and private use area characters are ignored and do NOT produce garbled characters (ㄎ, ㄏ, ㄇ, ㄖ).
    func testArrowKeysAndEscapeSequencesIgnoredWithoutGarbledCharacters() {
        // Feed Left Arrow escape sequence
        composer.handleKeys("su3\u{001B}[D")
        XCTAssertEqual(composer.completedSyllables.count, 1)
        XCTAssertEqual(composer.completedSyllables[0].raw, "ㄋㄧˇ")
        XCTAssertFalse(composer.hasComposingComponents, "Arrow key escape sequence should not leave initial ㄎ in-flight")
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ")

        // Individual private use arrow function keys
        let leftRes = composer.handleKey(character: "\u{F702}")
        XCTAssertEqual(leftRes, .ignored)
        let rightRes = composer.handleKey(character: "\u{F703}")
        XCTAssertEqual(rightRes, .ignored)
        let downRes = composer.handleKey(character: "\u{F701}")
        XCTAssertEqual(downRes, .ignored)
        let upRes = composer.handleKey(character: "\u{F700}")
        XCTAssertEqual(upRes, .ignored)

        XCTAssertFalse(composer.hasComposingComponents)
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ")
    }

    /// Test inserting syllable into the middle of an existing sequence and shifting
    func testMiddleSyllableInsertionAndShift() {
        // Compose "你好" (ㄋㄧˇ ㄏㄠˇ)
        composer.handleKeys("su3cl3")
        XCTAssertEqual(composer.completedSyllables.count, 2)
        XCTAssertEqual(composer.completedSyllables.map(\.raw), ["ㄋㄧˇ", "ㄏㄠˇ"])

        // User inserts "馬" (ㄇㄚˇ) at index 1 (between 你 and 好)
        let ma = Syllable(initial: "ㄇ", medial: nil, rhyme: "ㄚ", tone: .third)
        composer.insertCompletedSyllable(ma, at: 1)
        XCTAssertEqual(composer.completedSyllables.count, 3)
        XCTAssertEqual(composer.completedSyllables.map(\.raw), ["ㄋㄧˇ", "ㄇㄚˇ", "ㄏㄠˇ"])
        XCTAssertEqual(composer.displayText, "ㄋㄧˇ ㄇㄚˇ ㄏㄠˇ")

        // Delete the middle syllable
        let removed = composer.removeCompletedSyllable(at: 1)
        XCTAssertEqual(removed?.raw, "ㄇㄚˇ")
        XCTAssertEqual(composer.completedSyllables.map(\.raw), ["ㄋㄧˇ", "ㄏㄠˇ"])
    }
}
