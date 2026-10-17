import Cocoa
import InputMethodKit
import UniformTypeIdentifiers
import ZhuyinEngine

@objc(ZhuyinInputController)
public final class ZhuyinInputController: IMKInputController {
    private let composer = BopomofoComposer()
    private var engine: ZhuyinEngine {
        return HaoZhuyinAppDelegate.sharedEngine
    }

    private let candidateWindow = CandidateWindow()
    private var isSelectingCandidate = false
    private var currentCandidates: [String] = []
    private struct CandidateSpanInfo {
        let spanLength: Int
        let startOffset: Int
    }
    private var candidateSpanMap: [String: CandidateSpanInfo] = [:]

    /// Current insertion caret position (measured in completed items index, 0 ... composer.items.count).
    private var cursorIndex: Int = 0

    /// User-overridden characters/words/punctuations at specific item indices (0-indexed).
    private var userOverrides: [Int: String] = [:]

    /// The target item index currently being modified by the candidate window.
    private var targetOverrideIndex: Int? = nil

    /// Reference to the active text input client for mouse/async candidate selection.
    private var currentClient: Any? = nil

    public override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
        self.currentClient = client

        // Synchronize initial preferences
        let prefs = HaoZhuyinPreferences.shared
        candidateWindow.orientation = prefs.candidateOrientation
        composer.isSpatialModelEnabled = prefs.isSpatialToleranceEnabled
        engine.isSpatialToleranceEnabled = prefs.isSpatialToleranceEnabled

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferencesChanged(_:)),
            name: HaoZhuyinPreferences.didChangeNotification,
            object: nil
        )

        candidateWindow.onCandidateSelected = { [weak self] candidate in
            guard let self = self else { return }
            self.applyCandidateSelection(candidate, client: self.currentClient)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handlePreferencesChanged(_ notification: Notification) {
        let prefs = HaoZhuyinPreferences.shared
        candidateWindow.orientation = prefs.candidateOrientation
        composer.isSpatialModelEnabled = prefs.isSpatialToleranceEnabled
        engine.isSpatialToleranceEnabled = prefs.isSpatialToleranceEnabled
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        resetState()
    }

    public override func deactivateServer(_ sender: Any!) {
        if !composer.isEmpty {
            commitComposedText(client: sender)
        }
        resetState()
        super.deactivateServer(sender)
    }

    private func resetState() {
        candidateWindow.hide()
        isSelectingCandidate = false
        currentCandidates.removeAll()
        candidateSpanMap.removeAll()
        userOverrides.removeAll()
        targetOverrideIndex = nil
        currentClient = nil
        cursorIndex = 0
        composer.clear()
        engine.resetStabilizedHistory()
    }

    // MARK: - Keyboard Event Handling

    @objc(handleEvent:client:)
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return processKeyEvent(
            keyCode: Int(event.keyCode),
            characters: event.characters,
            flags: flags,
            client: sender
        )
    }

    @objc(inputText:key:modifiers:client:)
    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(flags)).intersection(.deviceIndependentFlagsMask)
        return processKeyEvent(
            keyCode: keyCode,
            characters: string,
            flags: modifierFlags,
            client: sender
        )
    }

    @objc(inputText:client:)
    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard let string = string, !string.isEmpty else { return false }

        // Detect ANSI escape sequences and function keys
        if string == "\u{001B}[D" || string == "\u{F702}" {
            return processKeyEvent(keyCode: 0x7B, characters: nil, flags: [], client: sender)
        }
        if string == "\u{001B}[C" || string == "\u{F703}" {
            return processKeyEvent(keyCode: 0x7C, characters: nil, flags: [], client: sender)
        }
        if string == "\u{001B}[B" || string == "\u{F701}" {
            return processKeyEvent(keyCode: 0x7D, characters: nil, flags: [], client: sender)
        }
        if string == "\u{001B}[A" || string == "\u{F700}" {
            return processKeyEvent(keyCode: 0x7E, characters: nil, flags: [], client: sender)
        }
        if string == "\u{F72C}" || string == "\u{001B}[5~" {
            return processKeyEvent(keyCode: 0x74, characters: nil, flags: [], client: sender)
        }
        if string == "\u{F72D}" || string == "\u{001B}[6~" {
            return processKeyEvent(keyCode: 0x79, characters: nil, flags: [], client: sender)
        }
        if string == "\t" {
            return processKeyEvent(keyCode: 0x30, characters: nil, flags: [], client: sender)
        }
        if string == "\r" || string == "\n" {
            return processKeyEvent(keyCode: 0x24, characters: nil, flags: [], client: sender)
        }
        if string == "\u{7F}" || string == "\u{08}" {
            return processKeyEvent(keyCode: 0x33, characters: nil, flags: [], client: sender)
        }
        if string == "\u{1B}" {
            return processKeyEvent(keyCode: 0x35, characters: nil, flags: [], client: sender)
        }
        if string == " " {
            return processKeyEvent(keyCode: 0x31, characters: " ", flags: [], client: sender)
        }

        // Strip ANSI escape codes if present
        let cleaned = string.replacingOccurrences(of: #"\x1b\[[0-9;]*[a-zA-Z]"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return true }

        var handled = false
        for char in cleaned {
            if processKeyEvent(keyCode: -1, characters: String(char), flags: [], client: sender) {
                handled = true
            }
        }
        return handled
    }

    // MARK: - Unified Key Event Processing

    private func processKeyEvent(
        keyCode: Int,
        characters: String?,
        flags: NSEvent.ModifierFlags,
        client sender: Any!
    ) -> Bool {
        self.currentClient = sender
        // Pass-through standard command / control keyboard shortcuts (Cmd+C, Cmd+V, Cmd+A, etc.)
        if flags.contains(.command) || flags.contains(.control) {
            if isSelectingCandidate {
                candidateWindow.hide()
                isSelectingCandidate = false
                targetOverrideIndex = nil
            }
            return false
        }

        // Normalize virtual key code using character metadata if non-standard
        var effectiveKeyCode = keyCode
        if let chars = characters, chars.count == 1, let first = chars.first {
            switch first {
            case "\u{F702}": effectiveKeyCode = 0x7B // Left Arrow
            case "\u{F703}": effectiveKeyCode = 0x7C // Right Arrow
            case "\u{F701}": effectiveKeyCode = 0x7D // Down Arrow
            case "\u{F700}": effectiveKeyCode = 0x7E // Up Arrow
            case "\u{F728}": effectiveKeyCode = 0x75 // Forward Delete
            case "\u{F72C}": effectiveKeyCode = 0x74 // Page Up
            case "\u{F72D}": effectiveKeyCode = 0x79 // Page Down
            default: break
            }
        }

        let isShift = flags.contains(.shift)
        let isOption = flags.contains(.option)
        let char = characters?.first

        // MARK: Actions when Candidate Window is OPEN
        if isSelectingCandidate {
            // If punctuation key is pressed while candidate window is open:
            // Confirm currently highlighted candidate, close candidate window, then proceed to handle punctuation.
            if let punctDef = PunctuationTable.lookup(keyCode: effectiveKeyCode, character: char, isShift: isShift, isOption: isOption) {
                if let selected = candidateWindow.currentCandidate() {
                    applyCandidateSelection(selected, client: sender)
                } else {
                    candidateWindow.hide()
                    isSelectingCandidate = false
                    targetOverrideIndex = nil
                }
                insertPunctuationAtCursor(punctDef.primary)
                updateMarkedText(client: sender)
                return true
            }

            // 1. Page Down (0x79)
            if effectiveKeyCode == 0x79 {
                candidateWindow.pageNext()
                return true
            }

            // 2. Page Up (0x74)
            if effectiveKeyCode == 0x74 {
                candidateWindow.pagePrevious()
                return true
            }

            // 3. Tab (0x30)
            if effectiveKeyCode == 0x30 {
                if isShift {
                    candidateWindow.pagePrevious()
                } else {
                    candidateWindow.pageNext()
                }
                return true
            }

            // 4. Directional Navigation (Up, Down, Left, Right Arrow)
            if candidateWindow.orientation == .vertical {
                // Vertical Layout: Down/Up navigates candidates, Right/Left flips pages
                if effectiveKeyCode == 0x7D { // Down Arrow
                    candidateWindow.selectNext()
                    return true
                }
                if effectiveKeyCode == 0x7E { // Up Arrow
                    candidateWindow.selectPrevious()
                    return true
                }
                if effectiveKeyCode == 0x7C { // Right Arrow
                    candidateWindow.pageNext()
                    return true
                }
                if effectiveKeyCode == 0x7B { // Left Arrow
                    candidateWindow.pagePrevious()
                    return true
                }
            } else {
                // Horizontal Layout: Left/Right navigates candidates, Down/Up flips pages
                if effectiveKeyCode == 0x7D { // Down Arrow
                    if candidateWindow.totalPages > 1 {
                        candidateWindow.pageNext()
                    } else {
                        candidateWindow.selectNext()
                    }
                    return true
                }
                if effectiveKeyCode == 0x7E { // Up Arrow
                    if candidateWindow.totalPages > 1 {
                        candidateWindow.pagePrevious()
                    } else {
                        candidateWindow.selectPrevious()
                    }
                    return true
                }
                if effectiveKeyCode == 0x7C { // Right Arrow
                    candidateWindow.selectNext()
                    return true
                }
                if effectiveKeyCode == 0x7B { // Left Arrow
                    candidateWindow.selectPrevious()
                    return true
                }
            }

            // 8. Space Bar (0x31): Flip to next page if multi-page; confirm candidate if single-page
            if effectiveKeyCode == 0x31 {
                if candidateWindow.totalPages > 1 {
                    candidateWindow.pageNext()
                } else if let selected = candidateWindow.currentCandidate() {
                    applyCandidateSelection(selected, client: sender)
                }
                return true
            }

            // 9. Return / Enter (0x24): Commit highlighted candidate and commit composed text
            if effectiveKeyCode == 0x24 {
                if let selected = candidateWindow.currentCandidate() {
                    applyCandidateSelection(selected, client: sender)
                }
                commitComposedText(client: sender)
                return true
            }

            // 10. Number Keys (1 ~ 9): Select corresponding candidate on current page
            if let chars = characters, let firstChar = chars.first,
               let digit = Int(String(firstChar)), digit >= 1 && digit <= 9 {
                if let candidate = candidateWindow.candidateForCurrentPage(digit: digit) {
                    applyCandidateSelection(candidate, client: sender)
                    return true
                }
            }

            // 11. Escape (0x35) / Backspace (0x33): Close candidate window
            if effectiveKeyCode == 0x35 || effectiveKeyCode == 0x33 {
                candidateWindow.hide()
                isSelectingCandidate = false
                targetOverrideIndex = nil
                updateMarkedText(client: sender)
                return true
            }

            return true
        }

        // MARK: Actions when Candidate Window is NOT OPEN

        // Check for macOS Punctuation Shortcuts
        if let punctDef = PunctuationTable.lookup(keyCode: effectiveKeyCode, character: char, isShift: isShift, isOption: isOption) {
            // If in-flight Zhuyin components exist, finalize them (first tone)
            if composer.hasComposingComponents {
                let prevCount = composer.items.count
                _ = composer.handleKey(character: " ")
                if composer.items.count > prevCount {
                    onSyllableCompletedAtCursor()
                } else {
                    composer.clearInFlight()
                }
            }

            let isSymbolPalette = (effectiveKeyCode == 0x0B || char == "B" || char == "b") && isShift && isOption
            insertPunctuationAtCursor(punctDef.primary)

            if isSymbolPalette {
                // Option + Shift + B: Open the full symbol palette immediately
                showCandidateWindowForCursor(client: sender, customCandidates: punctDef.candidates)
            } else {
                updateMarkedText(client: sender)
            }
            return true
        }

        // 1. Left Arrow (0x7B): Move caret / highlight left within composing text
        if effectiveKeyCode == 0x7B {
            if !composer.isEmpty {
                if composer.hasComposingComponents {
                    composer.clearInFlight()
                }
                cursorIndex = max(0, cursorIndex - 1)
                updateMarkedText(client: sender)
                return true
            }
            return false
        }

        // 2. Right Arrow (0x7C): Move caret / highlight right within composing text
        if effectiveKeyCode == 0x7C {
            if !composer.isEmpty {
                if composer.hasComposingComponents {
                    composer.clearInFlight()
                }
                cursorIndex = min(composer.items.count, cursorIndex + 1)
                updateMarkedText(client: sender)
                return true
            }
            return false
        }

        // 3. Down Arrow (0x7D): Open candidate window for the focused character or punctuation
        if effectiveKeyCode == 0x7D {
            if !composer.isEmpty {
                if composer.hasComposingComponents {
                    composer.clearInFlight()
                }
                showCandidateWindowForCursor(client: sender)
                return true
            }
            return false
        }

        // 4. Up Arrow (0x7E)
        if effectiveKeyCode == 0x7E {
            if !composer.isEmpty {
                return true
            }
            return false
        }

        // 5. Return / Enter (0x24): Commit finalized text
        if effectiveKeyCode == 0x24 {
            if !composer.isEmpty {
                commitComposedText(client: sender)
                return true
            }
            return false
        }

        // 6. Escape (0x35): Cancel composition
        if effectiveKeyCode == 0x35 {
            if !composer.isEmpty {
                clearMarkedText(client: sender)
                resetState()
                return true
            }
            return false
        }

        // 7. Backspace (0x33)
        if effectiveKeyCode == 0x33 {
            if !composer.isEmpty {
                handleBackspace(client: sender)
                return true
            }
            return false
        }

        // 8. Forward Delete (0x75)
        if effectiveKeyCode == 0x75 {
            if !composer.isEmpty {
                handleForwardDelete(client: sender)
                return true
            }
            return false
        }

        // 9. Space Bar (0x31)
        if effectiveKeyCode == 0x31 {
            if composer.hasComposingComponents {
                // Space acts as 1st tone (陰平聲)
                let prevCount = composer.items.count
                _ = composer.handleKey(character: " ")
                if composer.items.count > prevCount {
                    onSyllableCompletedAtCursor()
                }
                updateMarkedText(client: sender)
                return true
            }
            if !composer.items.isEmpty {
                // Space triggers candidate window for focused character or punctuation
                showCandidateWindowForCursor(client: sender)
                return true
            }
            return false
        }

        // 10. Printable Characters (Zhuyin composer keys)
        guard let characters = characters, !characters.isEmpty else {
            return false
        }

        let firstChar = characters.first!
        // Ignore control characters, escape, and Unicode private use characters
        if let ascii = firstChar.asciiValue, ascii < 0x20 {
            return false
        }
        if firstChar == "\u{1B}" || (firstChar >= "\u{F700}" && firstChar <= "\u{F8FF}") {
            return false
        }

        let prevCount = composer.items.count
        let result = composer.handleKey(character: firstChar)

        if result != .ignored {
            if composer.items.count > prevCount {
                // A new syllable completed (by tone key 3, 4, 6, 7)
                onSyllableCompletedAtCursor()
            }
            updateMarkedText(client: sender)
            return true
        } else {
            if !composer.isEmpty {
                // Non-Zhuyin key entered during composition: commit current text first
                commitComposedText(client: sender)
                return false
            }
            return false
        }
    }

    // MARK: - Internal Item Insertion & Editing Operations

    /// Called whenever a new syllable is completed (via tone key or space).
    private func onSyllableCompletedAtCursor() {
        let total = composer.items.count
        guard total > 0 else { return }

        // Syllable was appended at the end of items by BopomofoComposer
        guard let completedItem = composer.removeItem(at: total - 1) else { return }

        // Insert at cursorIndex (supports inserting anywhere in the string)
        let insertPos = min(max(0, cursorIndex), composer.items.count)
        composer.insertItem(completedItem, at: insertPos)

        // Shift userOverrides for subsequent characters right by 1
        var shifted: [Int: String] = [:]
        for (key, val) in userOverrides {
            if key >= insertPos {
                shifted[key + 1] = val
            } else {
                shifted[key] = val
            }
        }
        userOverrides = shifted

        cursorIndex = insertPos + 1
    }

    /// Inserts a punctuation mark at current cursor position.
    private func insertPunctuationAtCursor(_ punctuation: String) {
        let insertPos = min(max(0, cursorIndex), composer.items.count)
        composer.insertPunctuation(punctuation, at: insertPos)

        var shifted: [Int: String] = [:]
        for (key, val) in userOverrides {
            if key >= insertPos {
                shifted[key + 1] = val
            } else {
                shifted[key] = val
            }
        }
        userOverrides = shifted

        cursorIndex = insertPos + 1
    }

    /// Retrieves the text of the character immediately preceding the given item index using full-context Viterbi decoding.
    private func precedingCharacterText(before index: Int) -> String? {
        guard index > 0 && index <= composer.items.count else { return nil }
        let prevIdx = index - 1
        if let ov = userOverrides[prevIdx] {
            return ov
        }
        let items = composer.items
        switch items[prevIdx] {
        case .punctuation(let p):
            return p
        case .syllable:
            var runStart = prevIdx
            while runStart > 0, case .syllable = items[runStart - 1] {
                runStart -= 1
            }
            var runSyls: [Syllable] = []
            for k in runStart...prevIdx {
                if case .syllable(let s) = items[k] {
                    runSyls.append(s)
                }
            }
            let decoded = engine.decode(syllables: runSyls, topK: 1, updateHistory: false)
            let chars = Array(decoded.bestText)
            let offset = prevIdx - runStart
            if offset < chars.count {
                return String(chars[offset])
            }
            if case .syllable(let syl) = items[prevIdx] {
                return syl.raw
            }
            return nil
        }
    }

    /// Opens the Candidate Window for the character or punctuation immediately preceding the caret.
    private func showCandidateWindowForCursor(client sender: Any!, customCandidates: [String]? = nil) {
        let items = composer.items
        guard !items.isEmpty else { return }

        // When caret is behind an item (cursorIndex > 0), target that item (cursorIndex - 1).
        // When caret is at position 0, target the first item (index 0).
        let targetIdx: Int
        if cursorIndex > 0 {
            targetIdx = min(cursorIndex - 1, items.count - 1)
        } else {
            targetIdx = 0
        }

        if let custom = customCandidates {
            currentCandidates = custom
            candidateSpanMap.removeAll()
            for cand in custom {
                candidateSpanMap[cand] = CandidateSpanInfo(spanLength: 1, startOffset: 0)
            }
        } else {
            let item = items[targetIdx]
            switch item {
            case .syllable:
                var subSyllables: [Syllable] = []
                var k = targetIdx
                while k < items.count, case .syllable(let s) = items[k] {
                    subSyllables.append(s)
                    k += 1
                }

                // Extract preceding contiguous syllables (up to 3) for backward phrase/idiom deduction
                var precedingSyllables: [Syllable] = []
                var p = targetIdx - 1
                while p >= 0, case .syllable(let s) = items[p] {
                    precedingSyllables.insert(s, at: 0)
                    if precedingSyllables.count >= 3 { break }
                    p -= 1
                }

                // Preceding context word
                let prevWord = precedingCharacterText(before: targetIdx)

                let entries = engine.candidatesWithSpan(
                    for: subSyllables,
                    startIndex: 0,
                    precedingSyllables: precedingSyllables,
                    prevWord: prevWord,
                    maxCount: 100
                )
                currentCandidates = entries.map { $0.text }
                candidateSpanMap.removeAll()
                for entry in entries {
                    candidateSpanMap[entry.text] = CandidateSpanInfo(spanLength: entry.spanLength, startOffset: entry.startOffset)
                }

            case .punctuation(let punct):
                let activePunct = userOverrides[targetIdx] ?? punct
                currentCandidates = PunctuationTable.candidates(for: activePunct, maxCount: 100)
                candidateSpanMap.removeAll()
                for cand in currentCandidates {
                    candidateSpanMap[cand] = CandidateSpanInfo(spanLength: 1, startOffset: 0)
                }
            }
        }

        guard !currentCandidates.isEmpty else { return }

        self.currentClient = sender
        targetOverrideIndex = targetIdx
        isSelectingCandidate = true
        updateMarkedText(client: sender)

        // Obtain caret rectangle from client
        var caretRect = NSRect.zero
        if let client = sender as? IMKTextInput {
            _ = client.attributes(forCharacterIndex: targetIdx, lineHeightRectangle: &caretRect)
            if caretRect == .zero || caretRect.width == 0 {
                var actualRange = NSRange(location: NSNotFound, length: 0)
                caretRect = client.firstRect(forCharacterRange: NSRange(location: targetIdx, length: 1), actualRange: &actualRange)
            }
            if caretRect == .zero || caretRect.width == 0 {
                if targetIdx > 0 {
                    _ = client.attributes(forCharacterIndex: targetIdx - 1, lineHeightRectangle: &caretRect)
                }
            }
        }
        if caretRect == .zero || caretRect.width == 0 {
            caretRect = NSRect(origin: NSEvent.mouseLocation, size: CGSize(width: 20, height: 20))
        }

        var initialIndex = 0
        if let override = userOverrides[targetIdx], let idx = currentCandidates.firstIndex(of: override) {
            initialIndex = idx
        }

        candidateWindow.show(candidates: currentCandidates, selectedIndex: initialIndex, at: caretRect)
    }

    /// Applies the selected candidate to the target character/punctuation index.
    private func applyCandidateSelection(_ candidate: String, client sender: Any!) {
        guard let targetIdx = targetOverrideIndex else { return }
        let spanInfo = candidateSpanMap[candidate] ?? CandidateSpanInfo(spanLength: 1, startOffset: 0)
        let spanLength = spanInfo.spanLength
        let startOffset = spanInfo.startOffset
        let effectiveStartIdx = max(0, targetIdx + startOffset)
        let items = composer.items

        if spanLength > 1 {
            // Multi-syllable phrase candidate selected
            let chars = Array(candidate)
            for i in 0..<min(chars.count, spanLength) {
                userOverrides[effectiveStartIdx + i] = String(chars[i])
            }
            let prevWord = precedingCharacterText(before: effectiveStartIdx)
            if let prev = prevWord {
                engine.learnBigram(prev: prev, next: candidate)
            }
            // Advance caret to the end of the selected phrase
            cursorIndex = min(items.count, effectiveStartIdx + spanLength)
        } else {
            // Single character or punctuation
            userOverrides[targetIdx] = candidate
            let prevWord = precedingCharacterText(before: targetIdx)
            if targetIdx < items.count, case .syllable(let syl) = items[targetIdx] {
                engine.learnHomophoneSelection(syllable: syl, word: candidate, prevWord: prevWord)
            }
            // Advance caret past the selected character
            cursorIndex = min(items.count, targetIdx + 1)
        }

        candidateWindow.hide()
        isSelectingCandidate = false
        targetOverrideIndex = nil
        updateMarkedText(client: sender)
    }

    /// Handles Backspace key editing.
    private func handleBackspace(client sender: Any!) {
        if composer.hasComposingComponents {
            _ = composer.handleBackspace()
        } else if !composer.items.isEmpty {
            if cursorIndex > 0 {
                // Delete the item immediately preceding the caret
                let deleteIdx = cursorIndex - 1
                composer.removeItem(at: deleteIdx)
                userOverrides.removeValue(forKey: deleteIdx)
                shiftOverridesLeft(from: deleteIdx)
                cursorIndex = max(0, cursorIndex - 1)
            }
        }

        if composer.isEmpty {
            clearMarkedText(client: sender)
            resetState()
        } else {
            updateMarkedText(client: sender)
        }
    }

    /// Handles Forward Delete (Fn+Backspace / Delete) key editing.
    private func handleForwardDelete(client sender: Any!) {
        if composer.hasComposingComponents {
            composer.clearInFlight()
        } else if !composer.items.isEmpty {
            if cursorIndex < composer.items.count {
                // Delete the item immediately following the caret
                let deleteIdx = cursorIndex
                composer.removeItem(at: deleteIdx)
                userOverrides.removeValue(forKey: deleteIdx)
                shiftOverridesLeft(from: deleteIdx)
            }
        }

        if composer.isEmpty {
            clearMarkedText(client: sender)
            resetState()
        } else {
            updateMarkedText(client: sender)
        }
    }

    private func shiftOverridesLeft(from deleteIdx: Int) {
        var shifted: [Int: String] = [:]
        for (key, val) in userOverrides {
            if key > deleteIdx {
                shifted[key - 1] = val
            } else if key < deleteIdx {
                shifted[key] = val
            }
        }
        userOverrides = shifted
    }

    // MARK: - Display String Construction

    /// Assembles the composed text and selection range based on cursor position, punctuated tokens, and in-flight Zhuyin symbols.
    private func buildDisplayString() -> (fullText: String, selectionRange: NSRange) {
        let items = composer.items
        let inFlight = composer.currentComposingZhuyin

        if items.isEmpty {
            return (inFlight, NSRange(location: inFlight.utf16.count, length: 0))
        }

        // 1. Decode segments (grouping consecutive syllables for Viterbi sentence decoding)
        var chars = [String]()
        var idx = 0
        while idx < items.count {
            switch items[idx] {
            case .punctuation(let punct):
                chars.append(punct)
                idx += 1
            case .syllable:
                let runStart = idx
                var runSyllables = [Syllable]()
                while idx < items.count, case .syllable(let s) = items[idx] {
                    runSyllables.append(s)
                    idx += 1
                }
                let decoded = engine.decode(syllables: runSyllables, runId: runStart, topK: 1)
                var runChars = Array(decoded.bestText).map(String.init)
                if runChars.count != runSyllables.count {
                    runChars = runSyllables.map {
                        let text = engine.decode(syllables: [$0], topK: 1, updateHistory: false).bestText
                        return text.isEmpty ? $0.raw : text
                    }
                }
                chars.append(contentsOf: runChars)
            }
        }

        // 2. Apply user-overridden characters/punctuations
        for (overrideIdx, overrideText) in userOverrides {
            if overrideIdx >= 0 && overrideIdx < chars.count {
                chars[overrideIdx] = overrideText
            }
        }

        // Safe insertion position
        let safeCursor = min(max(0, cursorIndex), chars.count)

        // 3. Assemble fullText
        let before = chars[0..<safeCursor].joined()
        let after = chars[safeCursor...].joined()
        let fullText = before + inFlight + after

        // 4. Determine selection range:
        // In macOS IMK / NSTextInputClient, a selectionRange with length > 0 causes the client
        // application's caret appearance to jump to the very end of the marked text.
        // Keeping length == 0 ensures the visual cursor remains stably at the user's current
        // caret position (cursorIndex) when modifying characters or browsing candidates.
        let caretLoc = before.utf16.count + inFlight.utf16.count
        return (fullText, NSRange(location: caretLoc, length: 0))
    }

    // MARK: - Client Text Operations

    private func updateMarkedText(client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        let displayInfo = buildDisplayString()
        guard !displayInfo.fullText.isEmpty else {
            clearMarkedText(client: sender)
            return
        }

        let attrString = NSAttributedString(
            string: displayInfo.fullText,
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markedClauseSegment: 0
            ]
        )

        client.setMarkedText(
            attrString,
            selectionRange: displayInfo.selectionRange,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func clearMarkedText(client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        client.setMarkedText(
            NSAttributedString(string: ""),
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func commitComposedText(client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        // Ensure internal cursor is positioned at the very end of the composed items
        cursorIndex = composer.items.count
        let displayInfo = buildDisplayString()
        if !displayInfo.fullText.isEmpty {
            let fullLen = displayInfo.fullText.utf16.count
            // 1. Explicitly move client selection to the end of the marked text before inserting
            client.setMarkedText(
                NSAttributedString(string: displayInfo.fullText),
                selectionRange: NSRange(location: fullLen, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )

            // 2. Insert the committed text into the document
            client.insertText(displayInfo.fullText, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

            // Trigger adaptive learning on the committed sentence:
            engine.learnCommittedSentence(
                items: composer.items,
                committedText: displayInfo.fullText,
                userOverrides: userOverrides
            )
        }
        resetState()
    }

    // MARK: - Menu Bar Menu (Input Method Menu)

    public override func menu() -> NSMenu! {
        let menu = NSMenu()

        // 1. Version title (simplified to "好注音 V1.0.0")
        let titleItem = NSMenuItem(title: "好注音 V1.0.0", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Candidate Window Orientation (Horizontal / Vertical)
        // NOTE: IMK input menus are rendered out-of-process by TextInputMenuAgent, which
        // does NOT dispatch actions for items nested inside submenus. These items must
        // therefore be top-level, otherwise selecting them silently does nothing.
        let isVertical = (HaoZhuyinPreferences.shared.candidateOrientation == .vertical)

        let horizontalItem = NSMenuItem(
            title: "橫式選字窗",
            action: #selector(setOrientationHorizontalAction(_:)),
            keyEquivalent: ""
        )
        horizontalItem.target = self
        horizontalItem.state = isVertical ? .off : .on
        menu.addItem(horizontalItem)

        let verticalItem = NSMenuItem(
            title: "直式選字窗",
            action: #selector(setOrientationVerticalAction(_:)),
            keyEquivalent: ""
        )
        verticalItem.target = self
        verticalItem.state = isVertical ? .on : .off
        menu.addItem(verticalItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Keyboard Spatial Model (手滑相鄰按鍵容錯) Toggle
        let isSpatialEnabled = HaoZhuyinPreferences.shared.isSpatialToleranceEnabled
        let spatialItem = NSMenuItem(
            title: "按鍵相鄰容錯 (手滑自動修正)",
            action: #selector(toggleSpatialToleranceAction(_:)),
            keyEquivalent: ""
        )
        spatialItem.target = self
        spatialItem.state = isSpatialEnabled ? .on : .off
        menu.addItem(spatialItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Pause Self-Learning Toggle
        let isPaused = engine.userLexicon.data.isLearningPaused
        let pauseItem = NSMenuItem(
            title: "暫停自我學習",
            action: #selector(togglePauseLearningAction(_:)),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.state = isPaused ? .on : .off
        menu.addItem(pauseItem)

        // 4. Clear Learned Data
        let clearItem = NSMenuItem(
            title: "清除學習紀錄...",
            action: #selector(clearLearningDataAction(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Article Ingestion Learning & Export/Import Learning Records
        let articleImportItem = NSMenuItem(
            title: "匯入文章學習...",
            action: #selector(importArticleLearningAction(_:)),
            keyEquivalent: ""
        )
        articleImportItem.target = self
        menu.addItem(articleImportItem)

        let exportItem = NSMenuItem(
            title: "匯出學習紀錄...",
            action: #selector(exportLearningDataAction(_:)),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)

        let importItem = NSMenuItem(
            title: "匯入學習紀錄...",
            action: #selector(importLearningDataAction(_:)),
            keyEquivalent: ""
        )
        importItem.target = self
        menu.addItem(importItem)

        return menu
    }

    @objc private func importArticleLearningAction(_ sender: Any?) {
        NSLog("[HaoZhuyin] Menu: opening ArticleImportWindowController")
        ArticleImportWindowController.shared.presentWindow()
    }

    @objc private func setOrientationHorizontalAction(_ sender: Any?) {
        NSLog("[HaoZhuyin] Menu: candidate orientation -> horizontal")
        HaoZhuyinPreferences.shared.candidateOrientation = .horizontal
    }

    @objc private func setOrientationVerticalAction(_ sender: Any?) {
        NSLog("[HaoZhuyin] Menu: candidate orientation -> vertical")
        HaoZhuyinPreferences.shared.candidateOrientation = .vertical
    }

    @objc private func toggleSpatialToleranceAction(_ sender: Any?) {
        let current = HaoZhuyinPreferences.shared.isSpatialToleranceEnabled
        NSLog("[HaoZhuyin] Menu: spatial tolerance -> \(!current)")
        HaoZhuyinPreferences.shared.isSpatialToleranceEnabled = !current
    }

    @objc private func togglePauseLearningAction(_ sender: Any?) {
        let current = engine.userLexicon.data.isLearningPaused
        engine.userLexicon.setLearningPaused(!current)
    }

    @objc private func clearLearningDataAction(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "確定要清除學習紀錄嗎？"
        alert.informativeText = "此動作將會清除所有已自我學習的選字偏好、常用詞與詞庫統計，且無法復原。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "確定清除")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            engine.userLexicon.clearAllLearnedData()
            engine.reloadUserLexicon()
            NSLog("[HaoZhuyin] User confirmed and cleared all learned data.")
        } else {
            NSLog("[HaoZhuyin] User cancelled clearing learned data.")
        }
    }

    @objc private func exportLearningDataAction(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let savePanel = NSSavePanel()
        savePanel.title = "匯出好注音學習紀錄"
        savePanel.prompt = "匯出"
        savePanel.nameFieldStringValue = "HaoZhuyin_LearningData.json"
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.json]

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try engine.userLexicon.export(to: targetURL)
                let alert = NSAlert()
                alert.messageText = "匯出成功"
                alert.informativeText = "學習紀錄已成功匯出至：\n\(targetURL.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好")
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "匯出失敗"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    @objc private func importLearningDataAction(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let openPanel = NSOpenPanel()
        openPanel.title = "匯入好注音學習紀錄"
        openPanel.prompt = "選擇檔案"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.json]

        if openPanel.runModal() == .OK, let sourceURL = openPanel.url {
            let choiceAlert = NSAlert()
            choiceAlert.messageText = "匯入學習紀錄"
            choiceAlert.informativeText = "請問要將檔案內容「合併」至現有學習紀錄，還是完全「覆蓋」目前紀錄？"
            choiceAlert.alertStyle = .informational
            choiceAlert.addButton(withTitle: "合併")
            choiceAlert.addButton(withTitle: "覆蓋")
            choiceAlert.addButton(withTitle: "取消")

            let choice = choiceAlert.runModal()
            if choice == .alertThirdButtonReturn {
                return
            }
            let shouldMerge = (choice == .alertFirstButtonReturn)

            do {
                try engine.userLexicon.importData(from: sourceURL, merge: shouldMerge)
                engine.reloadUserLexicon()
                let modeString = shouldMerge ? "合併" : "覆蓋"
                let successAlert = NSAlert()
                successAlert.messageText = "匯入成功"
                successAlert.informativeText = "學習紀錄已成功\(modeString)載入。"
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "好")
                successAlert.runModal()
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "匯入失敗"
                errorAlert.informativeText = "檔案格式不正確或已損毀：\n\(error.localizedDescription)"
                errorAlert.alertStyle = .critical
                errorAlert.addButton(withTitle: "好")
                errorAlert.runModal()
            }
        }
    }
}
