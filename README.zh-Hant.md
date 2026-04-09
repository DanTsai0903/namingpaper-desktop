<p align="center">
  <img src="macos/NamingPaper/NamingPaper/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" alt="NamingPaper 圖示">
</p>

# namingpaper

AI 驅動的學術 PDF 重新命名工具，搭配原生 macOS 應用程式與論文管理庫。

**重命名前：** `1-s2.0-S0304405X13000044-main.pdf`
**重命名後：** `Fama and French, (1993, JFE), Common risk factors in the returns on stocks and bonds.pdf`

## 專案內容

- **CLI 工具** — 從終端機重新命名 PDF，支援單一或批次處理
- **macOS 應用程式** — 原生 SwiftUI 桌面應用程式，具備論文庫、搜尋及 PDF 預覽功能
- **論文管理庫** — 以 SQLite 為基礎的目錄，搭配 AI 生成的摘要、分類及全文搜尋

## 安裝

### CLI

```bash
# 使用 uv（推薦）
uv tool install git+https://github.com/DanTsai0903/namingpaper-desktop.git

# 使用 pipx
pipx install git+https://github.com/DanTsai0903/namingpaper-desktop.git

# 搭配選用的雲端服務提供者
uv tool install "namingpaper[openai] @ git+https://github.com/DanTsai0903/namingpaper-desktop.git"
uv tool install "namingpaper[gemini] @ git+https://github.com/DanTsai0903/namingpaper-desktop.git"
```

### macOS 應用程式

從[最新 GitHub Release](https://github.com/DanTsai0903/namingpaper-desktop/releases/latest) 下載 `NamingPaper.dmg`，開啟後將 **NamingPaper.app** 拖曳至「應用程式」資料夾。應用程式支援自動更新——有新版本時會收到通知。

首次啟動時，macOS 會因未經公證而阻止開啟。解決方式：

1. 在「應用程式」中對 **NamingPaper.app** 按右鍵（或 Control + 點擊）
2. 從選單中選擇**開啟**
3. 在彈出的對話框中點擊**開啟**

只需操作一次即可。

**如果仍然無法開啟**，請前往**系統設定 → 隱私權與安全性**，向下捲動，在 NamingPaper 訊息旁點擊**仍要開啟**。若未看到訊息，請再次嘗試啟動應用程式。

最後手段是從終端機移除隔離標記：

```bash
xattr -d com.apple.quarantine /Applications/NamingPaper.app
```

也可以使用 Xcode 開啟 `macos/NamingPaper/NamingPaper.xcodeproj` 從原始碼建置。

## 快速入門

### CLI 快速入門

預設使用 ollama（本地端，無需 API 金鑰）。請從 [ollama.com](https://ollama.com) 安裝。其他本地選項包括適用於 Apple Silicon Mac 的 [oMLX](https://github.com/jundot/omlx) 以及跨平台本地推論的 [LM Studio](https://lmstudio.ai)。

各服務提供者的預設模型：

| 服務提供者 | 文字模型 | OCR 模型 |
| ---------- | -------- | -------- |
| ollama | `qwen3.5:4b` | `deepseek-ocr` |
| oMLX | `Qwen3.5-2B-MLX-4bit` | `DeepSeek-OCR-8bit` |
| LM Studio | `qwen3.5-2b-optiq` | —（選用，可透過 `lmstudio_ocr_model` 設定） |
| Claude | `claude-sonnet-4-20250514` | — |
| OpenAI | `gpt-4o` | — |
| Gemini | `gemini-2.0-flash` | — |

```bash
ollama pull qwen3:8b

# 預覽重命名（模擬執行）
namingpaper rename paper.pdf

# 執行重命名
namingpaper rename paper.pdf --execute

# 批次重命名
namingpaper batch ~/Downloads/papers --execute
```

使用雲端服務提供者（Claude、OpenAI、Gemini）：

```bash
export NAMINGPAPER_ANTHROPIC_API_KEY=sk-ant-...
namingpaper rename paper.pdf -p claude --execute
```

### macOS 應用程式快速入門

應用程式包裝了 CLI 工具，並加入視覺化的論文管理庫。可透過原生介面新增論文、依分類瀏覽、搜尋中繼資料及預覽 PDF。

功能特色：

- 拖放或檔案選取器新增論文
- AI 擷取的中繼資料及信心分數
- 分類樹側邊欄，智慧整理
- 跨標題、作者、期刊的全文模糊搜尋
- 內嵌 PDF 預覽及可編輯的中繼資料
- **與 PDF 對話** — 基於 RAG 的文件問答，支援 Markdown 與 LaTeX 渲染
- 透過工具列按鈕或右鍵選單將論文下載至任意資料夾
- 論文庫備份與還原；匯出／匯入 `.namingpaper` 套件以供分享
- 多語言介面 — 可在 English、繁體中文、简体中文、Español、日本語、한국어 之間切換
- API 金鑰安全儲存於 macOS 鑰匙圈

## 論文管理庫

```bash
# 新增論文（重命名 + 摘要 + 分類）
namingpaper add paper.pdf --execute

# 搜尋
namingpaper search "risk factors"
namingpaper search --author "Fama" --year 2020-2024

# 瀏覽
namingpaper list --category "Finance/Asset Pricing"
namingpaper info a3f2
namingpaper remove a3f2 --execute

# 下載 / 匯出
namingpaper download a3f2 --output ~/Desktop
namingpaper download --query "risk factors" --output ~/Desktop
namingpaper download --category "Finance" --output ~/Desktop
namingpaper download --all --output ~/Desktop --flat
```

論文預設存放於 `~/Papers/`（可透過 `NAMINGPAPER_PAPERS_DIR` 設定），並以分類子資料夾整理。

## CLI 參考

### `namingpaper rename <pdf>`

重新命名單一 PDF。

| 選項 | 說明 |
| ---- | ---- |
| `-x, --execute` | 實際執行重命名（預設為模擬執行） |
| `-y, --yes` | 跳過確認提示 |
| `-p, --provider` | AI 服務提供者：`ollama`、`omlx`、`lmstudio`、`claude`、`openai`、`gemini` |
| `-m, --model` | 覆寫預設模型 |
| `--ocr-model` | 覆寫 Ollama OCR 模型 |
| `-t, --template` | 檔名範本或預設組合 |
| `-o, --output-dir` | 複製至指定目錄（保留原檔） |
| `-c, --collision` | 衝突策略：`skip`、`increment`、`overwrite` |

### `namingpaper batch <directory>`

重新命名目錄中所有 PDF。

與 `rename` 相同的選項，另外支援：

| 選項 | 說明 |
| ---- | ---- |
| `-r, --recursive` | 掃描子目錄 |
| `-f, --filter` | Glob 模式篩選 |
| `--parallel N` | 並行擷取數量 |
| `--json` | JSON 輸出 |

### `namingpaper download`

將論文從管理庫匯出至指定目錄。

| 選項 | 說明 |
| ---- | ---- |
| `[IDs...]` | 要下載的論文 ID |
| `-o, --output` | 輸出目錄（必填） |
| `-q, --query` | 以搜尋關鍵字篩選論文 |
| `-c, --category` | 下載某分類的所有論文 |
| `--all` | 下載庫中所有論文 |
| `--flat` | 不建立分類子資料夾 |
| `--overwrite` | 覆寫已存在的檔案 |
| `-x, --execute` | 實際執行複製（預設為模擬執行） |

### 其他指令

```bash
namingpaper templates    # 顯示可用範本
namingpaper config --show
namingpaper version
namingpaper update --execute --yes
namingpaper uninstall --execute --yes [--purge]
```

## 檔名範本

| 預設 | 模式 | 範例 |
| ---- | ---- | ---- |
| `default` | `{authors}, ({year}, {journal}), {title}` | `Fama and French, (1993, JFE), Common risk....pdf` |
| `compact` | `{authors} ({year}) {title}` | `Fama and French (1993) Common risk....pdf` |
| `full` | `{authors}, ({year}, {journal_full}), {title}` | 使用完整期刊名稱 |
| `simple` | `{authors} - {year} - {title}` | `Fama and French - 1993 - Common risk....pdf` |

佔位符：`{authors}`、`{authors_full}`、`{authors_abbrev}`、`{year}`、`{journal}`、`{journal_full}`、`{journal_abbrev}`、`{title}`

## AI 服務提供者

| 服務提供者 | 設定方式 | 備註 |
| ---------- | -------- | ---- |
| **Ollama**（預設） | `ollama pull qwen3:8b` | 跨平台、本地端 |
| **oMLX** | `brew services start omlx` | 僅限 Apple Silicon，跨平台及本地 MLX 推論 |
| **LM Studio** | 從 [lmstudio.ai](https://lmstudio.ai) 下載，載入模型並啟動伺服器 | 跨平台、本地端|
| **Claude** | `NAMINGPAPER_ANTHROPIC_API_KEY` | |
| **OpenAI** | `NAMINGPAPER_OPENAI_API_KEY` | 需要 `namingpaper[openai]` |
| **Gemini** | `NAMINGPAPER_GEMINI_API_KEY` | 需要 `namingpaper[gemini]` |

## 設定

設定優先順序：CLI 參數 > 環境變數（`NAMINGPAPER_*`）> 設定檔（`~/.namingpaper/config.toml`）> 預設值。

```toml
# ~/.namingpaper/config.toml
ai_provider = "ollama"
template = "default"
max_authors = 3
max_filename_length = 200
```

使用 `namingpaper config --show` 查看完整環境變數列表。

## 開發

```bash
git clone https://github.com/DanTsai0903/namingpaper-desktop.git
cd namingpaper-desktop
uv sync --all-extras --dev
uv run pytest -v
```

## 致謝

最初從 [DanTsai0903/namingpaper](https://github.com/DanTsai0903/namingpaper) 分支而來。

## 授權條款

Apache 2.0
