import Foundation

/// Represents a candidate alternative syllable derived from the keyboard spatial layout error model.
public struct SpatialSyllableCandidate: Sendable, Hashable {
    /// The candidate syllable.
    public let syllable: Syllable
    /// Penalty cost added to unigram cost (0.0 for exact input, > 0.0 for spatial alternatives).
    public let penalty: Double
    /// The physical key originally typed on keyboard.
    public let sourceKey: Character?
    /// The adjacent physical key substituted in this candidate.
    public let substitutedKey: Character?
    /// The component type where the substitution occurred.
    public let componentType: BopomofoComponentType?

    public init(
        syllable: Syllable,
        penalty: Double,
        sourceKey: Character? = nil,
        substitutedKey: Character? = nil,
        componentType: BopomofoComponentType? = nil
    ) {
        self.syllable = syllable
        self.penalty = penalty
        self.sourceKey = sourceKey
        self.substitutedKey = substitutedKey
        self.componentType = componentType
    }
}

/// A spatial model representing physical macOS ANSI keyboard geometry and key adjacencies
/// for error-tolerant phonetic typing (手滑相鄰按鍵容錯).
public final class KeyboardSpatialModel: @unchecked Sendable {
    public static let shared = KeyboardSpatialModel()

    // MARK: - Key 2D Geometry (Standard macOS ANSI QWERTY Staggered Layout)

    public static let keyCoordinates: [Character: (row: Double, col: Double)] = [
        // Number row (Row 0)
        "1": (0.0, 1.0), "2": (0.0, 2.0), "3": (0.0, 3.0), "4": (0.0, 4.0), "5": (0.0, 5.0),
        "6": (0.0, 6.0), "7": (0.0, 7.0), "8": (0.0, 8.0), "9": (0.0, 9.0), "0": (0.0, 10.0),
        "-": (0.0, 11.0),

        // QWERTY row (Row 1)
        "q": (1.0, 1.5), "w": (1.0, 2.5), "e": (1.0, 3.5), "r": (1.0, 4.5), "t": (1.0, 5.5),
        "y": (1.0, 6.5), "u": (1.0, 7.5), "i": (1.0, 8.5), "o": (1.0, 9.5), "p": (1.0, 10.5),

        // Home row (Row 2)
        "a": (2.0, 1.8), "s": (2.0, 2.8), "d": (2.0, 3.8), "f": (2.0, 4.8), "g": (2.0, 5.8),
        "h": (2.0, 6.8), "j": (2.0, 7.8), "k": (2.0, 8.8), "l": (2.0, 9.8), ";": (2.0, 10.8),

        // Bottom row (Row 3)
        "z": (3.0, 2.3), "x": (3.0, 3.3), "c": (3.0, 4.3), "v": (3.0, 5.3), "b": (3.0, 6.3),
        "n": (3.0, 7.3), "m": (3.0, 8.3), ",": (3.0, 9.3), ".": (3.0, 10.3), "/": (3.0, 11.3),

        // Space bar (Row 4)
        " ": (4.0, 6.0)
    ]

    // MARK: - Reverse Mappings (Bopomofo Symbol to Physical Dachen Key)

    public let initialToKey: [Character: Character]
    public let medialToKey: [Character: Character]
    public let rhymeToKey: [Character: Character]
    public let toneToKey: [Tone: Character]

    private let cacheLock = NSLock()
    private var candidateCache = [Syllable: [SpatialSyllableCandidate]]()

    public init() {
        var revInit = [Character: Character]()
        for (k, v) in BopomofoComposer.initialMap { revInit[v] = k }
        self.initialToKey = revInit

        var revMed = [Character: Character]()
        for (k, v) in BopomofoComposer.medialMap { revMed[v] = k }
        self.medialToKey = revMed

        var revRhyme = [Character: Character]()
        for (k, v) in BopomofoComposer.rhymeMap { revRhyme[v] = k }
        self.rhymeToKey = revRhyme

        var revTone = [Tone: Character]()
        for (k, v) in BopomofoComposer.toneMap { revTone[v] = k }
        self.toneToKey = revTone
    }

    /// Computes physical Euclidean distance between two keys on the keyboard.
    public func distance(between k1: Character, and k2: Character) -> Double? {
        guard let p1 = Self.keyCoordinates[k1], let p2 = Self.keyCoordinates[k2] else {
            return nil
        }
        let dr = p1.row - p2.row
        let dc = p1.col - p2.col
        return sqrt(dr * dr + dc * dc)
    }

    /// Finds adjacent keys within max Euclidean distance (default: 1.25) sorted by ascending distance.
    public func adjacentKeys(for key: Character, maxDistance: Double = 1.25) -> [(key: Character, distance: Double)] {
        guard let p1 = Self.keyCoordinates[key] else { return [] }
        var result: [(key: Character, distance: Double)] = []

        for (k, p2) in Self.keyCoordinates {
            if k == key { continue }
            let dr = p1.row - p2.row
            let dc = p1.col - p2.col
            let dist = sqrt(dr * dr + dc * dc)
            if dist <= maxDistance {
                result.append((key: k, distance: dist))
            }
        }

        result.sort { $0.distance < $1.distance }
        return result
    }

    // MARK: - Syllable Candidate Generation

    /// Generates spatial candidate syllables with edit distance penalties for a given syllable.
    ///
    /// - Parameters:
    ///   - syllable: The original syllable entered by user.
    ///   - basePenalty: Base cost multiplier per Euclidean unit distance (default: 2.6).
    ///   - maxCandidatesPerSlot: Maximum number of spatial candidates to produce.
    /// - Returns: List of candidates, starting with original syllable (penalty = 0.0).
    public func generateCandidates(
        for syllable: Syllable,
        basePenalty: Double = 2.6,
        maxCandidatesPerSlot: Int = 8
    ) -> [SpatialSyllableCandidate] {
        if basePenalty == 2.6 && maxCandidatesPerSlot == 8 {
            cacheLock.lock()
            if let cached = candidateCache[syllable] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        var candidates: [SpatialSyllableCandidate] = []
        var seenSyllables = Set<Syllable>()

        // 1. Primary candidate (penalty = 0.0)
        candidates.append(SpatialSyllableCandidate(
            syllable: syllable,
            penalty: 0.0,
            sourceKey: nil,
            substitutedKey: nil,
            componentType: nil
        ))
        seenSyllables.insert(syllable)

        // 2. Initial component substitutions
        if let initial = syllable.initial, let key = initialToKey[initial] {
            let neighbors = adjacentKeys(for: key)
            for neighbor in neighbors.prefix(3) {
                if let altInitial = BopomofoComposer.initialMap[neighbor.key] {
                    let altSyllable = Syllable(
                        initial: altInitial,
                        medial: syllable.medial,
                        rhyme: syllable.rhyme,
                        tone: syllable.tone
                    )
                    if !seenSyllables.contains(altSyllable) {
                        seenSyllables.insert(altSyllable)
                        let penalty = basePenalty * neighbor.distance
                        candidates.append(SpatialSyllableCandidate(
                            syllable: altSyllable,
                            penalty: penalty,
                            sourceKey: key,
                            substitutedKey: neighbor.key,
                            componentType: .initial
                        ))
                    }
                }
            }
        }

        // 3. Medial component substitutions
        if let medial = syllable.medial, let key = medialToKey[medial] {
            let neighbors = adjacentKeys(for: key)
            for neighbor in neighbors.prefix(3) {
                if let altMedial = BopomofoComposer.medialMap[neighbor.key] {
                    let altSyllable = Syllable(
                        initial: syllable.initial,
                        medial: altMedial,
                        rhyme: syllable.rhyme,
                        tone: syllable.tone
                    )
                    if !seenSyllables.contains(altSyllable) {
                        seenSyllables.insert(altSyllable)
                        let penalty = basePenalty * neighbor.distance
                        candidates.append(SpatialSyllableCandidate(
                            syllable: altSyllable,
                            penalty: penalty,
                            sourceKey: key,
                            substitutedKey: neighbor.key,
                            componentType: .medial
                        ))
                    }
                }
            }
        }

        // 4. Rhyme component substitutions
        if let rhyme = syllable.rhyme, let key = rhymeToKey[rhyme] {
            let neighbors = adjacentKeys(for: key)
            for neighbor in neighbors.prefix(3) {
                if let altRhyme = BopomofoComposer.rhymeMap[neighbor.key] {
                    let altSyllable = Syllable(
                        initial: syllable.initial,
                        medial: syllable.medial,
                        rhyme: altRhyme,
                        tone: syllable.tone
                    )
                    if !seenSyllables.contains(altSyllable) {
                        seenSyllables.insert(altSyllable)
                        let penalty = basePenalty * neighbor.distance
                        candidates.append(SpatialSyllableCandidate(
                            syllable: altSyllable,
                            penalty: penalty,
                            sourceKey: key,
                            substitutedKey: neighbor.key,
                            componentType: .rhyme
                        ))
                    }
                }
            }
        }

        // 5. Tone component substitutions (adjacent tone keys e.g. 3 <-> 4, 6 <-> 7)
        if let toneKey = toneToKey[syllable.tone] {
            let neighbors = adjacentKeys(for: toneKey)
            for neighbor in neighbors.prefix(3) {
                if let altTone = BopomofoComposer.toneMap[neighbor.key], altTone != syllable.tone {
                    let altSyllable = Syllable(
                        initial: syllable.initial,
                        medial: syllable.medial,
                        rhyme: syllable.rhyme,
                        tone: altTone
                    )
                    if !seenSyllables.contains(altSyllable) {
                        seenSyllables.insert(altSyllable)
                        let penalty = basePenalty * 1.35 * neighbor.distance
                        candidates.append(SpatialSyllableCandidate(
                            syllable: altSyllable,
                            penalty: penalty,
                            sourceKey: toneKey,
                            substitutedKey: neighbor.key,
                            componentType: .tone
                        ))
                    }
                }
            }
        }

        let finalCandidates: [SpatialSyllableCandidate]
        if candidates.count > maxCandidatesPerSlot {
            // Keep primary (first) and sort rest by penalty
            let primary = candidates[0]
            let sortedRest = Array(candidates.dropFirst().sorted { $0.penalty < $1.penalty }.prefix(maxCandidatesPerSlot - 1))
            finalCandidates = [primary] + sortedRest
        } else {
            finalCandidates = candidates
        }

        if basePenalty == 2.6 && maxCandidatesPerSlot == 8 {
            cacheLock.lock()
            candidateCache[syllable] = finalCandidates
            cacheLock.unlock()
        }

        return finalCandidates
    }

    /// Generates candidate slots for a sequence of syllables.
    /// Supports `activeTailCount` (Spatial Horizon) to restrict spatial alternatives
    /// to the most recent input window, preventing combinatorial explosion on long sentences.
    public func generateCandidateSlots(
        for syllables: [Syllable],
        basePenalty: Double = 2.6,
        activeTailCount: Int = 8
    ) -> [[SpatialSyllableCandidate]] {
        let n = syllables.count
        guard activeTailCount > 0, n > activeTailCount else {
            return syllables.map { generateCandidates(for: $0, basePenalty: basePenalty) }
        }

        let horizonCutoff = n - activeTailCount
        return (0..<n).map { i in
            if i < horizonCutoff {
                // Historical syllables outside the active horizon keep only the exact primary syllable
                return [SpatialSyllableCandidate(syllable: syllables[i], penalty: 0.0)]
            } else {
                // Active focus window near current input position generates spatial alternatives
                return generateCandidates(for: syllables[i], basePenalty: basePenalty)
            }
        }
    }
}
