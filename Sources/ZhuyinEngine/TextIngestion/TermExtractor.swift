import Foundation

/// Represents a newly discovered out-of-vocabulary (OOV) multi-character term from article analysis.
public struct DiscoveredTerm: Sendable, Hashable {
    public let word: String
    public let count: Int
    public let pmi: Double
    public let leftEntropy: Double
    public let rightEntropy: Double

    public init(word: String, count: Int, pmi: Double, leftEntropy: Double, rightEntropy: Double) {
        self.word = word
        self.count = count
        self.pmi = pmi
        self.leftEntropy = leftEntropy
        self.rightEntropy = rightEntropy
    }

    /// Combined quality score weighting frequency, PMI cohesion, and boundary freedom.
    public var qualityScore: Double {
        let minEntropy = min(leftEntropy, rightEntropy)
        return log(Double(count) + 1.0) * (pmi + minEntropy * 1.5)
    }
}

/// Aggregated statistics extracted from segmented clauses and OOV phrase discovery.
public struct ExtractedCorpusStats: Sendable {
    /// Segmented clauses, where each clause is an array of segmented words.
    public let segmentedClauses: [[String]]
    /// Counts of known multi-character words (length 2..6) observed in the corpus.
    public let knownWordCounts: [String: Int]
    /// Counts of single-character tokens observed in the corpus.
    public let singleCharCounts: [String: Int]
    /// Adjacent word transition counts: ["prevWord|nextWord": count].
    public let bigramCounts: [String: Int]
    /// Contextual single-character counts given the immediately preceding word: ["prevWord": ["char": count]].
    public let contextualCharCounts: [String: [String: Int]]
    /// Newly discovered 2..4 character OOV terms sorted by descending quality score.
    public let discoveredNewWords: [DiscoveredTerm]

    public init(
        segmentedClauses: [[String]],
        knownWordCounts: [String: Int],
        singleCharCounts: [String: Int],
        bigramCounts: [String: Int],
        contextualCharCounts: [String: [String: Int]],
        discoveredNewWords: [DiscoveredTerm]
    ) {
        self.segmentedClauses = segmentedClauses
        self.knownWordCounts = knownWordCounts
        self.singleCharCounts = singleCharCounts
        self.bigramCounts = bigramCounts
        self.contextualCharCounts = contextualCharCounts
        self.discoveredNewWords = discoveredNewWords
    }
}

/// Dual-track Chinese word segmenter and unsupervised OOV term extractor (PMI + Left/Right Boundary Entropy).
public final class TermExtractor: @unchecked Sendable {
    /// Common functional/stop characters that should not appear at the start or end of newly discovered OOV terms.
    public static let boundaryStopCharacters: Set<Character> = [
        "的", "了", "在", "是", "我", "你", "他", "她", "它", "們",
        "和", "與", "及", "或", "也", "都", "就", "而", "著", "過",
        "吧", "嗎", "呢", "啊", "喔", "啦", "嗎", "從", "把", "被",
        "讓", "給", "向", "往", "對", "於", "但", "卻", "又", "再",
        "很", "更", "最", "太", "真", "好", "不", "沒", "有", "這", "那"
    ]

    /// Common functional multi-character words that should not be inside or overlap OOV glue.
    public static let stopSubstrings: Set<String> = [
        "因為", "所以", "如果", "雖然", "但是", "可以", "我們", "你們", "他們",
        "這個", "那個", "什麼", "怎麼", "一個", "一下", "一些", "已經", "進行"
    ]

    public let lexicon: Lexicon
    public let reverseLookup: ReverseZhuyinLookup

    public init(lexicon: Lexicon, reverseLookup: ReverseZhuyinLookup) {
        self.lexicon = lexicon
        self.reverseLookup = reverseLookup
    }

    /// Extracts corpus statistics, discovered OOV words, and segmented word bigrams from sanitized clauses.
    public func extract(
        from clauses: [String],
        existingUserWords: Set<String> = [],
        minNewWordCount: Int = 2,
        minPMI: Double = 1.8,
        minBoundaryEntropy: Double = 0.0
    ) -> ExtractedCorpusStats {
        guard !clauses.isEmpty else {
            return ExtractedCorpusStats(
                segmentedClauses: [],
                knownWordCounts: [:],
                singleCharCounts: [:],
                bigramCounts: [:],
                contextualCharCounts: [:],
                discoveredNewWords: []
            )
        }

        // Phase 1: Discover OOV 2..4 character terms via N-gram frequency, PMI, and Left/Right Boundary Entropy
        let discovered = discoverOOVTerms(
            in: clauses,
            existingUserWords: existingUserWords,
            minCount: minNewWordCount,
            minPMI: minPMI,
            minEntropy: minBoundaryEntropy
        )

        // Build temporary cost map for newly discovered OOV terms so Phase 2 segmentation recognizes them as whole words
        var customWordCosts: [String: Double] = [:]
        for term in discovered {
            let estimatedCost = max(1.2, 2.8 - 0.45 * log(Double(term.count) + 1.0))
            customWordCosts[term.word] = estimatedCost
        }

        // Phase 2: Minimum-cost Viterbi word segmentation across each clause
        var segmentedClauses: [[String]] = []
        segmentedClauses.reserveCapacity(clauses.count)

        var knownWordCounts: [String: Int] = [:]
        var singleCharCounts: [String: Int] = [:]
        var bigramCounts: [String: Int] = [:]
        var contextualCharCounts: [String: [String: Int]] = [:]

        let discoveredSet = Set(discovered.map { $0.word })

        for clause in clauses {
            let words = segmentClause(clause, additionalWordCosts: customWordCosts)
            guard !words.isEmpty else { continue }
            segmentedClauses.append(words)

            for i in 0..<words.count {
                let w = words[i]
                if w.count >= 2 {
                    if !discoveredSet.contains(w) {
                        knownWordCounts[w, default: 0] += 1
                    }
                } else if w.count == 1 {
                    singleCharCounts[w, default: 0] += 1
                }

                if i > 0 {
                    let prev = words[i - 1]
                    let bigramKey = "\(prev)|\(w)"
                    bigramCounts[bigramKey, default: 0] += 1

                    if w.count == 1 {
                        var map = contextualCharCounts[prev] ?? [:]
                        map[w, default: 0] += 1
                        contextualCharCounts[prev] = map
                    }
                }
            }
        }

        return ExtractedCorpusStats(
            segmentedClauses: segmentedClauses,
            knownWordCounts: knownWordCounts,
            singleCharCounts: singleCharCounts,
            bigramCounts: bigramCounts,
            contextualCharCounts: contextualCharCounts,
            discoveredNewWords: discovered
        )
    }

    // MARK: - Minimum-Cost Viterbi Word Segmentation

    /// Segments a pure Chinese clause into words using Viterbi dynamic programming over character spans (length 1..6).
    public func segmentClause(_ clause: String, additionalWordCosts: [String: Double] = [:]) -> [String] {
        let chars = Array(clause)
        let n = chars.count
        guard n > 0 else { return [] }
        if n == 1 { return [clause] }

        // dpCost[i]: minimum cost to segment prefix chars[0..<i]
        var dpCost = [Double](repeating: Double.infinity, count: n + 1)
        var dpPrev = [Int](repeating: 0, count: n + 1)
        var dpWord = [String](repeating: "", count: n + 1)
        dpCost[0] = 0.0

        let maxWordLen = min(6, n)

        for i in 0..<n {
            guard dpCost[i] < Double.infinity else { continue }
            let prevWord = (i == 0) ? Lexicon.sentenceStart : dpWord[i]
            let maxLen = min(maxWordLen, n - i)

            for len in 1...maxLen {
                let end = i + len
                let subWord = String(chars[i..<end])

                let wordCost: Double?
                if let custom = additionalWordCosts[subWord] {
                    wordCost = custom
                } else if let lexCost = lexicon.unigramCosts[subWord] {
                    wordCost = lexCost
                } else if len == 1 {
                    wordCost = lexicon.oovCost
                } else {
                    wordCost = nil
                }

                guard let uCost = wordCost else { continue }

                // Transition cost from previous segmented word
                let transCost: Double
                let bKey = BigramKey(prev: prevWord, next: subWord)
                if let directBigram = lexicon.bigramCosts[bKey] {
                    transCost = directBigram
                } else {
                    // Slight structural preference for multi-character words over fragmented single characters
                    let lengthBonus = (len >= 2) ? (Double(len - 1) * 1.6) : 0.0
                    transCost = max(0.5, uCost + lexicon.backoffPenalty - lengthBonus)
                }

                let candidateCost = dpCost[i] + transCost
                if candidateCost < dpCost[end] {
                    dpCost[end] = candidateCost
                    dpPrev[end] = i
                    dpWord[end] = subWord
                }
            }
        }

        // Backtrack from n to 0
        var result: [String] = []
        var curr = n
        while curr > 0 {
            let prev = dpPrev[curr]
            let w = dpWord[curr]
            if !w.isEmpty {
                result.append(w)
            } else {
                result.append(String(chars[prev..<curr]))
            }
            curr = prev
        }
        result.reverse()
        return result
    }

    // MARK: - Unsupervised OOV Term Discovery (PMI + Boundary Entropy)

    private func discoverOOVTerms(
        in clauses: [String],
        existingUserWords: Set<String>,
        minCount: Int,
        minPMI: Double,
        minEntropy: Double
    ) -> [DiscoveredTerm] {
        var totalChars = 0
        var ngramCounts: [String: Int] = [:]
        // Boundary neighbor counts: leftNeighbors[word][leftChar] = count
        var leftNeighbors: [String: [Character: Int]] = [:]
        var rightNeighbors: [String: [Character: Int]] = [:]

        // Boundary sentinel characters for start/end of clause (distinct per clause occurrence to reflect natural sentence boundaries)
        for (clauseIdx, clause) in clauses.enumerated() {
            let chars = Array(clause)
            let n = chars.count
            guard n >= 2 else {
                totalChars += n
                for c in chars {
                    ngramCounts[String(c), default: 0] += 1
                }
                continue
            }
            totalChars += n

            for i in 0..<n {
                // Count 1-grams
                ngramCounts[String(chars[i]), default: 0] += 1

                // Count 2..4-grams and record left/right boundary characters
                let maxLen = min(4, n - i)
                if maxLen >= 2 {
                    for len in 2...maxLen {
                        let end = i + len
                        let gram = String(chars[i..<end])
                        ngramCounts[gram, default: 0] += 1

                        let leftChar: Character = (i > 0)
                            ? chars[i - 1]
                            : (Character(UnicodeScalar(0xE000 + (clauseIdx % 1000)) ?? "^"))
                        let rightChar: Character = (end < n)
                            ? chars[end]
                            : (Character(UnicodeScalar(0xE400 + (clauseIdx % 1000)) ?? "$"))

                        leftNeighbors[gram, default: [:]][leftChar, default: 0] += 1
                        rightNeighbors[gram, default: [:]][rightChar, default: 0] += 1
                    }
                }
            }
        }

        guard totalChars >= 4 else { return [] }
        let totalN = Double(totalChars)

        var candidates: [DiscoveredTerm] = []

        for (gram, count) in ngramCounts {
            let len = gram.count
            guard len >= 2 && len <= 4 else { continue }
            guard count >= minCount else { continue }

            // Skip if already in base lexicon (as a multi-char entry) or already in active userWords
            if lexicon.unigramCosts[gram] != nil || existingUserWords.contains(gram) {
                continue
            }

            let gramChars = Array(gram)
            // Skip if first or last character is a functional stop character
            guard let firstChar = gramChars.first, let lastChar = gramChars.last else { continue }
            if Self.boundaryStopCharacters.contains(firstChar) || Self.boundaryStopCharacters.contains(lastChar) {
                continue
            }
            // Also skip if internal characters contain heavy structural function particles like "的", "了", "嗎"
            if gramChars.contains("的") || gramChars.contains("了") || gramChars.contains("嗎") || gramChars.contains("呢") {
                continue
            }
            if Self.stopSubstrings.contains(where: { gram.contains($0) }) {
                continue
            }
            // Ensure every character in the candidate has a known Zhuyin reading in the lexicon
            if !gramChars.allSatisfy({ !reverseLookup.lookupCharacter($0).isEmpty }) {
                continue
            }

            // Compute minimum internal Pointwise Mutual Information (PMI) across all binary split points
            let pGram = Double(count) / totalN
            var minSplitPMI = Double.infinity

            for split in 1..<len {
                let leftPart = String(gramChars[0..<split])
                let rightPart = String(gramChars[split..<len])
                let cLeft = Double(ngramCounts[leftPart] ?? count)
                let cRight = Double(ngramCounts[rightPart] ?? count)
                let pLeft = cLeft / totalN
                let pRight = cRight / totalN
                if pLeft > 0 && pRight > 0 {
                    let pmi = log(pGram / (pLeft * pRight))
                    if pmi < minSplitPMI {
                        minSplitPMI = pmi
                    }
                }
            }

            guard minSplitPMI.isFinite, minSplitPMI >= minPMI else { continue }

            // Compute Shannon Entropy of Left and Right Boundaries
            let hLeft = shannonEntropy(counts: leftNeighbors[gram] ?? [:])
            let hRight = shannonEntropy(counts: rightNeighbors[gram] ?? [:])

            // Require boundary diversity so substrings of longer repeating words are filtered out
            let effectiveMinEntropy = (count >= 3) ? max(minEntropy, 0.45) : max(minEntropy, 0.35)
            guard min(hLeft, hRight) >= effectiveMinEntropy else { continue }

            candidates.append(DiscoveredTerm(
                word: gram,
                count: count,
                pmi: minSplitPMI,
                leftEntropy: hLeft,
                rightEntropy: hRight
            ))
        }

        // Deduplicate substring shadows: if a shorter 2/3-gram has the exact same count as a longer accepted 3/4-gram
        // that contains it (meaning the shorter gram ONLY ever appeared inside the longer gram), drop the shorter fragment.
        let sortedByLengthDesc = candidates.sorted {
            if $0.word.count != $1.word.count { return $0.word.count > $1.word.count }
            return $0.qualityScore > $1.qualityScore
        }

        var accepted: [DiscoveredTerm] = []
        for cand in sortedByLengthDesc {
            let isShadowed = accepted.contains { longer in
                longer.word.count > cand.word.count &&
                longer.word.contains(cand.word) &&
                Double(cand.count) <= Double(longer.count) * 1.15
            }
            if !isShadowed {
                accepted.append(cand)
            }
        }

        return accepted.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.qualityScore > $1.qualityScore
        }
    }

    private func shannonEntropy(counts: [Character: Int]) -> Double {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return 0.0 }
        let totalD = Double(total)
        var entropy = 0.0
        for c in counts.values where c > 0 {
            let p = Double(c) / totalD
            entropy -= p * log(p)
        }
        return entropy
    }
}
