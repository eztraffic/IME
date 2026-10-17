import Foundation

/// High-level result of the Zhuyin decoding process.
public struct DecodingResult: Sendable {
    /// The optimal decoded Chinese text.
    public let bestText: String
    /// Decoding latency in milliseconds.
    public let durationMs: Double
    /// Top-K candidate paths sorted by ascending cost (best first).
    public let candidates: [CandidatePath]

    public init(bestText: String, durationMs: Double, candidates: [CandidatePath]) {
        self.bestText = bestText
        self.durationMs = durationMs
        self.candidates = candidates
    }
}

/// An entry returned in the candidate window with text and syllable span length.
public struct CandidateEntry: Sendable, Hashable {
    public let text: String
    public let spanLength: Int
    /// Starting offset relative to the target index (0 for forward phrases/homophones, negative for backward phrases/idioms).
    public let startOffset: Int

    public init(text: String, spanLength: Int, startOffset: Int = 0) {
        self.text = text
        self.spanLength = spanLength
        self.startOffset = startOffset
    }
}

/// The main entry point for the Phonetic-to-Chinese (P2C) Zhuyin Engine.
public final class ZhuyinEngine: @unchecked Sendable {
    public let lexicon: Lexicon
    public let trie: Trie
    public let latticeBuilder: LatticeBuilder
    public let decoder: ViterbiDecoder
    public let userLexicon: UserLexicon
    /// Reverse lookup index mapping Chinese characters and words to Zhuyin syllables.
    public lazy var reverseLookup: ReverseZhuyinLookup = ReverseZhuyinLookup(lexicon: lexicon)
    /// Whether keyboard spatial model error tolerance is active during Viterbi decoding. Defaults to false.
    public var isSpatialToleranceEnabled: Bool = false

    /// History of chosen syllables from previous sentence decoding, keyed by runId,
    /// used to stabilize historical slots in long sentences and prevent distant flip-flops.
    public var stabilizedSyllablesHistory: [Int: [Syllable]] = [:]

    /// Resets stabilized historical syllables (called on sentence commit, backspace-to-empty, or cancel).
    public func resetStabilizedHistory() {
        stabilizedSyllablesHistory.removeAll()
    }

    public init(lexicon: Lexicon = Lexicon(), userLexicon: UserLexicon? = nil) {
        self.lexicon = lexicon
        let trie = Trie()
        trie.build(from: lexicon)
        self.trie = trie
        self.latticeBuilder = LatticeBuilder(trie: trie, lexicon: lexicon)
        self.decoder = ViterbiDecoder(lexicon: lexicon)

        let loadedUserLexicon = userLexicon ?? UserLexicon.load()
        self.userLexicon = loadedUserLexicon
        applyUserLexicon(loadedUserLexicon)
    }

    /// Initializes a ZhuyinEngine with the full production lexicon (if available),
    /// gracefully falling back to the default lightweight lexicon.
    public static func production(lexiconURL: URL? = nil, userLexiconURL: URL? = nil) -> ZhuyinEngine {
        let uLex = (userLexiconURL != nil) ? UserLexicon.load(from: userLexiconURL) : UserLexicon.load()
        if let lexicon = try? Lexicon.loadProduction(from: lexiconURL) {
            return ZhuyinEngine(lexicon: lexicon, userLexicon: uLex)
        }
        return ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)
    }

    /// Resets in-memory Lexicon and Trie to their clean baseline and re-applies the current UserLexicon state.
    public func reloadUserLexicon() {
        lexicon.resetToBase()
        trie.rebuild(from: lexicon)
        applyUserLexicon(userLexicon)
        resetStabilizedHistory()
    }

    /// Analyzes and ingests an article into UserLexicon, returning the recorded IngestionBatch.
    @discardableResult
    public func ingestArticle(
        text: String,
        sourceName: String = "未命名文章",
        mode: ArticleIngestionMode = .autoImport
    ) -> IngestionBatch {
        let pipeline = ArticleIngestionPipeline(engine: self)
        let analysis = pipeline.analyze(text: text, sourceName: sourceName, mode: mode)
        return pipeline.commit(analysis: analysis)
    }

    /// Rolls back a previously ingested article batch by ID and hot-reloads the in-memory lexicon and Trie.
    @discardableResult
    public func rollbackIngestionBatch(id: UUID) -> Bool {
        let success = userLexicon.rollbackBatch(id: id)
        if success {
            reloadUserLexicon()
        }
        return success
    }

    /// Injects learned words, homophone boosts, and bigram transitions from UserLexicon into in-memory Trie and Lexicon.
    private func applyUserLexicon(_ uLex: UserLexicon) {
        let snapshot = uLex.data

        // 1. Ingest User Words
        for (_, entry) in snapshot.userWords {
            var syllables = [Syllable]()
            for sRaw in entry.syllablesRaw {
                if let s = Syllable(parsing: sRaw) {
                    syllables.append(s)
                }
            }
            if !syllables.isEmpty {
                let cost = entry.userCost ?? max(1.2, 2.5 - log(Double(entry.count + 1)))
                let wordEntry = WordEntry(word: entry.word, syllables: syllables, unigramCost: cost)
                lexicon.addEntry(wordEntry)
                trie.insertOrUpdate(wordEntry)
            }
        }

        // 2. Ingest Homophone adjustments (Global and Contextual)
        // Note: Single-syllable decoding and CandidateWindow already prioritize recentHomophones/contextualHomophones directly.
        // Keeping single-character unigram cost floor at 2.2 prevents two boosted single characters (e.g. 臨 + 進)
        // from undercutting legitimate 2-character dictionary compounds (e.g. 鄰近) in full-sentence Viterbi decoding.
        for (sylRaw, wordsMap) in snapshot.globalHomophones {
            let syl = Syllable(parsing: sylRaw)
            let sylList = (syl != nil) ? [syl!] : nil
            for (word, count) in wordsMap {
                let discount = min(2.0, 0.5 + 0.25 * log(Double(count + 1)))
                lexicon.boostWordCost(word: word, discount: discount, floor: 2.2)
                if let newCost = lexicon.unigramCosts[word] {
                    trie.updateWordCost(word, for: sylList, newCost: newCost)
                }
            }
            if let topWord = snapshot.recentHomophones[sylRaw]?.first {
                lexicon.boostWordCost(word: topWord, discount: 1.5, floor: 2.2)
                if let newCost = lexicon.unigramCosts[topWord] {
                    trie.updateWordCost(topWord, for: sylList, newCost: newCost)
                }
            }
        }

        for (ctxKey, wordsMap) in snapshot.contextualHomophones {
            let parts = ctxKey.split(separator: "#", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let prevWord = parts[0]
                for (word, count) in wordsMap {
                    let discount = min(2.5, 0.8 + 0.3 * log(Double(count + 1)))
                    lexicon.boostBigram(prev: prevWord, next: word, discount: discount, floor: 0.8)
                }
            }
        }

        // 3. Ingest Bigram transitions
        for (key, count) in snapshot.bigramCounts {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let discount = min(2.5, 0.8 + 0.3 * Double(count))
                lexicon.boostBigram(prev: parts[0], next: parts[1], discount: discount, floor: 0.8)
            }
        }
    }

    // MARK: - Dynamic Learning API

    /// Records homophone selection by the user, with optional previous word context.
    public func learnHomophoneSelection(syllable: Syllable, word: String, prevWord: String? = nil) {
        userLexicon.recordHomophoneSelection(syllableRaw: syllable.raw, word: word, prevWord: prevWord)
        lexicon.boostWordCost(word: word, discount: 3.0, floor: 0.5)
        if let newCost = lexicon.unigramCosts[word] {
            trie.updateWordCost(word, for: [syllable], newCost: newCost)
        }
        if let prev = prevWord, !prev.isEmpty, prev != Lexicon.sentenceStart {
            lexicon.boostBigram(prev: prev, next: word, discount: 2.0, floor: 0.5)
            userLexicon.recordBigram(prev: prev, next: word)
        }
    }

    /// Submits a novel phrase for candidate thresholding (Pending Gate: 2 commits to promote).
    public func learnCandidateUserWord(word: String, syllables: [Syllable]) -> Bool {
        guard !word.isEmpty, syllables.count >= 2, syllables.count <= 4 else { return false }
        let rawList = syllables.map { $0.raw }
        let promoted = userLexicon.recordCandidateUserWord(word: word, syllablesRaw: rawList)
        if promoted {
            let cost = max(1.2, 2.5 - log(3.0))
            let entry = WordEntry(word: word, syllables: syllables, unigramCost: cost)
            lexicon.addEntry(entry)
            trie.insertOrUpdate(entry)
            return true
        }
        return false
    }

    /// Registers a confirmed user phrase directly into the engine and user lexicon.
    public func learnUserWord(word: String, syllables: [Syllable]) {
        guard !word.isEmpty, syllables.count >= 2 else { return }
        let rawList = syllables.map { $0.raw }
        let cost = max(1.2, 2.8 - log(2.0))
        userLexicon.recordUserWord(word: word, syllablesRaw: rawList, cost: cost)
        let entry = WordEntry(word: word, syllables: syllables, unigramCost: cost)
        lexicon.addEntry(entry)
        trie.insertOrUpdate(entry)
    }

    /// Learns a bigram transition between consecutive words.
    public func learnBigram(prev: String, next: String) {
        guard !prev.isEmpty, !next.isEmpty else { return }
        guard prev != Lexicon.sentenceStart, next != Lexicon.sentenceEnd else { return }
        userLexicon.recordBigram(prev: prev, next: next)
        lexicon.boostBigram(prev: prev, next: next, discount: 1.5, floor: 0.8)
    }

    /// Analyzes a committed composed sentence, registering pending/active user phrases, homophone picks, and bigram transitions.
    public func learnCommittedSentence(
        items: [CompositionItem],
        committedText: String,
        userOverrides: [Int: String] = [:]
    ) {
        guard !items.isEmpty else { return }
        guard !userLexicon.data.isLearningPaused else { return }

        // 1. Learn individual homophone overrides with preceding context
        for (overrideIdx, overrideWord) in userOverrides {
            if overrideIdx < items.count, case .syllable(let syl) = items[overrideIdx] {
                var prevText: String? = nil
                if overrideIdx > 0 {
                    if let prevOv = userOverrides[overrideIdx - 1] {
                        prevText = prevOv
                    } else if case .syllable = items[overrideIdx - 1] {
                        var runStart = overrideIdx - 1
                        while runStart > 0, case .syllable = items[runStart - 1] {
                            runStart -= 1
                        }
                        var runSyls: [Syllable] = []
                        for k in runStart...(overrideIdx - 1) {
                            if case .syllable(let s) = items[k] {
                                runSyls.append(s)
                            }
                        }
                        let decoded = decode(syllables: runSyls, topK: 1, updateHistory: false)
                        let chars = Array(decoded.bestText)
                        let offset = (overrideIdx - 1) - runStart
                        if offset < chars.count {
                            prevText = String(chars[offset])
                        }
                    } else if case .punctuation(let p) = items[overrideIdx - 1] {
                        prevText = p
                    }
                }
                learnHomophoneSelection(syllable: syl, word: overrideWord, prevWord: prevText)
            }
        }

        // 2. Segment into continuous syllable runs (divided by punctuations)
        var i = 0
        var itemWords: [(word: String, wasOverridden: Bool)] = []

        while i < items.count {
            switch items[i] {
            case .punctuation(let punct):
                itemWords.append((word: punct, wasOverridden: false))
                i += 1
            case .syllable:
                let startIdx = i
                var runSyllables = [Syllable]()
                var hasOverrides = false
                while i < items.count, case .syllable(let s) = items[i] {
                    runSyllables.append(s)
                    if userOverrides[i] != nil {
                        hasOverrides = true
                    }
                    i += 1
                }
                let endIdx = i
                let runLen = runSyllables.count

                // 2a. Decode continuous syllable run with full Viterbi optimal path
                let runDecoded = decode(syllables: runSyllables, topK: 1, updateHistory: false)
                var runChars = Array(runDecoded.bestText).map(String.init)
                if runChars.count != runLen {
                    runChars = runSyllables.map { s in
                        let singleBest = decode(syllables: [s], topK: 1, updateHistory: false).bestText
                        return singleBest.isEmpty ? s.raw : singleBest
                    }
                }

                // 2b. Overlay user-overridden characters onto the Viterbi output
                for k in startIdx..<endIdx {
                    if let ov = userOverrides[k] {
                        let offset = k - startIdx
                        if offset < runChars.count {
                            runChars[offset] = ov
                        }
                    }
                }
                let runText = runChars.joined()

                // Only consider novel phrase learning if user made overrides and length is 2..4
                if hasOverrides && runLen >= 2 && runLen <= 4 {
                    let existingMatches = trie.commonPrefixSearch(in: runSyllables, from: 0)
                    let alreadyKnown = existingMatches.contains { $0.length == runLen && $0.entry.word == runText }
                    if !alreadyKnown {
                        _ = learnCandidateUserWord(word: runText, syllables: runSyllables)
                    }
                }

                // 2c. Segment run text into words for Bigram learning, tagging each word with whether user selected it
                if let bestPath = runDecoded.candidates.first,
                   bestPath.words.reduce(0, { $0 + $1.count }) == runChars.count {
                    var offset = 0
                    for word in bestPath.words {
                        let len = word.count
                        let actualWord = runChars[offset..<(offset + len)].joined()
                        var isOverriddenWord = false
                        for charOffset in offset..<(offset + len) {
                            if userOverrides[startIdx + charOffset] != nil {
                                isOverriddenWord = true
                                break
                            }
                        }
                        itemWords.append((word: actualWord, wasOverridden: isOverriddenWord))
                        offset += len
                    }
                } else {
                    itemWords.append((word: runText, wasOverridden: hasOverrides))
                }
            }
        }

        // 3. Learn bigrams ONLY for transitions involving user-selected words
        if itemWords.count >= 2 {
            for j in 0..<(itemWords.count - 1) {
                let (w1, ov1) = itemWords[j]
                let (w2, ov2) = itemWords[j + 1]
                // Only learn transition if user explicitly chose or modified at least one of the words
                if ov1 || ov2 {
                    learnBigram(prev: w1, next: w2)
                }
            }
        }
    }

    /// Decodes a space-separated string of Zhuyin syllables into Chinese text.
    public func decode(zhuyin: String, topK: Int = 3) -> DecodingResult {
        let syllables = Syllable.parseSequence(zhuyin)
        return decode(syllables: syllables, topK: topK)
    }

    /// Checks whether an existing stabilized syllable history is compatible with the input syllables prefix.
    private func isCompatible(history: [Syllable], with input: [Syllable]) -> Bool {
        guard !history.isEmpty else { return false }
        let count = min(history.count, input.count)
        guard count > 0 else { return false }
        for i in 0..<count {
            if history[i] == input[i] { continue }
            let candidates = KeyboardSpatialModel.shared.generateCandidates(for: input[i])
            if !candidates.contains(where: { $0.syllable == history[i] }) {
                return false
            }
        }
        return true
    }

    /// Generates candidate slots with Sticky Stabilized Slots for historical positions,
    /// preventing distant flip-flops (such as 否 reverting to 復) when typing long sentences.
    private func generateStabilizedCandidateSlots(
        for syllables: [Syllable],
        runId: Int = 0,
        activeTailCount: Int = 8
    ) -> (effectiveSyllables: [Syllable], slots: [[SpatialSyllableCandidate]]) {
        let n = syllables.count
        guard activeTailCount > 0, n > activeTailCount else {
            let slots = syllables.map { KeyboardSpatialModel.shared.generateCandidates(for: $0) }
            return (syllables, slots)
        }

        // Check if we need a forward progressive warmup pass (e.g. batch one-shot decode of a long sentence)
        if let history = stabilizedSyllablesHistory[runId], isCompatible(history: history, with: syllables) {
            // Incremental typing history available and valid
        } else {
            // History missing or reset: run quick forward stabilization pass to establish sticky history
            var currentStabilized = Array(syllables.prefix(min(n, activeTailCount)))
            let startK = activeTailCount
            for k in startK...n {
                let sub = Array(syllables.prefix(k))
                let horizon = k - activeTailCount
                var subEffective = sub
                var subSlots = [[SpatialSyllableCandidate]]()
                for j in 0..<k {
                    if j < horizon {
                        let s = (j < currentStabilized.count) ? currentStabilized[j] : sub[j]
                        subEffective[j] = s
                        subSlots.append([SpatialSyllableCandidate(syllable: s, penalty: 0.0)])
                    } else {
                        subSlots.append(KeyboardSpatialModel.shared.generateCandidates(for: sub[j]))
                    }
                }
                let subLattice = latticeBuilder.buildLattice(for: subEffective, candidateSlots: subSlots)
                let subDecoded = decoder.decode(lattice: subLattice, topK: 1)
                if let best = subDecoded.first, !best.syllables.isEmpty {
                    currentStabilized = best.syllables
                }
            }
            stabilizedSyllablesHistory[runId] = currentStabilized
        }

        let history = stabilizedSyllablesHistory[runId] ?? []
        let horizonCutoff = n - activeTailCount
        var effectiveSyllables = syllables
        var slots = [[SpatialSyllableCandidate]]()
        slots.reserveCapacity(n)

        for i in 0..<n {
            if i < horizonCutoff {
                let stabilized = (i < history.count) ? history[i] : syllables[i]
                effectiveSyllables[i] = stabilized
                slots.append([SpatialSyllableCandidate(syllable: stabilized, penalty: 0.0)])
            } else {
                slots.append(KeyboardSpatialModel.shared.generateCandidates(for: syllables[i]))
            }
        }

        return (effectiveSyllables, slots)
    }

    /// Decodes a sequence of parsed Zhuyin syllables into Chinese text, optionally using spatial candidate slots.
    public func decode(
        syllables: [Syllable],
        candidateSlots: [[SpatialSyllableCandidate]]? = nil,
        runId: Int = 0,
        topK: Int = 3,
        updateHistory: Bool = true
    ) -> DecodingResult {
        let startTime = DispatchTime.now()

        guard !syllables.isEmpty else {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
            return DecodingResult(bestText: "", durationMs: elapsed, candidates: [])
        }

        var effectiveSyllables = syllables
        let slots: [[SpatialSyllableCandidate]]?

        if let explicitSlots = candidateSlots {
            slots = explicitSlots
        } else if isSpatialToleranceEnabled {
            let (compSyllables, compSlots) = generateStabilizedCandidateSlots(for: syllables, runId: runId, activeTailCount: 8)
            effectiveSyllables = compSyllables
            slots = compSlots
        } else {
            slots = nil
        }

        let lattice = latticeBuilder.buildLattice(for: effectiveSyllables, candidateSlots: slots)
        var candidates = decoder.decode(lattice: lattice, topK: topK)

        // For a single syllable, prioritize recently chosen homophone
        if syllables.count == 1, let single = syllables.first,
           let topWord = userLexicon.recentHomophones(for: single.raw).first {
            if let idx = candidates.firstIndex(where: { $0.text == topWord }) {
                let topCand = candidates.remove(at: idx)
                candidates.insert(topCand, at: 0)
            } else {
                let topCand = CandidatePath(text: topWord, words: [topWord], totalCost: 0.1)
                candidates.insert(topCand, at: 0)
            }
        }

        if updateHistory, isSpatialToleranceEnabled, let bestPath = candidates.first, !bestPath.syllables.isEmpty {
            stabilizedSyllablesHistory[runId] = bestPath.syllables
        }

        let endTime = DispatchTime.now()
        let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        let bestText = candidates.first?.text ?? ""
        return DecodingResult(bestText: bestText, durationMs: elapsed, candidates: candidates)
    }

    /// Retrieves candidate items (prefix phrases, backward phrases/idioms, and single-syllable homophones) with their syllable spans and offsets.
    public func candidatesWithSpan(
        for syllables: [Syllable],
        startIndex: Int = 0,
        precedingSyllables: [Syllable] = [],
        prevWord: String? = nil,
        maxCount: Int = 100
    ) -> [CandidateEntry] {
        guard startIndex >= 0, startIndex < syllables.count else { return [] }
        let subSyllables = Array(syllables[startIndex...])
        guard !subSyllables.isEmpty else { return [] }

        var entries: [CandidateEntry] = []
        var seenTexts = Set<String>()

        // 1. Multi-syllable phrase candidates starting from startIndex (length 2..4)
        let maxPhraseLen = min(subSyllables.count, 4)
        if maxPhraseLen >= 2 {
            let trieMatches = trie.commonPrefixSearch(in: subSyllables, from: 0)
            let phraseMatches = trieMatches.filter { $0.length >= 2 && $0.length <= maxPhraseLen }

            let sortedPhrases = phraseMatches.sorted { (m1, m2) -> Bool in
                let cost1: Double
                let cost2: Double
                if let prev = prevWord, !prev.isEmpty {
                    cost1 = lexicon.transitionCost(from: prev, to: m1.entry.word)
                    cost2 = lexicon.transitionCost(from: prev, to: m2.entry.word)
                } else {
                    cost1 = m1.entry.unigramCost
                    cost2 = m2.entry.unigramCost
                }
                if cost1 != cost2 { return cost1 < cost2 }
                return m1.length > m2.length
            }

            for match in sortedPhrases {
                if !seenTexts.contains(match.entry.word) {
                    seenTexts.insert(match.entry.word)
                    entries.append(CandidateEntry(text: match.entry.word, spanLength: match.length, startOffset: 0))
                    if entries.count >= maxCount { return entries }
                }
            }
        }

        // 2. Backward multi-syllable phrase and idiom candidates ending at target syllable (length 2..4)
        if !precedingSyllables.isEmpty {
            let targetSyllable = subSyllables[0]
            let backwardWindow = precedingSyllables + [targetSyllable]
            let windowCount = backwardWindow.count
            let maxBackwardLen = min(windowCount, 4)

            if maxBackwardLen >= 2 {
                var backwardMatches: [(word: String, length: Int, unigramCost: Double, startOffset: Int)] = []
                for len in 2...maxBackwardLen {
                    let sliceStart = windowCount - len
                    let slice = Array(backwardWindow[sliceStart..<windowCount])
                    let matches = trie.commonPrefixSearch(in: slice, from: 0)
                    for m in matches where m.length == len {
                        backwardMatches.append((
                            word: m.entry.word,
                            length: len,
                            unigramCost: m.entry.unigramCost,
                            startOffset: -(len - 1)
                        ))
                    }
                }

                // Sort backward matches: longer phrases/idioms first (e.g. 4-character idiom before 2-character word);
                // within identical length, lower unigramCost (higher frequency) first.
                let sortedBackward = backwardMatches.sorted { (m1, m2) -> Bool in
                    if m1.length != m2.length {
                        return m1.length > m2.length
                    }
                    return m1.unigramCost < m2.unigramCost
                }

                for match in sortedBackward {
                    if !seenTexts.contains(match.word) {
                        seenTexts.insert(match.word)
                        entries.append(CandidateEntry(text: match.word, spanLength: match.length, startOffset: match.startOffset))
                        if entries.count >= maxCount { return entries }
                    }
                }
            }
        }

        // 3. Single-syllable homophones for target syllable
        let targetSyllable = subSyllables[0]

        // 2a. Context-matched homophones
        if let prev = prevWord, !prev.isEmpty {
            let ctxWords = userLexicon.contextualHomophones(for: targetSyllable.raw, prevWord: prev)
            for word in ctxWords {
                if !seenTexts.contains(word) {
                    seenTexts.insert(word)
                    entries.append(CandidateEntry(text: word, spanLength: 1))
                    if entries.count >= maxCount { return entries }
                }
            }
        }

        // 2b. Most recent homophones (MRU)
        let recentWords = userLexicon.recentHomophones(for: targetSyllable.raw)
        for word in recentWords {
            if !seenTexts.contains(word) {
                seenTexts.insert(word)
                entries.append(CandidateEntry(text: word, spanLength: 1))
                if entries.count >= maxCount { return entries }
            }
        }

        // 2c. Decoded optimal single-character path
        let singleDecoded = decode(syllables: [targetSyllable], topK: 5, updateHistory: false)
        for cand in singleDecoded.candidates {
            if !seenTexts.contains(cand.text) && !cand.text.isEmpty {
                seenTexts.insert(cand.text)
                entries.append(CandidateEntry(text: cand.text, spanLength: 1))
                if entries.count >= maxCount { return entries }
            }
        }

        // 2d. All single-syllable Trie matches sorted by unigramCost
        let singleMatches = trie.commonPrefixSearch(in: [targetSyllable], from: 0)
        let sortedSingles = singleMatches.sorted {
            let c1 = $0.entry.unigramCost
            let c2 = $1.entry.unigramCost
            return c1 < c2
        }
        for match in sortedSingles {
            if !seenTexts.contains(match.entry.word) {
                seenTexts.insert(match.entry.word)
                entries.append(CandidateEntry(text: match.entry.word, spanLength: 1))
                if entries.count >= maxCount { break }
            }
        }

        // 2e. Spatial error-tolerant single-character candidates if enabled and room permits
        if isSpatialToleranceEnabled && entries.count < maxCount {
            let spatialCandidates = KeyboardSpatialModel.shared.generateCandidates(for: targetSyllable).dropFirst()
            for spatialCand in spatialCandidates {
                let matches = trie.commonPrefixSearch(in: [spatialCand.syllable], from: 0)
                let sorted = matches.filter {
                    $0.entry.unigramCost <= 9.0
                }.sorted {
                    let c1 = $0.entry.unigramCost
                    let c2 = $1.entry.unigramCost
                    return c1 < c2
                }
                for match in sorted {
                    if !seenTexts.contains(match.entry.word) {
                        seenTexts.insert(match.entry.word)
                        entries.append(CandidateEntry(text: match.entry.word, spanLength: 1))
                        if entries.count >= maxCount { break }
                    }
                }
                if entries.count >= maxCount { break }
            }
        }

        return Array(entries.prefix(maxCount))
    }

    /// Retrieves candidate phrases or single-character homophones for the given syllables.
    public func candidates(for syllables: [Syllable], maxCount: Int = 100) -> [String] {
        return candidatesWithSpan(for: syllables, startIndex: 0, prevWord: nil, maxCount: maxCount).map { $0.text }
    }
}
