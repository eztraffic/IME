import XCTest
@testable import ZhuyinEngine

final class SyllableTests: XCTestCase {
    func testSyllableDecomposition() {
        let s1 = Syllable(parsing: "ㄐㄧㄣ")
        XCTAssertNotNil(s1)
        XCTAssertEqual(s1?.initial, "ㄐ")
        XCTAssertEqual(s1?.medial, "ㄧ")
        XCTAssertEqual(s1?.rhyme, "ㄣ")
        XCTAssertEqual(s1?.tone, .first)

        let s2 = Syllable(parsing: "ㄑㄧˋ")
        XCTAssertNotNil(s2)
        XCTAssertEqual(s2?.initial, "ㄑ")
        XCTAssertEqual(s2?.medial, "ㄧ")
        XCTAssertEqual(s2?.tone, .fourth)

        let s3 = Syllable(parsing: "ㄏㄣˇ")
        XCTAssertNotNil(s3)
        XCTAssertEqual(s3?.initial, "ㄏ")
        XCTAssertEqual(s3?.rhyme, "ㄣ")
        XCTAssertEqual(s3?.tone, .third)

        let s4 = Syllable(parsing: "ㄒㄩㄝˊ")
        XCTAssertNotNil(s4)
        XCTAssertEqual(s4?.initial, "ㄒ")
        XCTAssertEqual(s4?.medial, "ㄩ")
        XCTAssertEqual(s4?.rhyme, "ㄝ")
        XCTAssertEqual(s4?.tone, .second)
    }

    func testNeutralToneHandling() {
        // Test prefix neutral tone: ˙ㄉㄜ
        let sPrefix = Syllable(parsing: "˙ㄉㄜ")
        XCTAssertNotNil(sPrefix)
        XCTAssertEqual(sPrefix?.tone, .neutral)
        XCTAssertEqual(sPrefix?.initial, "ㄉ")
        XCTAssertEqual(sPrefix?.rhyme, "ㄜ")

        // Test suffix neutral tone: ㄉㄜ˙
        let sSuffix = Syllable(parsing: "ㄉㄜ˙")
        XCTAssertNotNil(sSuffix)
        XCTAssertEqual(sSuffix?.tone, .neutral)
        XCTAssertEqual(sSuffix?.initial, "ㄉ")
        XCTAssertEqual(sSuffix?.rhyme, "ㄜ")
    }

    func testSequenceParsing() {
        let text = "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ"
        let syllables = Syllable.parseSequence(text)
        XCTAssertEqual(syllables.count, 6)
        XCTAssertEqual(syllables[0].raw, "ㄐㄧㄣ")
        XCTAssertEqual(syllables[1].raw, "ㄊㄧㄢ")
        XCTAssertEqual(syllables[2].raw, "ㄊㄧㄢ")
        XCTAssertEqual(syllables[3].raw, "ㄑㄧˋ")
        XCTAssertEqual(syllables[4].raw, "ㄏㄣˇ")
        XCTAssertEqual(syllables[5].raw, "ㄏㄠˇ")
    }
}
