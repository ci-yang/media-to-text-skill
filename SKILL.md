---
name: media-to-text
description: >
  媒體轉文字完整工作流程。將影片 URL、本地影片或音訊檔轉換為逐字稿與結構化摘要，
  支援自動語言偵測與雙語輸出（原文 + 繁體中文翻譯）。可選發布至 Notion 或 NotebookLM。
  觸發詞：media-to-text、轉逐字稿、影片轉文字、音訊轉文字、會議記錄、
  YouTube 影片摘要、podcast 摘要、講座筆記、面試記錄、影音內容整理、
  錄音轉文字、語音辨識、video to text、audio transcription、
  meeting notes、逐字稿產生、字幕產生、錄影轉文字、音檔轉文字、
  播客筆記、訪談記錄、客戶訪談摘要、腦力激盪記錄、一對一會議記錄、
  bilingual transcript、雙語逐字稿、翻譯逐字稿、英文影片中文摘要。
---

# Media to Text Workflow

將任何影片或音訊來源轉換為高品質逐字稿與結構化摘要。支援多語言自動偵測，可產出雙語版本（原文 + 繁體中文翻譯）。

## 觸發條件

當使用者提到以下任一情境時啟動：
- 輸入 `/media-to-text`
- 提到「轉逐字稿」「影片轉文字」「音訊轉文字」「會議記錄」「YouTube 摘要」等關鍵詞
- 提供影片 URL 或音訊檔案路徑並要求轉錄或摘要

## 使用方式

```
/media-to-text <input> [--lang auto|en|zh|ja|ko|...] [--bilingual] [--template auto|meeting|...] [--publish local|notion|notebooklm|all] [--output-dir ./output]
```

### 範例

```bash
# 基本用法（自動偵測語言，單語輸出）
/media-to-text https://youtube.com/watch?v=xxx

# 中文會議，單語輸出
/media-to-text ~/recordings/meeting.m4a --template meeting --publish notion

# 英文影片，雙語輸出（原文 + 繁體中文翻譯）
/media-to-text https://youtube.com/watch?v=xxx --bilingual

# 明確指定語言
/media-to-text ~/Videos/lecture.mp4 --lang en --bilingual --template lecture
```

### 參數

| 參數 | 預設 | 說明 |
|------|------|------|
| `input` | （必填） | YouTube URL、本地影片路徑、或本地音訊路徑 |
| `--lang` | `auto` | 音訊主要語言。auto 自動偵測（見 Phase 2.1）。支援 Whisper 所有語言代碼 |
| `--bilingual` | `false` | 產出雙語版：原文逐字稿/摘要 + 繁體中文翻譯版。非中文音訊偵測到時會主動詢問 |
| `--template` | `auto` | 摘要範本，auto 自動偵測 |
| `--publish` | `local` | 發布目標：local / notion / notebooklm / all |
| `--output-dir` | `./output` | 本地輸出目錄 |

---

## 平台支援

| 平台 | Whisper 後端 | GPU 加速 |
|------|-------------|---------|
| macOS Apple Silicon | `mlx-whisper` | Metal GPU（~20x realtime） |
| Linux | `faster-whisper` | NVIDIA CUDA（~20x+ realtime） |
| Linux (無 GPU) | `faster-whisper` | CPU INT8（較慢但可用） |

後端自動偵測，程式碼統一使用 `scripts/transcribe.py` 抽象層。

## Python 環境

本 skill 使用共用虛擬環境 `~/.claude/.venv`，所有需要 Python 的地方都使用此路徑。

```bash
PYTHON="$HOME/.claude/.venv/bin/python"
```

**為何用 `~/.claude/.venv`**：此 skill 可在任何專案目錄下觸發，使用固定的全域 venv 避免每個專案都要安裝一次依賴。Whisper 模型快取在 `~/.cache/huggingface/hub/`，也是全域共用。

---

## 前置檢查

在開始前，用 Bash 工具執行以下檢查：

```bash
# 一次檢查所有依賴
echo "=== 依賴檢查 ==="
echo "平台: $(uname -s) $(uname -m)"
command -v yt-dlp   && echo "✅ yt-dlp"   || echo "❌ yt-dlp 缺失"
command -v ffmpeg   && echo "✅ ffmpeg"    || echo "❌ ffmpeg 缺失"
PYTHON="$HOME/.claude/.venv/bin/python"
[[ -x "$PYTHON" ]] && echo "✅ Python venv: $HOME/.claude/.venv" || echo "❌ .venv 缺失 → bash {skill_dir}/install.sh"

# Whisper 後端檢查（自動依平台）
if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    "$PYTHON" -c "import mlx_whisper" 2>/dev/null && echo "✅ mlx-whisper (Apple Silicon)" || echo "❌ mlx-whisper → pip install mlx-whisper"
else
    "$PYTHON" -c "import faster_whisper" 2>/dev/null && echo "✅ faster-whisper (CUDA/CPU)" || echo "❌ faster-whisper → pip install faster-whisper"
fi

"$PYTHON" -c "import opencc" 2>/dev/null && echo "✅ opencc" || echo "❌ opencc → pip install opencc-python-reimplemented"
```

若任何依賴缺失，告知使用者安裝指令後停止。

---

## 執行模式

提供兩種模式，優先使用一鍵模式：

### 一鍵模式（推薦）

Phase 1+2 用腳本一次完成擷取與轉錄，接著 Claude 執行 Phase 3-5：

```bash
bash {skill_dir}/scripts/media-to-text.sh "<input>" "<output_dir>"
```

腳本完成後 `<output_dir>/` 會包含 `transcript.md`、`transcript.txt`、`whisper_raw.json`，直接跳到 **Phase 3**。

### 分步模式

若腳本不可用或使用者要求逐步執行，按以下 Phase 依序進行。

---

## Phase 1：媒體擷取

**目標**：取得 16kHz mono WAV 音訊檔。

### 1.1 建立輸出目錄

```bash
OUTPUT_DIR="./output/$(date +%Y-%m-%d)_{safe_title}"
mkdir -p "$OUTPUT_DIR"
```

### 1.2 依輸入類型擷取音訊

**URL（YouTube 等）**：
```bash
yt-dlp -x --audio-format wav --audio-quality 0 -o "$OUTPUT_DIR/audio_raw.%(ext)s" "<url>"
```

**本地影片（mp4/mkv/avi/mov/webm/flv）**：
```bash
ffmpeg -y -i "<input>" -vn -acodec pcm_s16le "$OUTPUT_DIR/audio_raw.wav" -loglevel warning
```

**本地音訊（mp3/wav/m4a/flac/ogg/aac/aiff）**：直接使用原檔作為 audio_raw。

### 1.3 統一轉換為 16kHz mono WAV

```bash
ffmpeg -y -i "$OUTPUT_DIR/audio_raw"* -ar 16000 -ac 1 -c:a pcm_s16le "$OUTPUT_DIR/audio.wav" -loglevel warning
```

WHY 16kHz mono：Whisper 模型的原生輸入格式，減少不必要的降採樣計算。

### 1.4 報告

```
✅ Phase 1 完成：音訊擷取
   檔案：audio.wav (16kHz mono)
   時長：{用 ffprobe 取得}
   來源：{url 或檔名}
```

**失敗回退**：若 yt-dlp 失敗，提示使用者確認 URL。若 ffmpeg 失敗，檢查輸入格式。

---

## Phase 2：語言偵測與轉錄

**目標**：偵測語言 → 用該語言轉錄 → 可選翻譯為繁體中文。

### 2.1 語言偵測（若 `--lang auto`）

用 `transcribe.py` 轉錄完整音訊，讀取結果中的 `language` 欄位（或用 Whisper 跑前 30 秒片段偵測）：

```bash
$HOME/.claude/.venv/bin/python {skill_dir}/scripts/transcribe.py \
    "$OUTPUT_DIR/audio.wav" "$OUTPUT_DIR/whisper_raw.json" \
    --language auto
# 讀取偵測到的語言
DETECTED_LANG=$($HOME/.claude/.venv/bin/python -c "
import json; d=json.load(open('$OUTPUT_DIR/whisper_raw.json'))
print(d.get('language', 'unknown'))
")
```

偵測到語言後，向使用者確認（除非使用者已用 `--lang` 指定）：

```
🌐 偵測到主要語言：{detected_language}
```

若偵測到非中文語言且使用者未指定 `--bilingual`，主動詢問：
```
   是否需要繁體中文翻譯版？(Y/n)
```

若使用者用 `--lang` 明確指定語言，跳過偵測直接使用。

### 2.2 原文轉錄

用偵測到的語言（或使用者指定的語言）執行 Whisper 轉錄。

**關鍵原則**：Whisper 的 `language` 參數必須設為音訊的**實際語言**。英文音訊就設 `"en"`，中文音訊就設 `"zh"`。跨語言轉錄（如對英文音訊設 `language="zh"`）品質極差，絕對禁止。

轉錄統一使用跨平台抽象層 `transcribe.py`（自動偵測 mlx-whisper 或 faster-whisper）：

**中文音訊**：

```bash
$HOME/.claude/.venv/bin/python {skill_dir}/scripts/transcribe.py \
    "$OUTPUT_DIR/audio.wav" "$OUTPUT_DIR/whisper_raw.json" \
    --language zh \
    --initial-prompt "以下是繁體中文的錄音，可能包含英文術語。"
# 然後用 OpenCC s2twp 簡轉繁，產生 transcript.md / transcript.txt
```

輸出：`transcript.md`、`transcript.txt`、`whisper_raw.json`

**非中文音訊**（如英文）：

```bash
$HOME/.claude/.venv/bin/python {skill_dir}/scripts/transcribe.py \
    "$OUTPUT_DIR/audio.wav" "$OUTPUT_DIR/whisper_raw_{lang}.json" \
    --language en \
    --initial-prompt "This is an English recording. It may contain technical terms."
# 不需要 OpenCC，直接輸出原文
```

非中文音訊的輸出檔名帶語言後綴：
- `transcript_{lang}.md`（如 `transcript_en.md`）
- `transcript_{lang}.txt`（如 `transcript_en.txt`）
- `whisper_raw_{lang}.json`（如 `whisper_raw_en.json`）

### 2.3 繁體中文翻譯（若 `--bilingual` 或使用者同意）

僅在以下情況執行翻譯：
- 使用者指定 `--bilingual`
- 偵測到非中文語言且使用者回答「是」

**翻譯方式**：用 Agent 工具發送翻譯任務（Claude 翻譯品質最好）。

```
Agent prompt:
  讀取 {output_dir}/transcript_{lang}.md 的英文逐字稿，
  翻譯成繁體中文（台灣用語），寫入：
  1. {output_dir}/transcript.md（含時間戳，每段 1:1 對應）
  2. {output_dir}/transcript.txt（純文字版）
  翻譯規則：
  - 保留所有專有名詞英文原文
  - 時間戳段落數必須與原文完全一致
  - 使用台灣用語（記憶體、程式、伺服器）
```

翻譯方式的選擇邏輯：
| 方式 | 何時使用 |
|------|---------|
| Claude Agent 翻譯 | **預設且推薦**。品質最好、專有名詞處理佳、語氣自然 |
| 不翻譯 | 使用者明確拒絕雙語輸出時 |

### 2.4 initial_prompt 語言適配

根據偵測到的語言自動調整 `initial_prompt`：

| 語言 | initial_prompt |
|------|---------------|
| `zh` | `以下是繁體中文的錄音，可能包含英文術語。` |
| `en` | `This is an English recording. It may contain technical terms.`（可根據影片標題追加上下文）|
| `ja` | `以下は日本語の録音です。英語の専門用語が含まれる場合があります。` |
| 其他 | 不設定 initial_prompt，讓 Whisper 自行判斷 |

### 關鍵參數說明

| 參數 | 值 | 原因 |
|------|-----|------|
| 模型 | `large-v3-turbo`（mlx 用 `mlx-community/whisper-large-v3-turbo`） | 速度與品質兼顧，跨平台自動選擇 |
| `language` | 偵測到的語言或使用者指定 | 必須匹配音訊實際語言，跨語言轉錄品質極差 |
| `condition_on_previous_text` | `False` | **防止幻覺**：不讓前段轉錄錯誤影響後段 |
| `initial_prompt` | 依語言自動適配 | 引導模型偏好正確語言的輸出 |
| `word_timestamps` | `True` | 提供精確到字詞的時間戳 |
| OpenCC `s2twp` | 僅中文音訊使用 | 如「記憶體」而非「內存」，「程式」而非「程序」 |

### 報告

```
✅ Phase 2 完成：語音轉錄
   語言：{detected_language}
   字數：{char_count}
   段落：{segment_count}
   模式：{單語/雙語}
   輸出：{列出實際產生的檔案}
```

**失敗回退**：若 Whisper 記憶體不足，建議用較小模型 `mlx-community/whisper-base`。

---

## Phase 3：範本偵測與摘要

**目標**：偵測最適範本，生成結構化 `summary.md`。

### 3.1 讀取逐字稿前 500 字

用 Read 工具讀取 `{output_dir}/transcript.txt`，取前 500 字用於範本偵測。

### 3.2 範本偵測邏輯

根據逐字稿內容的特徵判斷最適範本：

| 範本 ID | 偵測關鍵詞 / 特徵 |
|---------|------------------|
| `meeting` | 會議、議程、決議、待辦、出席、主席、紀錄 |
| `interview` | 面試、候選人、應徵、履歷、職位、薪資、錄取 |
| `lecture` | 講座、課程、教授、同學、今天的課、投影片、作業 |
| `brainstorm` | 腦力激盪、點子、brainstorm、想法、發想、創意 |
| `client` | 客戶、需求、痛點、報價、合作、方案、demo |
| `podcast` | 歡迎收聽、podcast、節目、來賓、聽眾、這一集 |
| `one_on_one` | 1on1、一對一、進度、目標、feedback、回饋、障礙 |
| `general` | 以上都不符合時的預設範本 |

匹配方式：計算每個範本的關鍵詞命中數，選擇命中最多者。若命中數相同或都為 0，使用 `general`。

### 3.3 使用者確認

```
🔍 偵測到最適範本：{template_name}（{template_id}）
   依據：命中關鍵詞 [{matched_keywords}]
   使用此範本？(Y/n) 或輸入其他範本 ID：
```

等待使用者確認後繼續。若使用者指定了 `--template` 且非 `auto`，跳過偵測。

### 3.4 讀取範本 YAML

用 Read 工具讀取 `{skill_dir}/templates/{template_id}.yaml`。

其中 `{skill_dir}` 為此 SKILL.md 所在目錄的絕對路徑。

### 3.5 生成摘要

讀取主要逐字稿作為上下文（中文音訊用 `transcript.txt`，非中文音訊用 `transcript_{lang}.txt`），以範本 YAML 中的 `system_prompt` 設定角色，逐 section 生成摘要內容。

**雙語模式**：若為雙語輸出，先用原文逐字稿生成原文摘要（`summary_{lang}.md`），再翻譯為繁體中文摘要（`summary.md`）。翻譯摘要時同樣保留專有名詞原文。

**生成原則**（摘要是創意任務，給予判斷空間）：
- 使用 YAML 中各 section 的 `prompt` 作為指令，但可依逐字稿實際內容調整深度
- `required: true` 的 section 必須生成，但若逐字稿資訊不足，標註「逐字稿中未明確提及」而非虛構
- `required: false` 的 section 只在逐字稿有充足相關資訊時才生成
- 可依品質判斷合併內容過少的 section，或在備註中說明資訊不完整
- 摘要應可獨立閱讀——讀者沒看過逐字稿也能完整理解
- 保留說話者的個人風格和用語特色

生成格式：
```markdown
## {section.title}

{generated_content}
```

### 3.6 合併為 summary.md

將所有 section 合併，加上標題與元資料，寫入 `{output_dir}/summary.md`：

```markdown
# {template.icon} {template.name}：{auto_title}

> 範本：{template.name} | 產生時間：{timestamp}

---

## {section_1_title}
{content_1}

## {section_2_title}
{content_2}

...
```

用 Write 工具寫入 `{output_dir}/summary.md`。

### 報告

```
✅ Phase 3 完成：摘要生成
   範本：{template_name}
   段落數：{section_count}
   輸出：summary.md
```

---

## Phase 4：發布（可選）

僅在使用者指定 `--publish` 非 `local` 時執行。

### 4.1 Notion 發布

使用 Notion MCP 工具：

1. 用 `mcp__claude_ai_Notion__notion-search` 搜尋目標資料庫
2. 確認目標資料庫後，用 `mcp__claude_ai_Notion__notion-create-pages` 建立頁面
3. 頁面內容包含 summary.md 的完整內容，屬性含標題、日期、範本類型

### 4.2 NotebookLM 發布

```bash
notebooklm-mcp-cli upload --file "{output_dir}/transcript.txt" --title "{title}"
```

### 報告

```
✅ Phase 4 完成：發布
   📓 Notion：{notion_url}（若有）
   📚 NotebookLM：{nlm_url}（若有）
```

**失敗回退**：發布失敗不影響本地檔案。告知使用者手動發布方式。

---

## Phase 5：完成報告

輸出結構化完成報告：

```markdown
## ✅ Media to Text 完成

### 📥 輸入
- 來源：{source}
- 時長：{duration}

### 🎙️ 轉錄
- 語言：{detected_language}
- 字數：{char_count}
- 段落：{segment_count}
- 模式：{單語/雙語}
- 引擎：MLX Whisper large-v3-turbo

### 📋 摘要
- 範本：{template_icon} {template_name}
- 段落數：{section_count}

### 📁 輸出檔案
| 檔案 | 說明 |
|------|------|
| `transcript.md` | 含時間戳的逐字稿（繁體中文） |
| `transcript.txt` | 純文字逐字稿（繁體中文） |
| `transcript_{lang}.md` | 原文逐字稿（若非中文音訊） |
| `transcript_{lang}.txt` | 原文純文字（若非中文音訊） |
| `whisper_raw.json` | Whisper 原始輸出 |
| `summary.md` | 結構化摘要（繁體中文） |
| `summary_{lang}.md` | 原文摘要（若雙語模式） |

### 📂 輸出目錄
`{output_dir}/`

### 🌐 雲端（若有）
- Notion：{notion_url}
- NotebookLM：{nlm_url}
```

---

## 範本清單

| ID | 名稱 | 適用場景 |
|----|------|---------|
| `general` | 📝 通用摘要 | 不確定類型時的預設 |
| `meeting` | 📋 會議記錄 | 多人會議、團隊例會 |
| `interview` | 🎯 面試摘要 | 求職面試、人才評估 |
| `lecture` | 🎓 講座筆記 | 演講、課堂、教學影片 |
| `brainstorm` | 💡 腦力激盪 | 創意會議、發想 |
| `client` | 🤝 客戶訪談 | 業務拜訪、需求訪談 |
| `podcast` | 🎙️ 播客/訪談 | 節目、訪談、對談 |
| `one_on_one` | 👥 一對一會議 | 主管面談、1-on-1 |

範本 YAML 位於 `{skill_dir}/templates/{id}.yaml`。

---

## 重要原則

- **繁體中文為最終輸出語言**：所有面向使用者的輸出（摘要、報告、互動文字）使用繁體中文（台灣用語）
- **原文逐字稿忠實於音訊語言**：英文音訊的逐字稿就是英文，中文音訊就是中文，不強制轉換
- **每個 Phase 完成後報告進度**
- **關鍵決策讓使用者確認**：語言偵測結果、雙語選擇、範本選擇、發布目標
- **本地檔案永遠保存**，雲端發布為可選
- **失敗時不影響已完成的步驟產出**：Phase 2 失敗不會刪除 Phase 1 的音訊檔
- **翻譯用 Agent**：非中文逐字稿的中文翻譯用 Agent 工具（Claude 翻譯），品質遠優於 Whisper 跨語言轉錄
- **Python 環境固定**：永遠使用 `$HOME/.claude/.venv/bin/python`，不要搜尋或猜測其他 venv 路徑

---

## 禁止事項

- **NEVER** 對超過 3 小時的音訊直接呼叫 large-v3-turbo 模型
  WHY：單次處理超長音訊會導致 Apple Silicon 記憶體不足崩潰，應先用 ffmpeg 分段
- **NEVER** 在摘要中加入逐字稿未提及的資訊
  WHY：摘要必須忠實於原始內容，不可出現幻覺，引用必須可在逐字稿中找到對應段落
- **NEVER** 未經使用者確認就發布至 Notion 或 NotebookLM
  WHY：發布動作不可逆，可能涉及敏感或內部內容
- **NEVER** 跳過 OpenCC 簡繁轉換直接輸出 Whisper 原始結果
  WHY：Whisper 中文模型輸出為簡體，直接輸出會讓台灣使用者混淆（「内存」vs「記憶體」）
- **NEVER** 使用 `condition_on_previous_text=True`
  WHY：會導致前段辨識錯誤累積到後段，造成大量重複文字或無意義輸出（幻覺）
- **NEVER** 用 Whisper 跨語言轉錄（如對英文音訊設 `language="zh"`）
  WHY：品質極差，會產出大量「那那那」亂碼或無意義重複文字。已在實際測試中驗證，英文影片用 `language="zh"` 的轉錄結果完全不可用。正確做法是用音訊的實際語言轉錄，再用 Claude Agent 翻譯。
- **NEVER** 在完整轉錄時使用 Whisper 的 `language="auto"` 偵測
  WHY：中英夾雜內容易被誤判。語言偵測應在 Phase 2.1 用短片段單獨執行，完整轉錄時必須明確指定語言
- **NEVER** 在未確認使用者意圖前刪除中間檔案（audio_raw、whisper_raw.json）
  WHY：中間檔案是除錯和重新處理的依據
- **NEVER** 自動將摘要品質等同於逐字稿品質
  WHY：垃圾進垃圾出——如果逐字稿品質差，應先警告使用者再決定是否繼續摘要
- **NEVER** 使用專案目錄的 `.venv` 或系統 `python3` 來執行 Whisper
  WHY：依賴安裝在 `~/.claude/.venv`，使用其他 Python 環境會找不到 mlx_whisper 或 opencc 套件

---

## 思維指引

在執行各 Phase 前，用以下問題引導判斷：

### 開始前
- 這段音訊多長？超過 3 小時需要分段處理
- 是否有特殊領域術語？需要調整 initial_prompt
- 使用者是要完整逐字稿還是只要摘要？

### Phase 2 完成後（轉錄品質判斷）
- 逐字稿的辨識品質如何？是否有大量亂碼或重複文字？
- 如果品質明顯不佳（>20% 為亂碼），應警告使用者：「逐字稿品質偏低，建議檢查原始音訊品質後再進行摘要」
- 中英混用比例高嗎？若英文術語辨識差，建議在 initial_prompt 加入預期的英文詞彙

### Phase 3（摘要生成判斷）
- 範本 section 是否都有足夠的逐字稿資訊支撐？若某個 required section 資訊不足，寧可標註「逐字稿中未明確提及」也不要虛構
- 逐字稿夠長嗎？超短逐字稿（<200 字）可能不適合複雜範本
- 摘要應可獨立閱讀，不依賴逐字稿原文——讀者沒看過逐字稿也能理解
