#!/usr/bin/env bash
# media-to-text.sh - 媒體轉文字一鍵腳本（跨平台：macOS Apple Silicon + Linux）
# 用法: ./media-to-text.sh <input> [output_dir]
#   input: YouTube URL 或本地影片/音訊路徑
#   output_dir: 輸出目錄（預設 ./output/{date}_{title}）

set -euo pipefail

# ── 路徑設定 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATE_TAG="$(date +%Y-%m-%d)"

# Python 環境：固定使用 ~/.claude/.venv
# WHY: 此 skill 可在任何專案目錄下觸發，使用全域 venv 避免重複安裝
VENV_DIR="$HOME/.claude/.venv"
PYTHON="${VENV_DIR}/bin/python"

# ── 輔助函式 ──────────────────────────────────────────────
info()  { echo "   $*"; }
step()  { echo ""; echo "$*"; }
ok()    { echo "✅ $*"; }
fail()  { echo "❌ $*" >&2; exit 1; }

usage() {
    echo "用法: $0 <input> [output_dir]"
    echo "  input:      YouTube URL 或本地影片/音訊路徑"
    echo "  output_dir: 輸出目錄（預設 ./output/{date}_{title}）"
    exit 1
}

# 取得音訊時長（秒 → MM:SS）
get_duration() {
    local file="$1"
    local seconds
    seconds="$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$file" | cut -d. -f1)"
    if [[ -z "$seconds" || "$seconds" == "N/A" ]]; then
        echo "未知"
        return
    fi
    printf "%d:%02d" $((seconds / 60)) $((seconds % 60))
}

# ── 參數檢查 ──────────────────────────────────────────────
[[ $# -lt 1 ]] && usage
INPUT="$1"
OUTPUT_DIR="${2:-}"

# ── 1. 依賴檢查 ───────────────────────────────────────────
step "🔍 檢查依賴..."

# 平台偵測
OS="$(uname -s)"
ARCH="$(uname -m)"
if [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
    PLATFORM="macos-arm64"
elif [[ "$OS" == "Linux" ]]; then
    PLATFORM="linux"
else
    PLATFORM="other"
fi
ok "平台: ${PLATFORM} (${OS} ${ARCH})"

YTDLP="$(command -v yt-dlp 2>/dev/null || true)"
FFMPEG="$(command -v ffmpeg 2>/dev/null || true)"

if [[ "$PLATFORM" == "linux" ]]; then
    [[ -n "$YTDLP" ]]  && ok "yt-dlp: ${YTDLP}"  || fail "找不到 yt-dlp，請執行: sudo apt install yt-dlp 或 pip install yt-dlp"
    [[ -n "$FFMPEG" ]]  && ok "ffmpeg: ${FFMPEG}"  || fail "找不到 ffmpeg，請執行: sudo apt install ffmpeg"
else
    [[ -n "$YTDLP" ]]  && ok "yt-dlp: ${YTDLP}"  || fail "找不到 yt-dlp，請執行: brew install yt-dlp"
    [[ -n "$FFMPEG" ]]  && ok "ffmpeg: ${FFMPEG}"  || fail "找不到 ffmpeg，請執行: brew install ffmpeg"
fi

[[ -d "$VENV_DIR" ]] && ok "Python venv: ${VENV_DIR}/" || fail "找不到 Python venv: ${VENV_DIR}，請先執行: bash ${REPO_DIR}/install.sh"
[[ -x "$PYTHON" ]]  || fail "找不到 Python 執行檔: ${PYTHON}"

# 檢查 Whisper 後端（依平台）
if [[ "$PLATFORM" == "macos-arm64" ]]; then
    "$PYTHON" -c "import mlx_whisper" 2>/dev/null && ok "mlx-whisper (Apple Silicon)" \
        || fail "缺少 mlx_whisper，請執行: ${VENV_DIR}/bin/pip install mlx-whisper"
else
    "$PYTHON" -c "import faster_whisper" 2>/dev/null && ok "faster-whisper (CUDA/CPU)" \
        || fail "缺少 faster_whisper，請執行: ${VENV_DIR}/bin/pip install faster-whisper"
fi

"$PYTHON" -c "import opencc" 2>/dev/null && ok "opencc" \
    || fail "缺少 opencc，請執行: ${VENV_DIR}/bin/pip install opencc-python-reimplemented"

# ── 2. 輸入辨識與音訊取得 ─────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

AUDIO_RAW="${WORK_DIR}/audio_raw"
AUDIO_WAV="${WORK_DIR}/audio.wav"
TITLE=""

is_url() {
    [[ "$1" =~ ^https?:// ]]
}

is_video() {
    local ext="${1##*.}"
    ext="${ext,,}"
    [[ "$ext" =~ ^(mp4|mkv|avi|mov|webm|flv)$ ]]
}

is_audio() {
    local ext="${1##*.}"
    ext="${ext,,}"
    [[ "$ext" =~ ^(mp3|wav|m4a|flac|ogg|aac|aiff)$ ]]
}

if is_url "$INPUT"; then
    # ── YouTube / URL 下載 ──
    step "📥 下載影片音訊..."
    TITLE="$(yt-dlp --get-title "$INPUT" 2>/dev/null | head -1 || echo "untitled")"
    SAFE_TITLE="$(echo "$TITLE" | sed 's/[^a-zA-Z0-9._-]/_/g; s/__*/_/g; s/^_//; s/_$//' | cut -c1-80)"

    yt-dlp \
        -x --audio-format wav \
        --audio-quality 0 \
        -o "${AUDIO_RAW}.%(ext)s" \
        "$INPUT" \
        || fail "yt-dlp 下載失敗，請確認 URL 是否正確"

    AUDIO_RAW_FILE="$(ls "${AUDIO_RAW}"* 2>/dev/null | head -1)"
    [[ -f "$AUDIO_RAW_FILE" ]] || fail "找不到下載的音訊檔案"
    ok "音訊下載完成: $(basename "$AUDIO_RAW_FILE")"

elif is_video "$INPUT"; then
    [[ -f "$INPUT" ]] || fail "找不到檔案: ${INPUT}"
    step "📥 擷取影片音訊..."
    TITLE="$(basename "${INPUT%.*}")"
    SAFE_TITLE="$(echo "$TITLE" | sed 's/[^a-zA-Z0-9._-]/_/g; s/__*/_/g; s/^_//; s/_$//' | cut -c1-80)"
    AUDIO_RAW_FILE="${AUDIO_RAW}.wav"

    ffmpeg -y -i "$INPUT" -vn -acodec pcm_s16le "${AUDIO_RAW_FILE}" \
        -loglevel warning \
        || fail "ffmpeg 擷取音訊失敗"
    ok "音訊擷取完成: $(basename "$AUDIO_RAW_FILE")"

elif is_audio "$INPUT"; then
    [[ -f "$INPUT" ]] || fail "找不到檔案: ${INPUT}"
    step "📥 讀取音訊檔案..."
    TITLE="$(basename "${INPUT%.*}")"
    SAFE_TITLE="$(echo "$TITLE" | sed 's/[^a-zA-Z0-9._-]/_/g; s/__*/_/g; s/^_//; s/_$//' | cut -c1-80)"
    AUDIO_RAW_FILE="$INPUT"
    ok "音訊檔案: $(basename "$AUDIO_RAW_FILE")"

else
    fail "無法辨識輸入格式: ${INPUT}
  支援：YouTube URL / 影片 (mp4,mkv,avi,mov,webm,flv) / 音訊 (mp3,wav,m4a,flac,ogg,aac,aiff)"
fi

# ── 3. 音訊轉換（16kHz mono WAV）─────────────────────────
step "🔄 轉換音訊格式..."

ffmpeg -y -i "$AUDIO_RAW_FILE" \
    -ar 16000 -ac 1 -c:a pcm_s16le \
    "$AUDIO_WAV" \
    -loglevel warning \
    || fail "ffmpeg 音訊轉換失敗"

DURATION="$(get_duration "$AUDIO_WAV")"
ok "音訊處理完成: audio.wav (16kHz mono)"
info "時長: ${DURATION}"

# ── 4. 決定輸出目錄 ───────────────────────────────────────
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./output/${DATE_TAG}_${SAFE_TITLE}"
fi
mkdir -p "$OUTPUT_DIR"

# ── 5. Whisper 轉錄（跨平台）─────────────────────────────
step "🎙️ Whisper 轉錄中..."

WHISPER_JSON="${OUTPUT_DIR}/whisper_raw.json"

"$PYTHON" "${SCRIPT_DIR}/transcribe.py" \
    "$AUDIO_WAV" "$WHISPER_JSON" \
    --language zh \
    --initial-prompt "以下是繁體中文的錄音，可能包含英文術語。"

# 讀取統計
SEGMENTS="$(grep -c '"id"' "$WHISPER_JSON" 2>/dev/null || echo "?")"
CHAR_COUNT="$("$PYTHON" -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(len(d.get('text', '')))
" "$WHISPER_JSON" 2>/dev/null || echo "?")"

ok "轉錄完成！"
info "segments: ${SEGMENTS}"
info "字數: ${CHAR_COUNT}"

# ── 6. OpenCC 簡繁轉換 + 輸出格式化 ──────────────────────
step "📝 產生輸出檔案..."

TRANSCRIPT_MD="${OUTPUT_DIR}/transcript.md"
TRANSCRIPT_TXT="${OUTPUT_DIR}/transcript.txt"

"$PYTHON" - "$WHISPER_JSON" "$TRANSCRIPT_MD" "$TRANSCRIPT_TXT" "$TITLE" <<'PYEOF'
import sys
import json
import opencc

whisper_path = sys.argv[1]
md_path = sys.argv[2]
txt_path = sys.argv[3]
title = sys.argv[4]

converter = opencc.OpenCC("s2twp")

with open(whisper_path, "r", encoding="utf-8") as f:
    data = json.load(f)

segments = data.get("segments", [])
full_text = converter.convert(data.get("text", ""))


def fmt_time(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


# ── transcript.md（含時間戳）──
with open(md_path, "w", encoding="utf-8") as f:
    f.write(f"# {title}\n\n")
    for seg in segments:
        start = fmt_time(seg["start"])
        text = converter.convert(seg["text"].strip())
        if text:
            f.write(f"**[{start}]** {text}\n\n")

# ── transcript.txt（純文字）──
with open(txt_path, "w", encoding="utf-8") as f:
    f.write(full_text.strip() + "\n")

# 回寫轉換後的 JSON（更新 text 為繁體）
data["text"] = full_text
for seg in segments:
    seg["text"] = converter.convert(seg["text"])
with open(whisper_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF

ok "transcript.md (含時間戳)"
ok "transcript.txt (純文字)"
ok "whisper_raw.json (原始資料)"

# ── 7. 完成 ───────────────────────────────────────────────
step "🎉 完成！輸出目錄: ${OUTPUT_DIR}/"
echo ""
ls -lh "${OUTPUT_DIR}/"
