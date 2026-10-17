import Foundation

/// A term annotated with its Zhuyin pronunciation, heterophony candidates, and ambiguity status.
public struct AnnotatedTerm: Sendable, Hashable {
    public let word: String
    public let count: Int
    public let isNewWord: Bool
    public var selectedSyllables: [Syllable]
    /// Per-character candidate syllables sorted by preference.
    public let candidateSyllablesPerChar: [[Syllable]]
    /// Whole-word pronunciation combinations for quick selection in review UI (e.g., ["ㄔㄨㄥˊ ㄒㄧㄝˇ", "ㄓㄨㄥˋ ㄒㄧㄝˇ"]).
    public let candidateWordPronunciations: [[Syllable]]
    /// True if at least one character in the word has unresolved heterophony ambiguity.
    public let hasAmbiguity: Bool
    public let pmi: Double
    /// Computed language model unigram cost from ModelBlender.
    public var estimatedCost: Double
    /// Whether this term is selected for ingestion in the review workflow.
    public var isSelected: Bool

    public init(
        word: String,
        count: Int,
        isNewWord: Bool,
        selectedSyllables: [Syllable],
        candidateSyllablesPerChar: [[Syllable]],
        candidateWordPronunciations: [[Syllable]],
        hasAmbiguity: Bool,
        pmi: Double = 0.0,
        estimatedCost: Double = 2.0,
        isSelected: Bool = true
    ) {
        self.word = word
        self.count = count
        self.isNewWord = isNewWord
        self.selectedSyllables = selectedSyllables
        self.candidateSyllablesPerChar = candidateSyllablesPerChar
        self.candidateWordPronunciations = candidateWordPronunciations
        self.hasAmbiguity = hasAmbiguity
        self.pmi = pmi
        self.estimatedCost = estimatedCost
        self.isSelected = isSelected
    }

    /// Formatted space-separated Zhuyin string for the currently selected syllables.
    public var selectedZhuyinString: String {
        selectedSyllables.map { $0.raw }.joined(separator: " ")
    }
}

/// Grapheme-to-Phoneme (G2P) annotator that assigns Zhuyin syllables to Chinese words and disambiguates heterophonies.
public final class G2PAnnotator: @unchecked Sendable {
    public let reverseLookup: ReverseZhuyinLookup

    public init(reverseLookup: ReverseZhuyinLookup) {
        self.reverseLookup = reverseLookup
    }

    /// Annotates a newly discovered or known word with its most likely Zhuyin syllables and heterophony alternatives.
    public func annotate(
        word: String,
        count: Int,
        isNewWord: Bool,
        pmi: Double = 0.0,
        estimatedCost: Double = 2.0
    ) -> AnnotatedTerm? {
        let chars = Array(word)
        let n = chars.count
        guard n > 0 else { return nil }

        // Gather per-character candidate syllables
        var perCharCandidates: [[Syllable]] = []
        perCharCandidates.reserveCapacity(n)
        for ch in chars {
            let readings = reverseLookup.lookupCharacter(ch).map { $0.syllable }
            guard !readings.isEmpty else {
                return nil
            }
            perCharCandidates.append(readings)
        }

        // Case 1: Word already exists in ReverseZhuyinLookup
        let existingWordReadings = reverseLookup.lookupWord(word)
        if !existingWordReadings.isEmpty {
            let bestSyllables = existingWordReadings[0].syllables
            let wordPronunciations = existingWordReadings.map { $0.syllables }
            let ambiguous: Bool
            if existingWordReadings.count >= 2 {
                ambiguous = (existingWordReadings[1].cost - existingWordReadings[0].cost) <= 2.2
            } else {
                ambiguous = false
            }
            return AnnotatedTerm(
                word: word,
                count: count,
                isNewWord: isNewWord,
                selectedSyllables: bestSyllables,
                candidateSyllablesPerChar: perCharCandidates,
                candidateWordPronunciations: wordPronunciations,
                hasAmbiguity: ambiguous,
                pmi: pmi,
                estimatedCost: estimatedCost,
                isSelected: true
            )
        }

        // Case 2: Out-Of-Vocabulary (OOV) multi-character term — perform contextual compound disambiguation
        var resolvedSyllables = [Syllable?](repeating: nil, count: n)
        var resolvedByCompound = [Bool](repeating: false, count: n)

        // 2a. Check 3-character sub-compounds first, then 2-character sub-compounds
        if n >= 3 {
            for spanLen in stride(from: min(3, n), through: 2, by: -1) {
                for start in 0...(n - spanLen) {
                    let subWord = String(chars[start..<(start + spanLen)])
                    if let compSyls = reverseLookup.compoundReadings[subWord], compSyls.count == spanLen {
                        for offset in 0..<spanLen {
                            if resolvedSyllables[start + offset] == nil {
                                resolvedSyllables[start + offset] = compSyls[offset]
                                resolvedByCompound[start + offset] = true
                            }
                        }
                    }
                }
            }
        }

        // 2b. Fill remaining character positions with primary character reading and check for ambiguity
        var chosenSyllables: [Syllable] = []
        chosenSyllables.reserveCapacity(n)
        var hasUnresolvedAmbiguity = false

        for i in 0..<n {
            if let compSyl = resolvedSyllables[i] {
                chosenSyllables.append(compSyl)
                // Put the compound-resolved syllable at the front of perCharCandidates[i]
                var charList = perCharCandidates[i].filter { $0 != compSyl }
                charList.insert(compSyl, at: 0)
                perCharCandidates[i] = charList
            } else {
                let primary = perCharCandidates[i][0]
                chosenSyllables.append(primary)
                if !resolvedByCompound[i] && reverseLookup.hasCompetitiveHeterophony(for: chars[i]) {
                    hasUnresolvedAmbiguity = true
                }
            }
        }

        // Build whole-word pronunciation alternatives (up to 6 combinations) for UI dropdown selection
        let wordPronunciations = buildWordPronunciationAlternatives(
            chosen: chosenSyllables,
            perCharCandidates: perCharCandidates,
            resolvedByCompound: resolvedByCompound,
            maxAlternatives: 6
        )

        return AnnotatedTerm(
            word: word,
            count: count,
            isNewWord: isNewWord,
            selectedSyllables: chosenSyllables,
            candidateSyllablesPerChar: perCharCandidates,
            candidateWordPronunciations: wordPronunciations,
            hasAmbiguity: hasUnresolvedAmbiguity,
            pmi: pmi,
            estimatedCost: estimatedCost,
            isSelected: true
        )
    }

    private func buildWordPronunciationAlternatives(
        chosen: [Syllable],
        perCharCandidates: [[Syllable]],
        resolvedByCompound: [Bool],
        maxAlternatives: Int
    ) -> [[Syllable]] {
        var results: [[Syllable]] = [chosen]
        let n = chosen.count

        for i in 0..<n {
            // Even if resolved by compound, allow alternative readings in dropdown in case user wants to override
            let alternatives = perCharCandidates[i].prefix(3)
            guard alternatives.count > 1 else { continue }

            var expanded: [[Syllable]] = []
            for base in results {
                for alt in alternatives {
                    var modified = base
                    modified[i] = alt
                    if !expanded.contains(modified) {
                        expanded.append(modified)
                    }
                    if expanded.count >= maxAlternatives { break }
                }
                if expanded.count >= maxAlternatives { break }
            }
            results = expanded
            if results.count >= maxAlternatives { break }
        }

        return results
    }
}
