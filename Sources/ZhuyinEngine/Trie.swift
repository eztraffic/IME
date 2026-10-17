import Foundation

/// A node in the phonetic Trie.
public final class TrieNode: @unchecked Sendable {
    public var children: [Syllable: TrieNode] = [:]
    public var entries: [WordEntry] = []

    public init() {}
}

/// Prefix Trie for fast candidate word retrieval based on Zhuyin syllable sequences.
public final class Trie: @unchecked Sendable {
    public let root: TrieNode

    public init() {
        self.root = TrieNode()
    }

    /// Inserts a word entry into the Trie.
    public func insert(_ entry: WordEntry) {
        insertOrUpdate(entry)
    }

    /// Inserts or updates an entry in the Trie. If an entry with the same word already exists, updates its cost to the lower value.
    public func insertOrUpdate(_ entry: WordEntry) {
        guard !entry.syllables.isEmpty else { return }
        var current = root
        for syllable in entry.syllables {
            if let next = current.children[syllable] {
                current = next
            } else {
                let newNode = TrieNode()
                current.children[syllable] = newNode
                current = newNode
            }
        }
        if let idx = current.entries.firstIndex(where: { $0.word == entry.word }) {
            let existing = current.entries[idx]
            if entry.unigramCost < existing.unigramCost {
                current.entries[idx] = entry
            }
        } else {
            current.entries.append(entry)
        }
    }

    /// Updates the unigram cost of a word in the Trie, optionally filtering by specific syllables.
    public func updateWordCost(_ word: String, for syllables: [Syllable]? = nil, newCost: Double) {
        func traverse(node: TrieNode) {
            for i in 0..<node.entries.count {
                if node.entries[i].word == word {
                    if let targetSyllables = syllables, node.entries[i].syllables != targetSyllables {
                        continue
                    }
                    let old = node.entries[i]
                    if newCost < old.unigramCost {
                        node.entries[i] = WordEntry(word: old.word, syllables: old.syllables, unigramCost: newCost)
                    }
                }
            }
            for child in node.children.values {
                traverse(node: child)
            }
        }
        traverse(node: root)
    }

    /// Convenience method to bulk insert from a lexicon.
    public func build(from lexicon: Lexicon) {
        for entry in lexicon.entries {
            insert(entry)
        }
    }

    /// Clears all nodes in the Trie and rebuilds from the given lexicon.
    public func rebuild(from lexicon: Lexicon) {
        root.children.removeAll(keepingCapacity: true)
        root.entries.removeAll(keepingCapacity: true)
        build(from: lexicon)
    }

    /// Finds all matching words whose syllable sequence matches a prefix starting at `startIndex`.
    /// Returns tuples of (entry, matchedSyllableCount).
    public func commonPrefixSearch(in syllables: [Syllable], from startIndex: Int) -> [(entry: WordEntry, length: Int)] {
        var results: [(entry: WordEntry, length: Int)] = []
        guard startIndex >= 0 && startIndex < syllables.count else { return results }

        var current = root
        var currentIndex = startIndex

        while currentIndex < syllables.count {
            let syllable = syllables[currentIndex]
            guard let next = current.children[syllable] else {
                break
            }
            current = next
            currentIndex += 1

            if !current.entries.isEmpty {
                let length = currentIndex - startIndex
                for entry in current.entries {
                    results.append((entry: entry, length: length))
                }
            }
        }

        return results
    }
}
