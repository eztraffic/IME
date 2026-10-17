import Foundation

/// Represents the tone in Mandarin Zhuyin (Bopomofo).
public enum Tone: Int, Sendable, Hashable, CustomStringConvertible, CaseIterable {
    case first = 1   // 陰平 (通常無符號或 ˉ)
    case second = 2  // 陽平 (ˊ)
    case third = 3   // 上聲 (ˇ)
    case fourth = 4  // 去聲 (ˋ)
    case neutral = 5 // 輕聲 (˙)

    public var symbol: String {
        switch self {
        case .first: return ""
        case .second: return "ˊ"
        case .third: return "ˇ"
        case .fourth: return "ˋ"
        case .neutral: return "˙"
        }
    }

    public var description: String {
        return symbol
    }
}

/// Represents a single Zhuyin syllable composed of Initial, Medial, Rhyme, and Tone.
public struct Syllable: Sendable, Hashable, Equatable, CustomStringConvertible {
    public static let initials: Set<Character> = [
        "ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ",
        "ㄍ", "ㄎ", "ㄏ", "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ",
        "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"
    ]

    public static let medials: Set<Character> = [
        "ㄧ", "ㄨ", "ㄩ"
    ]

    public static let rhymes: Set<Character> = [
        "ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ",
        "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"
    ]

    public static let toneSymbols: [Character: Tone] = [
        "ˊ": .second,
        "ˇ": .third,
        "ˋ": .fourth,
        "˙": .neutral,
        "ˉ": .first
    ]

    public let initial: Character?
    public let medial: Character?
    public let rhyme: Character?
    public let tone: Tone

    /// Canonical normalized string (Initial + Medial + Rhyme + ToneSymbol).
    public let raw: String

    public init(initial: Character? = nil, medial: Character? = nil, rhyme: Character? = nil, tone: Tone = .first) {
        self.initial = initial
        self.medial = medial
        self.rhyme = rhyme
        self.tone = tone

        var str = ""
        if let initial = initial { str.append(initial) }
        if let medial = medial { str.append(medial) }
        if let rhyme = rhyme { str.append(rhyme) }
        str.append(tone.symbol)
        self.raw = str
    }

    /// Parses a single Zhuyin token string (e.g. "ㄐㄧㄣ", "ㄑㄧˋ", "˙ㄉㄜ", "ㄉㄜ˙", "ㄏㄣˇ").
    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var tone: Tone = .first
        var remaining = [Character]()

        for ch in trimmed {
            if let detectedTone = Self.toneSymbols[ch] {
                tone = detectedTone
            } else {
                remaining.append(ch)
            }
        }

        var initial: Character?
        var medial: Character?
        var rhyme: Character?

        var idx = 0
        if idx < remaining.count && Self.initials.contains(remaining[idx]) {
            initial = remaining[idx]
            idx += 1
        }

        if idx < remaining.count && Self.medials.contains(remaining[idx]) {
            medial = remaining[idx]
            idx += 1
        }

        if idx < remaining.count && Self.rhymes.contains(remaining[idx]) {
            rhyme = remaining[idx]
            idx += 1
        }

        // If extra characters remain, fallback to raw storage if at least one component matched,
        // or check if remaining characters can form valid components.
        guard initial != nil || medial != nil || rhyme != nil || !remaining.isEmpty else {
            return nil
        }

        self.initial = initial
        self.medial = medial
        self.rhyme = rhyme
        self.tone = tone

        var str = ""
        if let initial = initial { str.append(initial) }
        if let medial = medial { str.append(medial) }
        if let rhyme = rhyme { str.append(rhyme) }
        str.append(tone.symbol)
        self.raw = str.isEmpty ? String(remaining) : str
    }

    public var description: String {
        return raw
    }

    /// Parses a space-separated sequence of Zhuyin syllables.
    public static func parseSequence(_ text: String) -> [Syllable] {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        return parts.compactMap { Syllable(parsing: String($0)) }
    }
}
