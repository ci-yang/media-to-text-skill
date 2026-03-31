#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="$HOME/.claude/.venv"

echo "📦 Installing Media-to-Text dependencies..."
echo ""

# Check platform
if [[ "$(uname)" != "Darwin" ]]; then
    echo "⚠️  Warning: MLX Whisper requires macOS with Apple Silicon."
    echo "   This tool may not work on your platform."
    echo ""
fi

# Create venv in ~/.claude/.venv if not exists
# WHY: Global location so the skill works from any project directory
if [[ ! -d "$VENV_DIR" ]]; then
    echo "🔧 Creating Python virtual environment at ${VENV_DIR}..."
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
    echo "✅ Created ${VENV_DIR}/"
else
    echo "✅ ${VENV_DIR}/ already exists"
fi

# Install Python dependencies
echo ""
echo "📥 Installing Python packages..."
"${VENV_DIR}/bin/pip" install --upgrade pip -q
"${VENV_DIR}/bin/pip" install mlx-whisper opencc-python-reimplemented -q
echo "✅ Python packages installed"

# Check system dependencies
echo ""
echo "🔍 Checking system dependencies..."
command -v yt-dlp  >/dev/null 2>&1 && echo "✅ yt-dlp: $(command -v yt-dlp)"   || echo "❌ yt-dlp not found → brew install yt-dlp"
command -v ffmpeg  >/dev/null 2>&1 && echo "✅ ffmpeg: $(command -v ffmpeg)"    || echo "❌ ffmpeg not found → brew install ffmpeg"

# Verify
echo ""
echo "🔍 Verifying installation..."
"${VENV_DIR}/bin/python" -c "import mlx_whisper; print('✅ mlx-whisper')" 2>/dev/null || echo "❌ mlx-whisper import failed"
"${VENV_DIR}/bin/python" -c "import opencc; print('✅ opencc')" 2>/dev/null || echo "❌ opencc import failed"

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Python venv: ${VENV_DIR}/"
echo "Whisper model will be auto-downloaded on first run to ~/.cache/huggingface/hub/"
echo ""
echo "Usage:"
echo "  bash scripts/media-to-text.sh <video-url-or-audio-path>"
