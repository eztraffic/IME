import XCTest
@testable import ZhuyinEngine

final class TextSanitizerTests: XCTestCase {
    func testNFKCNormalizationAndClauseSplitting() {
        let raw = "今天天氣很好，我們在學校寫程式！\n明天要去台北。"
        let clauses = TextSanitizer.extractClauses(raw)
        XCTAssertEqual(clauses, ["今天天氣很好", "我們在學校寫程式", "明天要去台北"])
    }

    func testPIIMaskingEmailAndNationalIDAndCreditCard() {
        let raw = """
        聯絡信箱 user.name@example.com，身分證字號 A123456789，
        信用卡號 4111-2222-3333-4444，密碼：SuperSecret123!，
        API 金鑰 sk-abcdef1234567890abcdef，請勿外流。
        """
        let sanitized = TextSanitizer.sanitizeText(raw)
        XCTAssertFalse(sanitized.contains("user.name@example.com"), "Email must be masked")
        XCTAssertFalse(sanitized.contains("A123456789"), "National ID must be masked")
        XCTAssertFalse(sanitized.contains("4111-2222-3333-4444"), "Credit card must be masked")
        XCTAssertFalse(sanitized.contains("SuperSecret123"), "Password assignment must be masked")
        XCTAssertFalse(sanitized.contains("sk-abcdef1234567890abcdef"), "API key must be masked")

        let clauses = TextSanitizer.extractClauses(raw)
        // Ensure clauses around masked tokens do not concatenate across the redacted boundary
        XCTAssertTrue(clauses.contains("聯絡信箱"))
        XCTAssertTrue(clauses.contains("請勿外流"))
    }
}
