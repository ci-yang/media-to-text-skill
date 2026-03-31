"""Whisper transcription abstraction layer.

Auto-detects backend:
  - macOS Apple Silicon → mlx-whisper (Metal GPU)
  - Linux / other       → faster-whisper (CUDA or CPU)

Outputs unified JSON format compatible with both backends.

Usage:
    python transcribe.py <audio_path> <output_json> [--language zh] [--initial-prompt "..."]
"""

import argparse
import json
import platform
import sys
from typing import Any


def detect_backend() -> str:
    """Detect which Whisper backend is available."""
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        try:
            import mlx_whisper  # noqa: F401
            return "mlx"
        except ImportError:
            pass
    try:
        import faster_whisper  # noqa: F401
        return "faster"
    except ImportError:
        pass
    # Fallback: try mlx even on non-ARM Mac
    try:
        import mlx_whisper  # noqa: F401
        return "mlx"
    except ImportError:
        pass
    print("❌ No Whisper backend found. Install one of:", file=sys.stderr)
    print("   macOS Apple Silicon: pip install mlx-whisper", file=sys.stderr)
    print("   Linux (CUDA):       pip install faster-whisper", file=sys.stderr)
    sys.exit(1)


def transcribe_mlx(
    audio_path: str,
    language: str,
    initial_prompt: str,
) -> dict[str, Any]:
    """Transcribe using mlx-whisper (Apple Silicon)."""
    import mlx_whisper

    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
        language=language,
        initial_prompt=initial_prompt,
        condition_on_previous_text=False,
        word_timestamps=True,
        verbose=False,
    )
    return result


def transcribe_faster(
    audio_path: str,
    language: str,
    initial_prompt: str,
) -> dict[str, Any]:
    """Transcribe using faster-whisper (CUDA / CPU)."""
    from faster_whisper import WhisperModel

    # Auto-detect device: CUDA if available, otherwise CPU
    # faster-whisper uses ctranslate2 which handles CUDA directly
    device = "auto"
    compute_type = "default"
    try:
        import ctranslate2
        if "cuda" in ctranslate2.get_supported_compute_types("cuda"):
            device = "cuda"
            compute_type = "float16"
    except (ImportError, RuntimeError):
        device = "cpu"
        compute_type = "int8"
    print(f"Device: {device} ({compute_type})", file=sys.stderr)

    model = WhisperModel(
        "large-v3-turbo",
        device=device,
        compute_type=compute_type,
    )

    segments_gen, info = model.transcribe(
        audio_path,
        language=language,
        initial_prompt=initial_prompt,
        condition_on_previous_text=False,
        word_timestamps=True,
        vad_filter=True,
    )

    # Convert to mlx-whisper compatible dict format
    segments = []
    full_text_parts = []
    for seg in segments_gen:
        seg_dict: dict[str, Any] = {
            "id": len(segments),
            "start": seg.start,
            "end": seg.end,
            "text": seg.text,
        }
        if seg.words:
            seg_dict["words"] = [
                {
                    "word": w.word,
                    "start": w.start,
                    "end": w.end,
                    "probability": w.probability,
                }
                for w in seg.words
            ]
        segments.append(seg_dict)
        full_text_parts.append(seg.text)

    return {
        "text": "".join(full_text_parts),
        "segments": segments,
        "language": info.language,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Whisper transcription (cross-platform)")
    parser.add_argument("audio_path", help="Path to 16kHz mono WAV audio")
    parser.add_argument("output_json", help="Output path for whisper_raw.json")
    parser.add_argument("--language", default="zh", help="Audio language code (default: zh)")
    parser.add_argument(
        "--initial-prompt",
        default="以下是繁體中文的錄音，可能包含英文術語。",
        help="Initial prompt for Whisper",
    )
    args = parser.parse_args()

    backend = detect_backend()
    print(f"Backend: {backend}", file=sys.stderr)

    if backend == "mlx":
        result = transcribe_mlx(args.audio_path, args.language, args.initial_prompt)
    else:
        result = transcribe_faster(args.audio_path, args.language, args.initial_prompt)

    # Save result
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    # Print stats
    segments = result.get("segments", [])
    full_text = result.get("text", "")
    print(f"segments={len(segments)} chars={len(full_text)}", file=sys.stderr)


if __name__ == "__main__":
    main()
