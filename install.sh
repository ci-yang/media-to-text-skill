#!/usr/bin/env bash
set -euo pipefail

echo "📦 Installing Media-to-Text dependencies..."
echo ""

# Check platform
if [[ "$(uname)" != "Darwin" ]]; then
    echo "⚠️  Warning: MLX Whisper requires macOS with Apple Silicon."
    echo "   This tool may not work on your platform."
    echo ""
fi

# Create venv if not exists
if [[ ! -d ".venv" ]]; then
    echo "🔧 Creating Python virtual environment..."
    python3 -m venv .venv
    echo "✅ Created .venv/"
else
    echo "✅ .venv/ already exists"
fi

source .venv/bin/activate

# Install Python dependencies
echo ""
echo "📥 Installing Python packages..."
pip install --upgrade pip -q
pip install mlx-whisper opencc-python-reimplemented -q
echo "✅ Python packages installed"

# Check system dependencies
echo ""
echo "🔍 Checking system dependencies..."
command -v yt-dlp  >/dev/null 2>&1 && echo "✅ yt-dlp: $(command -v yt-dlp)"   || echo "❌ yt-dlp not found → brew install yt-dlp"
command -v ffmpeg  >/dev/null 2>&1 && echo "✅ ffmpeg: $(command -v ffmpeg)"    || echo "❌ ffmpeg not found → brew install ffmpeg"

# Verify
echo ""
echo "🔍 Verifying installation..."
.venv/bin/python -c "import mlx_whisper; print('✅ mlx-whisper')" 2>/dev/null || echo "❌ mlx-whisper import failed"
.venv/bin/python -c "import opencc; print('✅ opencc')" 2>/dev/null || echo "❌ opencc import failed"

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Usage:"
echo "  source .venv/bin/activate"
echo "  bash scripts/media-to-text.sh <video-url-or-audio-path>"
