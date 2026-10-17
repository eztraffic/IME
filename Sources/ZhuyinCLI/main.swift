import Foundation
import ZhuyinEngine

func printResult(_ result: DecodingResult, composedZhuyin: String? = nil) {
    print("========================================")
    if let zhuyin = composedZhuyin, !zhuyin.isEmpty {
        print("【組字注音】    : \(zhuyin)")
    }
    print("【最優文字結果】: \(result.bestText)")
    print("【解碼耗時】    : \(String(format: "%.3f", result.durationMs)) ms")
    print("【Top-3 候選路徑】:")
    if result.candidates.isEmpty {
        print("  (無候選路徑)")
    } else {
        for (idx, candidate) in result.candidates.enumerated() {
            let segmentation = candidate.words.joined(separator: " | ")
            print("  \(idx + 1). \(candidate.text) (Cost: \(String(format: "%.2f", candidate.totalCost))) [\(segmentation)]")
        }
    }
    print("========================================\n")
}

let engine = ZhuyinEngine.production()
let args = CommandLine.arguments

func decodeInput(_ input: String) {
    let sanitized = input.replacingOccurrences(of: #"\x1b\[[0-9;]*[a-zA-Z]"#, with: "", options: .regularExpression)
    let composer = BopomofoComposer()
    composer.handleKeys(sanitized)

    let syllables = composer.allSyllables
    if !syllables.isEmpty {
        let result = engine.decode(syllables: syllables, topK: 3)
        printResult(result, composedZhuyin: composer.displayText)
    } else {
        // Fallback for direct Zhuyin symbol string input (e.g. "ㄐㄧㄣ ㄊㄧㄢ")
        let result = engine.decode(zhuyin: sanitized, topK: 3)
        printResult(result, composedZhuyin: sanitized)
    }
}

if args.count > 1 {
    if args[1] == "--ingest" && args.count >= 3 {
        let target = args[2...].joined(separator: " ")
        let fileURL = URL(fileURLWithPath: target)
        let rawText: String
        let sourceName: String
        if FileManager.default.fileExists(atPath: fileURL.path),
           let loaded = try? String(contentsOf: fileURL, encoding: .utf8) {
            rawText = loaded
            sourceName = fileURL.lastPathComponent
        } else {
            rawText = target
            sourceName = "CLI 輸入文章"
        }

        let pipeline = ArticleIngestionPipeline(engine: engine)
        let analysis = pipeline.analyze(text: rawText, sourceName: sourceName, mode: .reviewFirst)
        let batch = pipeline.commit(analysis: analysis)
        engine.userLexicon.saveSync()

        print("========================================")
        print("【文章匯入自主學習完成】")
        print("  來源名稱        : \(batch.sourceName)")
        print("  有效中文子句數  : \(analysis.clauseCount) 句 (\(analysis.totalCharacterCount) 字)")
        print("  學習詞彙數      : \(batch.wordDeltas.count) 筆")
        for term in analysis.annotatedTerms where term.isSelected {
            let tag = term.isNewWord ? "[新詞]" : "[強化]"
            print("    • \(tag) \(term.word) (\(term.selectedZhuyinString)) x\(term.count) [Cost: \(String(format: "%.2f", term.estimatedCost))]")
        }
        print("  前後文搭配數    : \(batch.bigramDeltas.count) 組")
        print("  上下文同音字數  : \(batch.contextualHomophoneDeltas.count) 組")
        print("========================================\n")
    } else {
        // Command line argument mode (e.g. swift run ZhuyinCLI su3cl3)
        let input = args[1...].joined(separator: " ")
        decodeInput(input)
    }
} else {
    // Interactive REPL mode
    print("========================================")
    print("  ZhuyinEngine P2C CLI (Interactive)   ")
    print("  詞庫狀態: 已載入 \(engine.lexicon.entries.count) 條詞彙")
    print("  打字模式: 支援標準大千鍵盤盲打（如輸入 'su3cl3' 即 'ㄋㄧˇ ㄏㄠˇ'）")
    print("           亦可直接輸入注音（如 'ㄐㄧㄣ ㄊㄧㄢ'）")
    print("           匯入文章: --ingest <檔案路徑或文章內容>")
    print("  指令說明: 輸入 'exit' 或 'quit' 退出")
    print("========================================\n")

    while true {
        print("> ", terminator: "")
        fflush(stdout)
        guard let line = readLine() else {
            break
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        if trimmed.lowercased() == "exit" || trimmed.lowercased() == "quit" {
            print("Bye!")
            break
        }

        decodeInput(trimmed)
    }
}
