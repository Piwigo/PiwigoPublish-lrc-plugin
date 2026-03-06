"""
CLI — Interface en ligne de commande du Video Toolkit.

Deux modes :
  1. Mode non-interactif (appelé depuis Lightroom via args)
     python video_toolkit.py --mode probe --input video.mp4
     python video_toolkit.py --mode batch --batch-file batch.json

  2. Mode interactif (menu terminal, lancé sans args)
     python video_toolkit.py

L'interface interactive utilise les patterns Menu Generator :
  - Menus compacts par sections
  - Annulation systématique (0 / x / ENTRÉE)
  - Rapport structuré après chaque opération
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .config import Config
from .ffprobe import FFprobe, ProbeError
from .hasher import partial_hash
from .presets import PresetManager, PRESET_ORDER
from .processor import VideoProcessor
from .status import StatusManager, GlobalStatusFile, STATE_PROCESSING, STATE_COMPLETE, STATE_ERROR
from .ui import Colors, OutputFormatter, clear_screen, pause

# ---------------------------------------------------------------------------
# Parser non-interactif
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="video_toolkit.py",
        description="Video Toolkit — Local video processing for PiwigoPublish",
    )
    p.add_argument(
        "--mode",
        choices=["check", "probe", "process", "batch", "status", "clean"],
        help="Mode d'exécution (sans --mode : mode interactif)",
    )
    p.add_argument("--input",          help="Fichier vidéo source")
    p.add_argument("--preset",         help="Preset : small/medium/large/xlarge/xxl/origin")
    p.add_argument("--config",         help="Chemin vers le fichier de configuration JSON")
    p.add_argument("--output-dir",     help="Dossier de sortie (défaut : même que la source)")
    p.add_argument("--batch-file",     help="Fichier JSON liste de vidéos (mode batch)")
    p.add_argument("--status-file",    help="Fichier statut global pour le polling Lightroom")
    p.add_argument("--force",          action="store_true", help="Forcer le re-traitement même si cache valide")
    p.add_argument("--thumbnail-only", action="store_true", dest="thumbnail_only", help="Générer uniquement la miniature")
    p.add_argument("--keep",           help="Preset à conserver lors du nettoyage (mode clean)")
    p.add_argument("--check-config",   dest="check_config", help="Fichier JSON avec les chemins à valider (mode check)")
    p.add_argument("--ffmpeg-path",    dest="ffmpeg_path",   help="Chemin explicite vers ffmpeg (override config)")
    p.add_argument("--exiftool-path",  dest="exiftool_path", help="Chemin explicite vers exiftool (override config)")
    p.add_argument("--log-file",       dest="log_file",      help="Fichier log pour capturer stdout+stderr (diagnostic)")
    p.add_argument("--verbose",        action="store_true", help="Sortie détaillée")
    p.add_argument("--dry-run",        action="store_true", dest="dry_run", help="Simuler sans écrire")
    p.add_argument("--hwaccel",        choices=["auto", "cpu", "gpu"], default=None,
                   help="Hardware acceleration: auto/cpu/gpu (default: from config)")
    return p


# ---------------------------------------------------------------------------
# Mode probe (non-interactif — appelé par Lightroom)
# ---------------------------------------------------------------------------

def run_probe(args: argparse.Namespace, cfg: Config) -> int:
    """Analyse une vidéo et écrit le résultat JSON sur stdout. Exit 0 = OK."""
    if not args.input:
        _json_error("--input requis pour le mode probe")
        return 1

    ffprobe_bin = cfg.resolve_tool("ffprobe") or "ffprobe"
    prober = FFprobe(ffprobe_bin)

    try:
        info = prober.probe(args.input)
    except ProbeError as e:
        _json_error(str(e))
        return 1

    # Enrichir avec le hash partiel
    try:
        h = partial_hash(args.input)
    except OSError as e:
        _json_error(f"Impossible de lire le fichier : {e}")
        return 1

    result = info.to_dict()
    result["hash"] = h

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------------------
# Mode process (non-interactif — appelé par Lightroom)
# ---------------------------------------------------------------------------

def run_process(args: argparse.Namespace, cfg: Config) -> int:
    """Traite une vidéo unique selon le preset donné. Écrit le résultat JSON sur stdout."""
    if not args.input:
        _json_error("--input requis pour le mode process")
        return 1

    preset_key: str = str(args.preset or cfg.get("default_preset", "medium"))
    dry_run = getattr(args, "dry_run", False)
    force = getattr(args, "force", False)
    thumbnail_only = getattr(args, "thumbnail_only", False)

    processor = _build_processor(cfg, getattr(args, "hwaccel", None))

    global_sf = None
    if args.status_file:
        global_sf = GlobalStatusFile(args.status_file)
        global_sf.update(STATE_PROCESSING, progress=0, current_file=args.input, total=1, done=0)

    def _progress(pct: int) -> None:
        if global_sf:
            global_sf.update(STATE_PROCESSING, progress=pct, current_file=args.input, total=1, done=0)

    result = processor.process(
        input_path=args.input,
        preset_key=preset_key,
        output_dir=args.output_dir or None,
        force=force,
        thumbnail_only=thumbnail_only,
        dry_run=dry_run,
        progress_callback=_progress,
    )

    if result.error:
        if global_sf:
            global_sf.mark_error(result.error)
        _json_error(result.error)
        return 1

    output = {
        "status": "ok",
        "skipped": result.skipped,
        "input": result.input_path,
        "variant": result.variant_path,
        "thumbnail": result.thumbnail_path,
        "preset": result.preset_key,
        "width": result.width,
        "height": result.height,
        "duration": result.duration,
        "size": result.size,
        "thumbnail_size": result.thumbnail_size,
    }
    if result.orig:
        output["orig"] = result.orig
    if result.conv:
        output["conv"] = result.conv

    if global_sf:
        global_sf.mark_complete(files=[result.variant_path, result.thumbnail_path])

    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------------------
# Mode batch (non-interactif — appelé par Lightroom)
# ---------------------------------------------------------------------------

def run_batch(args: argparse.Namespace, cfg: Config) -> int:
    """Traite un batch de vidéos depuis un fichier JSON."""
    if not args.batch_file:
        _json_error("--batch-file requis pour le mode batch")
        return 1

    batch_path = Path(args.batch_file)
    if not batch_path.exists():
        _json_error(f"Fichier batch introuvable : {args.batch_file}")
        return 1

    try:
        with batch_path.open("r", encoding="utf-8") as f:
            batch = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        _json_error(f"Erreur lecture batch : {e}")
        return 1

    videos = batch.get("videos", [])
    total = len(videos)
    dry_run = getattr(args, "dry_run", False)

    global_sf = None
    status_file = args.status_file or batch.get("status_file")
    if status_file:
        global_sf = GlobalStatusFile(status_file)
        global_sf.update(STATE_PROCESSING, progress=0, total=total, done=0)

    processor = _build_processor(cfg, getattr(args, "hwaccel", None))

    # Construire les jobs depuis le batch JSON
    jobs = []
    for item in videos:
        jobs.append({
            "input":          item.get("input", ""),
            "preset":         item.get("preset") or cfg.get("default_preset", "medium"),
            "output_dir":     item.get("output_dir"),
            "force":          item.get("force", False),
            "thumbnail_only": item.get("thumbnail_only", False),
            "dry_run":        dry_run,
        })

    def _batch_progress(done: int, total_: int, current: str) -> None:
        if global_sf and total_ > 0:
            pct = int(done * 100 / total_)
            global_sf.update(STATE_PROCESSING, progress=pct, current_file=current,
                             total=total_, done=done)

    results_out = []
    for idx, job in enumerate(jobs):
        _batch_progress(idx, total, job["input"])
        r = processor.process(
            input_path=job["input"],
            preset_key=job["preset"],
            output_dir=job.get("output_dir"),
            force=job.get("force", False),
            thumbnail_only=job.get("thumbnail_only", False),
            dry_run=job.get("dry_run", False),
        )
        entry = {
            "input":     r.input_path,
            "variant":   r.variant_path,
            "thumbnail": r.thumbnail_path,
            "preset":    r.preset_key,
            "width":     r.width,
            "height":    r.height,
            "duration":  r.duration,
            "size":      r.size,
            "skipped":   r.skipped,
            "status":    "error" if r.error else "ok",
        }
        if r.error:
            entry["error"] = r.error
        if r.orig:
            entry["orig"] = r.orig
        if r.conv:
            entry["conv"] = r.conv
        results_out.append(entry)

    _batch_progress(total, total, "")

    has_errors = any(r["status"] == "error" for r in results_out)
    output = {
        "status": "error" if has_errors else "ok",
        "total": total,
        "results": results_out,
    }

    if global_sf:
        if has_errors:
            errors = [r["error"] for r in results_out if r.get("error")]
            global_sf.mark_error("; ".join(errors[:3]))
        else:
            global_sf.mark_complete(files=[r["variant"] for r in results_out if r.get("variant")])

    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 1 if has_errors else 0


# ---------------------------------------------------------------------------
# Mode clean (non-interactif)
# ---------------------------------------------------------------------------

def run_clean(args: argparse.Namespace, cfg: Config) -> int:
    """Supprime les variantes d'une vidéo (garde éventuellement un preset)."""
    if not args.input:
        _json_error("--input requis pour le mode clean")
        return 1

    input_path = Path(args.input)
    if not input_path.exists():
        _json_error(f"Fichier introuvable : {args.input}")
        return 1

    keep_preset = getattr(args, "keep", None)
    dry_run = getattr(args, "dry_run", False)

    from .presets import BUILTIN_PRESETS
    stem = input_path.stem
    parent = input_path.parent

    deleted: list[str] = []
    skipped: list[str] = []

    for key, preset in BUILTIN_PRESETS.items():
        if not preset.suffix:
            continue  # Origin = pas de variante fichier
        if keep_preset and key == keep_preset.lower():
            continue

        variant = parent / f"{stem}{preset.suffix}.mp4"
        if variant.exists():
            if not dry_run:
                variant.unlink()
            deleted.append(str(variant))

    # Poster
    poster = parent / f"{stem}_poster.jpg"
    if poster.exists() and not keep_preset:
        if not dry_run:
            poster.unlink()
        deleted.append(str(poster))

    # Fichier statut .vtk/
    from .status import VTK_DIR
    status_file = parent / VTK_DIR / f"{stem}.json"
    if status_file.exists() and not keep_preset:
        if not dry_run:
            status_file.unlink()
        deleted.append(str(status_file))

    output = {
        "status": "ok",
        "dry_run": dry_run,
        "deleted": deleted,
        "skipped": skipped,
    }
    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------------------
# Mode status (non-interactif)
# ---------------------------------------------------------------------------

def run_status(args: argparse.Namespace, cfg: Config) -> int:
    """Vérifie le statut d'une vidéo déjà traitée."""
    if not args.input:
        _json_error("--input requis pour le mode status")
        return 1

    sm = StatusManager(args.input, str(cfg.get("vtk_dir_name") or ".vtk"))
    state = sm.get_state()
    source = sm.get_source()
    variants = {
        k: v for k, v in sm._data.get("variants", {}).items()
    }

    result = {
        "state": state,
        "source": source,
        "variants": variants,
        "thumbnail": sm.get_thumbnail(),
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------------------
# Mode interactif — Menu principal
# ---------------------------------------------------------------------------

class InteractiveCLI:
    """Menu interactif pour tester et configurer le Video Toolkit."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.c = Colors()
        self.fmt = OutputFormatter(self.c)
        self.presets = PresetManager(cfg.get_presets_file())

    def run(self) -> None:
        while True:
            clear_screen()
            self._print_header()
            self._print_main_menu()

            choice = input(self.c.prompt("Votre choix (0-5): ")).strip()

            if choice == "0":
                print(f"\n{self.c.DIM}Au revoir.{self.c.RESET}\n")
                break
            elif choice == "1":
                self._menu_probe()
            elif choice == "2":
                self._menu_process()
            elif choice == "3":
                self._menu_presets()
            elif choice == "4":
                self._menu_tools()
            elif choice == "5":
                self._menu_config()
            else:
                print(self.c.error(f'Choix invalide : "{choice}"'))
                pause(self.c)

    # --- Header ---

    def _print_header(self) -> None:
        print()
        print(self.c.box_header("VIDEO TOOLKIT — PiwigoPublish", width=70))
        print()

        # Ligne de statut outils
        tools = self.cfg.tool_status()
        parts = []
        for name, path in tools.items():
            if path:
                parts.append(f"{self.c.KEY}{name}{self.c.RESET}: {self.c.OK}OK{self.c.RESET}")
            else:
                parts.append(f"{self.c.KEY}{name}{self.c.RESET}: {self.c.ERROR}absent{self.c.RESET}")
        print("  " + "  |  ".join(parts))
        print()

    # --- Menu principal ---

    def _print_main_menu(self) -> None:
        c = self.c

        print(c.title("ANALYSE & TRAITEMENT"))
        print(c.separator())
        print(c.menu_option("1", "Probe          - Analyser une vidéo (résolution, codecs, durée...)"))
        print(c.menu_option("2", "Traiter        - Transcoder une vidéo selon un preset"))
        print()
        print(c.title("CONFIGURATION"))
        print(c.separator())
        print(c.menu_option("3", "Presets        - Voir et gérer les presets vidéo"))
        print(c.menu_option("4", "Outils         - Vérifier FFmpeg / FFprobe / ExifTool"))
        print(c.menu_option("5", "Paramètres     - Configuration générale"))
        print()
        print(c.menu_option("0", f"{c.DIM}Quitter{c.RESET}"))
        print()

    # --- 1. Menu Probe ---

    def _menu_probe(self) -> None:
        while True:
            clear_screen()
            print()
            print(self.c.box_header("PROBE — Analyse d'une vidéo", width=70))
            print()

            ffprobe_path = self.cfg.resolve_tool("ffprobe")
            if ffprobe_path:
                print(f"  ffprobe : {self.c.OK}OK{self.c.RESET} ({self.c.VALUE}{ffprobe_path}{self.c.RESET})")
            else:
                print(f"  ffprobe : {self.c.ERROR}non trouvé{self.c.RESET}")
                print(f"  {self.c.DIM}Configurez le chemin dans Outils (option 3).{self.c.RESET}")
                pause(self.c)
                return
            print()

            print(f"  {self.c.DIM}Entrez le chemin vers un fichier vidéo (x pour annuler) :{self.c.RESET}")
            path = input(self.c.prompt("  > ")).strip()

            if path.lower() == "x" or not path:
                return

            video_path = Path(path.strip('"').strip("'"))
            if not video_path.exists():
                print(self.c.error(f"Fichier introuvable : {video_path}"))
                pause(self.c)
                continue

            # Lancer probe
            print(f"\n{self.c.DIM}Analyse en cours...{self.c.RESET}")
            prober = FFprobe(ffprobe_path)
            try:
                info = prober.probe(str(video_path))
                h = partial_hash(str(video_path))
            except ProbeError as e:
                print(self.c.error(str(e)))
                pause(self.c)
                continue
            except OSError as e:
                print(self.c.error(f"Erreur lecture : {e}"))
                pause(self.c)
                continue

            # Rapport
            self.fmt.print_section_header("RÉSULTAT PROBE")

            rows = [
                ("Fichier",        video_path.name),
                ("Résolution",     info.resolution),
                ("Durée",          info.duration_str),
                ("FPS",            f"{info.fps:.3f}"),
                ("Codec vidéo",    info.video_codec),
                ("Codec audio",    info.audio_codec),
                ("Bitrate vidéo",  f"{info.video_bitrate} kbps" if info.video_bitrate else "inconnu"),
                ("Bitrate audio",  f"{info.audio_bitrate} kbps" if info.audio_bitrate else "inconnu"),
                ("Taille",         _format_size(info.size)),
                ("Container",      info.container),
                ("Hash (partiel)", h),
            ]

            # HDR detection
            if info.is_hdr:
                hdr_label = "HDR (PQ)" if info.color_transfer == "smpte2084" else "HDR (HLG)"
                rows.append(("Colorimétrie", f"{self.c.YELLOW}{hdr_label}{self.c.RESET} → tonemap auto SDR"))
            elif info.color_transfer:
                rows.append(("Colorimétrie", f"SDR ({info.color_transfer})"))

            self.fmt.aligned_output(rows)

            # Suggestion de preset adapté
            print()
            suggested = _suggest_preset(info.width, info.height)
            print(f"  {self.c.DIM}Preset suggéré :{self.c.RESET} {self.c.VALUE}{suggested}{self.c.RESET}")

            self.fmt.print_section_divider()
            pause(self.c)
            return

    # --- 2. Menu Process ---

    def _menu_process(self) -> None:
        """Menu interactif de traitement vidéo (probe + transcode + miniature)."""
        while True:
            clear_screen()
            print()
            print(self.c.box_header("TRAITEMENT — Transcoder une vidéo", width=70))
            print()

            # Vérifier FFmpeg
            ffmpeg_path = self.cfg.resolve_tool("ffmpeg")
            if not ffmpeg_path:
                print(f"  {self.c.error_marker()} FFmpeg non trouvé — requis pour le transcodage.")
                print(f"  {self.c.DIM}Configurez le chemin dans Outils (option 4).{self.c.RESET}")
                pause(self.c)
                return

            default_preset: str = str(self.cfg.get("default_preset", "medium"))

            print(f"  {self.c.DIM}Entrez le chemin vers un fichier vidéo (x pour annuler) :{self.c.RESET}")
            path = input(self.c.prompt("  > ")).strip()

            if path.lower() == "x" or not path:
                return

            video_path = Path(path.strip('"').strip("'"))
            if not video_path.exists():
                print(self.c.error(f"Fichier introuvable : {video_path}"))
                pause(self.c)
                continue

            # Choix du preset
            print()
            print(self.c.title("Preset de transcodage"))
            print(self.c.separator())
            for i, key in enumerate(PRESET_ORDER, 1):
                p = self.presets.get_preset(key)
                marker = f" {self.c.OK}← défaut{self.c.RESET}" if key == default_preset else ""
                print(f"  {self.c.YELLOW}{i}{self.c.RESET}. {p.name:<8} {self.c.DIM}{p.max_width}×{p.max_height}  {p.video_bitrate} kbps{self.c.RESET}{marker}")
            print(f"  {self.c.YELLOW}0{self.c.RESET}. Annuler")
            print()

            preset_choice = input(self.c.prompt(f"Preset (1-{len(PRESET_ORDER)}, ENTRÉE={default_preset}): ")).strip()
            if preset_choice == "0":
                continue
            if preset_choice == "":
                preset_key = default_preset
            else:
                try:
                    idx = int(preset_choice) - 1
                    if 0 <= idx < len(PRESET_ORDER):
                        preset_key = PRESET_ORDER[idx]
                    else:
                        print(self.c.error(f'Choix invalide : "{preset_choice}"'))
                        pause(self.c)
                        continue
                except ValueError:
                    print(self.c.error(f'Choix invalide : "{preset_choice}"'))
                    pause(self.c)
                    continue

            print()
            print(f"  {self.c.DIM}Traitement en cours : {video_path.name} → preset {preset_key}...{self.c.RESET}")
            print()

            processor = _build_processor(self.cfg)
            last_pct = [0]

            def _show_progress(pct: int) -> None:
                if pct != last_pct[0]:
                    last_pct[0] = pct
                    bar = "█" * (pct // 5) + "░" * (20 - pct // 5)
                    print(f"\r  [{bar}] {pct:3d}%", end="", flush=True)

            result = processor.process(
                input_path=video_path,
                preset_key=preset_key,
                progress_callback=_show_progress,
            )
            print()  # après la barre de progression

            # Rapport
            self.fmt.print_section_header("RÉSULTAT TRAITEMENT")

            if result.error:
                print(self.c.error(f"Erreur : {result.error}"))
            elif result.skipped:
                print(self.c.success("Variante déjà à jour — aucun traitement nécessaire."))
                self.fmt.aligned_output([
                    ("Variante",   result.variant_path),
                    ("Miniature",  result.thumbnail_path),
                ])
            else:
                self.fmt.aligned_output([
                    ("Variante",      result.variant_path),
                    ("Résolution",    f"{result.width}×{result.height}"),
                    ("Taille",        _format_size(result.size)),
                    ("Miniature",     result.thumbnail_path),
                    ("Taille poster", _format_size(result.thumbnail_size)),
                ])
                print(self.c.success("Traitement terminé."))

            self.fmt.print_section_divider()
            pause(self.c)
            return

    # --- 3. Menu Presets ---

    def _menu_presets(self) -> None:
        clear_screen()
        print()
        print(self.c.box_header("PRESETS — Configuration des presets vidéo", width=70))
        print()

        all_presets = self.presets.list_presets()
        default_key = self.cfg.get("default_preset", "medium")

        print(self.c.title("Presets disponibles"))
        print(self.c.separator())
        print()

        for key, preset in all_presets:
            marker = f" {self.c.OK}← défaut{self.c.RESET}" if key == default_key else ""
            print(
                f"  {self.c.BOLD}{preset.name:<8}{self.c.RESET}"
                f"  {self.c.VALUE}{preset.max_width}×{preset.max_height}{self.c.RESET:<6}"
                f"  {self.c.DIM}{preset.video_bitrate:>6} kbps vidéo"
                f"  {preset.audio_bitrate:>4} kbps audio"
                f"  {preset.h264_profile:<8}{self.c.RESET}"
                f"{marker}"
            )
        print()

        presets_file = self.cfg.get_presets_file()
        if presets_file.exists():
            print(f"  {self.c.DIM}Fichier :{self.c.RESET} {self.c.VALUE}{presets_file}{self.c.RESET}")
        else:
            print(f"  {self.c.DIM}Fichier presets non configuré (presets builtin utilisés){self.c.RESET}")

        print()
        pause(self.c)

    # --- 3. Menu Outils ---

    def _menu_tools(self) -> None:
        while True:
            clear_screen()
            print()
            print(self.c.box_header("OUTILS — Vérification des dépendances", width=70))
            print()

            tools = {
                "ffmpeg":   ("FFmpeg",   "Transcodage vidéo", True),
                "ffprobe":  ("FFprobe",  "Analyse vidéo (inclus avec FFmpeg)", True),
                "exiftool": ("ExifTool", "Copie de métadonnées (optionnel)", False),
            }

            all_ok = True
            missing = []

            for tool_key, (tool_name, description, required) in tools.items():
                path = self.cfg.resolve_tool(tool_key)
                if path:
                    version = _get_tool_version(tool_key, path)
                    ver_str = f" {self.c.DIM}v{version}{self.c.RESET}" if version else ""
                    print(f"  {self.c.ok_marker()} {self.c.KEY}{tool_name:<12}{self.c.RESET} {self.c.VALUE}{path}{self.c.RESET}{ver_str}")
                    print(f"      {self.c.DIM}{description}{self.c.RESET}\n")
                else:
                    all_ok = False
                    severity = "REQUIS" if required else "OPTIONNEL"
                    marker = self.c.error_marker() if required else self.c.warn_marker()
                    print(f"  {marker} {self.c.KEY}{tool_name:<12}{self.c.RESET} non trouvé ({severity})")
                    print(f"      {self.c.DIM}{description}{self.c.RESET}\n")
                    missing.append((tool_key, tool_name, required))

            # Afficher les instructions d'installation pour les outils manquants
            if missing:
                print()
                print(self.c.title("Installation des outils manquants"))
                print(self.c.separator())
                print()

                for tool_key, tool_name, _ in missing:
                    _print_install_instructions(self.c, tool_key, tool_name)

            else:
                print(self.c.success("Tous les outils requis sont disponibles."))

            # Section encodeurs GPU
            print()
            print(self.c.title("Encodeurs GPU détectés"))
            print(self.c.separator())
            print()
            ffmpeg_path = self.cfg.resolve_tool("ffmpeg")
            if ffmpeg_path:
                from .hwaccel import HWAccelDetector, _ENCODER_REGISTRY
                detector = HWAccelDetector(ffmpeg_path)
                available = detector.list_available()
                available_codecs = {e.codec for e in available}
                os_key = sys.platform if sys.platform in ("win32", "darwin") else "linux"
                all_candidates = _ENCODER_REGISTRY.get(os_key, [])
                if all_candidates:
                    for enc in all_candidates:
                        if enc.codec in available_codecs:
                            print(f"  {self.c.ok_marker()} {self.c.VALUE}{enc.codec:<22}{self.c.RESET} {enc.name}")
                        else:
                            print(f"  {self.c.error_marker()} {self.c.DIM}{enc.codec:<22}{self.c.RESET} {enc.name} — non disponible")
                else:
                    print(f"  {self.c.DIM}Aucun encodeur GPU connu pour cette plateforme{self.c.RESET}")
                if not available:
                    print(f"\n  {self.c.DIM}Aucun encodeur GPU détecté — le CPU sera utilisé{self.c.RESET}")
                else:
                    hw_mode = self.cfg.get("hardware_accel", "auto")
                    print(f"\n  {self.c.DIM}Mode actuel :{self.c.RESET} {self.c.VALUE}{hw_mode}{self.c.RESET}")
            else:
                print(f"  {self.c.DIM}FFmpeg non trouvé — impossible de détecter les encodeurs GPU{self.c.RESET}")

            print()
            if missing:
                print(f"  {self.c.YELLOW}1{self.c.RESET}. Configurer les chemins manuellement")
                print(f"  {self.c.YELLOW}0{self.c.RESET}. Retour\n")
                choice = input(self.c.prompt("Votre choix (0-1): ")).strip()
                if choice == "0":
                    return
                elif choice == "1":
                    self._menu_config()  # option 5 du menu principal
                else:
                    print(self.c.error(f'Choix invalide : "{choice}"'))
                    pause(self.c)
            else:
                pause(self.c)
                return

    # --- 4. Menu Config ---

    def _menu_config(self) -> None:
        while True:
            clear_screen()
            print()
            print(self.c.box_header("PARAMÈTRES — Configuration générale", width=70))
            print()

            default_preset: str = str(self.cfg.get("default_preset", "medium"))
            generate_poster = self.cfg.get("generate_poster", True)
            poster_ts = self.cfg.get("poster_timestamp_pct", 10)
            ffmpeg_path = self.cfg.get("ffmpeg_path", "") or self.c.DIM + "(auto)" + self.c.RESET
            ffprobe_path = self.cfg.get("ffprobe_path", "") or self.c.DIM + "(auto)" + self.c.RESET
            exiftool_path = self.cfg.get("exiftool_path", "") or self.c.DIM + "(auto)" + self.c.RESET
            presets_file = str(self.cfg.get_presets_file())
            hw_accel: str = str(self.cfg.get("hardware_accel") or "auto")

            poster_status = f"{self.c.OK}activé{self.c.RESET}" if generate_poster else f"{self.c.DIM}désactivé{self.c.RESET}"

            print(self.c.title("Paramètres actuels"))
            print()
            print(self.c.config_line("1. Preset par défaut",    default_preset))
            print(self.c.config_line("2. Génération poster",    poster_status))
            print(self.c.config_line("3. Timestamp poster",     f"{poster_ts}% de la durée"))
            print(self.c.config_line("4. FFmpeg path",          ffmpeg_path))
            print(self.c.config_line("5. FFprobe path",         ffprobe_path))
            print(self.c.config_line("6. ExifTool path",        exiftool_path))
            print(self.c.config_line("7. Fichier presets",      presets_file))
            print(self.c.config_line("8. Accélération GPU",     hw_accel))
            print()
            print(self.c.separator())
            print(f"  {self.c.DIM}Numéro pour modifier, 0 pour revenir{self.c.RESET}")
            print()

            choice = input(self.c.prompt("Votre choix (0-8): ")).strip()

            if choice == "0":
                return
            elif choice == "1":
                self._edit_default_preset()
            elif choice == "2":
                current = self.cfg.get("generate_poster", True)
                self.cfg.set("generate_poster", not current)
                self.cfg.save()
            elif choice == "3":
                self._edit_poster_timestamp()
            elif choice in ("4", "5", "6"):
                key_map = {"4": "ffmpeg", "5": "ffprobe", "6": "exiftool"}
                self._edit_tool_path(key_map[choice])
            elif choice == "7":
                self._edit_presets_file()
            elif choice == "8":
                self._edit_hardware_accel()
            else:
                print(self.c.error(f'Choix invalide : "{choice}"'))
                pause(self.c)

    def _edit_default_preset(self) -> None:
        print()
        print(self.c.title("Preset par défaut"))
        print(self.c.separator())
        for i, key in enumerate(PRESET_ORDER, 1):
            preset = self.presets.get_preset(key)
            print(f"  {self.c.YELLOW}{i}{self.c.RESET}. {preset.name} ({preset.max_width}×{preset.max_height})")
        print()
        choice = input(self.c.prompt("Choix (1-6, x pour annuler): ")).strip()
        if choice.lower() == "x":
            return
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(PRESET_ORDER):
                self.cfg.set("default_preset", PRESET_ORDER[idx])
                self.cfg.save()
                print(self.c.success(f"Preset par défaut : {PRESET_ORDER[idx]}"))
            else:
                print(self.c.error(f'Choix invalide : "{choice}"'))
        except ValueError:
            print(self.c.error(f'Choix invalide : "{choice}"'))
        pause(self.c)

    def _edit_poster_timestamp(self) -> None:
        print()
        current = self.cfg.get("poster_timestamp_pct", 10)
        val = input(self.c.prompt(f"Timestamp poster en % (actuel: {current}%, x pour annuler): ")).strip()
        if val.lower() == "x" or not val:
            return
        try:
            pct = int(val)
            if 0 <= pct <= 95:
                self.cfg.set("poster_timestamp_pct", pct)
                self.cfg.save()
                print(self.c.success(f"Timestamp poster : {pct}%"))
            else:
                print(self.c.error("Valeur entre 0 et 95"))
        except ValueError:
            print(self.c.error(f'Valeur invalide : "{val}"'))
        pause(self.c)

    def _edit_tool_path(self, tool: str) -> None:
        print()
        current = self.cfg.get(f"{tool}_path", "")
        if current:
            print(f"  Actuel : {self.c.VALUE}{current}{self.c.RESET}")
        print(f"  {self.c.DIM}Laissez vide pour auto-détection (ENTRÉE pour garder, x pour annuler){self.c.RESET}")
        val = input(self.c.prompt(f"Chemin {tool}: ")).strip()
        if val.lower() == "x":
            return
        if val == "":
            print(self.c.success("Chemin inchangé"))
            return
        self.cfg.set(f"{tool}_path", val)
        self.cfg.save()
        print(self.c.success(f"{tool} configuré : {val}"))
        pause(self.c)

    def _edit_presets_file(self) -> None:
        print()
        current = str(self.cfg.get_presets_file())
        print(f"  Actuel : {self.c.VALUE}{current}{self.c.RESET}")
        val = input(self.c.prompt("Chemin fichier presets (ENTRÉE pour garder, x pour annuler): ")).strip()
        if val.lower() == "x":
            return
        if val == "":
            print(self.c.success("Chemin inchangé"))
            return
        self.cfg.set("presets_file", val)
        self.cfg.save()
        print(self.c.success(f"Fichier presets : {val}"))
        pause(self.c)

    def _edit_hardware_accel(self) -> None:
        print()
        print(self.c.title("Accélération GPU"))
        print(self.c.separator())
        modes = [("auto", "Auto (détecte le GPU disponible)"),
                 ("cpu",  "CPU uniquement (libx264)"),
                 ("gpu",  "GPU (force, fallback CPU si échec)")]
        for i, (key, desc) in enumerate(modes, 1):
            print(f"  {self.c.YELLOW}{i}{self.c.RESET}. {desc}")
        print()
        choice = input(self.c.prompt("Choix (1-3, x pour annuler): ")).strip()
        if choice.lower() == "x":
            return
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(modes):
                self.cfg.set("hardware_accel", modes[idx][0])
                self.cfg.save()
                print(self.c.success(f"Accélération GPU : {modes[idx][0]}"))
            else:
                print(self.c.error(f'Choix invalide : "{choice}"'))
        except ValueError:
            print(self.c.error(f'Choix invalide : "{choice}"'))
        pause(self.c)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_processor(cfg: Config, hwaccel_mode: str | None = None) -> VideoProcessor:
    """Construit un VideoProcessor avec les chemins d'outils depuis la config."""
    from .presets import PresetManager as PM
    effective_hwaccel: str = str(hwaccel_mode or cfg.get("hardware_accel", "auto"))
    return VideoProcessor(
        ffmpeg_path=cfg.resolve_tool("ffmpeg") or "ffmpeg",
        ffprobe_path=cfg.resolve_tool("ffprobe") or "ffprobe",
        exiftool_path=cfg.resolve_tool("exiftool") or "exiftool",
        preset_manager=PM(cfg.get_presets_file()),
        thumbnail_timestamp_pct=int(cfg.get("poster_timestamp_pct") or 10),
        thumbnail_max_width=int(cfg.get("thumbnail_width") or 1280),
        copy_metadata=bool(cfg.get("copy_metadata", True)),
        hwaccel_mode=effective_hwaccel,
    )


def _json_error(msg: str) -> None:
    """Écrit une erreur JSON sur stderr (pour les appels Lightroom)."""
    import json as _json
    print(_json.dumps({"status": "error", "error": msg}), file=sys.stderr)


def _format_size(size: float) -> str:
    for unit in ("o", "Ko", "Mo", "Go"):
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} To"


def _suggest_preset(width: int, height: int) -> str:
    """Suggère le preset le plus adapté à la résolution source."""
    if width >= 3840 or height >= 2160:
        return "xxl"
    if width >= 2560 or height >= 1440:
        return "xlarge"
    if width >= 1920 or height >= 1080:
        return "large"
    if width >= 1280 or height >= 720:
        return "medium"
    return "small"


def _get_tool_version(tool: str, path: str) -> str | None:
    """Extrait la version d'un outil (ffmpeg, ffprobe, exiftool)."""
    import subprocess
    from . import SUBPROCESS_FLAGS
    try:
        r = subprocess.run([path, "-version"], capture_output=True, text=True, timeout=5, **SUBPROCESS_FLAGS)
        first = r.stdout.splitlines()[0] if r.stdout else ""
        parts = first.split()
        if tool in ("ffmpeg", "ffprobe") and len(parts) >= 3:
            return parts[2]
        if tool == "exiftool" and len(parts) >= 2:
            return parts[-1]
    except Exception:
        pass
    return None


INSTALL_INSTRUCTIONS = {
    "ffmpeg": {
        "Windows": [
            ("Méthode 1 (recommandée):", "winget install ffmpeg"),
            ("Méthode 2 (Chocolatey):", "choco install ffmpeg"),
            ("Méthode 3 (manuel):", "Télécharger sur https://ffmpeg.org/download.html"),
        ],
        "macOS": [
            ("Avec Homebrew:", "brew install ffmpeg"),
            ("Voir aussi:", "https://ffmpeg.org/download.html"),
        ],
        "Linux": [
            ("Debian/Ubuntu:", "sudo apt install ffmpeg"),
            ("Fedora/RHEL:", "sudo dnf install ffmpeg"),
            ("Arch:", "sudo pacman -S ffmpeg"),
        ],
    },
    "exiftool": {
        "Windows": [
            ("Méthode 1 (winget):", "winget install exiftool"),
            ("Méthode 2 (Chocolatey):", "choco install exiftool"),
            ("Méthode 3 (manuel):", "Télécharger sur https://exiftool.org/"),
        ],
        "macOS": [
            ("Avec Homebrew:", "brew install exiftool"),
            ("Voir aussi:", "https://exiftool.org/"),
        ],
        "Linux": [
            ("Debian/Ubuntu:", "sudo apt install libimage-exiftool-perl"),
            ("Fedora/RHEL:", "sudo dnf install perl-Image-ExifTool"),
            ("Arch:", "sudo pacman -S perl-image-exiftool"),
        ],
    },
}


def _print_install_instructions(c: Colors, tool: str, tool_name: str) -> None:
    """Affiche les instructions d'installation pour un outil."""
    import sys

    instructions = INSTALL_INSTRUCTIONS.get(tool, {})
    if not instructions:
        print(f"  {c.DIM}Aucune instruction d'installation pour {tool_name}{c.RESET}\n")
        return

    os_label = "Windows" if sys.platform == "win32" else ("macOS" if sys.platform == "darwin" else "Linux")
    methods = instructions.get(os_label, instructions.get("Linux", []))

    print(f"  {c.BOLD}{tool_name}{c.RESET}")
    for label, cmd in methods:
        print(f"    {c.DIM}{label}{c.RESET}")
        print(f"      {c.VALUE}{cmd}{c.RESET}")
    print()
