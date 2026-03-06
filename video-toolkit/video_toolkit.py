#!/usr/bin/env python3
"""
Video Toolkit — Point d'entrée principal.

Usage non-interactif (depuis Lightroom) :
    python video_toolkit.py --mode probe --input video.mp4
    python video_toolkit.py --mode batch --batch-file batch.json --status-file status.json
    python video_toolkit.py --mode status --input video.mp4

Usage interactif (terminal) :
    python video_toolkit.py

Codes de sortie :
    0 = succès
    1 = erreur (message JSON sur stderr)
"""

import sys
import os

# Ajouter le répertoire du script au path
sys.path.insert(0, os.path.dirname(__file__))

from src.cli import build_parser, run_probe, run_process, run_batch, run_status, run_clean, InteractiveCLI
from src.config import Config


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    # Charger la configuration
    cfg = Config(args.config if hasattr(args, "config") and args.config else None)

    # Propager les overrides CLI → config (priorité sur le fichier de config)
    if getattr(args, "ffmpeg_path", None):
        cfg.set("ffmpeg_path", args.ffmpeg_path)
    if getattr(args, "exiftool_path", None):
        cfg.set("exiftool_path", args.exiftool_path)
    if getattr(args, "hwaccel", None):
        cfg.set("hardware_accel", args.hwaccel)

    # Rediriger stdout+stderr vers un fichier log si --log-file fourni
    _log_fh = None
    if getattr(args, "log_file", None):
        try:
            _log_fh = open(args.log_file, "w", encoding="utf-8", buffering=1)
            sys.stdout = _log_fh
            sys.stderr = _log_fh
        except OSError as e:
            # Pas bloquant — on continue sans log
            print(f"[VTK] Impossible d'ouvrir le log file: {e}", file=sys.__stderr__)

    # Mode non-interactif (avec --mode)
    if args.mode:
        if args.mode == "check":
            import json
            from pathlib import Path
            # Lire les chemins configurés depuis le fichier JSON passé par Lightroom
            explicit = {}
            check_cfg = getattr(args, "check_config", None)
            if check_cfg:
                try:
                    with open(check_cfg, "r", encoding="utf-8") as fh:
                        explicit = json.load(fh)
                except Exception:
                    pass

            tools_out = {}
            for tool in ["ffmpeg", "ffprobe", "exiftool"]:
                configured = explicit.get(tool)
                if configured:
                    # Chemin fourni explicitement : vérifier qu'il existe
                    if Path(configured).is_file():
                        tools_out[tool] = configured
                    else:
                        tools_out[tool] = f"not found at: {configured}"
                else:
                    # Auto-détection
                    found = cfg.resolve_tool(tool)
                    tools_out[tool] = found or "not found"

            # Detect GPU encoders
            from src.hwaccel import HWAccelDetector
            ffmpeg_resolved = tools_out.get("ffmpeg", "ffmpeg")
            if ffmpeg_resolved and not ffmpeg_resolved.startswith("not found"):
                detector = HWAccelDetector(ffmpeg_resolved)
                gpu_list = [{"name": e.name, "codec": e.codec} for e in detector.list_available()]
            else:
                gpu_list = []

            any_invalid = any(v.startswith("not found at:") for v in tools_out.values() if v)
            ok = (tools_out["ffprobe"] not in (None, "not found")
                  and not tools_out["ffprobe"].startswith("not found at:")
                  and not any_invalid)
            print(json.dumps({
                "status":         "ok" if ok else "error",
                "python_version": sys.version.split()[0],
                "ffmpeg":         tools_out["ffmpeg"],
                "ffprobe":        tools_out["ffprobe"],
                "exiftool":       tools_out["exiftool"],
                "gpu_encoders":   gpu_list,
            }))
            return 0 if ok else 1
        if args.mode == "probe":
            return run_probe(args, cfg)
        if args.mode == "process":
            return run_process(args, cfg)
        if args.mode == "batch":
            return run_batch(args, cfg)
        if args.mode == "status":
            return run_status(args, cfg)
        if args.mode == "clean":
            return run_clean(args, cfg)

    # Mode interactif
    cli = InteractiveCLI(cfg)
    cli.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
