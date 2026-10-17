import Foundation

/// Represents an item in the input composition buffer: either a phonetically composed `Syllable` or a `Punctuation` mark.
public enum CompositionItem: Sendable, Equatable, Hashable {
    case syllable(Syllable)
    case punctuation(String)

    /// Raw text representation (Zhuyin raw string for syllable, or symbol string for punctuation).
    public var rawText: String {
        switch self {
        case .syllable(let s):
            return s.raw
        case .punctuation(let p):
            return p
        }
    }

    /// True if this item is a punctuation mark.
    public var isPunctuation: Bool {
        if case .punctuation = self { return true }
        return false
    }

    /// The associated syllable if this item is a syllable.
    public var syllable: Syllable? {
        if case .syllable(let s) = self { return s }
        return nil
    }

    /// The associated punctuation string if this item is punctuation.
    public var punctuationString: String? {
        if case .punctuation(let p) = self { return p }
        return nil
    }
}
