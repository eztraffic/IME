import Foundation

/// Reading candidate for a Chinese word or character with its associated language model cost.
public struct PronunciationCandidate: Sendable, Hashable {
    public let syllables: [Syllable]
    public let cost: Double

    public init(syllables: [Syllable], cost: Double) {
        self.syllables = syllables
        self.cost = cost
    }

    /// Formatted space-separated Zhuyin string (e.g. "ㄧㄣˊ ㄏㄤˊ").
    public var displayString: String {
        syllables.map { $0.raw }.joined(separator: " ")
    }
}

/// Provides fast reverse lookup from Chinese characters and words to Zhuyin syllable sequences.
public final class ReverseZhuyinLookup: @unchecked Sendable {
    /// Maps a word or single character string to its sorted pronunciation candidates (lowest cost / highest frequency first).
    public private(set) var wordReadings: [String: [PronunciationCandidate]] = [:]

    /// Maps a 2-character compound word to its primary syllable pair, used for contextual heterophony disambiguation.
    public private(set) var compoundReadings: [String: [Syllable]] = [:]

    public init(lexicon: Lexicon) {
        buildIndex(from: lexicon)
    }

    /// Rebuilds the reverse lookup index from the provided lexicon.
    public func buildIndex(from lexicon: Lexicon) {
        var tempReadings: [String: [PronunciationCandidate]] = [:]
        tempReadings.reserveCapacity(lexicon.unigramCosts.count)

        for entry in lexicon.entries {
            guard !entry.word.isEmpty, !entry.syllables.isEmpty else { continue }
            // Only index entries where syllable count matches character count
            guard entry.word.count == entry.syllables.count else { continue }

            let candidate = PronunciationCandidate(syllables: entry.syllables, cost: entry.unigramCost)
            tempReadings[entry.word, default: []].append(candidate)
        }

        var finalizedReadings: [String: [PronunciationCandidate]] = [:]
        finalizedReadings.reserveCapacity(tempReadings.count)
        var compounds: [String: [Syllable]] = [:]

        for (word, list) in tempReadings {
            // Sort by ascending cost (most common reading first) and deduplicate identical syllable sequences
            let sorted = list.sorted { $0.cost < $1.cost }
            var unique: [PronunciationCandidate] = []
            var seenSyllables = Set<[Syllable]>()
            for item in sorted {
                if !seenSyllables.contains(item.syllables) {
                    seenSyllables.insert(item.syllables)
                    unique.append(item)
                }
            }
            finalizedReadings[word] = unique

            if word.count >= 2, let best = unique.first {
                compounds[word] = best.syllables
            }
        }

        self.wordReadings = finalizedReadings
        self.compoundReadings = compounds
    }

    /// Looks up all known syllable sequences for a word or character, sorted from most likely (lowest cost) to least likely.
    public func lookupWord(_ word: String) -> [PronunciationCandidate] {
        return wordReadings[word] ?? []
    }

    /// Looks up all known single-syllable readings for a single Chinese character, sorted by ascending cost.
    public func lookupCharacter(_ char: Character) -> [(syllable: Syllable, cost: Double)] {
        let key = String(char)
        guard let candidates = wordReadings[key] else { return [] }
        return candidates.compactMap { cand in
            guard let first = cand.syllables.first else { return nil }
            return (syllable: first, cost: cand.cost)
        }
    }

    /// Returns whether a character has multiple competitive readings (heterophony / 破音字) within a given cost margin.
    public func hasCompetitiveHeterophony(for char: Character, costMargin: Double = 2.2) -> Bool {
        let readings = lookupCharacter(char)
        guard readings.count >= 2 else { return false }
        let bestCost = readings[0].cost
        let secondCost = readings[1].cost
        // Ignore pure neutral-tone vs full-tone duplicates of function words if needed, or check cost proximity
        return (secondCost - bestCost) <= costMargin && secondCost <= 10.5
    }
}
