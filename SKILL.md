---
name: media-to-text
description: >
  媒體轉文字完整工作流程。將影片 URL、本地影片或音訊檔轉換為精準的繁體中文逐字稿，
  並根據場景範本自動生成結構化摘要，可選發布至 Notion 或 NotebookLM。
  觸發詞：media-to-text、轉逐字稿、影片轉文字、音訊轉文字、會議記錄、
  YouTube 影片摘要、podcast 摘要、講座筆記、面試記錄、影音內容整理、
  錄音轉文字、語音辨識、video to text、audio transcription、
  meeting notes、逐字稿產生、字幕產生、錄影轉文字、音檔轉文字、
  播客筆記、訪談記錄、客戶訪談摘要、腦力激盪記錄、一對一會議記錄。
---

# Media to Text Workflow

將任何影片或音訊來源轉換為高品質繁體中文逐字稿與結構化摘要。

## 觸發條件

當使用者提到以下任一情境時啟動：
- 輸入 `/media-to-text`
- 提到「轉逐字稿」「影片轉文字」「音訊轉文字」「會議記錄」「YouTube 摘要」等關鍵詞
- 提供影片 URL 或音訊檔案路徑並要求轉錄或摘要

## 使用方式

```
/media-to-text <input> [--template auto|meeting|interview|lecture|brainstorm|client|podcast|one_on_one|general] [--publish local|notion|notebooklm|all] [--output-dir ./output]
```

### 範例

```bash
/media-to-text https://youtube.com/watch?v=xxx
/media-to-text ~/recordings/meeting.m4a --template meeting --publish notion
/media-to-text ~/Videos/lecture.mp4 --template lecture
```

### 參數

| 參數 | 預設 | 說明 |
|------|------|------|
| `input` | （必填） | YouTube URL、本地影片路徑、或本地音訊路徑 |
| `--template` | `auto` | 摘要範本，auto 自動偵測 |
| `--publish` | `local` | 發布目標：local / notion / notebooklm / all |
| `--output-dir` | `./output` | 本地輸出目錄 |

---

## 依賴工具

| 工具 | 用途 | 安裝方式 |
|------|------|---------|
| `yt-dlp` | 下載影片音訊 | `brew install yt-dlp` |
| `ffmpeg` | 音訊格式轉換 | `brew install ffmpeg` |
| `mlx-whisper` | 語音辨識（Apple Silicon 優化） | `pip install mlx-whisper` |
| `opencc-python-reimplemented` | 簡繁轉換（台灣用語） | `pip install opencc-python-reimplemented` |

### 快速安裝

```bash
bash {skill_dir}/install.sh
```

或手動安裝：

```bash
brew install yt-dlp ffmpeg
python3 -m venv .venv && source .venv/bin/activate
pip install mlx-whisper opencc-python-reimplemented
```

---

## 前置檢查

在開始前，用 Bash 工具執行以下檢查：

```bash
# 依賴檢查
echo "=== 依賴檢查 ==="
command -v yt-dlp   && echo "✅ yt-dlp"   || echo "❌ yt-dlp 缺失 → brew install yt-dlp"
command -v ffmpeg   && echo "✅ ffmpeg"    || echo "❌ ffmpeg 缺失 → brew install ffmpeg"

# Python 偵測（優先順序：$VIRTUAL_ENV → .venv/ → 系統 python3）
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    PYTHON="${VIRTUAL_ENV}/bin/python"
elif [[ -x ".venv/bin/python" ]]; then
    PYTHON=".venv/bin/python"
else
    PYTHON="python3"
fi
"$PYTHON" -c "import mlx_whisper" 2>/dev/null && echo "✅ mlx-whisper" || echo "❌ mlx-whisper → pip install mlx-whisper"
"$PYTHON" -c "import opencc"      2>/dev/null && echo "✅ opencc"      || echo "❌ opencc → pip install opencc-python-reimplemented"
```

若任何依賴缺失，告知使用者安裝指令後停止。

---

## 執行模式

提供兩種模式，優先使用一鍵模式：

### 一鍵模式（推薦）

Phase 1+2 用腳本一次完成擷取與轉錄，接著 Claude 執行 Phase 3-5：

```bash
bash {skill_dir}/scripts/media-to-text.sh "<input>" "./output"
```

腳本完成後 `./output/` 會包含 `transcript.md`、`transcript.txt`、`whisper_raw.json`，直接跳到 **Phase 3**。

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

## Phase 2：Whisper 轉錄

**目標**：產生 `transcript.md`、`transcript.txt`、`whisper_raw.json`。

用 Bash 工具執行以下 Python 腳本（使用前置檢查偵測到的 `$PYTHON`）：

```bash
# Python 偵測（與前置檢查相同邏輯）
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    PYTHON="${VIRTUAL_ENV}/bin/python"
elif [[ -x ".venv/bin/python" ]]; then
    PYTHON=".venv/bin/python"
else
    PYTHON="python3"
fi

"$PYTHON" - "$OUTPUT_DIR/audio.wav" "$OUTPUT_DIR" <<'PYEOF'
import sys, json
import mlx_whisper
import opencc

audio_path = sys.argv[1]
output_dir = sys.argv[2]

# ── Whisper 轉錄 ──
result = mlx_whisper.transcribe(
    audio_path,
    path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
    language="zh",
    initial_prompt="以下是繁體中文的錄音，可能包含英文術語。",
    condition_on_previous_text=False,  # 防止幻覺：避免前段錯誤累積到後段
    word_timestamps=True,
    verbose=False,
)

# ── OpenCC 簡轉繁（台灣用語）──
cc = opencc.OpenCC("s2twp")  # s2twp = 簡體→繁體（台灣慣用詞）

segments = result.get("segments", [])
full_text = cc.convert(result.get("text", ""))

def fmt_time(seconds: float) -> str:
    h, rem = divmod(int(seconds), 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"

# ── 輸出 transcript.md（含時間戳）──
with open(f"{output_dir}/transcript.md", "w", encoding="utf-8") as f:
    f.write("# 逐字稿\n\n")
    for seg in segments:
        text = cc.convert(seg["text"].strip())
        if text:
            f.write(f"**[{fmt_time(seg['start'])}]** {text}\n\n")

# ── 輸出 transcript.txt（純文字）──
with open(f"{output_dir}/transcript.txt", "w", encoding="utf-8") as f:
    f.write(full_text.strip() + "\n")

# ── 輸出 whisper_raw.json（完整資料）──
result["text"] = full_text
for seg in segments:
    seg["text"] = cc.convert(seg["text"])
with open(f"{output_dir}/whisper_raw.json", "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f"segments={len(segments)} chars={len(full_text)}")
PYEOF
```

### 關鍵參數說明

| 參數 | 值 | 原因 |
|------|-----|------|
| `path_or_hf_repo` | `mlx-community/whisper-large-v3-turbo` | Apple Silicon 優化，速度與品質兼顧 |
| `language` | `"zh"` | 強制中文辨識，避免語言偵測錯誤 |
| `condition_on_previous_text` | `False` | **防止幻覺**：不讓前段轉錄錯誤影響後段 |
| `initial_prompt` | 繁體中文提示 | 引導模型偏好繁體中文與英文術語 |
| `word_timestamps` | `True` | 提供精確到字詞的時間戳 |
| OpenCC `s2twp` | 簡→繁（台灣慣用詞） | 如「記憶體」而非「內存」，「程式」而非「程序」 |

### 報告

```
✅ Phase 2 完成：語音轉錄
   字數：{char_count}
   段落：{segment_count}
   輸出：transcript.md, transcript.txt, whisper_raw.json
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

讀取完整的 `transcript.txt` 作為上下文，以範本 YAML 中的 `system_prompt` 設定角色，逐 section 生成摘要內容。

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
- 字數：{char_count}
- 段落：{segment_count}
- 引擎：MLX Whisper large-v3-turbo

### 📋 摘要
- 範本：{template_icon} {template_name}
- 段落數：{section_count}

### 📁 輸出檔案
| 檔案 | 說明 |
|------|------|
| `transcript.md` | 含時間戳的逐字稿 |
| `transcript.txt` | 純文字逐字稿 |
| `whisper_raw.json` | Whisper 原始輸出 |
| `summary.md` | 結構化摘要 |

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

- **永遠使用繁體中文**（台灣用語）
- **每個 Phase 完成後報告進度**
- **關鍵決策讓使用者確認**：範本選擇、發布目標
- **本地檔案永遠保存**，雲端發布為可選
- **失敗時不影響已完成的步驟產出**：Phase 2 失敗不會刪除 Phase 1 的音訊檔
- **不調度外部 agent**：所有步驟在此 skill 內直接用 Bash/Read/Write/MCP 工具完成

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
- **NEVER** 使用 Whisper 的 `language="auto"` 偵測
  WHY：中英夾雜內容易被誤判為英文，導致整段中文被辨識為亂碼
- **NEVER** 在未確認使用者意圖前刪除中間檔案（audio_raw、whisper_raw.json）
  WHY：中間檔案是除錯和重新處理的依據
- **NEVER** 自動將摘要品質等同於逐字稿品質
  WHY：垃圾進垃圾出——如果逐字稿品質差，應先警告使用者再決定是否繼續摘要

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
