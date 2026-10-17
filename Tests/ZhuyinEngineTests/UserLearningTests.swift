import XCTest
@testable import ZhuyinEngine

final class UserLearningTests: XCTestCase {
    var tempDirectoryURL: URL!
    var tempLexiconURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        tempLexiconURL = tempDirectoryURL.appendingPathComponent("user_lexicon_test.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        super.tearDown()
    }

    func testHomophoneAggressivePromotion() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)
        let syl = Syllable(parsing: "ㄕㄣ")!

        let initialCandidates = engine.candidates(for: [syl], maxCount: 9)
        XCTAssertFalse(initialCandidates.isEmpty)
        XCTAssertNotEqual(initialCandidates.first, "申", "Default first candidate should not be 申")

        // User manually chooses "申"
        engine.learnHomophoneSelection(syllable: syl, word: "申")

        let learnedCandidates = engine.candidates(for: [syl], maxCount: 9)
        XCTAssertEqual(learnedCandidates.first, "申", "After selection, 申 must immediately be the top candidate (#1)")

        // Best decode path for single syllable should also prioritize "申"
        let decodeRes = engine.decode(syllables: [syl], topK: 1)
        XCTAssertEqual(decodeRes.bestText, "申")
    }

    func testProductionNiHaoNiPromotion() {
        let engine = ZhuyinEngine.production(userLexiconURL: tempLexiconURL)
        let syl = Syllable(parsing: "ㄋㄧˇ")!

        let initialCandidates = engine.candidates(for: [syl], maxCount: 9)
        print("Initial production candidates for ㄋㄧˇ: \(initialCandidates)")
        XCTAssertEqual(initialCandidates.first, "你")

        // Learn "擬"
        engine.learnHomophoneSelection(syllable: syl, word: "擬")

        let learnedCandidates = engine.candidates(for: [syl], maxCount: 9)
        print("Learned production candidates for ㄋㄧˇ: \(learnedCandidates)")
        XCTAssertEqual(learnedCandidates.first, "擬")

        let decoded = engine.decode(syllables: [syl], topK: 1)
        print("Learned production decode for ㄋㄧˇ: \(decoded.bestText)")
        XCTAssertEqual(decoded.bestText, "擬")
    }

    func testAutoUserPhraseLearningDirect() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)
        let syllables = Syllable.parseSequence("ㄔㄣˊ ㄒㄧㄠˇ ㄇㄧㄥˊ")

        // Learn user word directly
        engine.learnUserWord(word: "陳小明", syllables: syllables)

        // After learning, decode must directly produce "陳小明"
        let afterDecode = engine.decode(syllables: syllables, topK: 1)
        XCTAssertEqual(afterDecode.bestText, "陳小明", "Learned user phrase must decode as optimal text")

        // Candidates must include "陳小明"
        let cands = engine.candidates(for: syllables, maxCount: 5)
        XCTAssertEqual(cands.first, "陳小明")
    }

    func testPendingWordRequiresTwoCommitsToPromote() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)

        let s1 = Syllable(parsing: "ㄔㄣˊ")!
        let s2 = Syllable(parsing: "ㄒㄧㄠˇ")!
        let s3 = Syllable(parsing: "ㄇㄧㄥˊ")!
        let items: [CompositionItem] = [.syllable(s1), .syllable(s2), .syllable(s3)]
        let overrides = [0: "陳", 1: "小", 2: "明"]

        // 1st Commit: Enters pending pool (count = 1), NOT yet active in Trie
        engine.learnCommittedSentence(
            items: items,
            committedText: "陳小明",
            userOverrides: overrides
        )

        XCTAssertEqual(uLex.data.pendingWords["陳小明"]?.count, 1, "First commit must place phrase in pendingWords with count 1")
        XCTAssertNil(uLex.data.userWords["陳小明"], "First commit must NOT enter active userWords")

        // 2nd Commit: Confirmed usage reaches threshold (count >= 2) -> promoted!
        engine.learnCommittedSentence(
            items: items,
            committedText: "陳小明",
            userOverrides: overrides
        )

        XCTAssertNil(uLex.data.pendingWords["陳小明"], "Promoted phrase must be removed from pendingWords")
        XCTAssertNotNil(uLex.data.userWords["陳小明"], "Second commit must promote phrase to active userWords")
        XCTAssertEqual(uLex.data.userWords["陳小明"]?.count, 2)

        // Now Viterbi decode must produce "陳小明"
        let decoded = engine.decode(syllables: [s1, s2, s3], topK: 1)
        XCTAssertEqual(decoded.bestText, "陳小明")
    }

    func testPrefixPhraseCandidatesReturned() {
        let engine = ZhuyinEngine.production()
        let syllables = Syllable.parseSequence("ㄋㄧˇ ㄏㄠˇ") // 你好
        XCTAssertEqual(syllables.count, 2)

        let entries = engine.candidatesWithSpan(for: syllables, startIndex: 0, prevWord: nil, maxCount: 10)
        XCTAssertFalse(entries.isEmpty)

        // Must include phrase "你好" with spanLength == 2
        let phraseEntry = entries.first(where: { $0.text == "你好" })
        XCTAssertNotNil(phraseEntry, "Candidate list must include prefix phrase 你好")
        XCTAssertEqual(phraseEntry?.spanLength, 2, "你好 should have spanLength 2")

        // Must also include single-syllable "你" with spanLength == 1
        let singleEntry = entries.first(where: { $0.text == "你" })
        XCTAssertNotNil(singleEntry)
        XCTAssertEqual(singleEntry?.spanLength, 1)
    }

    func testContextualHomophoneLearning() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)
        let syl = Syllable(parsing: "ㄕㄣ")!

        // Learn "申" specifically after previous word "在"
        engine.learnHomophoneSelection(syllable: syl, word: "申", prevWord: "在")

        // Under context "在", "申" is top contextual homophone
        let ctxWords = uLex.contextualHomophones(for: syl.raw, prevWord: "在")
        XCTAssertEqual(ctxWords.first, "申")

        // Under a different context "去", "申" is not contextual
        let otherCtx = uLex.contextualHomophones(for: syl.raw, prevWord: "去")
        XCTAssertTrue(otherCtx.isEmpty)
    }

    func testBigramTransitionLearning() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)

        let initialCost = engine.lexicon.transitionCost(from: "自然", to: "語言")

        // Learn bigram
        engine.learnBigram(prev: "自然", next: "語言")

        let boostedCost = engine.lexicon.transitionCost(from: "自然", to: "語言")
        XCTAssertLessThan(boostedCost, initialCost, "Learned bigram must have strictly lower transition cost")
    }

    func testV1DataAutoBackupAndReset() throws {
        // Create simulated V1 JSON file with version: 1
        let legacyJson = """
        {
            "version": 1,
            "userWords": {
                "錯詞": {
                    "word": "錯詞",
                    "syllablesRaw": ["ㄘㄨㄛˋ", "ㄘˊ"],
                    "count": 1,
                    "lastUsed": "2026-10-10T12:00:00Z"
                }
            },
            "homophoneSelections": {},
            "recentHomophones": {},
            "bigramCounts": {},
            "lastModified": "2026-10-10T12:00:00Z"
        }
        """
        try legacyJson.data(using: .utf8)!.write(to: tempLexiconURL)

        // Loading should trigger backup to .v1.bak and return fresh v2
        let loaded = UserLexicon.load(from: tempLexiconURL)
        XCTAssertEqual(loaded.data.version, 2, "Loaded instance must be upgraded to version 2")
        XCTAssertTrue(loaded.data.userWords.isEmpty, "Upgraded instance should start clean")

        let bakURL = tempLexiconURL.deletingPathExtension().appendingPathExtension("json.v1.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path), "Legacy file must be backed up as .v1.bak")
    }

    func testPauseLearningFlag() {
        let uLex = UserLexicon(storageURL: tempLexiconURL)
        let engine = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex)
        let syl = Syllable(parsing: "ㄕㄣ")!

        uLex.setLearningPaused(true)
        XCTAssertTrue(uLex.data.isLearningPaused)

        // Attempt learning while paused
        engine.learnHomophoneSelection(syllable: syl, word: "申")
        engine.learnBigram(prev: "好", next: "注音")
        _ = engine.learnCandidateUserWord(word: "好注音", syllables: Syllable.parseSequence("ㄏㄠˇ ㄓㄨˋ ㄧㄣ"))

        XCTAssertTrue(uLex.data.globalHomophones.isEmpty, "Homophones should not be recorded when paused")
        XCTAssertTrue(uLex.data.bigramCounts.isEmpty, "Bigrams should not be recorded when paused")
        XCTAssertTrue(uLex.data.pendingWords.isEmpty, "Pending words should not be recorded when paused")
    }

    func testUserLexiconPersistence() throws {
        // 1. Create engine and perform learning
        let uLex1 = UserLexicon(storageURL: tempLexiconURL)
        let engine1 = ZhuyinEngine(lexicon: Lexicon(), userLexicon: uLex1)

        let syl = Syllable(parsing: "ㄕㄣ")!
        engine1.learnHomophoneSelection(syllable: syl, word: "申")
        engine1.learnUserWord(word: "好注音", syllables: Syllable.parseSequence("ㄏㄠˇ ㄓㄨˋ ㄧㄣ"))
        engine1.learnBigram(prev: "好", next: "注音")

        // Save synchronously
        uLex1.saveSync()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempLexiconURL.path))

        // 2. Initialize brand new engine loading from the persisted file
        let loadedULex = UserLexicon.load(from: tempLexiconURL)
        let engine2 = ZhuyinEngine(lexicon: Lexicon(), userLexicon: loadedULex)

        // Verify homophone preference persisted
        let cands = engine2.candidates(for: [syl], maxCount: 5)
        XCTAssertEqual(cands.first, "申", "Persisted homophone preference must be restored")

        // Verify user phrase persisted
        let decodePhrase = engine2.decode(syllables: Syllable.parseSequence("ㄏㄠˇ ㄓㄨˋ ㄧㄣ"), topK: 1)
        XCTAssertEqual(decodePhrase.bestText, "好注音", "Persisted user word must be restored")
    }

    func testZaiRenHeWeiZhi() {
        let engine = ZhuyinEngine.production()
        
        // 1. 驗證「在任何位置」在整句 Viterbi 解碼下 100% 穩定輸出正確介詞「在」
        let zaiSyllables = Syllable.parseSequence("ㄗㄞˋ ㄖㄣˋ ㄏㄜˊ ㄨㄟˋ ㄓˋ")
        let zaiResult = engine.decode(syllables: zaiSyllables, topK: 3)
        XCTAssertEqual(zaiResult.bestText, "在任何位置", "ㄗㄞˋ ㄖㄣˋ ㄏㄜˊ ㄨㄟˋ ㄓˋ 必須解碼為「在任何位置」")
        XCTAssertEqual(zaiResult.candidates.first?.words, ["在", "任何", "位置"])

        // 2. 驗證「在所有情況」亦正確解碼為「在」
        let suoYou = Syllable.parseSequence("ㄗㄞˋ ㄙㄨㄛˇ ㄧㄡˇ")
        let suoYouResult = engine.decode(syllables: suoYou, topK: 1)
        XCTAssertEqual(suoYouResult.bestText, "在所有")

        // 3. 驗證副詞「再一次」正確解碼為「再」
        let zaiCi = Syllable.parseSequence("ㄗㄞˋ ㄧ ㄘˋ")
        let zaiCiResult = engine.decode(syllables: zaiCi, topK: 1)
        XCTAssertEqual(zaiCiResult.bestText, "再一次")
    }

    func testBackwardPhraseCandidatesAtEnd() {
        let engine = ZhuyinEngine.production()

        // 1. 驗證四字成語「一馬當先」在最末字「先」時能往前回溯推算
        let idiomSyllables = Syllable.parseSequence("ㄧ ㄇㄚˇ ㄉㄤ ㄒㄧㄢ")
        let targetSyllable = idiomSyllables.last!
        let preceding = Array(idiomSyllables.dropLast())

        let entries = engine.candidatesWithSpan(
            for: [targetSyllable],
            startIndex: 0,
            precedingSyllables: preceding,
            maxCount: 20
        )

        // 必須包含成語「一馬當先」，且跨度為 4、位移為 -3
        let idiomEntry = entries.first(where: { $0.text == "一馬當先" })
        XCTAssertNotNil(idiomEntry, "末字候選詞必須包含往前推算之成語「一馬當先」")
        XCTAssertEqual(idiomEntry?.spanLength, 4)
        XCTAssertEqual(idiomEntry?.startOffset, -3)

        // 必須包含末兩字詞「當先」，跨度為 2、位移為 -1
        let twoCharEntry = entries.first(where: { $0.text == "當先" })
        XCTAssertNotNil(twoCharEntry, "末字候選詞必須包含往前推算之雙字詞「當先」")
        XCTAssertEqual(twoCharEntry?.spanLength, 2)
        XCTAssertEqual(twoCharEntry?.startOffset, -1)

        // 必須包含單字「先」，跨度為 1、位移為 0
        let singleEntry = entries.first(where: { $0.text == "先" })
        XCTAssertNotNil(singleEntry)
        XCTAssertEqual(singleEntry?.spanLength, 1)
        XCTAssertEqual(singleEntry?.startOffset, 0)

        // 成語長度 4 應排在單字與短詞之前
        if let idxIdiom = entries.firstIndex(where: { $0.text == "一馬當先" }),
           let idxSingle = entries.firstIndex(where: { $0.text == "先" }) {
            XCTAssertLessThan(idxIdiom, idxSingle, "整句成語候選詞應排在末字單字之前")
        }

        // 2. 驗證雙字詞「今天」在最末字「天」時能往前回溯推算
        let jinTian = Syllable.parseSequence("ㄐㄧㄣ ㄊㄧㄢ")
        let tianSyllable = jinTian.last!
        let jinTianEntries = engine.candidatesWithSpan(
            for: [tianSyllable],
            startIndex: 0,
            precedingSyllables: [jinTian[0]],
            maxCount: 20
        )

        let jinTianEntry = jinTianEntries.first(where: { $0.text == "今天" })
        XCTAssertNotNil(jinTianEntry, "末字「天」候選詞必須包含往前推算之雙字詞「今天」")
        XCTAssertEqual(jinTianEntry?.spanLength, 2)
        XCTAssertEqual(jinTianEntry?.startOffset, -1)
    }

    /// 驗證若使用者未手動選字（純打字送出），絕不自動向 bigramCounts 記錄未確認的詞對，防止記憶庫污染與拼湊錯字。
    func testNoBigramPollutionWhenNoOverrides() {
        let engine = ZhuyinEngine.production(userLexiconURL: tempLexiconURL)

        let syllables = Syllable.parseSequence("ㄨㄛˇ ㄉㄧˋ ㄧ ㄘˋ ㄕˇ ㄩㄥˋ") // 我 第一次 使用
        let items = syllables.map { CompositionItem.syllable($0) }

        // 無手動選字，直接送出整句
        engine.learnCommittedSentence(
            items: items,
            committedText: "我第一次使用",
            userOverrides: [:]
        )

        // bigramCounts 必須保持完全空白！
        XCTAssertTrue(engine.userLexicon.data.bigramCounts.isEmpty, "無手動選字時，不得無差別記錄未驗證之二元搭配")
    }

    /// 驗證當使用者有手動選字時，正確記錄該選字之二元搭配，且詞彙名稱直接採用整句 Viterbi 最優路徑（不被拆成孤立字音）。
    func testBigramLearnedOnlyWhenUserOverrides() {
        let engine = ZhuyinEngine.production(userLexiconURL: tempLexiconURL)

        // 模擬輸入：在 任何 位置
        let syllables = Syllable.parseSequence("ㄗㄞˋ ㄖㄣˋ ㄏㄜˊ ㄨㄟˋ ㄓˋ")
        let items = syllables.map { CompositionItem.syllable($0) }

        // 使用者手動選定第 0 字為「在」
        let overrides: [Int: String] = [0: "在"]

        engine.learnCommittedSentence(
            items: items,
            committedText: "在任何位置",
            userOverrides: overrides
        )

        // 應當記錄「在|任何」的轉移搭配，但「任何|位置」因未被使用者選取，不應記錄
        XCTAssertEqual(engine.userLexicon.data.bigramCounts["在|任何"], 1, "手動選字處「在|任何」必須被記錄")
        XCTAssertNil(engine.userLexicon.data.bigramCounts["任何|位置"], "未手動選取之詞對「任何|位置」不應被記錄")
    }
}

