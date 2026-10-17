import Foundation

/// Complete analysis output from running an article through the TextIngestion pipeline.
public struct IngestionAnalysisResult: Sendable {
    public let sourceName: String
    public let clauseCount: Int
    public let totalCharacterCount: Int
    /// Annotated candidate terms (both newly discovered OOV words and boosted known phrases).
    public var annotatedTerms: [AnnotatedTerm]
    /// Extracted adjacent word bigram counts: ["prevWord|nextWord": count].
    public let bigramCounts: [String: Int]
    /// Contextual single-character homophone counts: ["prevWord#syllableRaw": [word: count]].
    public let contextualHomophoneDeltas: [String: [String: Int]]
    /// Global single-character homophone counts: [syllableRaw: [word: count]].
    public let globalHomophoneDeltas: [String: [String: Int]]

    public init(
        sourceName: String,
        clauseCount: Int,
        totalCharacterCount: Int,
        annotatedTerms: [AnnotatedTerm],
        bigramCounts: [String: Int],
        contextualHomophoneDeltas: [String: [String: Int]],
        globalHomophoneDeltas: [String: [String: Int]]
    ) {
        self.sourceName = sourceName
        self.clauseCount = clauseCount
        self.totalCharacterCount = totalCharacterCount
        self.annotatedTerms = annotatedTerms
        self.bigramCounts = bigramCounts
        self.contextualHomophoneDeltas = contextualHomophoneDeltas
        self.globalHomophoneDeltas = globalHomophoneDeltas
    }
}

/// Orchestrates article sanitization, segmentation, OOV discovery, G2P annotation, and UserLexicon batch commitment.
public final class ArticleIngestionPipeline: @unchecked Sendable {
    public let engine: ZhuyinEngine

    public init(engine: ZhuyinEngine) {
        self.engine = engine
    }

    /// Analyzes raw article text and produces an `IngestionAnalysisResult` for either UI preview or direct commit.
    public func analyze(
        text: String,
        sourceName: String = "未命名文章",
        mode: ArticleIngestionMode = .reviewFirst
    ) -> IngestionAnalysisResult {
        let clauses = TextSanitizer.extractClauses(text)
        let totalChars = clauses.reduce(0) { $0 + $1.count }

        let existingUserWords = Set(engine.userLexicon.data.userWords.keys)
        let extractor = TermExtractor(lexicon: engine.lexicon, reverseLookup: engine.reverseLookup)
        let stats = extractor.extract(from: clauses, existingUserWords: existingUserWords)

        let annotator = G2PAnnotator(reverseLookup: engine.reverseLookup)
        let terms = ModelBlender.filterTerms(
            discoveredTerms: stats.discoveredNewWords,
            knownWordCounts: stats.knownWordCounts,
            annotator: annotator,
            mode: mode
        )

        // Build contextual and global single-character homophone deltas from the segmented corpus
        var contextualDeltas: [String: [String: Int]] = [:]
        var globalDeltas: [String: [String: Int]] = [:]

        for (charStr, count) in stats.singleCharCounts where charStr.count == 1 {
            if let firstChar = charStr.first,
               let primaryReading = engine.reverseLookup.lookupCharacter(firstChar).first?.syllable {
                globalDeltas[primaryReading.raw, default: [:]][charStr, default: 0] += count
            }
        }

        for (prevWord, charMap) in stats.contextualCharCounts {
            for (charStr, count) in charMap where charStr.count == 1 {
                if let firstChar = charStr.first,
                   let primaryReading = engine.reverseLookup.lookupCharacter(firstChar).first?.syllable {
                    let ctxKey = "\(prevWord)#\(primaryReading.raw)"
                    contextualDeltas[ctxKey, default: [:]][charStr, default: 0] += count
                }
            }
        }

        return IngestionAnalysisResult(
            sourceName: sourceName,
            clauseCount: clauses.count,
            totalCharacterCount: totalChars,
            annotatedTerms: terms,
            bigramCounts: stats.bigramCounts,
            contextualHomophoneDeltas: contextualDeltas,
            globalHomophoneDeltas: globalDeltas
        )
    }

    /// Commits the approved terms and corpus transition statistics as a reversible `IngestionBatch` into `UserLexicon` and hot-reloads the engine.
    @discardableResult
    public func commit(
        analysis: IngestionAnalysisResult,
        approvedTerms: [AnnotatedTerm]? = nil
    ) -> IngestionBatch {
        let termsToApply = (approvedTerms ?? analysis.annotatedTerms).filter { $0.isSelected }

        var wordDeltas: [String: Int] = [:]
        var wordSyllables: [String: [String]] = [:]
        var wordCosts: [String: Double] = [:]

        for term in termsToApply {
            guard !term.word.isEmpty, !term.selectedSyllables.isEmpty else { continue }
            wordDeltas[term.word, default: 0] += term.count
            wordSyllables[term.word] = term.selectedSyllables.map { $0.raw }
            wordCosts[term.word] = ModelBlender.computeUnigramCost(count: term.count)
        }

        let batch = IngestionBatch(
            id: UUID(),
            sourceName: analysis.sourceName,
            timestamp: Date(),
            wordDeltas: wordDeltas,
            wordSyllables: wordSyllables,
            wordCosts: wordCosts,
            bigramDeltas: analysis.bigramCounts,
            contextualHomophoneDeltas: analysis.contextualHomophoneDeltas,
            globalHomophoneDeltas: analysis.globalHomophoneDeltas
        )

        engine.userLexicon.applyIngestionBatch(batch)
        engine.reloadUserLexicon()
        return batch
    }
}
