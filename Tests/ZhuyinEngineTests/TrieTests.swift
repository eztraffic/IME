import XCTest
@testable import ZhuyinEngine

final class TrieTests: XCTestCase {
    func testTrieInsertionAndCommonPrefixSearch() {
        let trie = Trie()
        let sylJin = Syllable(parsing: "ㄐㄧㄣ")!
        let sylTian = Syllable(parsing: "ㄊㄧㄢ")!

        let entry1 = WordEntry(word: "今", syllables: [sylJin], unigramCost: 4.2)
        let entry2 = WordEntry(word: "今天", syllables: [sylJin, sylTian], unigramCost: 3.0)

        trie.insert(entry1)
        trie.insert(entry2)

        let sequence = [sylJin, sylTian]
        let matches = trie.commonPrefixSearch(in: sequence, from: 0)

        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.contains { $0.entry.word == "今" && $0.length == 1 })
        XCTAssertTrue(matches.contains { $0.entry.word == "今天" && $0.length == 2 })

        let matchesFrom1 = trie.commonPrefixSearch(in: sequence, from: 1)
        XCTAssertEqual(matchesFrom1.count, 0)
    }
}
