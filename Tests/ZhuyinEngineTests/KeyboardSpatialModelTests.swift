import XCTest
@testable import ZhuyinEngine

final class KeyboardSpatialModelTests: XCTestCase {
    func testKeyCoordinatesAndDistances() {
        let model = KeyboardSpatialModel.shared

        // Test distance from 'w' to adjacent keys
        let distWtoQ = model.distance(between: "w", and: "q")
        let distWtoE = model.distance(between: "w", and: "e")
        let distWtoS = model.distance(between: "w", and: "s")

        XCTAssertNotNil(distWtoQ)
        XCTAssertNotNil(distWtoE)
        XCTAssertNotNil(distWtoS)

        // Horizontal neighbors have distance 1.0
        XCTAssertEqual(distWtoQ!, 1.0, accuracy: 0.01)
        XCTAssertEqual(distWtoE!, 1.0, accuracy: 0.01)

        // Directly below neighbor 's'
        XCTAssertEqual(distWtoS!, 1.04, accuracy: 0.05)

        // Non-neighbor 'p' should have much larger distance
        let distWtoP = model.distance(between: "w", and: "p")
        XCTAssertNotNil(distWtoP)
        XCTAssertGreaterThan(distWtoP!, 5.0)
    }

    func testAdjacentKeysForW() {
        let model = KeyboardSpatialModel.shared
        let neighbors = model.adjacentKeys(for: "w", maxDistance: 1.35)
        let neighborKeys = Set(neighbors.map { $0.key })

        // 'w' should have neighbors 'q', 'e', 's', '2', '3', 'a'
        XCTAssertTrue(neighborKeys.contains("q"), "w neighbors should contain q")
        XCTAssertTrue(neighborKeys.contains("e"), "w neighbors should contain e")
        XCTAssertTrue(neighborKeys.contains("s"), "w neighbors should contain s")
        XCTAssertTrue(neighborKeys.contains("2"), "w neighbors should contain 2")
        XCTAssertFalse(neighborKeys.contains("p"), "w neighbors should NOT contain p")
    }

    func testGenerateCandidatesForSyllableWithInitialW() {
        let model = KeyboardSpatialModel.shared
        // Syllable: ㄊㄧㄢ (keys: w u 0, tone first)
        let tian = Syllable(initial: "ㄊ", medial: "ㄧ", rhyme: "ㄢ", tone: .first)
        let candidates = model.generateCandidates(for: tian)

        XCTAssertFalse(candidates.isEmpty)

        // 1st candidate must be exact original syllable with penalty 0.0
        XCTAssertEqual(candidates[0].syllable, tian)
        XCTAssertEqual(candidates[0].penalty, 0.0)

        // Neighbor initials for 'w' include:
        // 'q' -> ㄆ (ㄆㄧㄢ)
        // 'e' -> ㄍ (ㄍㄧㄢ)
        // 's' -> ㄋ (ㄋㄧㄢ)
        let candidateInitials = Set(candidates.compactMap { $0.syllable.initial })
        XCTAssertTrue(candidateInitials.contains("ㄆ"), "Candidates should include ㄆ from neighbor q")
        XCTAssertTrue(candidateInitials.contains("ㄍ"), "Candidates should include ㄍ from neighbor e")
        XCTAssertTrue(candidateInitials.contains("ㄋ"), "Candidates should include ㄋ from neighbor s")

        // Penalties for neighbors must be > 0.0
        for cand in candidates.dropFirst() {
            XCTAssertGreaterThan(cand.penalty, 0.0)
        }
    }

    func testComposerSpatialIntegration() {
        let composer = BopomofoComposer()
        XCTAssertFalse(composer.isSpatialModelEnabled, "Spatial model should be disabled by default")

        // Explicitly enable spatial model for testing
        composer.isSpatialModelEnabled = true

        // Type 'w', 'u', '0', Space -> ㄊㄧㄢ
        composer.handleKeys("wu0 ")
        XCTAssertEqual(composer.completedSyllables.count, 1)

        let slots = composer.allCandidateSlots()
        XCTAssertEqual(slots.count, 1)
        XCTAssertGreaterThan(slots[0].count, 1)
        XCTAssertEqual(slots[0][0].syllable.raw, "ㄊㄧㄢ")
        XCTAssertEqual(slots[0][0].penalty, 0.0)

        // Toggle spatial model off
        composer.isSpatialModelEnabled = false
        let slotsDisabled = composer.allCandidateSlots()
        XCTAssertEqual(slotsDisabled.count, 1)
        XCTAssertEqual(slotsDisabled[0].count, 1) // Only original syllable
    }
}
