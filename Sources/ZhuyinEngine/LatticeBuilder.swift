import Foundation

/// A node in the Word Lattice DAG.
public struct LatticeNode: Hashable, Sendable, CustomStringConvertible {
    public let id: Int
    public let start: Int
    public let end: Int
    public let word: String
    public let unigramCost: Double
    public let syllables: [Syllable]

    public init(id: Int, start: Int, end: Int, word: String, unigramCost: Double, syllables: [Syllable] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.word = word
        self.unigramCost = unigramCost
        self.syllables = syllables
    }

    public var description: String {
        return "Node(\(id): \"\(word)\" [\(start)..\(end)], cost=\(String(format: "%.2f", unigramCost)))"
    }
}

/// A Directed Acyclic Graph (DAG) representing all word segmentation hypotheses.
public struct Lattice: Sendable {
    public let syllables: [Syllable]
    public let startNode: LatticeNode
    public let endNode: LatticeNode
    public let allNodes: [LatticeNode]

    /// Nodes indexed by their start syllable position (0..<N).
    public let nodesStartingAt: [[LatticeNode]]

    /// Nodes indexed by their end syllable position (0...N).
    public let nodesEndingAt: [[LatticeNode]]

    public init(
        syllables: [Syllable],
        startNode: LatticeNode,
        endNode: LatticeNode,
        allNodes: [LatticeNode],
        nodesStartingAt: [[LatticeNode]],
        nodesEndingAt: [[LatticeNode]]
    ) {
        self.syllables = syllables
        self.startNode = startNode
        self.endNode = endNode
        self.allNodes = allNodes
        self.nodesStartingAt = nodesStartingAt
        self.nodesEndingAt = nodesEndingAt
    }
}

/// Builds a Word Lattice DAG from a sequence of syllables using a Trie and Lexicon.
public final class LatticeBuilder: Sendable {
    public let trie: Trie
    public let lexicon: Lexicon

    public init(trie: Trie, lexicon: Lexicon) {
        self.trie = trie
        self.lexicon = lexicon
    }

    /// Constructs the Lattice DAG for the given syllables, optionally incorporating spatial candidate slots.
    public func buildLattice(
        for syllables: [Syllable],
        candidateSlots: [[SpatialSyllableCandidate]]? = nil
    ) -> Lattice {
        let n = syllables.count
        var nextId = 0

        let startNode = LatticeNode(
            id: nextId,
            start: -1,
            end: 0,
            word: Lexicon.sentenceStart,
            unigramCost: 0.0,
            syllables: []
        )
        nextId += 1

        var allNodes: [LatticeNode] = [startNode]
        var startingAt = [[LatticeNode]](repeating: [], count: n + 1)
        var endingAt = [[LatticeNode]](repeating: [], count: n + 1)

        // Ensure valid candidate slots matching syllable count
        let slots: [[SpatialSyllableCandidate]]
        if let providedSlots = candidateSlots, providedSlots.count == n {
            slots = providedSlots
        } else {
            slots = syllables.map { [SpatialSyllableCandidate(syllable: $0, penalty: 0.0)] }
        }

        // Find candidate words starting at each position
        for i in 0..<n {
            var bestNodesForWord = [String: (end: Int, cost: Double, syllables: [Syllable])]()

            // 1. Fast-path: Common prefix search on primary syllables starting at i
            let primaryMatches = trie.commonPrefixSearch(in: syllables, from: i)
            for match in primaryMatches {
                let cost = match.entry.unigramCost
                bestNodesForWord[match.entry.word] = (i + match.length, cost, match.entry.syllables)
            }

            // 2. Spatial error-tolerance branches (single typo in length 1 or length 2 words)
            // 2a. Length 1 with typo at position i
            if slots[i].count > 1 {
                let hasExactMatches = trie.root.children[slots[i][0].syllable]?.entries.isEmpty == false
                // When the exact primary syllable exists in dictionary, apply an extra barrier (+2.5)
                // to prevent single-character typo hypotheses from displacing cleanly typed characters
                let extraSingleCharPenalty = hasExactMatches ? 2.5 : 0.0

                for c0 in slots[i].dropFirst() {
                    guard let node0 = trie.root.children[c0.syllable] else { continue }
                    for entry in node0.entries {
                        // Guard against rare phantom readings (e.g. 復 as ㄈㄡˋ with entry.unigramCost 14.5)
                        guard entry.unigramCost <= 9.0 else { continue }
                        let baseCost = entry.unigramCost
                        let totalCost = baseCost + c0.penalty + extraSingleCharPenalty
                        guard totalCost <= 13.0 else { continue }
                        if let existing = bestNodesForWord[entry.word] {
                            if totalCost < existing.cost {
                                bestNodesForWord[entry.word] = (i + 1, totalCost, [c0.syllable])
                            }
                        } else {
                            bestNodesForWord[entry.word] = (i + 1, totalCost, [c0.syllable])
                        }
                    }
                }
            }

            // 2b. Length 2 with typo at position i (primary at i + 1)
            if i + 1 < n {
                if slots[i].count > 1 {
                    let primary1 = slots[i + 1][0]
                    for c0 in slots[i].dropFirst() {
                        guard let node0 = trie.root.children[c0.syllable],
                              let node1 = node0.children[primary1.syllable] else { continue }
                        for entry in node1.entries {
                            guard entry.unigramCost <= 9.5 else { continue }
                            let baseCost = entry.unigramCost
                            let totalCost = baseCost + c0.penalty
                            guard totalCost <= 13.0 else { continue }
                            if let existing = bestNodesForWord[entry.word] {
                                if totalCost < existing.cost {
                                    bestNodesForWord[entry.word] = (i + 2, totalCost, [c0.syllable, primary1.syllable])
                                }
                            } else {
                                bestNodesForWord[entry.word] = (i + 2, totalCost, [c0.syllable, primary1.syllable])
                            }
                        }
                    }
                }

                // 2c. Length 2 with primary at position i (typo at i + 1)
                if slots[i + 1].count > 1 {
                    let primary0 = slots[i][0]
                    if let node0 = trie.root.children[primary0.syllable] {
                        for c1 in slots[i + 1].dropFirst() {
                            guard let node1 = node0.children[c1.syllable] else { continue }
                            for entry in node1.entries {
                                guard entry.unigramCost <= 9.5 else { continue }
                                let baseCost = entry.unigramCost
                                let totalCost = baseCost + c1.penalty
                                guard totalCost <= 13.0 else { continue }
                                if let existing = bestNodesForWord[entry.word] {
                                    if totalCost < existing.cost {
                                        bestNodesForWord[entry.word] = (i + 2, totalCost, [primary0.syllable, c1.syllable])
                                    }
                                } else {
                                    bestNodesForWord[entry.word] = (i + 2, totalCost, [primary0.syllable, c1.syllable])
                                }
                            }
                        }
                    }
                }
            }

            if !bestNodesForWord.isEmpty {
                for (word, spanInfo) in bestNodesForWord {
                    let node = LatticeNode(
                        id: nextId,
                        start: i,
                        end: spanInfo.end,
                        word: word,
                        unigramCost: spanInfo.cost,
                        syllables: spanInfo.syllables
                    )
                    nextId += 1
                    allNodes.append(node)
                    startingAt[node.start].append(node)
                    endingAt[node.end].append(node)
                }
            } else {
                // Fallback OOV node for unknown syllable to guarantee continuous path
                let fallbackSyllable = slots[i].first?.syllable ?? syllables[i]
                let node = LatticeNode(
                    id: nextId,
                    start: i,
                    end: i + 1,
                    word: fallbackSyllable.raw,
                    unigramCost: lexicon.oovCost,
                    syllables: [fallbackSyllable]
                )
                nextId += 1
                allNodes.append(node)
                startingAt[i].append(node)
                endingAt[i + 1].append(node)
            }
        }

        let endNode = LatticeNode(
            id: nextId,
            start: n,
            end: n + 1,
            word: Lexicon.sentenceEnd,
            unigramCost: 0.0,
            syllables: []
        )
        allNodes.append(endNode)
        startingAt[n].append(endNode)

        return Lattice(
            syllables: syllables,
            startNode: startNode,
            endNode: endNode,
            allNodes: allNodes,
            nodesStartingAt: startingAt,
            nodesEndingAt: endingAt
        )
    }
}
