import Foundation

/// Represents a decoded candidate path through the lattice.
public struct CandidatePath: Sendable, CustomStringConvertible {
    public let text: String
    public let words: [String]
    public let totalCost: Double
    public let syllables: [Syllable]

    public init(text: String, words: [String], totalCost: Double, syllables: [Syllable] = []) {
        self.text = text
        self.words = words
        self.totalCost = totalCost
        self.syllables = syllables
    }

    public var description: String {
        return "\"\(text)\" (Cost: \(String(format: "%.2f", totalCost))) [\(words.joined(separator: " | "))]"
    }
}

/// Compact hypothesis node stored in a contiguous pool for zero-allocation path tracking.
private struct Hypothesis: Comparable {
    let cost: Double
    let nodeId: Int
    let prevIndex: Int?

    static func < (lhs: Hypothesis, rhs: Hypothesis) -> Bool {
        return lhs.cost < rhs.cost
    }
}

/// Viterbi dynamic programming decoder with backoff smoothing and K-best path extraction.
public final class ViterbiDecoder: Sendable {
    public let lexicon: Lexicon

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// Decodes the lattice and returns the top-K optimal paths.
    public func decode(lattice: Lattice, topK: Int = 3) -> [CandidatePath] {
        guard !lattice.syllables.isEmpty else { return [] }
        let n = lattice.syllables.count
        let beamLimit = max(topK * 10, 30)

        // Contiguous pool of hypotheses
        var pool = [Hypothesis]()
        pool.reserveCapacity(512)

        // Maps node id to hypothesis indices in `pool`
        var nodeHypotheses = [Int: [Int]]()
        nodeHypotheses.reserveCapacity(lattice.allNodes.count)

        // Start node hypothesis
        pool.append(Hypothesis(cost: 0.0, nodeId: lattice.startNode.id, prevIndex: nil))
        nodeHypotheses[lattice.startNode.id] = [0]

        // Forward DP across boundary positions: 0 to N
        for t in 0...n {
            let incomingNodes = (t == 0) ? [lattice.startNode] : lattice.nodesEndingAt[t]
            let outgoingNodes = (t == n) ? [lattice.endNode] : lattice.nodesStartingAt[t]

            guard !incomingNodes.isEmpty && !outgoingNodes.isEmpty else {
                continue
            }

            // Filter incoming nodes that have valid hypotheses
            let validIncoming = incomingNodes.compactMap { u -> (node: LatticeNode, indices: [Int])? in
                guard let indices = nodeHypotheses[u.id], !indices.isEmpty else { return nil }
                return (u, indices)
            }

            guard !validIncoming.isEmpty else { continue }

            // Compute hypotheses for each outgoing node v
            for v in outgoingNodes {
                var candidateHyps = [Hypothesis]()
                candidateHyps.reserveCapacity(validIncoming.count * beamLimit)

                // Account for any typo edit-distance penalty attached to node v (e.g. from spatial tolerance)
                let typoPenalty = max(0.0, v.unigramCost - (lexicon.unigramCosts[v.word] ?? v.unigramCost))

                for (u, uIndices) in validIncoming {
                    let transCost = lexicon.transitionCost(from: u.word, to: v.word)

                    for hypIdx in uIndices {
                        let prevCost = pool[hypIdx].cost
                        let newCost = prevCost + transCost + typoPenalty
                        candidateHyps.append(Hypothesis(cost: newCost, nodeId: v.id, prevIndex: hypIdx))
                    }
                }

                if !candidateHyps.isEmpty {
                    candidateHyps.sort()
                    let countToKeep = min(candidateHyps.count, beamLimit)
                    var keptIndices = [Int]()
                    keptIndices.reserveCapacity(countToKeep)

                    for i in 0..<countToKeep {
                        let poolIdx = pool.count
                        pool.append(candidateHyps[i])
                        keptIndices.append(poolIdx)
                    }

                    nodeHypotheses[v.id] = keptIndices
                }
            }
        }

        guard let endIndices = nodeHypotheses[lattice.endNode.id], !endIndices.isEmpty else {
            return []
        }

        // Backtrack and build candidate paths
        var seenTexts = Set<String>()
        var candidates: [CandidatePath] = []

        for endIdx in endIndices {
            let finalHyp = pool[endIdx]

            // Backtrack path
            var words = [String]()
            var syllables = [Syllable]()
            var current: Int? = finalHyp.prevIndex
            while let idx = current {
                let h = pool[idx]
                let node = lattice.allNodes[h.nodeId]
                if node.id != lattice.startNode.id && node.id != lattice.endNode.id {
                    words.append(node.word)
                    syllables.append(contentsOf: node.syllables.reversed())
                }
                current = h.prevIndex
            }
            words.reverse()
            syllables.reverse()

            let text = words.joined()
            if !seenTexts.contains(text) {
                seenTexts.insert(text)
                candidates.append(CandidatePath(
                    text: text,
                    words: words,
                    totalCost: finalHyp.cost,
                    syllables: syllables
                ))
                if candidates.count >= topK {
                    break
                }
            }
        }

        return candidates
    }
}
