import Foundation

/// Ingestion mode determining how extracted terms and language model weights are filtered and applied.
public enum ArticleIngestionMode: String, Codable, Sendable {
    /// Interactive review mode: presents candidate new words and high-frequency phrases for user confirmation.
    case reviewFirst
    /// Fast automatic mode: applies strict confidence thresholds and commits directly without manual review.
    case autoImport
}

/// Calculates language model costs, bigram transition discounts, and mode-based filtering thresholds.
public enum ModelBlender {
    /// Minimum allowed unigram cost floor for article-learned words to prevent overshadowing core grammar.
    public static let costFloor: Double = 0.8
    /// Base unigram cost before logarithmic frequency discount.
    public static let baseCost: Double = 2.8
    /// Logarithmic scaling factor alpha in Cost(w) = max(0.8, 2.8 - alpha * ln(count + 1)).
    public static let alpha: Double = 0.45

    /// Computes smoothed unigram cost from occurrence count:
    /// Cost(w) = max(0.8, 2.8 - 0.45 * ln(count(w) + 1))
    public static func computeUnigramCost(count: Int) -> Double {
        let safeCount = max(1, count)
        let discounted = baseCost - alpha * log(Double(safeCount) + 1.0)
        return max(costFloor, discounted)
    }

    /// Computes bigram transition discount from observed transition count.
    public static func computeBigramDiscount(count: Int) -> Double {
        let safeCount = max(1, count)
        return min(2.5, 0.8 + 0.3 * Double(safeCount))
    }

    /// Filters and ranks annotated terms according to the chosen ingestion mode.
    public static func filterTerms(
        discoveredTerms: [DiscoveredTerm],
        knownWordCounts: [String: Int],
        annotator: G2PAnnotator,
        mode: ArticleIngestionMode
    ) -> [AnnotatedTerm] {
        var results: [AnnotatedTerm] = []

        // 1. Annotate newly discovered OOV terms
        for item in discoveredTerms {
            let cost = computeUnigramCost(count: item.count)
            guard var annotated = annotator.annotate(
                word: item.word,
                count: item.count,
                isNewWord: true,
                pmi: item.pmi,
                estimatedCost: cost
            ) else { continue }

            switch mode {
            case .reviewFirst:
                // In review mode, include all discovered terms (count >= 2); pre-select high-confidence ones
                annotated.isSelected = (item.count >= 2 && item.pmi >= 1.8)
                results.append(annotated)
            case .autoImport:
                // In auto-import mode, require higher confidence:
                // either unambiguous reading or count >= 2 with strong PMI
                if !annotated.hasAmbiguity || (item.count >= 3 && item.pmi >= 2.2) {
                    annotated.isSelected = true
                    results.append(annotated)
                }
            }
        }

        // 2. Annotate frequent known multi-character words (count >= 2) to boost user-specific domain vocabulary
        let sortedKnown = knownWordCounts
            .filter { $0.key.count >= 2 && $0.key.count <= 4 && $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(100)

        for (word, count) in sortedKnown {
            let cost = computeUnigramCost(count: count)
            guard var annotated = annotator.annotate(
                word: word,
                count: count,
                isNewWord: false,
                pmi: 0.0,
                estimatedCost: cost
            ) else { continue }

            annotated.isSelected = true
            results.append(annotated)
        }

        return results
    }
}
