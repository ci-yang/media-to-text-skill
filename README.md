<div align="center">

# 🎙️ Media-to-Text Skill

**Convert any video or audio into accurate Traditional Chinese transcripts + structured summaries**

*Powered by MLX Whisper on Apple Silicon — fast, free, local.*

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

### As Claude Code Skill (Recommended)

Copy into your project's skill directory:

```bash
cp -r media-to-text-skill /path/to/your-project/.claude/skills/media-to-text
```

Then in Claude Code:

```
/media-to-text https://youtube.com/watch?v=xxx
/media-to-text ~/recordings/meeting.m4a --template meeting
```

### As Standalone Script

```bash
source .venv/bin/activate
bash scripts/media-to-text.sh https://youtube.com/watch?v=xxx
bash scripts/media-to-text.sh ~/meeting.m4a ./output/my-meeting
```

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
                  OpenCC s2twp      ──→  summary.md
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
| `language` | `"zh"` | Force Chinese recognition, prevent misdetection |
| `condition_on_previous_text` | `False` | **Prevent hallucination** — stops error accumulation |
| `initial_prompt` | TW Chinese hint | Guide model toward Traditional Chinese + English terms |
| OpenCC profile | `s2twp` | Simplified → Traditional with Taiwan vocabulary |

## 📂 Output

Each run produces in `./output/{date}_{title}/`:

```
output/2026-03-16_my-meeting/
├── transcript.md        # Timestamped transcript
├── transcript.txt       # Plain text (for LLM summarization)
├── whisper_raw.json     # Raw Whisper output
└── summary.md           # Structured summary
```

## 🔧 Troubleshooting

<details>
<summary><b>Common Issues</b></summary>

| Problem | Solution |
|---------|----------|
| yt-dlp 403 Forbidden | `brew upgrade yt-dlp` (version too old) |
| Whisper out of memory | Use smaller model: change to `whisper-base` |
| pip install fails (PEP 668) | Use venv: `python3 -m venv .venv` |
| Simplified Chinese in output | Ensure OpenCC installed with `s2twp` profile |
| Repeated/hallucinated text | Verify `condition_on_previous_text=False` |

</details>

## 📄 License

[MIT](./LICENSE) — free for personal and commercial use.

---

<div align="center">

Made with ❤️ for the Traditional Chinese community

**[Report Bug](https://github.com/ci-yang/media-to-text-skill/issues)** · **[Request Feature](https://github.com/ci-yang/media-to-text-skill/issues)**

</div>
