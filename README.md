<div align="center">

# 🎙️ Media-to-Text Skill

**Convert any video or audio into accurate transcripts + structured summaries**

*Powered by MLX Whisper on Apple Silicon — fast, free, local. Multi-language with bilingual output.*

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20Apple%20Silicon-000000?logo=apple&logoColor=white)](https://support.apple.com/en-us/116943)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-7C3AED?logo=anthropic&logoColor=white)](https://claude.ai/claude-code)
[![MLX](https://img.shields.io/badge/MLX-Whisper-FF6F00?logo=apple&logoColor=white)](https://github.com/ml-explore/mlx-examples)
[![OpenCC](https://img.shields.io/badge/OpenCC-s2twp-E34F26)](https://github.com/BYVoid/OpenCC)

[繁體中文說明](./README-zh-TW.md)

<img src="./docs/workflow-flow-en.png" alt="Workflow" width="700" />

</div>

---

## ✨ Features

| | Feature | Description |
|---|---------|-------------|
| 🎬 | **Multi-source input** | YouTube URLs, local video (mp4/mkv/avi/mov), local audio (mp3/m4a/wav/flac) |
| ⚡ | **Local GPU transcription** | MLX Whisper large-v3-turbo on Apple Silicon (~20x realtime on M4 Pro) |
| 🌐 | **Multi-language support** | Auto-detect audio language, transcribe in native language |
| 🔄 | **Bilingual output** | Original transcript + Traditional Chinese translation (via Claude Agent) |
| 🇹🇼 | **Traditional Chinese optimized** | OpenCC s2twp with Taiwan-specific terminology |
| 📋 | **8 scene templates** | Auto-detect or manually select — meeting, interview, lecture, brainstorm, client, podcast, 1-on-1, general |
| 🤖 | **Claude Code Skill** | Full integration with `/media-to-text` command |
| 📤 | **Optional publishing** | Notion database + NotebookLM notebook via MCP |

## 📦 Requirements

- macOS with Apple Silicon (M1/M2/M3/M4)
- 16GB RAM minimum (24GB+ recommended)
- Python 3.10+
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org/)

## 🚀 Quick Start

### Installation

```bash
git clone https://github.com/ci-yang/media-to-text-skill.git
cd media-to-text-skill
bash install.sh
```

> **Note:** Dependencies are installed to `~/.claude/.venv` (global venv) so the skill works from any project directory. The Whisper model (~1.5 GB) is cached at `~/.cache/huggingface/hub/`.

### As Claude Code Skill (Recommended)

Copy into your project's skill directory:

```bash
cp -r media-to-text-skill /path/to/your-project/.claude/skills/media-to-text
```

Then in Claude Code:

```
/media-to-text https://youtube.com/watch?v=xxx
/media-to-text ~/recordings/meeting.m4a --template meeting
/media-to-text https://youtube.com/watch?v=xxx --bilingual
/media-to-text ~/Videos/lecture.mp4 --lang en --bilingual --template lecture
```

### As Standalone Script

```bash
bash scripts/media-to-text.sh https://youtube.com/watch?v=xxx
bash scripts/media-to-text.sh ~/meeting.m4a ./output/my-meeting
```

## 🌐 Multi-Language & Bilingual

### How It Works

1. **Auto-detect** — Whisper analyzes a 30-second sample to identify the audio language
2. **Native transcription** — Transcribe using the detected language (English audio → English transcript)
3. **Optional translation** — Claude Agent translates to Traditional Chinese (much better quality than Whisper cross-language)

### Examples

| Input | `--bilingual` | Output |
|-------|:------------:|--------|
| Chinese audio | No | `transcript.md` (Traditional Chinese) |
| English audio | No | `transcript_en.md` (English only) |
| English audio | Yes | `transcript_en.md` + `transcript.md` (Chinese translation) |
| Japanese audio | Yes | `transcript_ja.md` + `transcript.md` (Chinese translation) |

### Why Not Cross-Language Whisper?

Setting `language="zh"` on English audio produces garbage output. The correct approach: transcribe in the native language, then translate with Claude Agent.

## 📑 Templates

| Template | Name | Use Case |
|:--------:|------|----------|
| `general` | 📝 General Summary | Default when type is unclear |
| `meeting` | 📋 Meeting Notes | Team meetings, standups |
| `interview` | 🎯 Interview Summary | Job interviews, evaluations |
| `lecture` | 🎓 Lecture Notes | Talks, classes, tutorials |
| `brainstorm` | 💡 Brainstorm | Creative sessions, ideation |
| `client` | 🤝 Client Visit | Sales calls, requirements |
| `podcast` | 🎙️ Podcast/Interview | Shows, discussions |
| `one_on_one` | 👥 One-on-One | Manager 1:1s, check-ins |

## 🏗️ Architecture

<div align="center">
<img src="./docs/skill-architecture-en.png" alt="Architecture" width="700" />
</div>

### How It Works

```
📥 Input          🔄 Process              📄 Output          📤 Publish
─────────        ──────────────          ─────────          ─────────
YouTube URL  ──→  yt-dlp extract    ──→  transcript.md  ──→  Notion
Local video  ──→  ffmpeg → 16kHz WAV ─→  transcript.txt     NotebookLM
Local audio  ──→  MLX Whisper GPU   ──→  whisper_raw.json
                  Language detect   ──→  transcript_{lang}.*
                  OpenCC s2twp      ──→  summary.md
                  Claude Agent      ──→  (bilingual translation)
                  Claude + Template
```

### 🧠 Whisper Model

| | Detail |
|---|--------|
| **Model** | [`mlx-community/whisper-large-v3-turbo`](https://huggingface.co/mlx-community/whisper-large-v3-turbo) |
| **Size** | ~1.5 GB |
| **Framework** | [MLX](https://github.com/ml-explore/mlx) — Apple's ML framework for Apple Silicon |
| **Storage** | `~/.cache/huggingface/hub/` (auto-downloaded on first run) |
| **Cost** | **Free** — runs entirely on local GPU, no API key needed |
| **Speed** | ~20x realtime on M4 Pro (1 hour audio ≈ 3 min) |

> **First run note:** The model (~1.5 GB) will be automatically downloaded from Hugging Face on first use. Subsequent runs use the cached version instantly.

<details>
<summary><b>Alternative models</b></summary>

You can switch models by editing `scripts/media-to-text.sh`:

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| `whisper-large-v3-turbo` | 1.5 GB | ⚡ Fast | ✅ High | **Default — best balance** |
| `whisper-large-v3` | 3.1 GB | 🐢 Slower | ✅✅ Highest | Maximum accuracy needed |
| `whisper-base` | 142 MB | ⚡⚡ Fastest | ⚠️ Lower | Low RAM / quick draft |

</details>

### Key Parameters

| Parameter | Value | Why |
|-----------|:-----:|-----|
| `language` | detected / specified | Must match actual audio language — cross-language is forbidden |
| `condition_on_previous_text` | `False` | **Prevent hallucination** — stops error accumulation |
| `initial_prompt` | language-adapted | Guide model toward correct language output |
| OpenCC profile | `s2twp` | Simplified → Traditional with Taiwan vocabulary (Chinese only) |

### 🔧 Python Environment

| | Path |
|---|------|
| **Virtual environment** | `~/.claude/.venv/` |
| **Python binary** | `~/.claude/.venv/bin/python` |
| **Whisper model cache** | `~/.cache/huggingface/hub/` |

> The global venv at `~/.claude/.venv` is used so the skill works from any project directory without per-project installation.

## 📂 Output

Each run produces in `./output/{date}_{title}/`:

```
output/2026-03-16_my-meeting/
├── transcript.md        # Timestamped transcript (Traditional Chinese)
├── transcript.txt       # Plain text (for LLM summarization)
├── transcript_{lang}.md # Original language transcript (if non-Chinese)
├── transcript_{lang}.txt# Original language plain text (if non-Chinese)
├── whisper_raw.json     # Raw Whisper output
├── summary.md           # Structured summary (Traditional Chinese)
└── summary_{lang}.md    # Original language summary (if bilingual)
```

## 🔧 Troubleshooting

<details>
<summary><b>Common Issues</b></summary>

| Problem | Solution |
|---------|----------|
| yt-dlp 403 Forbidden | `brew upgrade yt-dlp` (version too old) |
| Whisper out of memory | Use smaller model: change to `whisper-base` |
| pip install fails (PEP 668) | Uses venv at `~/.claude/.venv` — run `bash install.sh` |
| Simplified Chinese in output | Ensure OpenCC installed with `s2twp` profile |
| Repeated/hallucinated text | Verify `condition_on_previous_text=False` |
| Python/mlx_whisper not found | Check `~/.claude/.venv/bin/python` exists — run `bash install.sh` |
| English audio gives garbage Chinese | Never use `language="zh"` on non-Chinese audio — use `--bilingual` instead |

</details>

## 📄 License

[MIT](./LICENSE) — free for personal and commercial use.

---

<div align="center">

Made with ❤️ for the Traditional Chinese community

**[Report Bug](https://github.com/ci-yang/media-to-text-skill/issues)** · **[Request Feature](https://github.com/ci-yang/media-to-text-skill/issues)**

</div>
