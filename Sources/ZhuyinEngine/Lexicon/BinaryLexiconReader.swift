import Foundation

/// Fast parser and loader for precompiled binary Zhuyin lexicon files (`.bin`).
public enum BinaryLexiconReader {
    public enum LexiconError: Error, LocalizedError {
        case fileNotFound
        case invalidMagic
        case unsupportedVersion(UInt16)
        case corruptedData(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The binary lexicon file could not be found."
            case .invalidMagic:
                return "The binary file magic bytes do not match expected 'ZYLX'."
            case .unsupportedVersion(let ver):
                return "Unsupported binary lexicon version: \(ver)."
            case .corruptedData(let msg):
                return "Corrupted binary lexicon data: \(msg)."
            }
        }
    }

    /// Locates the bundled or workspace `lexicon.bin` file.
    public static func findDefaultBinaryURL() -> URL? {
        let fileManager = FileManager.default

        // 1. Check Bundle.main first (when running as macOS .app bundle, fully self-contained)
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("lexicon.bin"),
           fileManager.fileExists(atPath: resURL.path) {
            return resURL
        }
        if let mainURL = Bundle.main.url(forResource: "lexicon", withExtension: "bin"),
           fileManager.fileExists(atPath: mainURL.path) {
            return mainURL
        }
        if let bundleResURL = Bundle.main.resourceURL?.appendingPathComponent("ZhuyinEngine_ZhuyinEngine.bundle/lexicon.bin"),
           fileManager.fileExists(atPath: bundleResURL.path) {
            return bundleResURL
        }

        // 2. Check Bundle.module (primarily for SPM xctest runners or standalone library clients)
        #if SWIFT_PACKAGE
        if let bundleURL = Bundle.module.url(forResource: "lexicon", withExtension: "bin"),
           fileManager.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        if let resURL = Bundle.module.resourceURL?.appendingPathComponent("lexicon.bin"),
           fileManager.fileExists(atPath: resURL.path) {
            return resURL
        }
        #endif

        // 3. Check candidate local paths relative to current working directory
        let localCandidates = [
            "Sources/ZhuyinEngine/Resources/lexicon.bin",
            "../Sources/ZhuyinEngine/Resources/lexicon.bin",
            "../../Sources/ZhuyinEngine/Resources/lexicon.bin"
        ]

        let cwd = fileManager.currentDirectoryPath
        for rel in localCandidates {
            let fullPath = URL(fileURLWithPath: cwd).appendingPathComponent(rel).standardized.path
            if fileManager.fileExists(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }

        return nil
    }

    @inline(__always)
    private static func readUInt16(from ptr: UnsafePointer<UInt8>, offset: Int) -> UInt16 {
        return UInt16(ptr[offset]) | (UInt16(ptr[offset + 1]) << 8)
    }

    @inline(__always)
    private static func readUInt32(from ptr: UnsafePointer<UInt8>, offset: Int) -> UInt32 {
        return UInt32(ptr[offset])
            | (UInt32(ptr[offset + 1]) << 8)
            | (UInt32(ptr[offset + 2]) << 16)
            | (UInt32(ptr[offset + 3]) << 24)
    }

    @inline(__always)
    private static func readFloat32(from ptr: UnsafePointer<UInt8>, offset: Int) -> Float32 {
        let bits = readUInt32(from: ptr, offset: offset)
        return Float32(bitPattern: bits)
    }

    /// Deserializes a `Lexicon` from raw binary `Data`.
    public static func read(from data: Data) throws -> Lexicon {
        return try data.withUnsafeBytes { rawBuffer -> Lexicon in
            guard rawBuffer.count >= 16 else {
                throw LexiconError.corruptedData("Header too small")
            }

            let base = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var offset = 0

            // 1. Verify Magic "ZYLX" (0x5A, 0x59, 0x4C, 0x58)
            guard base[0] == 0x5A, base[1] == 0x59, base[2] == 0x4C, base[3] == 0x58 else {
                throw LexiconError.invalidMagic
            }
            offset += 4

            // 2. Read Header fields (alignment-safe)
            let version = readUInt16(from: base, offset: offset)
            offset += 2
            guard version == 1 else {
                throw LexiconError.unsupportedVersion(version)
            }

            _ = readUInt16(from: base, offset: offset) // flags
            offset += 2

            let entryCount = Int(readUInt32(from: base, offset: offset))
            offset += 4

            let bigramCount = Int(readUInt32(from: base, offset: offset))
            offset += 4

            // 3. Read Entries
            var entries = [WordEntry]()
            entries.reserveCapacity(entryCount)
            var unigramCosts = [String: Double]()
            unigramCosts.reserveCapacity(entryCount)

            // Cache repeated parsed syllables to eliminate duplicate parsing
            var syllableCache = [String: Syllable]()
            syllableCache.reserveCapacity(2000)

            let totalBytes = rawBuffer.count

            for _ in 0..<entryCount {
                guard offset < totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in entries")
                }
                let wordLen = Int(base[offset])
                offset += 1

                guard offset + wordLen <= totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in word string")
                }
                let word = String(decoding: UnsafeBufferPointer(start: base + offset, count: wordLen), as: UTF8.self)
                offset += wordLen

                guard offset + 4 <= totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in cost")
                }
                let costFloat = readFloat32(from: base, offset: offset)
                let cost = Double(costFloat)
                offset += 4

                guard offset < totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in syllable count")
                }
                let sylCount = Int(base[offset])
                offset += 1

                var syllables = [Syllable]()
                syllables.reserveCapacity(sylCount)

                for _ in 0..<sylCount {
                    guard offset < totalBytes else {
                        throw LexiconError.corruptedData("Unexpected EOF in syllable length")
                    }
                    let sylLen = Int(base[offset])
                    offset += 1

                    guard offset + sylLen <= totalBytes else {
                        throw LexiconError.corruptedData("Unexpected EOF in syllable string")
                    }
                    let sylStr = String(decoding: UnsafeBufferPointer(start: base + offset, count: sylLen), as: UTF8.self)
                    offset += sylLen

                    if let cached = syllableCache[sylStr] {
                        syllables.append(cached)
                    } else if let parsed = Syllable(parsing: sylStr) {
                        syllableCache[sylStr] = parsed
                        syllables.append(parsed)
                    } else {
                        let fallback = Syllable(initial: nil, medial: nil, rhyme: nil, tone: .first)
                        syllables.append(fallback)
                    }
                }

                let entry = WordEntry(word: word, syllables: syllables, unigramCost: cost)
                entries.append(entry)
                if let existing = unigramCosts[word] {
                    unigramCosts[word] = min(existing, cost)
                } else {
                    unigramCosts[word] = cost
                }
            }

            // 4. Read Bigram Transitions
            var bigramCosts = [BigramKey: Double]()
            bigramCosts.reserveCapacity(bigramCount)

            for _ in 0..<bigramCount {
                guard offset < totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in bigram prev length")
                }
                let prevLen = Int(base[offset])
                offset += 1

                guard offset + prevLen <= totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in bigram prev string")
                }
                let prev = String(decoding: UnsafeBufferPointer(start: base + offset, count: prevLen), as: UTF8.self)
                offset += prevLen

                guard offset < totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in bigram next length")
                }
                let nextLen = Int(base[offset])
                offset += 1

                guard offset + nextLen <= totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in bigram next string")
                }
                let next = String(decoding: UnsafeBufferPointer(start: base + offset, count: nextLen), as: UTF8.self)
                offset += nextLen

                guard offset + 4 <= totalBytes else {
                    throw LexiconError.corruptedData("Unexpected EOF in bigram cost")
                }
                let costFloat = readFloat32(from: base, offset: offset)
                offset += 4

                bigramCosts[BigramKey(prev: prev, next: next)] = Double(costFloat)
            }

            return Lexicon(entries: entries, bigrams: bigramCosts, backoffPenalty: 3.5)
        }
    }
}
