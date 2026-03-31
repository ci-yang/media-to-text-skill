#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="$HOME/.claude/.venv"

echo "📦 Installing Media-to-Text dependencies..."
echo ""

# ── 平台偵測 ──────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
    PLATFORM="macos-arm64"
    echo "🖥️  Platform: macOS Apple Silicon (MLX backend)"
elif [[ "$OS" == "Linux" ]]; then
    PLATFORM="linux"
    echo "🐧 Platform: Linux (faster-whisper backend)"
else
    PLATFORM="other"
    echo "⚠️  Platform: ${OS} ${ARCH} (faster-whisper backend, CPU mode)"
fi
echo ""

# ── 建立全域 venv ─────────────────────────────────────────
if [[ ! -d "$VENV_DIR" ]]; then
    echo "🔧 Creating Python virtual environment at ${VENV_DIR}..."
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
    echo "✅ Created ${VENV_DIR}/"
else
    echo "✅ ${VENV_DIR}/ already exists"
fi

PIP="${VENV_DIR}/bin/pip"
PYTHON="${VENV_DIR}/bin/python"

"$PIP" install --upgrade pip -q

# ── 安裝 Whisper 後端（依平台）────────────────────────────
echo ""
echo "📥 Installing Whisper backend..."

if [[ "$PLATFORM" == "macos-arm64" ]]; then
    "$PIP" install mlx-whisper -q
    echo "✅ mlx-whisper (Apple Silicon GPU)"
else
    "$PIP" install faster-whisper -q
    echo "✅ faster-whisper (CUDA / CPU)"
    if [[ "$PLATFORM" == "linux" ]]; then
        # Check CUDA availability
        if "$PYTHON" -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
            echo "   🎮 CUDA detected — GPU acceleration enabled"
        else
            echo "   ⚠️  No CUDA detected — will use CPU mode (slower)"
            echo "   For GPU: install NVIDIA drivers + CUDA toolkit"
        fi
    fi
fi

# ── 共用依賴 ──────────────────────────────────────────────
echo ""
echo "📥 Installing common dependencies..."
"$PIP" install opencc-python-reimplemented -q
echo "✅ opencc-python-reimplemented"

# ── 系統依賴檢查 ──────────────────────────────────────────
echo ""
echo "🔍 Checking system dependencies..."

if [[ "$PLATFORM" == "linux" ]]; then
    command -v yt-dlp  >/dev/null 2>&1 && echo "✅ yt-dlp: $(command -v yt-dlp)"   || echo "❌ yt-dlp not found → sudo apt install yt-dlp 或 pip install yt-dlp"
    command -v ffmpeg  >/dev/null 2>&1 && echo "✅ ffmpeg: $(command -v ffmpeg)"    || echo "❌ ffmpeg not found → sudo apt install ffmpeg"
else
    command -v yt-dlp  >/dev/null 2>&1 && echo "✅ yt-dlp: $(command -v yt-dlp)"   || echo "❌ yt-dlp not found → brew install yt-dlp"
    command -v ffmpeg  >/dev/null 2>&1 && echo "✅ ffmpeg: $(command -v ffmpeg)"    || echo "❌ ffmpeg not found → brew install ffmpeg"
fi

# ── 驗證安裝 ──────────────────────────────────────────────
echo ""
echo "🔍 Verifying installation..."

if [[ "$PLATFORM" == "macos-arm64" ]]; then
    "$PYTHON" -c "import mlx_whisper; print('✅ mlx-whisper')" 2>/dev/null || echo "❌ mlx-whisper import failed"
else
    "$PYTHON" -c "import faster_whisper; print('✅ faster-whisper')" 2>/dev/null || echo "❌ faster-whisper import failed"
fi
"$PYTHON" -c "import opencc; print('✅ opencc')" 2>/dev/null || echo "❌ opencc import failed"

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Python venv: ${VENV_DIR}/"
echo "Whisper model will be auto-downloaded on first run to ~/.cache/huggingface/hub/"
echo ""
echo "Usage:"
echo "  bash scripts/media-to-text.sh <video-url-or-audio-path>"
