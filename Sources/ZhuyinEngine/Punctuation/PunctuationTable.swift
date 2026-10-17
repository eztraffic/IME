import Foundation

/// Represents the definition and candidates for a punctuation mark.
public struct PunctuationDefinition: Sendable, Equatable {
    /// The default primary character or symbol string.
    public let primary: String
    /// Candidate variations accessible via candidate selection (Space / Down Arrow).
    public let candidates: [String]

    public init(primary: String, candidates: [String]) {
        self.primary = primary
        self.candidates = candidates
    }
}

/// Comprehensive punctuation mapping adhering strictly to macOS Traditional Chinese Zhuyin (Apple 繁體注音) conventions.
public enum PunctuationTable {
    // MARK: - Standard Candidate Mappings (Aligned with macOS CoreChineseEngine CIMPunctuationCandidates)

    public static let candidateMap: [String: [String]] = [
        "，": ["，", "、", "　", "《", "〈", "＜", ","],
        "。": ["。", "……", "⋯⋯", "　", "・", "·", "．", "》", "〉", "＞", "."],
        "、": ["、", "＼", "\\", "｜", "|"],
        "；": ["；", "：", ";"],
        "：": ["：", "；", ":"],
        "！": ["！", "１", "!"],
        "？": ["？", "/", "／", "÷", "?"],
        "·": ["·", "・", "。", "、", "`", "｀", "‘", "’"],
        "’": ["’", "‘", "'", "、"],
        "‘": ["‘", "’", "'", "、"],
        "”": ["”", "“", "\"", "〃", "々"],
        "“": ["“", "”", "\"", "〃", "々"],
        "（": ["（", "(", "９"],
        "）": ["）", ")", "０"],
        "［": ["［", "〔", "｛", "["],
        "］": ["］", "〕", "｝", "]"],
        "｛": ["｛", "〔", "［", "{"],
        "｝": ["｝", "〕", "］", "}"],
        "〈": ["〈", "《", "＜", "<"],
        "〉": ["〉", "》", "＞", ">"],
        "《": ["《", "〈", "＜", "<", "，"],
        "》": ["》", "〉", "＞", ">", "。"],
        "「": ["「", "『", "【", "〖", "〔", "［", "｛"],
        "」": ["」", "』", "】", "〗", "〕", "］", "｝"],
        "『": ["『", "「", "【", "〖", "〔", "［", "｛"],
        "』": ["』", "」", "】", "〗", "〕", "］", "｝"],
        "【": ["【", "「", "『", "〖", "〔", "［"],
        "】": ["】", "」", "』", "〗", "〕", "］"],
        "〔": ["〔", "［", "｛"],
        "〕": ["〕", "］", "｝"],
        "〖": ["〖", "「", "『", "【"],
        "〗": ["〗", "」", "』", "】"],
        "＠": ["＠", "@", "２"],
        "＃": ["＃", "#", "３"],
        "＄": ["＄", "$", "４", "¥", "￥", "€"],
        "％": ["％", "%", "５", "‰"],
        "……": ["……", "⋯⋯", "＾", "^", "６", "。"],
        "⋯⋯": ["⋯⋯", "……", "。"],
        "＆": ["＆", "&", "７"],
        "＊": ["＊", "*", "８", "×"],
        "——": ["——", "—", "＿", "－", "-", "−"],
        "—": ["—", "——", "＿", "－", "-", "−"],
        "＿": ["＿", "——", "—", "－", "-", "−"],
        "－": ["－", "-", "——", "—", "＿", "−"],
        "＋": ["＋", "+", "＝", "=", "×", "÷"],
        "＝": ["＝", "=", "＋", "+", "×", "÷"],
        "｜": ["｜", "|", "＼", "\\"],
        "～": ["～", "~", "﹋"],
        "　": ["　", " "]
    ]

    /// The curated Traditional Chinese Symbol Palette triggered by Option + Shift + B.
    public static let symbolPalette: [String] = [
        "，", "。", "！", "？", "：", "；", "、", "「", "」",
        "『", "』", "——", "……", "（", "）", "《", "》", "～"
    ]

    // MARK: - Key Definitions

    /// Retrieves candidate list for a given punctuation mark.
    public static func candidates(for punctuation: String, maxCount: Int = 100) -> [String] {
        if let list = candidateMap[punctuation] {
            return Array(list.prefix(maxCount))
        }
        return [punctuation]
    }

    /// Looks up a punctuation definition based on virtual key code, input character, and modifier flags.
    ///
    /// - Parameters:
    ///   - keyCode: macOS virtual key code (e.g. 0x2B for comma). Pass -1 if unavailable.
    ///   - character: Input character string.
    ///   - isShift: Whether the Shift modifier is pressed.
    ///   - isOption: Whether the Option (Alt) modifier is pressed.
    /// - Returns: A matching `PunctuationDefinition`, or nil if the key is not a punctuation trigger.
    public static func lookup(
        keyCode: Int,
        character: Character?,
        isShift: Bool,
        isOption: Bool
    ) -> PunctuationDefinition? {
        // 1. Shift + Option Combinations
        if isShift && isOption {
            // Shift + Option + B: Symbol Palette
            if keyCode == 0x0B || character == "B" || character == "b" {
                return PunctuationDefinition(primary: "，", candidates: symbolPalette)
            }
            // Shift + Option + Space: Fullwidth Space (　)
            if keyCode == 0x31 || character == " " {
                return PunctuationDefinition(primary: "　", candidates: candidateMap["　"] ?? ["　", " "])
            }
            // Shift + Option + ,: Left Book Title Mark (《)
            if keyCode == 0x2B || character == "<" || character == "," {
                return PunctuationDefinition(primary: "《", candidates: candidateMap["《"]!)
            }
            // Shift + Option + .: Right Book Title Mark (》)
            if keyCode == 0x2F || character == ">" || character == "." {
                return PunctuationDefinition(primary: "》", candidates: candidateMap["》"]!)
            }
        }

        // 2. Option Only Combinations
        if isOption && !isShift {
            // Option + ;: Semicolon (；)
            if keyCode == 0x29 || character == ";" || character == "…" {
                return PunctuationDefinition(primary: "；", candidates: candidateMap["；"]!)
            }
            // Option + -: Dash (—)
            if keyCode == 0x1B || character == "-" || character == "–" {
                return PunctuationDefinition(primary: "—", candidates: candidateMap["—"]!)
            }
            // Option + ,: Left Book Title Mark (《)
            if keyCode == 0x2B || character == "," || character == "≤" {
                return PunctuationDefinition(primary: "《", candidates: candidateMap["《"]!)
            }
            // Option + .: Right Book Title Mark (》)
            if keyCode == 0x2F || character == "." || character == "≥" {
                return PunctuationDefinition(primary: "》", candidates: candidateMap["》"]!)
            }
            // Option + [: Left Corner Bracket (「)
            if keyCode == 0x21 || character == "[" || character == "“" {
                return PunctuationDefinition(primary: "「", candidates: candidateMap["「"]!)
            }
            // Option + ]: Right Corner Bracket (」)
            if keyCode == 0x1E || character == "]" || character == "‘" {
                return PunctuationDefinition(primary: "」", candidates: candidateMap["」"]!)
            }
        }

        // 3. Shift Only Combinations
        if isShift && !isOption {
            // Shift + , (<): Fullwidth Comma (，)
            if keyCode == 0x2B || character == "<" {
                return PunctuationDefinition(primary: "，", candidates: candidateMap["，"]!)
            }
            // Shift + . (>): Fullwidth Full Stop / Period (。)
            if keyCode == 0x2F || character == ">" {
                return PunctuationDefinition(primary: "。", candidates: candidateMap["。"]!)
            }
            // Shift + / (?): Fullwidth Question Mark (？)
            if keyCode == 0x2C || character == "?" {
                return PunctuationDefinition(primary: "？", candidates: candidateMap["？"]!)
            }
            // Shift + ; (:): Fullwidth Colon (：)
            if keyCode == 0x29 || character == ":" {
                return PunctuationDefinition(primary: "：", candidates: candidateMap["："]!)
            }
            // Shift + ' ("): Fullwidth Double Quote (”)
            if keyCode == 0x27 || character == "\"" {
                return PunctuationDefinition(primary: "”", candidates: candidateMap["”"]!)
            }
            // Shift + 1 (!): Fullwidth Exclamation Mark (！)
            if keyCode == 0x12 || character == "!" {
                return PunctuationDefinition(primary: "！", candidates: candidateMap["！"]!)
            }
            // Shift + 2 (@): Fullwidth At (＠)
            if keyCode == 0x13 || character == "@" {
                return PunctuationDefinition(primary: "＠", candidates: candidateMap["＠"]!)
            }
            // Shift + 3 (#): Fullwidth Number Sign (＃)
            if keyCode == 0x14 || character == "#" {
                return PunctuationDefinition(primary: "＃", candidates: candidateMap["＃"]!)
            }
            // Shift + 4 ($): Fullwidth Dollar (＄)
            if keyCode == 0x15 || character == "$" {
                return PunctuationDefinition(primary: "＄", candidates: candidateMap["＄"]!)
            }
            // Shift + 5 (%): Fullwidth Percent (％)
            if keyCode == 0x17 || character == "%" {
                return PunctuationDefinition(primary: "％", candidates: candidateMap["％"]!)
            }
            // Shift + 6 (^): Ellipsis (……)
            if keyCode == 0x16 || character == "^" {
                return PunctuationDefinition(primary: "……", candidates: candidateMap["……"]!)
            }
            // Shift + 7 (&): Fullwidth Ampersand (＆)
            if keyCode == 0x1A || character == "&" {
                return PunctuationDefinition(primary: "＆", candidates: candidateMap["＆"]!)
            }
            // Shift + 8 (*): Fullwidth Asterisk (＊)
            if keyCode == 0x1C || character == "*" {
                return PunctuationDefinition(primary: "＊", candidates: candidateMap["＊"]!)
            }
            // Shift + 9 ((): Fullwidth Left Parenthesis (（)
            if keyCode == 0x19 || character == "(" {
                return PunctuationDefinition(primary: "（", candidates: candidateMap["（"]!)
            }
            // Shift + 0 ()): Fullwidth Right Parenthesis (）)
            if keyCode == 0x1D || character == ")" {
                return PunctuationDefinition(primary: "）", candidates: candidateMap["）"]!)
            }
            // Shift + - (_): Em Dash (——)
            if keyCode == 0x1B || character == "_" {
                return PunctuationDefinition(primary: "——", candidates: candidateMap["——"]!)
            }
            // Shift + = (+): Fullwidth Plus (＋)
            if keyCode == 0x18 || character == "+" {
                return PunctuationDefinition(primary: "＋", candidates: candidateMap["＋"]!)
            }
            // Shift + [ ({): Left Double Corner Bracket (『)
            if keyCode == 0x21 || character == "{" {
                return PunctuationDefinition(primary: "『", candidates: candidateMap["『"]!)
            }
            // Shift + ] (}): Right Double Corner Bracket (』)
            if keyCode == 0x1E || character == "}" {
                return PunctuationDefinition(primary: "』", candidates: candidateMap["』"]!)
            }
            // Shift + \ (|): Fullwidth Vertical Line (｜)
            if keyCode == 0x2A || character == "|" {
                return PunctuationDefinition(primary: "｜", candidates: candidateMap["｜"]!)
            }
            // Shift + ` (~): Fullwidth Tilde (～)
            if keyCode == 0x32 || character == "~" {
                return PunctuationDefinition(primary: "～", candidates: candidateMap["～"]!)
            }
        }

        // 4. Unshifted Non-Zhuyin Punctuation Keys
        if !isShift && !isOption {
            // [ : Left Corner Bracket (「)
            if keyCode == 0x21 || character == "[" {
                return PunctuationDefinition(primary: "「", candidates: candidateMap["「"]!)
            }
            // ] : Right Corner Bracket (」)
            if keyCode == 0x1E || character == "]" {
                return PunctuationDefinition(primary: "」", candidates: candidateMap["」"]!)
            }
            // \ : Ideographic Comma / Dunhao (、)
            if keyCode == 0x2A || character == "\\" {
                return PunctuationDefinition(primary: "、", candidates: candidateMap["、"]!)
            }
            // ' : Fullwidth Single Quote (’)
            if keyCode == 0x27 || character == "'" {
                return PunctuationDefinition(primary: "’", candidates: candidateMap["’"]!)
            }
            // ` : Middle Dot (·)
            if keyCode == 0x32 || character == "`" {
                return PunctuationDefinition(primary: "·", candidates: candidateMap["·"]!)
            }
            // = : Fullwidth Equal (＝)
            if keyCode == 0x18 || character == "=" {
                return PunctuationDefinition(primary: "＝", candidates: candidateMap["＝"]!)
            }
        }

        // 5. Fallback check for directly typed fullwidth punctuation characters
        if let char = character {
            let str = String(char)
            if let list = candidateMap[str] {
                return PunctuationDefinition(primary: str, candidates: list)
            }
        }

        return nil
    }
}
