import Foundation

/// A word candidate in the lexicon.
public struct WordEntry: Sendable, Hashable {
    public let word: String
    public let syllables: [Syllable]
    /// Negative Log-Likelihood cost: -ln(P(w))
    public let unigramCost: Double

    public init(word: String, syllables: [Syllable], unigramCost: Double) {
        self.word = word
        self.syllables = syllables
        self.unigramCost = unigramCost
    }
}

/// Key representing a bigram transition: (prevWord, nextWord).
public struct BigramKey: Hashable, Sendable {
    public let prev: String
    public let next: String

    public init(prev: String, next: String) {
        self.prev = prev
        self.next = next
    }
}

/// Manages vocabulary entries and statistical language model costs.
public final class Lexicon: @unchecked Sendable {
    public static let sentenceStart = "<s>"
    public static let sentenceEnd = "</s>"

    /// All word entries.
    public private(set) var entries: [WordEntry] = []
    
    /// Unigram cost dictionary for fast lookup.
    public private(set) var unigramCosts: [String: Double] = [:]

    /// Bigram transition costs: -ln(P(next | prev)).
    public private(set) var bigramCosts: [BigramKey: Double] = [:]

    ///Default penalty added to unigram cost when a bigram transition is missing.
    public var backoffPenalty: Double = 3.5

    /// Cost for unseen single-character out-of-vocabulary fallback.
    public var oovCost: Double = 15.0

    /// Snapshot of initial base lexicon state prior to dynamic user learning adjustments.
    private var baseEntryCount: Int = 0
    private var baseUnigramCosts: [String: Double] = [:]
    private var baseBigramCosts: [BigramKey: Double] = [:]

    public init() {
        loadDefaultLexicon()
        captureBaseSnapshot()
    }

    public init(entries: [WordEntry], bigrams: [BigramKey: Double], backoffPenalty: Double = 3.5) {
        self.entries = entries
        self.bigramCosts = bigrams
        self.backoffPenalty = backoffPenalty
        for entry in entries {
            if let existing = self.unigramCosts[entry.word] {
                self.unigramCosts[entry.word] = min(existing, entry.unigramCost)
            } else {
                self.unigramCosts[entry.word] = entry.unigramCost
            }
        }
        captureBaseSnapshot()
    }

    /// Captures the current lexicon state as the clean baseline snapshot.
    public func captureBaseSnapshot() {
        self.baseEntryCount = self.entries.count
        self.baseUnigramCosts = self.unigramCosts
        self.baseBigramCosts = self.bigramCosts
    }

    /// Restores entries, unigramCosts, and bigramCosts back to the initial base snapshot.
    public func resetToBase() {
        if entries.count > baseEntryCount {
            entries.removeSubrange(baseEntryCount..<entries.count)
        }
        unigramCosts = baseUnigramCosts
        bigramCosts = baseBigramCosts
    }

    /// Loads a production lexicon from a binary file at `url`, or automatically finds `lexicon.bin`.
    public static func loadProduction(from url: URL? = nil) throws -> Lexicon {
        let targetURL: URL
        if let url = url {
            targetURL = url
        } else if let foundURL = BinaryLexiconReader.findDefaultBinaryURL() {
            targetURL = foundURL
        } else {
            throw BinaryLexiconReader.LexiconError.fileNotFound
        }

        let data = try Data(contentsOf: targetURL, options: .mappedIfSafe)
        return try BinaryLexiconReader.read(from: data)
    }

    /// Loads a binary lexicon from in-memory Data.
    public static func loadBinary(from data: Data) throws -> Lexicon {
        return try BinaryLexiconReader.read(from: data)
    }

    /// Calculates transition cost from `prevWord` to `nextWord`.
    public func transitionCost(from prevWord: String, to nextWord: String) -> Double {
        let key = BigramKey(prev: prevWord, next: nextWord)
        if let cost = bigramCosts[key] {
            return cost
        }

        // Backoff: Unigram cost + penalty
        if let unigram = unigramCosts[nextWord] {
            return unigram + backoffPenalty
        }

        // If nextWord is end of sentence, return small default
        if nextWord == Self.sentenceEnd {
            return 1.0
        }

        // Unseen word fallback
        return oovCost + backoffPenalty
    }

    /// Adds a word entry to the lexicon.
    public func addEntry(_ entry: WordEntry) {
        entries.append(entry)
        if let existing = unigramCosts[entry.word] {
            unigramCosts[entry.word] = min(existing, entry.unigramCost)
        } else {
            unigramCosts[entry.word] = entry.unigramCost
        }
    }

    /// Dynamically adjusts or overrides the unigram cost for a word.
    public func adjustUnigramCost(word: String, newCost: Double) {
        if let existing = unigramCosts[word] {
            unigramCosts[word] = min(existing, newCost)
        } else {
            unigramCosts[word] = newCost
        }
    }

    /// Boosts a word by reducing its unigram cost (increasing its likelihood).
    public func boostWordCost(word: String, discount: Double = 3.0, floor: Double = 1.0) {
        let current = unigramCosts[word] ?? 5.0
        let updated = max(floor, current - discount)
        unigramCosts[word] = updated
    }

    /// Adds a bigram transition.
    public func addBigram(prev: String, next: String, cost: Double) {
        bigramCosts[BigramKey(prev: prev, next: next)] = cost
    }

    /// Boosts a bigram transition by reducing its cost.
    public func boostBigram(prev: String, next: String, discount: Double = 2.0, floor: Double = 0.5) {
        let key = BigramKey(prev: prev, next: next)
        let current = bigramCosts[key] ?? 4.0
        bigramCosts[key] = max(floor, current - discount)
    }

    // MARK: - Built-in High Quality Mock Corpus
    private func loadDefaultLexicon() {
        let rawEntries: [(String, String, Double)] = [
            // High frequency phrases
            ("今天", "ㄐㄧㄣ ㄊㄧㄢ", 3.0),
            ("金天", "ㄐㄧㄣ ㄊㄧㄢ", 9.0),
            ("天氣", "ㄊㄧㄢ ㄑㄧˋ", 3.2),
            ("很好", "ㄏㄣˇ ㄏㄠˇ", 3.0),
            ("學校", "ㄒㄩㄝˊ ㄒㄧㄠˋ", 3.2),
            ("申請", "ㄕㄣ ㄑㄧㄥˇ", 3.4),
            ("再見", "ㄗㄞˋ ㄐㄧㄢˋ", 3.0),
            ("明天", "ㄇㄧㄥˊ ㄊㄧㄢ", 3.3),
            ("昨天", "ㄗㄨㄛˊ ㄊㄧㄢ", 3.5),
            ("大家", "ㄉㄚˋ ㄐㄧㄚ", 3.2),
            ("同學", "ㄊㄨㄥˊ ㄒㄩㄝˊ", 3.4),
            ("老師", "ㄌㄠˇ ㄕ", 3.2),
            ("朋友", "ㄆㄥˊ ㄧㄡˇ", 3.3),
            ("吃飯", "ㄔ ㄈㄢˋ", 3.6),
            ("高興", "ㄍㄠ ㄒㄧㄥˋ", 3.5),
            ("台灣", "ㄊㄞˊ ㄨㄢ", 3.2),
            ("台北", "ㄊㄞˊ ㄅㄟˇ", 3.3),
            ("電腦", "ㄉㄧㄢˋ ㄋㄠˇ", 3.5),
            ("程式", "ㄔㄥˊ ㄕˋ", 3.4),
            ("語言", "ㄩˇ ㄧㄢˊ", 3.5),
            ("開始", "ㄎㄞ ㄕˇ", 3.4),
            ("結束", "ㄐㄧㄝˊ ㄕㄨˋ", 3.6),
            ("可以", "ㄎㄜˇ ㄧˇ", 3.0),
            ("知道", "ㄓ ㄉㄠˋ", 3.1),
            ("現在", "ㄒㄧㄢˋ ㄗㄞˋ", 3.0),
            ("如果", "ㄖㄨˊ ㄍㄨㄛˇ", 3.4),

            // Single characters & function words
            ("我", "ㄨㄛˇ", 1.8),
            ("你", "ㄋㄧˇ", 2.0),
            ("他", "ㄊㄚ", 2.2),
            ("她", "ㄊㄚ", 2.5),
            ("它", "ㄊㄚ", 3.2),
            ("在", "ㄗㄞˋ", 2.0),
            ("再", "ㄗㄞˋ", 2.8),
            ("的", "˙ㄉㄜ", 1.2),
            ("了", "˙ㄌㄜ", 1.6),
            ("是", "ㄕˋ", 1.8),
            ("有", "ㄧㄡˇ", 2.0),
            ("好", "ㄏㄠˇ", 2.4),
            ("很", "ㄏㄣˇ", 2.5),
            ("也", "ㄧㄝˇ", 2.6),
            ("都", "ㄉㄡ", 2.5),
            ("就", "ㄐㄧㄡˋ", 2.4),
            ("去", "ㄑㄩˋ", 2.4),
            ("來", "ㄌㄞˊ", 2.5),
            ("要", "ㄧㄠˋ", 2.3),
            ("看", "ㄎㄢˋ", 2.8),
            ("說", "ㄕㄨㄛ", 2.6),
            ("想", "ㄒㄧㄤˇ", 2.7),
            ("做", "ㄗㄨㄛˋ", 2.7),
            ("作", "ㄗㄨㄛˋ", 3.0),

            // Single character parts of homophones
            ("今", "ㄐㄧㄣ", 4.2),
            ("金", "ㄐㄧㄣ", 4.5),
            ("斤", "ㄐㄧㄣ", 5.0),
            ("天", "ㄊㄧㄢ", 3.5),
            ("氣", "ㄑㄧˋ", 4.0),
            ("見", "ㄐㄧㄢˋ", 3.2),
            ("學", "ㄒㄩㄝˊ", 3.4),
            ("校", "ㄒㄧㄠˋ", 3.8),
            ("申", "ㄕㄣ", 4.5),
            ("身", "ㄕㄣ", 4.0),
            ("深", "ㄕㄣ", 4.3),
            ("請", "ㄑㄧㄥˇ", 3.3),
            ("晴", "ㄑㄧㄥˊ", 4.2),
            ("情", "ㄑㄧㄥˊ", 3.8)
        ]

        for (word, zhuyin, cost) in rawEntries {
            let syllables = Syllable.parseSequence(zhuyin)
            addEntry(WordEntry(word: word, syllables: syllables, unigramCost: cost))
        }

        // Transitions
        let transitions: [(String, String, Double)] = [
            // Sentence starts
            (Self.sentenceStart, "今天", 2.0),
            (Self.sentenceStart, "金天", 9.5),
            (Self.sentenceStart, "我", 1.8),
            (Self.sentenceStart, "你", 2.0),
            (Self.sentenceStart, "大家", 2.4),
            (Self.sentenceStart, "現在", 2.2),
            (Self.sentenceStart, "如果", 2.5),

            // "今天天氣很好"
            ("今天", "天氣", 1.4),
            ("金天", "天氣", 10.0),
            ("天氣", "很好", 1.1),
            ("很好", Self.sentenceEnd, 1.0),

            // "我在學校", "我在申請學校"
            ("我", "在", 1.3),
            ("我", "再", 8.0),
            ("在", "學校", 1.2),
            ("再", "學校", 9.0),
            ("在", "申請", 1.4),
            ("再", "申請", 8.5),
            ("申請", "學校", 1.2),
            ("學校", Self.sentenceEnd, 1.0),

            // "再見"
            ("再", "見", 1.0),
            ("在", "見", 8.5),
            ("再見", Self.sentenceEnd, 1.0),

            // General transitions
            ("在", "這裡", 1.5),
            // 介詞「在」+ 限定詞/處所 vs 副詞「再」+ 次數
            ("在", "任何", 1.0),
            ("再", "任何", 9.5),
            ("在", "所有", 1.2),
            ("再", "所有", 9.0),
            ("在", "每個", 1.2),
            ("再", "每個", 9.0),
            ("在", "哪裡", 1.2),
            ("再", "哪裡", 9.0),
            ("任何", "位置", 1.5),
            ("任何", "地方", 1.5),
            ("再", "一次", 1.0),
            ("在", "一次", 9.5),
            ("再", "次", 1.2),
            ("在", "次", 9.5),
            // 「的」 vs 「得」
            ("覺", "得", 1.0),
            ("覺", "的", 9.5),
            ("覺得", "很好", 1.2),
            ("記", "得", 1.0),
            ("記", "的", 9.5),
            ("變", "得", 1.1),
            ("變", "的", 9.0),
            ("我", "的", 1.1),
            ("我", "得", 8.5),
            ("你", "的", 1.1),
            ("好", "的", 1.2),
            ("真", "的", 1.2),
            ("的", "字", 1.8),
            ("字", "是否", 2.0),
            ("在", "看", 2.0),
            ("在", "做", 2.0),
            ("我", "想", 1.8),
            ("我", "要", 1.7),
            ("很", "好", 1.5),
            ("很", "高興", 1.6),
            ("高興", Self.sentenceEnd, 1.0),
            ("大家", "好", 1.2),
            ("同學", "們", 1.5),
            ("老師", "好", 1.2),
            ("程式", "語言", 1.3),
            ("電腦", "程式", 1.5)
        ]

        for (prev, next, cost) in transitions {
            addBigram(prev: prev, next: next, cost: cost)
        }
    }
}
