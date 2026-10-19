# 好注音 (HaoZhuyin)

> **專為 macOS 設計的高效原生繁體中文注音輸入法**  
> 具備自適應自我學習、鍵盤空間鄰近鍵容錯，以及流暢純粹的輸入體驗。

[![macOS](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 🌟 核心特色

1. **高效能注音解碼引擎 (ZhuyinEngine)**
   - 採用 **大千鍵盤佈局狀態機** 與 **Trie 樹前綴檢索**。
   - **Viterbi 最優路徑演算法**，整句解碼延遲小於 **2ms**。
   - 內建 6.5 萬條緊湊二進位詞庫（`lexicon.bin`），冷啟動載入小於 **200ms**。

2. **自適應自我學習系統 (Adaptive Learning)**
   - **同音字即時置頂**：選字時手動挑選同音字，下次鍵入立即優先推薦。
   - **自組詞自動記憶**：連續鍵入多字組合並送出時，自動學習成為新詞條。
   - **二元搭配學習 (Bigram Transitions)**：根據日常輸入習慣動態調整相鄰詞轉移成本，愈打愈聰明。
   - **零延遲與持久化**：學習資料於背景防抖寫入 `~/Library/Application Support/HaoZhuyin/user_lexicon.json`，絕不阻塞打字。

3. **常用文章匯入自主學習 (Article Ingestion & Adaptive Learning)**
   - **一鍵匯入個人語料**：支援拖放 `.txt` / `.md` 檔案或直接貼上常用文章、筆記與郵件，快速適應個人行文習慣與專業術語。
   - **無監督新詞探勘**：結合字元格最小成本 Viterbi 斷詞、點互資訊（PMI 凝固度）與左右邊界資訊熵，自動發掘 2～4 字專有名詞與自組詞。
   - **注音反查與破音字消歧**：內建全詞庫漢字轉注音反查索引，依複合詞結構智慧消歧多音字（如「老銀行」自動消歧為 `ㄏㄤˊ`）。
   - **前後文轉移強化與單字保護**：自動建立相鄰詞 Bigram 搭配與上下文選字偏好，且不干擾單字 MRU 即時選字佇列。
   - **雙軌模式與批次一鍵撤銷**：提供「預覽審核模式（可調整多音字讀音）」與「快速自動模式」；每次匯入皆記錄批次增量，可隨時一鍵精準撤銷復原，零詞庫污染風險。

4. **鍵盤空間鄰近按鍵容錯 (Keyboard Spatial Error Tolerance)**
   - 根據大千鍵盤的實體按鍵相鄰距離計算幾何懲罰分，智慧校正相鄰誤觸（如 `ㄍ` 與 `ㄐ`、`ㄖ` 與 `ㄈ`）。
   - 偏好設定中可自由開啟/關閉。

5. **現代極簡選字 UI**
   - 支援 **水平橫向** 與 **垂直直向** 候選字視窗切換。
   - 支援分頁翻頁、全候選字瀏覽，選單列顯示清晰之專屬「好」字圖示。

---

## 📦 安裝說明

### 雙擊 PKG 安裝（推薦）
1. 至 [Releases](https://github.com/eztraffic/IME/releases/tag/v1.0.0) 下載最新版 `HaoZhuyin-Installer.pkg`（或自行建置）。
2. 雙擊執行安裝程式，依指示完成安裝。
3. 前往 macOS **「系統設定」>「鍵盤」>「文字輸入」>「輸入方式」>「編輯…」**，點選 **「+」**，於「繁體中文」中新增 **「好注音」**。
4. 切換為「好注音」即可開始打字！

---

## 📖 常用文章匯入自主學習指南

「好注音」支援透過分析使用者既有的常用文章、專業文件或筆記，快速訓練出最懂你的個人化輸入法：

### 1. 透過選單列圖形介面 (GUI)
1. 點擊 macOS 選單列右上角「好注音」的「好」圖示。
2. 點選 **「匯入文章學習...」** 開啟專屬面板。
3. **選擇輸入方式**：
   - 拖放任何 `.txt`、`.md` 檔案至視窗拖放區，或點選「選擇檔案...」。
   - 亦可直接於編輯框內貼上常用文章段落，並自訂批次名稱。
4. **選擇匯入模式**：
   - **預覽審核模式（推薦）**：分析後列出所有發掘的新詞與高頻詞，支援透過下拉選單自由切換破音字讀音，確認後點擊「確認寫入」。
   - **快速自動模式**：以高置信度門檻自動過濾並直接注入詞庫，無打擾快速完成。
5. **安全一鍵撤銷 (Rollback)**：
   - 視窗下方「歷史匯入批次紀錄」保留每筆匯入的增量摘要，點擊「撤銷復原」即可精確扣除該批次之詞條與 Bigram，並即時熱重載詞庫，絕不殘留污染。

### 2. 透過命令列工具 (CLI)
開發者或進階使用者亦可透過 CLI 指令快速批次匯入：
```bash
# 匯入本機檔案
swift run ZhuyinCLI --ingest /path/to/article.txt

# 或直接傳入文章文字
swift run ZhuyinCLI --ingest "今天陳小明去學校上課，大家都覺得陳小明很認真。"
```

---

## 🛠️ 從原始碼編譯與建置

本專案使用標準 Swift Package Manager 與 Makefile 建置。

### 系統需求
- macOS 13.0 (Ventura) 或更新版本
- Xcode 15.0+ 或 Command Line Tools (Swift 5.9+)
- Python 3 (僅維護與重新生成詞庫時需要)

### 常用指令

```bash
# 1. 編譯並打包出安裝套件 (dist/HaoZhuyin-Installer.pkg)
make pkg
# 或直接：
make

# 2. 開發階段直接安裝至目前使用者目錄 (~/Library/Input Methods)
make install

# 3. 執行完整單元測試與效能驗收測試 (80+ Tests)
make test

# 4. 診斷目前輸入法安裝狀態與系統註冊
make status

# 5. 清理建置產物
make clean

# 6. 徹底從系統中移除好注音（含註冊清理）
make uninstall
```

---

## 📚 詞庫管線 (Data Pipeline)

詞庫管線位於 `Tools/DataPipeline/build_lexicon.py`：
- 自動自開源專案下載台灣中文詞庫與字音資料（包含 McBopomofo BPMFMappings、phrase.occ、BPMFBase 等）。
- 執行詞頻歸一化、排除古代罕見音、建立「在/再」與「的/得」文法轉移矩陣。
- 壓縮生成高效二進位檔 `Sources/ZhuyinEngine/Resources/lexicon.bin`。

如需更新詞庫：
```bash
python3 Tools/DataPipeline/build_lexicon.py
```

---

## 📂 專案檔案結構

```
IME/
├── .gitignore                      # Git 忽略設定
├── LICENSE                         # MIT 開源授權條款
├── Makefile                        # 建置與打包捷徑指令
├── Package.swift                   # Swift Package Manager 配置
├── README.md                       # 專案手冊
├── Sources/
│   ├── HaoZhuyin/                  # macOS 輸入法主程式與選字視窗 UI
│   │   ├── ArticleImportWindow.swift # 常用文章匯入、審核與撤銷 AppKit 視窗
│   │   ├── CandidateWindow.swift     # 候選字視窗
│   │   └── ZhuyinInputController.swift # IMK 輸入控制器與選單列掛載
│   ├── ZhuyinCLI/                  # 開發與除錯 CLI 工具（支援 --ingest）
│   └── ZhuyinEngine/               # 核心注音編解碼引擎、學習系統與二進位詞庫
│       ├── Lexicon/                # 詞庫管理、二進位讀取器、UserLexicon 與注音反查
│       ├── TextIngestion/          # 文章前處理、機敏過濾、PMI 新詞探勘與 G2P 標註流水線
│       └── Resources/              # 緊湊二進位詞庫 (lexicon.bin)
├── Tests/
│   └── ZhuyinEngineTests/          # 完整單元測試與效能驗收測試套件 (80+ Tests)
└── Tools/
    ├── DataPipeline/
    │   └── build_lexicon.py        # 詞庫下載與二進位編譯工具
    ├── generate_icons.swift        # 選單列「好」圖標與 AppIcon 動態生成腳本
    ├── package_ime.sh              # PKG 自動化封裝與註冊腳本
    ├── pkg_scripts/                # PKG 安裝前後註冊腳本
    └── uninstall.sh                # 乾淨卸載工具
```

---

## 📄 開源授權與致謝

- 本專案採用 [MIT License](LICENSE) 授權。
- 詞庫資料集衍生自 [openvanilla/McBopomofo (小麥注音)](https://github.com/openvanilla/McBopomofo) 開源資料集，感謝開源社群的付出與貢獻。
