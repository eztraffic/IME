import XCTest
@testable import ZhuyinEngine

final class LatticeTests: XCTestCase {
    func testLatticeBuilding() {
        let lexicon = Lexicon()
        let trie = Trie()
        trie.build(from: lexicon)
        let builder = LatticeBuilder(trie: trie, lexicon: lexicon)

        let syllables = Syllable.parseSequence("ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ")
        let lattice = builder.buildLattice(for: syllables)

        XCTAssertEqual(lattice.syllables.count, 6)
        XCTAssertEqual(lattice.startNode.word, Lexicon.sentenceStart)
        XCTAssertEqual(lattice.endNode.word, Lexicon.sentenceEnd)

        // Nodes starting at 0 should include "今", "今天", "金天", etc.
        let startWords = lattice.nodesStartingAt[0].map { $0.word }
        XCTAssertTrue(startWords.contains("今天"))
        XCTAssertTrue(startWords.contains("今"))

        // Nodes ending at 6 should connect to end
        let endCandidates = lattice.nodesEndingAt[6].map { $0.word }
        XCTAssertTrue(endCandidates.contains("很好"))
        XCTAssertTrue(endCandidates.contains("好"))
    }
}
