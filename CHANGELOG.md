# Changelog

## [1.2.0] - 2026-03-31

### Added
- **Linux support** via `faster-whisper` backend (CUDA GPU + CPU INT8 fallback)
- Cross-platform transcription abstraction layer: `scripts/transcribe.py`
  - macOS Apple Silicon → mlx-whisper (Metal GPU)
  - Linux → faster-whisper (CUDA or CPU)
  - Auto-detects backend, outputs unified JSON format
- Platform detection in `install.sh` and `scripts/media-to-text.sh`

### Changed
- `install.sh` installs platform-appropriate Whisper backend automatically
- `scripts/media-to-text.sh` uses `transcribe.py` instead of inline mlx_whisper code
- Shell script dependency checks now show platform-specific install instructions

## [1.1.0] - 2026-03-31

### Added
- Multi-language auto-detection (Phase 2.1) — Whisper analyzes 30-second sample to identify audio language
- Bilingual output mode (`--bilingual`) — original transcript + Traditional Chinese translation
- `--lang` parameter to manually specify audio language
- Claude Agent translation for non-Chinese audio (much better than Whisper cross-language)
- Language-adapted `initial_prompt` for English, Japanese, and other languages
- Non-Chinese output files with language suffix (`transcript_en.md`, `summary_en.md`)
- Explicit Python environment documentation (`~/.claude/.venv`)

### Changed
- Python venv location: `~/.claude/.venv` (global) instead of project-local `.venv`
  - WHY: Skill can be triggered from any project directory; global venv avoids per-project installation
- `install.sh` now installs to `~/.claude/.venv`
- `scripts/media-to-text.sh` uses `~/.claude/.venv/bin/python` directly
- Phase 2 restructured: "Whisper Transcription" → "Language Detection & Transcription"
- Phase 5 report now includes language and mode information

### Fixed
- LLM frequently could not find `.venv` or Whisper model — now uses explicit absolute paths

## [1.0.0] - 2026-03-16

### Added
- Initial release
- MLX Whisper transcription with Apple Silicon optimization
- OpenCC s2twp Traditional Chinese conversion
- 8 scene templates (meeting, interview, lecture, brainstorm, client, podcast, one-on-one, general)
- Auto template detection via keyword matching
- One-click shell script for extract + transcribe
- Claude Code Skill integration
- Optional publishing to Notion and NotebookLM
