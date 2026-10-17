import Cocoa
import UniformTypeIdentifiers
import ZhuyinEngine

/// Drag-and-drop container view that accepts `.txt` and `.md` text files.
private final class ArticleDropZoneView: NSView {
    var onFileDropped: ((URL) -> Void)?
    private var isDragHighlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractValidFileURL(from: sender) != nil {
            isDragHighlighted = true
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        guard let url = extractValidFileURL(from: sender) else { return false }
        onFileDropped?(url)
        return true
    }

    private func extractValidFileURL(from info: NSDraggingInfo) -> URL? {
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = items.first else { return nil }
        let ext = first.pathExtension.lowercased()
        if ["txt", "md", "markdown", "text"].contains(ext) {
            return first
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let boundsRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: boundsRect, xRadius: 8, yRadius: 8)
        let dash: [CGFloat] = [5.0, 3.0]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineWidth = 1.5

        if isDragHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            path.fill()
            NSColor.tertiaryLabelColor.setStroke()
        }
        path.stroke()
    }
}

/// Native macOS window panel for importing articles, reviewing discovered terms/pronunciations, and rolling back batches.
@objc(ArticleImportWindowController)
public final class ArticleImportWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = ArticleImportWindowController()

    private var engine: ZhuyinEngine {
        return HaoZhuyinAppDelegate.sharedEngine
    }

    // UI Controls
    private var dropZoneView: ArticleDropZoneView!
    private var sourceNameField: NSTextField!
    private var articleTextView: NSTextView!
    private var reviewModeRadio: NSButton!
    private var autoModeRadio: NSButton!
    private var analyzeButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!

    // Review Table
    private var reviewTableView: NSTableView!
    private var commitReviewButton: NSButton!
    private var selectAllButton: NSButton!

    // Batch History Table
    private var historyTableView: NSTableView!

    // State
    private var currentMode: ArticleIngestionMode = .reviewFirst
    private var currentAnalysis: IngestionAnalysisResult?
    private var reviewItems: [AnnotatedTerm] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "好注音 — 常用文章匯入與選字學習"
        window.minSize = NSSize(width: 680, height: 600)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func presentWindow() {
        NSApp.activate(ignoringOtherApps: true)
        historyTableView?.reloadData()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI Layout Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 1. Top Drop Zone & File Picker Header
        dropZoneView = ArticleDropZoneView(frame: .zero)
        dropZoneView.translatesAutoresizingMaskIntoConstraints = false
        dropZoneView.onFileDropped = { [weak self] url in
            self?.loadFile(from: url)
        }

        let dropStack = NSStackView()
        dropStack.orientation = .horizontal
        dropStack.alignment = .centerY
        dropStack.spacing = 12
        dropStack.translatesAutoresizingMaskIntoConstraints = false

        let dropLabel = NSTextField(labelWithString: "📄 拖放常用文章檔案 (.txt / .md) 至此，或直接於下方貼上文章內容")
        dropLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let chooseFileBtn = NSButton(title: "選擇檔案...", target: self, action: #selector(chooseFileAction(_:)))
        chooseFileBtn.bezelStyle = .rounded

        let sourceLabel = NSTextField(labelWithString: "來源名稱：")
        sourceLabel.font = NSFont.systemFont(ofSize: 12)
        sourceNameField = NSTextField(string: "手動貼上文章")
        sourceNameField.placeholderString = "輸入批次來源名稱"
        sourceNameField.font = NSFont.systemFont(ofSize: 12)
        sourceNameField.translatesAutoresizingMaskIntoConstraints = false
        sourceNameField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        dropStack.addArrangedSubview(dropLabel)
        dropStack.addArrangedSubview(chooseFileBtn)
        dropStack.addArrangedSubview(sourceLabel)
        dropStack.addArrangedSubview(sourceNameField)

        dropZoneView.addSubview(dropStack)
        NSLayoutConstraint.activate([
            dropZoneView.heightAnchor.constraint(equalToConstant: 44),
            dropStack.centerYAnchor.constraint(equalTo: dropZoneView.centerYAnchor),
            dropStack.leadingAnchor.constraint(equalTo: dropZoneView.leadingAnchor, constant: 14),
            dropStack.trailingAnchor.constraint(lessThanOrEqualTo: dropZoneView.trailingAnchor, constant: -14)
        ])
        rootStack.addArrangedSubview(dropZoneView)
        dropZoneView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36).isActive = true

        // 2. Article Text Paste/Edit Area
        let textScroll = NSScrollView()
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        articleTextView = NSTextView()
        articleTextView.isEditable = true
        articleTextView.isRichText = false
        articleTextView.font = NSFont.systemFont(ofSize: 13)
        articleTextView.textContainerInset = NSSize(width: 6, height: 6)
        articleTextView.autoresizingMask = [.width]
        textScroll.documentView = articleTextView

        rootStack.addArrangedSubview(textScroll)
        NSLayoutConstraint.activate([
            textScroll.heightAnchor.constraint(equalToConstant: 120),
            textScroll.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36)
        ])

        // 3. Mode Selection & Action Bar
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 14

        let modeTitle = NSTextField(labelWithString: "匯入模式：")
        modeTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        reviewModeRadio = NSButton(
            radioButtonWithTitle: "預覽審核模式（可勾選新詞、切換破音字讀音）",
            target: self,
            action: #selector(modeRadioChanged(_:))
        )
        reviewModeRadio.state = .on

        autoModeRadio = NSButton(
            radioButtonWithTitle: "快速自動模式（高置信度直接寫入詞庫）",
            target: self,
            action: #selector(modeRadioChanged(_:))
        )
        autoModeRadio.state = .off

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        analyzeButton = NSButton(title: "開始分析文章", target: self, action: #selector(runIngestionAction(_:)))
        analyzeButton.bezelStyle = .rounded
        analyzeButton.keyEquivalent = "\r"

        modeRow.addArrangedSubview(modeTitle)
        modeRow.addArrangedSubview(reviewModeRadio)
        modeRow.addArrangedSubview(autoModeRadio)
        modeRow.addArrangedSubview(progressIndicator)
        modeRow.addArrangedSubview(analyzeButton)
        rootStack.addArrangedSubview(modeRow)

        // 4. Review Section Header + Table
        let reviewHeaderRow = NSStackView()
        reviewHeaderRow.orientation = .horizontal
        reviewHeaderRow.alignment = .centerY
        reviewHeaderRow.spacing = 12

        let reviewTitle = NSTextField(labelWithString: "🔍 擷取詞彙與破音字審核清單：")
        reviewTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        statusLabel = NSTextField(labelWithString: "尚未分析文章")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        selectAllButton = NSButton(title: "全選 / 取消全選", target: self, action: #selector(toggleSelectAllAction(_:)))
        selectAllButton.bezelStyle = .rounded
        selectAllButton.controlSize = .small
        selectAllButton.isEnabled = false

        commitReviewButton = NSButton(title: "確認寫入選取詞彙與上下文搭配", target: self, action: #selector(commitReviewedTermsAction(_:)))
        commitReviewButton.bezelStyle = .rounded
        commitReviewButton.isEnabled = false

        reviewHeaderRow.addArrangedSubview(reviewTitle)
        reviewHeaderRow.addArrangedSubview(statusLabel)
        reviewHeaderRow.addArrangedSubview(selectAllButton)
        reviewHeaderRow.addArrangedSubview(commitReviewButton)
        rootStack.addArrangedSubview(reviewHeaderRow)

        let reviewScroll = NSScrollView()
        reviewScroll.hasVerticalScroller = true
        reviewScroll.borderType = .bezelBorder
        reviewScroll.translatesAutoresizingMaskIntoConstraints = false

        reviewTableView = NSTableView()
        reviewTableView.usesAlternatingRowBackgroundColors = true
        reviewTableView.rowHeight = 26
        reviewTableView.delegate = self
        reviewTableView.dataSource = self

        let colCheck = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_check"))
        colCheck.title = "選取"
        colCheck.width = 45
        reviewTableView.addTableColumn(colCheck)

        let colWord = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_word"))
        colWord.title = "詞彙"
        colWord.width = 110
        reviewTableView.addTableColumn(colWord)

        let colType = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_type"))
        colType.title = "類型 / 狀態"
        colType.width = 150
        reviewTableView.addTableColumn(colType)

        let colZhuyin = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_zhuyin"))
        colZhuyin.title = "注音讀音（可切換多音字）"
        colZhuyin.width = 240
        reviewTableView.addTableColumn(colZhuyin)

        let colCount = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_count"))
        colCount.title = "出現次數"
        colCount.width = 80
        reviewTableView.addTableColumn(colCount)

        reviewScroll.documentView = reviewTableView
        rootStack.addArrangedSubview(reviewScroll)
        NSLayoutConstraint.activate([
            reviewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 185),
            reviewScroll.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36)
        ])

        // 5. Batch History & One-Click Rollback Section
        let historyTitle = NSTextField(labelWithString: "🕒 歷史匯入批次紀錄（支援一鍵撤銷復原，防止詞庫污染）：")
        historyTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        rootStack.addArrangedSubview(historyTitle)

        let historyScroll = NSScrollView()
        historyScroll.hasVerticalScroller = true
        historyScroll.borderType = .bezelBorder
        historyScroll.translatesAutoresizingMaskIntoConstraints = false

        historyTableView = NSTableView()
        historyTableView.usesAlternatingRowBackgroundColors = true
        historyTableView.rowHeight = 26
        historyTableView.delegate = self
        historyTableView.dataSource = self

        let hColSource = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("h_source"))
        hColSource.title = "來源名稱"
        hColSource.width = 180
        historyTableView.addTableColumn(hColSource)

        let hColDate = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("h_date"))
        hColDate.title = "匯入時間"
        hColDate.width = 165
        historyTableView.addTableColumn(hColDate)

        let hColStats = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("h_stats"))
        hColStats.title = "學習摘要（詞彙 / 上下文搭配）"
        hColStats.width = 240
        historyTableView.addTableColumn(hColStats)

        let hColAction = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("h_action"))
        hColAction.title = "操作"
        hColAction.width = 100
        historyTableView.addTableColumn(hColAction)

        historyScroll.documentView = historyTableView
        rootStack.addArrangedSubview(historyScroll)
        NSLayoutConstraint.activate([
            historyScroll.heightAnchor.constraint(equalToConstant: 125),
            historyScroll.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36)
        ])
    }

    // MARK: - Actions

    @objc private func chooseFileAction(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.title = "選擇要匯入學習的常用文章"
        openPanel.prompt = "讀取文章"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            loadFile(from: url)
        }
    }

    private func loadFile(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            articleTextView.string = content
            sourceNameField.stringValue = url.lastPathComponent
            statusLabel.stringValue = "已載入檔案：\(url.lastPathComponent)（\(content.count) 字）"
        } catch {
            let alert = NSAlert()
            alert.messageText = "無法讀取檔案"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func modeRadioChanged(_ sender: NSButton) {
        if sender == reviewModeRadio {
            reviewModeRadio.state = .on
            autoModeRadio.state = .off
            currentMode = .reviewFirst
            analyzeButton.title = "開始分析文章"
        } else {
            reviewModeRadio.state = .off
            autoModeRadio.state = .on
            currentMode = .autoImport
            analyzeButton.title = "快速匯入學習"
        }
    }

    @objc private func runIngestionAction(_ sender: Any?) {
        let rawText = articleTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "文章內容為空"
            alert.informativeText = "請先選擇檔案（.txt / .md）或在文字框中貼上常用文章內容。"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let srcName = sourceNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名文章"
            : sourceNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = currentMode

        progressIndicator.startAnimation(nil)
        analyzeButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let pipeline = ArticleIngestionPipeline(engine: self.engine)
            let analysis = pipeline.analyze(text: rawText, sourceName: srcName, mode: mode)

            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil)
                self.analyzeButton.isEnabled = true
                self.currentAnalysis = analysis
                self.reviewItems = analysis.annotatedTerms
                self.reviewTableView.reloadData()

                let newWordCount = self.reviewItems.filter { $0.isNewWord }.count
                let knownBoostCount = self.reviewItems.filter { !$0.isNewWord }.count
                let bigramTotal = analysis.bigramCounts.count

                if mode == .autoImport {
                    let batch = pipeline.commit(analysis: analysis, approvedTerms: self.reviewItems)
                    self.historyTableView.reloadData()
                    self.commitReviewButton.isEnabled = false
                    self.selectAllButton.isEnabled = false
                    self.statusLabel.stringValue = "已自動學習：\(batch.wordDeltas.count) 個詞彙、\(batch.bigramDeltas.count) 組前後文搭配"

                    let alert = NSAlert()
                    alert.messageText = "快速自動匯入完成"
                    alert.informativeText = "來源：\(srcName)\n• 學習詞彙：\(batch.wordDeltas.count) 筆\n• 前後文搭配 (Bigram)：\(batch.bigramDeltas.count) 組\n• 上下文同音字偏好：\(batch.contextualHomophoneDeltas.count) 組\n\n如需還原，可隨時於下方歷史批次點選「撤銷復原」。"
                    alert.alertStyle = .informational
                    alert.runModal()
                } else {
                    self.commitReviewButton.isEnabled = (analysis.clauseCount > 0)
                    self.selectAllButton.isEnabled = !self.reviewItems.isEmpty
                    self.statusLabel.stringValue = "共分析 \(analysis.clauseCount) 句（\(analysis.totalCharacterCount) 字）：探勘新詞 \(newWordCount) 個、常用詞 \(knownBoostCount) 個、前後文搭配 \(bigramTotal) 組"
                }
            }
        }
    }

    @objc private func toggleSelectAllAction(_ sender: Any?) {
        guard !reviewItems.isEmpty else { return }
        let anyUnselected = reviewItems.contains { !$0.isSelected }
        for i in 0..<reviewItems.count {
            reviewItems[i].isSelected = anyUnselected
        }
        reviewTableView.reloadData()
    }

    @objc private func commitReviewedTermsAction(_ sender: Any?) {
        guard let analysis = currentAnalysis else { return }
        let pipeline = ArticleIngestionPipeline(engine: engine)
        let batch = pipeline.commit(analysis: analysis, approvedTerms: reviewItems)

        historyTableView.reloadData()
        commitReviewButton.isEnabled = false
        statusLabel.stringValue = "✅ 已寫入詞庫：\(batch.wordDeltas.count) 個詞彙、\(batch.bigramDeltas.count) 組前後文搭配"

        let alert = NSAlert()
        alert.messageText = "文章學習完成"
        alert.informativeText = "已成功將選取的 \(batch.wordDeltas.count) 個詞彙與 \(batch.bigramDeltas.count) 組前後文搭配寫入使用者詞庫，並即時更新解碼引擎！"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func termCheckboxToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < reviewItems.count else { return }
        reviewItems[row].isSelected = (sender.state == .on)
    }

    @objc private func pronunciationPopUpChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row >= 0 && row < reviewItems.count else { return }
        let selectedIdx = sender.indexOfSelectedItem
        let options = reviewItems[row].candidateWordPronunciations
        guard selectedIdx >= 0 && selectedIdx < options.count else { return }
        reviewItems[row].selectedSyllables = options[selectedIdx]
    }

    @objc private func rollbackBatchButtonClicked(_ sender: NSButton) {
        let row = sender.tag
        let batches = engine.userLexicon.data.batchHistory
        guard row >= 0 && row < batches.count else { return }
        let targetBatch = batches[row]

        let confirm = NSAlert()
        confirm.messageText = "確定要撤銷此批次的學習紀錄嗎？"
        confirm.informativeText = "來源：「\(targetBatch.sourceName)」\n將精確扣回該次匯入的 \(targetBatch.wordDeltas.count) 個詞彙與 \(targetBatch.bigramDeltas.count) 組前後文搭配，並即時熱重載詞庫。"
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "確定撤銷")
        confirm.addButton(withTitle: "取消")

        if confirm.runModal() == .alertFirstButtonReturn {
            if engine.rollbackIngestionBatch(id: targetBatch.id) {
                historyTableView.reloadData()
                statusLabel.stringValue = "↩️ 已撤銷批次：「\(targetBatch.sourceName)」"
            }
        }
    }

    // MARK: - NSTableViewDataSource & NSTableViewDelegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == reviewTableView {
            return reviewItems.count
        } else if tableView == historyTableView {
            return engine.userLexicon.data.batchHistory.count
        }
        return 0
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue else { return nil }

        if tableView == reviewTableView {
            guard row < reviewItems.count else { return nil }
            let item = reviewItems[row]

            switch colId {
            case "col_check":
                let chk = NSButton(checkboxWithTitle: "", target: self, action: #selector(termCheckboxToggled(_:)))
                chk.state = item.isSelected ? .on : .off
                chk.tag = row
                return chk

            case "col_word":
                let label = NSTextField(labelWithString: item.word)
                label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                return label

            case "col_type":
                var badge = item.isNewWord ? "✨ 新詞探勘" : "📈 既有詞強化"
                if item.hasAmbiguity {
                    badge += " ⚠️多音"
                }
                let label = NSTextField(labelWithString: badge)
                label.font = NSFont.systemFont(ofSize: 12)
                label.textColor = item.isNewWord ? .systemBlue : .secondaryLabelColor
                return label

            case "col_zhuyin":
                if item.candidateWordPronunciations.count > 1 {
                    let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
                    popUp.controlSize = .small
                    popUp.font = NSFont.systemFont(ofSize: 12)
                    popUp.tag = row
                    popUp.target = self
                    popUp.action = #selector(pronunciationPopUpChanged(_:))
                    for syls in item.candidateWordPronunciations {
                        let title = syls.map { $0.raw }.joined(separator: " ")
                        popUp.addItem(withTitle: title)
                    }
                    if let currentIdx = item.candidateWordPronunciations.firstIndex(of: item.selectedSyllables) {
                        popUp.selectItem(at: currentIdx)
                    }
                    return popUp
                } else {
                    let label = NSTextField(labelWithString: item.selectedZhuyinString)
                    label.font = NSFont.systemFont(ofSize: 12)
                    return label
                }

            case "col_count":
                let label = NSTextField(labelWithString: "\(item.count) 次")
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                return label

            default:
                return nil
            }
        } else if tableView == historyTableView {
            let batches = engine.userLexicon.data.batchHistory
            guard row < batches.count else { return nil }
            let batch = batches[row]

            switch colId {
            case "h_source":
                let label = NSTextField(labelWithString: batch.sourceName)
                label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                return label

            case "h_date":
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let label = NSTextField(labelWithString: formatter.string(from: batch.timestamp))
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                label.textColor = .secondaryLabelColor
                return label

            case "h_stats":
                let summary = "詞彙 \(batch.wordDeltas.count) 筆 / 雙詞搭配 \(batch.bigramDeltas.count) 組"
                let label = NSTextField(labelWithString: summary)
                label.font = NSFont.systemFont(ofSize: 12)
                return label

            case "h_action":
                let btn = NSButton(title: "撤銷復原", target: self, action: #selector(rollbackBatchButtonClicked(_:)))
                btn.bezelStyle = .rounded
                btn.controlSize = .small
                btn.tag = row
                return btn

            default:
                return nil
            }
        }

        return nil
    }
}
