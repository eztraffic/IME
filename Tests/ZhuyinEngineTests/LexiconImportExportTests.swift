import XCTest
@testable import ZhuyinEngine

final class LexiconImportExportTests: XCTestCase {
    var tempDirectoryURL: URL!
    var tempLexiconURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        tempLexiconURL = tempDirectoryURL.appendingPathComponent("user_lexicon_test.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        super.tearDown()
    }

    func testExportToFile() throws {
        let lexicon = UserLexicon(storageURL: tempLexiconURL)
        lexicon.recordHomophoneSelection(syllableRaw: "ㄋㄧˇ", word: "擬")
        lexicon.recordBigram(prev: "今天", next: "天氣")
        lexicon.saveSync()

        let exportURL = tempDirectoryURL.appendingPathComponent("exported.json")
        try lexicon.export(to: exportURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UserLexiconData.self, from: data)

        XCTAssertEqual(decoded.globalHomophones["ㄋㄧˇ"]?["擬"], 1)
        XCTAssertEqual(decoded.bigramCounts["今天|天氣"], 1)
    }

    func testImportOverwrite() throws {
        let lexicon1 = UserLexicon(storageURL: tempLexiconURL)
        lexicon1.recordHomophoneSelection(syllableRaw: "ㄋㄧˇ", word: "擬")
        lexicon1.recordBigram(prev: "今天", next: "天氣")
        lexicon1.saveSync()

        let exportURL = tempDirectoryURL.appendingPathComponent("backup.json")
        try lexicon1.export(to: exportURL)

        // Create a different lexicon2 with different data
        let lexicon2URL = tempDirectoryURL.appendingPathComponent("lexicon2.json")
        let lexicon2 = UserLexicon(storageURL: lexicon2URL)
        lexicon2.recordHomophoneSelection(syllableRaw: "ㄕㄣ", word: "申")
        lexicon2.saveSync()

        // Overwrite lexicon2 with backup
        try lexicon2.importData(from: exportURL, merge: false)

        // Should now have lexicon1's data and NOT have lexicon2's old data
        XCTAssertEqual(lexicon2.data.globalHomophones["ㄋㄧˇ"]?["擬"], 1)
        XCTAssertEqual(lexicon2.data.bigramCounts["今天|天氣"], 1)
        XCTAssertNil(lexicon2.data.globalHomophones["ㄕㄣ"])
    }

    func testImportMerge() throws {
        // Base lexicon
        let lexicon = UserLexicon(storageURL: tempLexiconURL)
        lexicon.recordHomophoneSelection(syllableRaw: "ㄋㄧˇ", word: "擬")
        lexicon.recordBigram(prev: "今天", next: "天氣")
        lexicon.recordUserWord(word: "好注音", syllablesRaw: ["ㄏㄠˇ", "ㄓㄨˋ", "ㄧㄣ"])
        lexicon.saveSync()

        // Create another dataset to import
        var otherData = UserLexiconData()
        otherData.globalHomophones["ㄋㄧˇ"] = ["擬": 2, "泥": 1]
        otherData.bigramCounts["今天|天氣"] = 3
        otherData.bigramCounts["天氣|很好"] = 1
        otherData.userWords["超讚"] = UserWordEntry(word: "超讚", syllablesRaw: ["ㄔㄠ", "ㄗㄢˋ"], count: 5)

        let otherURL = tempDirectoryURL.appendingPathComponent("other.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(otherData)
        try encoded.write(to: otherURL)

        // Merge into lexicon
        try lexicon.importData(from: otherURL, merge: true)

        // 擬 count should be 1 + 2 = 3
        XCTAssertEqual(lexicon.data.globalHomophones["ㄋㄧˇ"]?["擬"], 3)
        // 泥 count should be 1
        XCTAssertEqual(lexicon.data.globalHomophones["ㄋㄧˇ"]?["泥"], 1)
        // 今天|天氣 count should be 1 + 3 = 4
        XCTAssertEqual(lexicon.data.bigramCounts["今天|天氣"], 4)
        XCTAssertEqual(lexicon.data.bigramCounts["天氣|很好"], 1)
        // Both custom words should exist
        XCTAssertNotNil(lexicon.data.userWords["好注音"])
        XCTAssertEqual(lexicon.data.userWords["超讚"]?.count, 5)
    }

    func testImportInvalidFileThrowsError() {
        let lexicon = UserLexicon(storageURL: tempLexiconURL)
        let invalidURL = tempDirectoryURL.appendingPathComponent("invalid.json")
        try? "not a valid json".write(to: invalidURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try lexicon.importData(from: invalidURL, merge: false))
    }
}
