import XCTest
@testable import ZhuyinEngine

final class ViterbiDecoderTests: XCTestCase {
    var engine: ZhuyinEngine!

    override func setUp() {
        super.setUp()
        engine = ZhuyinEngine()
    }

    func testJinTianWeatherDisambiguation() {
        // "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ" -> "今天天氣很好"
        let result = engine.decode(zhuyin: "ㄐㄧㄣ ㄊㄧㄢ ㄊㄧㄢ ㄑㄧˋ ㄏㄣˇ ㄏㄠˇ", topK: 3)
        XCTAssertEqual(result.bestText, "今天天氣很好")
        XCTAssertFalse(result.candidates.isEmpty)
        // Ensure candidates are sorted by ascending cost
        for i in 0..<(result.candidates.count - 1) {
            XCTAssertLessThanOrEqual(result.candidates[i].totalCost, result.candidates[i + 1].totalCost)
        }
    }

    func testZaiSchoolDisambiguation() {
        // "ㄨㄛˇ ㄗㄞˋ ㄒㄩㄝˊ ㄒㄧㄠˋ" -> "我在學校" (not "再")
        let result = engine.decode(zhuyin: "ㄨㄛˇ ㄗㄞˋ ㄒㄩㄝˊ ㄒㄧㄠˋ", topK: 3)
        XCTAssertEqual(result.bestText, "我在學校")
    }

    func testZaiApplySchoolDisambiguation() {
        // "ㄨㄛˇ ㄗㄞˋ ㄕㄣ ㄑㄧㄥˇ ㄒㄩㄝˊ ㄒㄧㄠˋ" -> "我在申請學校"
        let result = engine.decode(zhuyin: "ㄨㄛˇ ㄗㄞˋ ㄕㄣ ㄑㄧㄥˇ ㄒㄩㄝˊ ㄒㄧㄠˋ", topK: 3)
        XCTAssertEqual(result.bestText, "我在申請學校")
    }

    func testZaiJianDisambiguation() {
        // "ㄗㄞˋ ㄐㄧㄢˋ" -> "再見" (not "在見")
        let result = engine.decode(zhuyin: "ㄗㄞˋ ㄐㄧㄢˋ", topK: 3)
        XCTAssertEqual(result.bestText, "再見")
    }
}
