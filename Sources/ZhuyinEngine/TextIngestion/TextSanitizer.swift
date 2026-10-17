import Foundation

/// Preprocesses raw article text with Unicode NFKC normalization, PII masking, and clause segmentation.
public enum TextSanitizer {
    /// Placeholder token inserted where sensitive PII is masked, acting as a hard sentence boundary.
    public static let maskPlaceholder = " [REDACTED] "

    private static let piiPatterns: [NSRegularExpression] = {
        let rawPatterns = [
            // URLs
            #"https?://[^\s\u4e00-\u9fff]+"#,
            // Email addresses
            #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            // Taiwan National ID / ARC (身分證字號 / 統一證號)
            #"(?<![A-Za-z0-9])[A-Z][1289ABCD]\d{8}(?![A-Za-z0-9])"#,
            // Credit card numbers (13~19 digits with optional spaces or hyphens)
            #"(?<!\d)(?:\d{4}[\s\-]?){3}\d{1,7}(?!\d)"#,
            // Taiwan mobile / phone numbers
            #"(?<!\d)09\d{2}[\s\-]?\d{3}[\s\-]?\d{3}(?!\d)"#,
            // API keys, bearer tokens, hex hashes, or long secret strings
            #"\b(?:sk-[A-Za-z0-9_\-]{12,}|gh[pousr]_[A-Za-z0-9]{12,}|AIza[0-9A-Za-z_\-]{20,}|[A-Za-z0-9_\-]{24,})\b"#,
            // Key-value password/token assignments (e.g., password: xxx, token=xxx, 密碼：xxx)
            #"(?:(?i:password|passwd|secret|api[_\-]?key|token)|密碼|通行碼|驗證碼)\s*[:=：]\s*[^\s，。！？；\n]+"#
        ]
        return rawPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    /// Regex matching contiguous runs of CJK Unified Ideographs (excluding Bopomofo/punctuation).
    private static let hanClauseRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"\p{Han}+"#, options: [])
    }()

    /// Performs NFKC normalization and masks sensitive PII patterns in the input text.
    public static func sanitizeText(_ rawText: String) -> String {
        guard !rawText.isEmpty else { return "" }

        // 1. Unicode NFKC Normalization (converts fullwidth ASCII/numbers to standard forms, composes characters)
        var text = rawText.precomposedStringWithCompatibilityMapping

        // 2. Mask PII patterns
        for regex in piiPatterns {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: maskPlaceholder)
        }

        return text
    }

    /// Sanitizes raw text and splits it into pure Chinese clauses separated by punctuation, newlines, or non-Han characters.
    /// Strict boundary splitting prevents cross-sentence or cross-punctuation false bigrams.
    public static func extractClauses(_ rawText: String) -> [String] {
        let sanitized = sanitizeText(rawText)
        guard !sanitized.isEmpty else { return [] }

        let nsRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        let matches = hanClauseRegex.matches(in: sanitized, options: [], range: nsRange)

        var clauses: [String] = []
        clauses.reserveCapacity(matches.count)

        for match in matches {
            if let range = Range(match.range, in: sanitized) {
                let clause = String(sanitized[range])
                if !clause.isEmpty {
                    clauses.append(clause)
                }
            }
        }

        return clauses
    }
}
