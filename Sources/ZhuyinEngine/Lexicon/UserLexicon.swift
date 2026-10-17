import Foundation

/// Represents a user-learned or custom vocabulary entry.
public struct UserWordEntry: Codable, Sendable, Hashable {
    public let word: String
    public let syllablesRaw: [String]
    public var count: Int
    public var lastUsed: Date
    public var userCost: Double?

    public init(
        word: String,
        syllablesRaw: [String],
        count: Int = 1,
        lastUsed: Date = Date(),
        userCost: Double? = nil
    ) {
        self.word = word
        self.syllablesRaw = syllablesRaw
        self.count = count
        self.lastUsed = lastUsed
        self.userCost = userCost
    }
}

/// Represents a candidate phrase waiting for confirmation threshold.
public struct PendingWordEntry: Codable, Sendable, Hashable {
    public let word: String
    public let syllablesRaw: [String]
    public var count: Int
    public var lastSeen: Date

    public init(
        word: String,
        syllablesRaw: [String],
        count: Int = 1,
        lastSeen: Date = Date()
    ) {
        self.word = word
        self.syllablesRaw = syllablesRaw
        self.count = count
        self.lastSeen = lastSeen
    }
}

/// Represents a recorded article ingestion batch that can be inspected and rolled back.
public struct IngestionBatch: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sourceName: String
    public let timestamp: Date
    /// Word frequency deltas applied in this batch: [word: countDelta]
    public let wordDeltas: [String: Int]
    /// Syllable sequences for words in this batch: [word: [syllableRaw]]
    public let wordSyllables: [String: [String]]
    /// Computed unigram costs for words in this batch: [word: cost]
    public let wordCosts: [String: Double]
    /// Bigram transition deltas applied in this batch: ["prevWord|nextWord": countDelta]
    public let bigramDeltas: [String: Int]
    /// Contextual homophone deltas: ["prevWord#syllableRaw": [word: countDelta]]
    public let contextualHomophoneDeltas: [String: [String: Int]]
    /// Global homophone deltas: [syllableRaw: [word: countDelta]]
    public let globalHomophoneDeltas: [String: [String: Int]]

    public init(
        id: UUID = UUID(),
        sourceName: String,
        timestamp: Date = Date(),
        wordDeltas: [String: Int],
        wordSyllables: [String: [String]],
        wordCosts: [String: Double] = [:],
        bigramDeltas: [String: Int],
        contextualHomophoneDeltas: [String: [String: Int]] = [:],
        globalHomophoneDeltas: [String: [String: Int]] = [:]
    ) {
        self.id = id
        self.sourceName = sourceName
        self.timestamp = timestamp
        self.wordDeltas = wordDeltas
        self.wordSyllables = wordSyllables
        self.wordCosts = wordCosts
        self.bigramDeltas = bigramDeltas
        self.contextualHomophoneDeltas = contextualHomophoneDeltas
        self.globalHomophoneDeltas = globalHomophoneDeltas
    }
}

/// Persistent data schema for UserLexicon (Version 2).
public struct UserLexiconData: Codable, Sendable {
    public var version: Int = 2
    /// Whether adaptive learning is paused by the user.
    public var isLearningPaused: Bool = false
    /// Confirmed user-defined or auto-promoted words keyed by word string.
    public var userWords: [String: UserWordEntry] = [:]
    /// Candidate phrases waiting for second confirmation threshold before entering dictionary.
    public var pendingWords: [String: PendingWordEntry] = [:]
    /// Context-sensitive homophone selection counts: ["prevWord#syllableRaw": [word: count]]
    public var contextualHomophones: [String: [String: Int]] = [:]
    /// Global homophone selection counts: [syllableRaw: [word: count]]
    public var globalHomophones: [String: [String: Int]] = [:]
    /// Most-Recently-Used (MRU) homophone list for top ranking: [syllableRaw: [word]]
    public var recentHomophones: [String: [String]] = [:]
    /// Bigram transition counts: ["prevWord|nextWord": count]
    public var bigramCounts: [String: Int] = [:]
    /// History of article ingestion batches for one-click rollback.
    public var batchHistory: [IngestionBatch] = []
    /// Last modification timestamp.
    public var lastModified: Date = Date()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version
        case isLearningPaused
        case userWords
        case pendingWords
        case contextualHomophones
        case globalHomophones
        case recentHomophones
        case bigramCounts
        case batchHistory
        case lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.isLearningPaused = try container.decodeIfPresent(Bool.self, forKey: .isLearningPaused) ?? false
        self.userWords = try container.decode([String: UserWordEntry].self, forKey: .userWords)
        self.pendingWords = try container.decodeIfPresent([String: PendingWordEntry].self, forKey: .pendingWords) ?? [:]
        self.contextualHomophones = try container.decode([String: [String: Int]].self, forKey: .contextualHomophones)
        self.globalHomophones = try container.decode([String: [String: Int]].self, forKey: .globalHomophones)
        self.recentHomophones = try container.decode([String: [String]].self, forKey: .recentHomophones)
        self.bigramCounts = try container.decode([String: Int].self, forKey: .bigramCounts)
        self.batchHistory = try container.decodeIfPresent([IngestionBatch].self, forKey: .batchHistory) ?? []
        self.lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
    }
}

/// Manages dynamic learning, user vocabulary, adaptive homophone preferences,
/// bigram context learning, and background persistence.
public final class UserLexicon: @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var data: UserLexiconData
    public let storageURL: URL?

    private var saveWorkItem: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "org.antigravity.HaoZhuyin.UserLexiconIO", qos: .utility)

    public init(data: UserLexiconData = UserLexiconData(), storageURL: URL? = nil) {
        self.data = data
        self.storageURL = storageURL
    }

    /// Default persistence URL: ~/Library/Application Support/HaoZhuyin/user_lexicon.json
    public static func defaultStorageURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = appSupport.appendingPathComponent("HaoZhuyin", isDirectory: true)
        return folder.appendingPathComponent("user_lexicon.json")
    }

    /// Loads the UserLexicon from disk if available, or returns an empty instance.
    /// Handles migration/reset: if file is version 1 or unreadable, creates a backup `.v1.bak` and starts clean V2.
    public static func load(from url: URL? = nil) -> UserLexicon {
        let targetURL = url ?? defaultStorageURL()
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return UserLexicon(storageURL: targetURL)
        }

        do {
            let fileData = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Try decoding Version 2
            if let decoded = try? decoder.decode(UserLexiconData.self, from: fileData), decoded.version >= 2 {
                return UserLexicon(data: decoded, storageURL: targetURL)
            }

            // Older version (v1) or incompatible schema: backup old file and reset clean v2
            let bakURL = targetURL.deletingPathExtension().appendingPathExtension("json.v1.bak")
            try? FileManager.default.removeItem(at: bakURL)
            try? FileManager.default.copyItem(at: targetURL, to: bakURL)
            NSLog("[HaoZhuyin] Backed up legacy user lexicon to %@ and initialized clean v2 lexicon.", bakURL.path)

            let fresh = UserLexicon(storageURL: targetURL)
            fresh.saveSync()
            return fresh
        } catch {
            NSLog("[HaoZhuyin] Warning: Failed to load user lexicon from %@: %@", targetURL.path, error.localizedDescription)
            return UserLexicon(storageURL: targetURL)
        }
    }

    // MARK: - Learning State Control

    /// Toggles learning pause state.
    public func setLearningPaused(_ paused: Bool) {
        lock.lock()
        data.isLearningPaused = paused
        data.lastModified = Date()
        lock.unlock()
        scheduleSave()
    }

    // MARK: - Learning Operations

    /// Records a homophone selection by the user, optionally with prior context word.
    public func recordHomophoneSelection(syllableRaw: String, word: String, prevWord: String? = nil) {
        lock.lock()
        defer {
            lock.unlock()
            scheduleSave()
        }

        guard !data.isLearningPaused else { return }

        // 1. Contextual record if previous word exists
        if let prev = prevWord, !prev.isEmpty {
            let ctxKey = "\(prev)#\(syllableRaw)"
            var ctxMap = data.contextualHomophones[ctxKey] ?? [:]
            ctxMap[word, default: 0] += 1
            data.contextualHomophones[ctxKey] = ctxMap
        }

        // 2. Global count
        var global = data.globalHomophones[syllableRaw] ?? [:]
        global[word, default: 0] += 1
        data.globalHomophones[syllableRaw] = global

        // 3. Update MRU list (limit to 10)
        var recent = data.recentHomophones[syllableRaw] ?? []
        recent.removeAll { $0 == word }
        recent.insert(word, at: 0)
        if recent.count > 10 {
            recent = Array(recent.prefix(10))
        }
        data.recentHomophones[syllableRaw] = recent
        data.lastModified = Date()
    }

    /// Returns the context-matched homophones for a syllable given previous word.
    public func contextualHomophones(for syllableRaw: String, prevWord: String?) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard let prev = prevWord, !prev.isEmpty else { return [] }
        let ctxKey = "\(prev)#\(syllableRaw)"
        guard let map = data.contextualHomophones[ctxKey] else { return [] }
        return map.sorted { $0.value > $1.value }.map { $0.key }
    }

    /// Returns the most recently chosen homophones for this syllable.
    public func recentHomophones(for syllableRaw: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return data.recentHomophones[syllableRaw] ?? []
    }

    /// Records a candidate user word into pending pool.
    /// Returns true if this phrase reaches threshold (count >= 2) and is promoted to active user words!
    public func recordCandidateUserWord(word: String, syllablesRaw: [String], cost: Double? = nil) -> Bool {
        guard !word.isEmpty, syllablesRaw.count >= 2, syllablesRaw.count <= 4 else { return false }

        lock.lock()
        defer {
            lock.unlock()
            scheduleSave()
        }

        guard !data.isLearningPaused else { return false }

        // If already an active user word, increment usage count
        if var existing = data.userWords[word] {
            existing.count += 1
            existing.lastUsed = Date()
            if let cost = cost { existing.userCost = cost }
            data.userWords[word] = existing
            data.lastModified = Date()
            return false
        }

        // Check pending candidate pool
        if var pending = data.pendingWords[word] {
            pending.count += 1
            pending.lastSeen = Date()

            if pending.count >= 2 {
                // Promoted to active user words!
                data.pendingWords.removeValue(forKey: word)
                let finalCost = cost ?? max(1.2, 2.5 - log(Double(pending.count + 1)))
                let active = UserWordEntry(
                    word: word,
                    syllablesRaw: syllablesRaw,
                    count: pending.count,
                    lastUsed: Date(),
                    userCost: finalCost
                )
                data.userWords[word] = active
                data.lastModified = Date()
                return true
            } else {
                data.pendingWords[word] = pending
                data.lastModified = Date()
                return false
            }
        } else {
            // First time seen: place in pending pool
            let entry = PendingWordEntry(word: word, syllablesRaw: syllablesRaw, count: 1, lastSeen: Date())
            data.pendingWords[word] = entry
            data.lastModified = Date()
            return false
        }
    }

    /// Directly registers or updates an active user word (used for import or confirmed phrases).
    public func recordUserWord(word: String, syllablesRaw: [String], cost: Double? = nil) {
        guard !word.isEmpty && !syllablesRaw.isEmpty else { return }

        lock.lock()
        defer {
            lock.unlock()
            scheduleSave()
        }

        guard !data.isLearningPaused else { return }

        if var existing = data.userWords[word] {
            existing.count += 1
            existing.lastUsed = Date()
            if let cost = cost {
                existing.userCost = cost
            }
            data.userWords[word] = existing
        } else {
            let entry = UserWordEntry(
                word: word,
                syllablesRaw: syllablesRaw,
                count: 1,
                lastUsed: Date(),
                userCost: cost
            )
            data.userWords[word] = entry
        }
        data.lastModified = Date()
    }

    /// Records a bigram transition between consecutive words.
    public func recordBigram(prev: String, next: String) {
        guard !prev.isEmpty && !next.isEmpty else { return }
        guard prev != Lexicon.sentenceStart && next != Lexicon.sentenceEnd else { return }

        lock.lock()
        defer {
            lock.unlock()
            scheduleSave()
        }

        guard !data.isLearningPaused else { return }

        let key = "\(prev)|\(next)"
        data.bigramCounts[key, default: 0] += 1
        data.lastModified = Date()
    }

    /// Clears all learned data.
    public func clearAllLearnedData() {
        lock.lock()
        data = UserLexiconData()
        lock.unlock()
        saveSync()
    }

    /// Backward compatibility alias.
    public func clear() {
        clearAllLearnedData()
    }

    // MARK: - Export and Import

    /// Exports the user lexicon data to a destination file URL as formatted JSON.
    public func export(to destinationURL: URL) throws {
        let snapshot: UserLexiconData
        lock.lock()
        snapshot = self.data
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(snapshot)

        let folder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try encodedData.write(to: destinationURL, options: .atomic)
    }

    /// Imports user lexicon data from a file URL.
    /// - Parameters:
    ///   - sourceURL: The source JSON file URL.
    ///   - merge: If true, merges entries with existing data. If false, completely replaces current data.
    public func importData(from sourceURL: URL, merge: Bool = true) throws {
        let fileData = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(UserLexiconData.self, from: fileData)

        lock.lock()
        if merge {
            // 1. Merge userWords
            for (word, entry) in imported.userWords {
                if var existing = data.userWords[word] {
                    existing.count += entry.count
                    existing.lastUsed = max(existing.lastUsed, entry.lastUsed)
                    if let newCost = entry.userCost {
                        existing.userCost = min(existing.userCost ?? newCost, newCost)
                    }
                    data.userWords[word] = existing
                } else {
                    data.userWords[word] = entry
                }
            }

            // 2. Merge pendingWords
            for (word, entry) in imported.pendingWords {
                if var existing = data.pendingWords[word] {
                    existing.count += entry.count
                    existing.lastSeen = max(existing.lastSeen, entry.lastSeen)
                    data.pendingWords[word] = existing
                } else {
                    data.pendingWords[word] = entry
                }
            }

            // 3. Merge contextualHomophones
            for (key, dict) in imported.contextualHomophones {
                var current = data.contextualHomophones[key] ?? [:]
                for (char, cnt) in dict {
                    current[char, default: 0] += cnt
                }
                data.contextualHomophones[key] = current
            }

            // 4. Merge globalHomophones
            for (key, dict) in imported.globalHomophones {
                var current = data.globalHomophones[key] ?? [:]
                for (char, cnt) in dict {
                    current[char, default: 0] += cnt
                }
                data.globalHomophones[key] = current
            }

            // 5. Merge recentHomophones
            for (key, list) in imported.recentHomophones {
                var current = data.recentHomophones[key] ?? []
                for item in list {
                    if !current.contains(item) {
                        current.append(item)
                    }
                }
                data.recentHomophones[key] = current
            }

        // 6. Merge bigramCounts
            for (key, count) in imported.bigramCounts {
                data.bigramCounts[key, default: 0] += count
            }

            // 7. Merge batchHistory
            let existingBatchIDs = Set(data.batchHistory.map { $0.id })
            for batch in imported.batchHistory where !existingBatchIDs.contains(batch.id) {
                data.batchHistory.append(batch)
            }

            data.lastModified = Date()
        } else {
            // Replace completely
            data = imported
            data.lastModified = Date()
        }
        lock.unlock()

        saveSync()
    }

    // MARK: - Article Ingestion Batch & Rollback

    /// Applies an article ingestion batch into the user lexicon and records it in `batchHistory`.
    /// Note: Does NOT modify `recentHomophones` (MRU) so single-character typing is never hijacked by the end of an article.
    public func applyIngestionBatch(_ batch: IngestionBatch) {
        lock.lock()
        defer {
            lock.unlock()
            scheduleSave()
        }

        // 1. Apply word deltas
        for (word, delta) in batch.wordDeltas where delta > 0 {
            if var existing = data.userWords[word] {
                existing.count += delta
                existing.lastUsed = max(existing.lastUsed, batch.timestamp)
                let newCost = ModelBlender.computeUnigramCost(count: existing.count)
                if let prevCost = existing.userCost {
                    existing.userCost = min(prevCost, newCost)
                } else {
                    existing.userCost = newCost
                }
                data.userWords[word] = existing
            } else if let syls = batch.wordSyllables[word], !syls.isEmpty {
                let cost = batch.wordCosts[word] ?? ModelBlender.computeUnigramCost(count: delta)
                let entry = UserWordEntry(
                    word: word,
                    syllablesRaw: syls,
                    count: delta,
                    lastUsed: batch.timestamp,
                    userCost: cost
                )
                data.userWords[word] = entry
            }
        }

        // 2. Apply bigram deltas
        for (key, delta) in batch.bigramDeltas where delta > 0 {
            data.bigramCounts[key, default: 0] += delta
        }

        // 3. Apply contextual homophone deltas
        for (ctxKey, wordMap) in batch.contextualHomophoneDeltas {
            var current = data.contextualHomophones[ctxKey] ?? [:]
            for (word, delta) in wordMap where delta > 0 {
                current[word, default: 0] += delta
            }
            if !current.isEmpty {
                data.contextualHomophones[ctxKey] = current
            }
        }

        // 4. Apply global homophone deltas
        for (sylRaw, wordMap) in batch.globalHomophoneDeltas {
            var current = data.globalHomophones[sylRaw] ?? [:]
            for (word, delta) in wordMap where delta > 0 {
                current[word, default: 0] += delta
            }
            if !current.isEmpty {
                data.globalHomophones[sylRaw] = current
            }
        }

        // 5. Record batch in history (most recent first, cap at 50)
        data.batchHistory.insert(batch, at: 0)
        if data.batchHistory.count > 50 {
            data.batchHistory = Array(data.batchHistory.prefix(50))
        }
        data.lastModified = Date()
    }

    /// Rolls back a previously applied ingestion batch by subtracting its exact deltas.
    /// Returns true if the batch was found and rolled back.
    @discardableResult
    public func rollbackBatch(id: UUID) -> Bool {
        lock.lock()
        guard let idx = data.batchHistory.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return false
        }

        let batch = data.batchHistory.remove(at: idx)

        // 1. Subtract word deltas
        for (word, delta) in batch.wordDeltas where delta > 0 {
            if var existing = data.userWords[word] {
                existing.count -= delta
                if existing.count <= 0 {
                    data.userWords.removeValue(forKey: word)
                } else {
                    existing.userCost = ModelBlender.computeUnigramCost(count: existing.count)
                    data.userWords[word] = existing
                }
            }
        }

        // 2. Subtract bigram deltas
        for (key, delta) in batch.bigramDeltas where delta > 0 {
            if let current = data.bigramCounts[key] {
                let remaining = current - delta
                if remaining <= 0 {
                    data.bigramCounts.removeValue(forKey: key)
                } else {
                    data.bigramCounts[key] = remaining
                }
            }
        }

        // 3. Subtract contextual homophone deltas
        for (ctxKey, wordMap) in batch.contextualHomophoneDeltas {
            guard var current = data.contextualHomophones[ctxKey] else { continue }
            for (word, delta) in wordMap where delta > 0 {
                if let cnt = current[word] {
                    let remaining = cnt - delta
                    if remaining <= 0 {
                        current.removeValue(forKey: word)
                    } else {
                        current[word] = remaining
                    }
                }
            }
            if current.isEmpty {
                data.contextualHomophones.removeValue(forKey: ctxKey)
            } else {
                data.contextualHomophones[ctxKey] = current
            }
        }

        // 4. Subtract global homophone deltas
        for (sylRaw, wordMap) in batch.globalHomophoneDeltas {
            guard var current = data.globalHomophones[sylRaw] else { continue }
            for (word, delta) in wordMap where delta > 0 {
                if let cnt = current[word] {
                    let remaining = cnt - delta
                    if remaining <= 0 {
                        current.removeValue(forKey: word)
                    } else {
                        current[word] = remaining
                    }
                }
            }
            if current.isEmpty {
                data.globalHomophones.removeValue(forKey: sylRaw)
            } else {
                data.globalHomophones[sylRaw] = current
            }
        }

        data.lastModified = Date()
        lock.unlock()

        saveSync()
        return true
    }

    // MARK: - Persistence & Debounced Saving

    /// Schedules a debounced background save (0.3s delay) to ensure zero UI latency.
    public func scheduleSave() {
        guard let targetURL = storageURL else { return }

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.saveWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.saveSync(to: targetURL)
            }
            self.saveWorkItem = workItem
            self.ioQueue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }

    /// Synchronously writes data to disk (used during app termination or tests).
    public func saveSync(to url: URL? = nil) {
        guard let targetURL = url ?? storageURL else { return }

        let snapshot: UserLexiconData
        lock.lock()
        snapshot = self.data
        lock.unlock()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let encodedData = try encoder.encode(snapshot)

            let folder = targetURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            try encodedData.write(to: targetURL, options: .atomic)
        } catch {
            NSLog("[HaoZhuyin] Error saving user lexicon to %@: %@", targetURL.path, error.localizedDescription)
        }
    }

    /// Flushes any pending background save immediately.
    public func flushSync() {
        saveWorkItem?.cancel()
        saveSync()
    }
}
