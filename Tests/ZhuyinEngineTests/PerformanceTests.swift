import XCTest
@testable import ZhuyinEngine

final class PerformanceTests: XCTestCase {
    var engine: ZhuyinEngine!

    override func setUp() {
        super.setUp()
        engine = ZhuyinEngine()
    }

    func testTwentySyllablesUnder5ms() {
        // 20 syllables sequence
        let zhuyin = "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ ㄨㄛˇ ㄗㄞˋ ㄒㄩㄝˊ ㄒㄧㄠˋ ㄕㄣ ㄑㄧㄥˇ ㄒㄩㄝˊ ㄒㄧㄠˋ ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ"
        let syllables = Syllable.parseSequence(zhuyin)
        XCTAssertEqual(syllables.count, 20, "Should have exactly 20 syllables")

        // Warm up
        for _ in 0..<5 {
            _ = engine.decode(syllables: syllables, topK: 3)
        }

        // Benchmark 100 iterations
        let iterations = 100
        var totalMs = 0.0
        var maxMs = 0.0

        for _ in 0..<iterations {
            let res = engine.decode(syllables: syllables, topK: 3)
            totalMs += res.durationMs
            if res.durationMs > maxMs {
                maxMs = res.durationMs
            }
        }

        let avgMs = totalMs / Double(iterations)
        print("Performance Benchmark (20 syllables): avg = \(String(format: "%.3f", avgMs)) ms, max = \(String(format: "%.3f", maxMs)) ms")

        XCTAssertLessThan(avgMs, 5.0, "Average decoding time must be strictly under 5.0 ms")
        XCTAssertLessThan(maxMs, 30.0, "Maximum decoding time must be strictly under 30.0 ms")
    }

    func testLongSentenceSpatialTolerancePerformance() {
        // 30 syllables long sentence
        let longZhuyin = "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ ㄨㄛˇ ㄗㄞˋ ㄒㄩㄝˊ ㄒㄧㄠˋ ㄕㄣ ㄑㄧㄥˇ ㄒㄩㄝˊ ㄒㄧㄠˋ ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ ㄉㄚˋ ㄐㄧㄚ ㄉㄡ ㄏㄣˇ ㄍㄠ ㄒㄧㄥˋ"
        let syllables = Syllable.parseSequence(longZhuyin)
        XCTAssertGreaterThanOrEqual(syllables.count, 25)

        // Explicitly enable spatial error tolerance
        engine.isSpatialToleranceEnabled = true

        // Warm up
        for _ in 0..<5 {
            _ = engine.decode(syllables: syllables, topK: 3)
        }

        let iterations = 50
        var totalMs = 0.0
        var maxMs = 0.0

        for _ in 0..<iterations {
            let res = engine.decode(syllables: syllables, topK: 3)
            totalMs += res.durationMs
            if res.durationMs > maxMs {
                maxMs = res.durationMs
            }
        }

        let avgMs = totalMs / Double(iterations)
        print("Performance Benchmark (Long sentence 27+ syllables with Spatial Model): avg = \(String(format: "%.3f", avgMs)) ms, max = \(String(format: "%.3f", maxMs)) ms")

        XCTAssertLessThan(avgMs, 4.0, "Long sentence with spatial tolerance should average under 4.0 ms thanks to active horizon windowing")
    }
}
