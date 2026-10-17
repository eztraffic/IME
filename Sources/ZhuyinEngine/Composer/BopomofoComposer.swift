import Foundation

/// Represents the classification of a Zhuyin phonetic symbol.
public enum BopomofoComponentType: Sendable, Equatable {
    case initial
    case medial
    case rhyme
    case tone
}

/// The result returned after processing a keyboard event in `BopomofoComposer`.
public enum KeyHandlingResult: Sendable, Equatable {
    /// A symbol was appended or replaced in the current in-flight syllable buffer.
    case composing(currentSyllable: String, displayText: String)
    /// A tone key completed an entire syllable.
    case syllableCompleted(Syllable, displayText: String)
    /// A backspace operation deleted a component or a completed item.
    case backspaced(displayText: String)
    /// The key has no mapping or was ignored.
    case ignored
    /// The buffer was already empty when backspace or an invalid action occurred.
    case empty
}

/// A state machine that converts raw keyboard input (standard Dachen layout) into Zhuyin syllables and composition items.
public final class BopomofoComposer: @unchecked Sendable {
    // MARK: - Dachen Keyboard Layout Mappings

    public static let initialMap: [Character: Character] = [
        "1": "ㄅ", "q": "ㄆ", "a": "ㄇ", "z": "ㄈ",
        "2": "ㄉ", "w": "ㄊ", "s": "ㄋ", "x": "ㄌ",
        "e": "ㄍ", "d": "ㄎ", "c": "ㄏ",
        "r": "ㄐ", "f": "ㄑ", "v": "ㄒ",
        "5": "ㄓ", "t": "ㄔ", "g": "ㄕ", "b": "ㄖ",
        "y": "ㄗ", "h": "ㄘ", "n": "ㄙ"
    ]

    public static let medialMap: [Character: Character] = [
        "u": "ㄧ", "j": "ㄨ", "m": "ㄩ"
    ]

    public static let rhymeMap: [Character: Character] = [
        "8": "ㄚ", "i": "ㄛ", "k": "ㄜ", ",": "ㄝ",
        "9": "ㄞ", "o": "ㄟ", "l": "ㄠ", ".": "ㄡ",
        "0": "ㄢ", "p": "ㄣ", ";": "ㄤ", "/": "ㄥ",
        "-": "ㄦ"
    ]

    public static let toneMap: [Character: Tone] = [
        " ": .first,
        "6": .second,
        "3": .third,
        "4": .fourth,
        "7": .neutral
    ]

    // MARK: - Spatial Error Tolerance Model

    public static let spatialModel = KeyboardSpatialModel.shared

    /// Whether adjacent keyboard spatial model error tolerance is active. Defaults to false.
    public var isSpatialModelEnabled: Bool = false

    /// Returns spatial candidate syllables for a given syllable with distance penalty costs.
    public func spatialCandidates(for syllable: Syllable) -> [SpatialSyllableCandidate] {
        guard isSpatialModelEnabled else {
            return [SpatialSyllableCandidate(syllable: syllable, penalty: 0.0)]
        }
        return Self.spatialModel.generateCandidates(for: syllable)
    }

    /// Returns spatial candidate slots for a sequence of syllables.
    public func candidateSlots(for syllables: [Syllable]) -> [[SpatialSyllableCandidate]] {
        guard isSpatialModelEnabled else {
            return syllables.map { [SpatialSyllableCandidate(syllable: $0, penalty: 0.0)] }
        }
        return Self.spatialModel.generateCandidateSlots(for: syllables)
    }

    /// Returns candidate slots for all completed syllables currently in `items`.
    public func allCandidateSlots() -> [[SpatialSyllableCandidate]] {
        return candidateSlots(for: completedSyllables)
    }

    // MARK: - Internal State

    /// All fully finalized composition items (syllables and punctuation marks) in the composing buffer.
    public private(set) var items: [CompositionItem] = []

    /// Backwards compatibility accessor returning only the Syllables from `items`.
    public var completedSyllables: [Syllable] {
        return items.compactMap(\.syllable)
    }

    /// Current uncompleted syllable slots.
    public private(set) var currentInitial: Character?
    public private(set) var currentMedial: Character?
    public private(set) var currentRhyme: Character?

    /// History stack of slot changes in the current syllable for precise step-by-step backspace.
    private var componentHistory: [BopomofoComponentType] = []

    public init() {}

    /// True if there are currently no completed items and no in-flight symbols.
    public var isEmpty: Bool {
        return items.isEmpty && !hasComposingComponents
    }

    /// True if there are any symbols currently in the in-flight syllable buffer.
    public var hasComposingComponents: Bool {
        return currentInitial != nil || currentMedial != nil || currentRhyme != nil
    }

    /// The Zhuyin string representation of the currently in-flight syllable (without tone).
    public var currentComposingZhuyin: String {
        var str = ""
        if let initial = currentInitial { str.append(initial) }
        if let medial = currentMedial { str.append(medial) }
        if let rhyme = currentRhyme { str.append(rhyme) }
        return str
    }

    /// The complete display string showing completed items separated by space,
    /// followed by any in-flight composing Zhuyin symbols.
    public var displayText: String {
        var parts: [String] = []
        for item in items {
            parts.append(item.rawText)
        }
        let current = currentComposingZhuyin
        if !current.isEmpty {
            parts.append(current)
        }
        return parts.joined(separator: " ")
    }

    /// All syllables, including completed ones. If an in-flight syllable exists without tone,
    /// it is tentatively finalized with first tone.
    public var allSyllables: [Syllable] {
        var list = completedSyllables
        if hasComposingComponents {
            list.append(Syllable(
                initial: currentInitial,
                medial: currentMedial,
                rhyme: currentRhyme,
                tone: .first
            ))
        }
        return list
    }

    // MARK: - Key Handling

    /// Processes a single input character according to the standard Dachen keyboard layout.
    @discardableResult
    public func handleKey(character: Character) -> KeyHandlingResult {
        // Ignore control characters (except Space), escape characters, and Unicode Private Use area function keys
        if let ascii = character.asciiValue, ascii < 0x20 && ascii != 0x20 {
            return .ignored
        }
        if character == "\u{1B}" {
            return .ignored
        }
        if character >= "\u{F700}" && character <= "\u{F8FF}" {
            return .ignored
        }

        let key = character.isLetter ? Character(character.lowercased()) : character

        // 1. Check Initials
        if let initial = Self.initialMap[key] {
            currentInitial = initial
            if !componentHistory.contains(.initial) {
                componentHistory.append(.initial)
            }
            return .composing(currentSyllable: currentComposingZhuyin, displayText: displayText)
        }

        // 2. Check Medials
        if let medial = Self.medialMap[key] {
            currentMedial = medial
            if !componentHistory.contains(.medial) {
                componentHistory.append(.medial)
            }
            return .composing(currentSyllable: currentComposingZhuyin, displayText: displayText)
        }

        // 3. Check Rhymes
        if let rhyme = Self.rhymeMap[key] {
            currentRhyme = rhyme
            if !componentHistory.contains(.rhyme) {
                componentHistory.append(.rhyme)
            }
            return .composing(currentSyllable: currentComposingZhuyin, displayText: displayText)
        }

        // 4. Check Tone keys (Space, 6, 3, 4, 7)
        if let tone = Self.toneMap[key] {
            guard hasComposingComponents else {
                return .ignored
            }

            let syllable = Syllable(
                initial: currentInitial,
                medial: currentMedial,
                rhyme: currentRhyme,
                tone: tone
            )
            items.append(.syllable(syllable))

            // Reset current syllable slots
            currentInitial = nil
            currentMedial = nil
            currentRhyme = nil
            componentHistory.removeAll()

            return .syllableCompleted(syllable, displayText: displayText)
        }

        return .ignored
    }

    /// Convenience method for string input sequences.
    @discardableResult
    public func handleKeys(_ keys: String) -> [KeyHandlingResult] {
        // Strip ANSI escape sequences like \u{1b}[D, \u{1b}[A, etc.
        let cleaned = keys.replacingOccurrences(of: #"\x1b\[[0-9;]*[a-zA-Z]"#, with: "", options: .regularExpression)
        return cleaned.map { handleKey(character: $0) }
    }

    /// Handles Backspace key editing:
    /// - Deletes the last entered component in the in-flight syllable.
    /// - If the in-flight syllable is empty, deletes the previous completed item.
    @discardableResult
    public func handleBackspace() -> KeyHandlingResult {
        if hasComposingComponents {
            // Delete the last component according to history or fallback hierarchy
            if let lastType = componentHistory.popLast() {
                switch lastType {
                case .rhyme:
                    currentRhyme = nil
                case .medial:
                    currentMedial = nil
                case .initial:
                    currentInitial = nil
                case .tone:
                    break
                }
            } else {
                // Fallback hierarchy: Rhyme -> Medial -> Initial
                if currentRhyme != nil {
                    currentRhyme = nil
                } else if currentMedial != nil {
                    currentMedial = nil
                } else if currentInitial != nil {
                    currentInitial = nil
                }
            }
            return .backspaced(displayText: displayText)
        }

        // If in-flight buffer is empty, pop the last completed item
        if !items.isEmpty {
            items.removeLast()
            return .backspaced(displayText: displayText)
        }

        return .empty
    }

    /// Clears all completed items and in-flight buffers.
    public func clear() {
        items.removeAll()
        clearInFlight()
    }

    /// Clears any currently uncompleted in-flight components without clearing completed items.
    public func clearInFlight() {
        currentInitial = nil
        currentMedial = nil
        currentRhyme = nil
        componentHistory.removeAll()
    }

    // MARK: - Item & Syllable Manipulation at Arbitrary Index

    /// Appends a punctuation mark to the end of the composition items.
    public func appendPunctuation(_ punctuation: String) {
        items.append(.punctuation(punctuation))
    }

    /// Inserts a punctuation mark at the specified index.
    public func insertPunctuation(_ punctuation: String, at index: Int) {
        let safeIndex = max(0, min(index, items.count))
        items.insert(.punctuation(punctuation), at: safeIndex)
    }

    /// Appends a composition item.
    public func appendItem(_ item: CompositionItem) {
        items.append(item)
    }

    /// Inserts a composition item at the specified index.
    public func insertItem(_ item: CompositionItem, at index: Int) {
        let safeIndex = max(0, min(index, items.count))
        items.insert(item, at: safeIndex)
    }

    /// Removes a composition item at the given index.
    @discardableResult
    public func removeItem(at index: Int) -> CompositionItem? {
        guard index >= 0 && index < items.count else { return nil }
        return items.remove(at: index)
    }

    /// Removes a completed syllable at the given index in `items`.
    @discardableResult
    public func removeCompletedSyllable(at index: Int) -> Syllable? {
        guard index >= 0 && index < items.count else { return nil }
        let removed = items.remove(at: index)
        return removed.syllable
    }

    /// Inserts a completed syllable at the given index in `items`.
    public func insertCompletedSyllable(_ syllable: Syllable, at index: Int) {
        let safeIndex = max(0, min(index, items.count))
        items.insert(.syllable(syllable), at: safeIndex)
    }
}
