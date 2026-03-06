"""
UI — Couleurs ANSI, menus et rapports pour le Video Toolkit CLI.

Patterns inspirés du Menu Generator skill : menus compacts, sections
catégorisées, annulation systématique, rapports structurés.
"""

import os
import sys
import ctypes
from pathlib import Path


# ---------------------------------------------------------------------------
# Détection et activation ANSI
# ---------------------------------------------------------------------------

def _activate_windows_ansi() -> bool:
    """Active le mode ANSI sur Windows via kernel32. Retourne True si OK."""
    if sys.platform != "win32":
        return True
    try:
        kernel32 = ctypes.windll.kernel32
        # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
        return True
    except Exception:
        return False


def _detect_color_support() -> bool:
    """Détecte si le terminal supporte les couleurs ANSI."""
    # NO_COLOR standard
    if os.environ.get("NO_COLOR"):
        return False
    # Force couleurs
    if os.environ.get("FORCE_COLOR"):
        return True
    # Terminaux Windows modernes
    if os.environ.get("WT_SESSION"):
        return True
    if os.environ.get("ConEmuANSI") == "ON":
        return True
    # Vérifier isatty (toutes plateformes)
    if not (hasattr(sys.stdout, "isatty") and sys.stdout.isatty()):
        return False
    # Activation Windows
    if sys.platform == "win32":
        return _activate_windows_ansi()
    # Unix : isatty déjà vérifié
    return True


# ---------------------------------------------------------------------------
# Classe Colors
# ---------------------------------------------------------------------------

class Colors:
    """Gestion des couleurs ANSI avec détection automatique du terminal."""

    def __init__(self, force_color: bool | None = None):
        if force_color is None:
            self._enabled = _detect_color_support()
        else:
            self._enabled = force_color

        self._setup_codes()

    def _setup_codes(self):
        e = self._enabled

        def c(code: str) -> str:
            return code if e else ""

        # Couleurs de base
        self.RED            = c("\033[31m")
        self.GREEN          = c("\033[32m")
        self.YELLOW         = c("\033[33m")
        self.BLUE           = c("\033[34m")
        self.MAGENTA        = c("\033[35m")
        self.CYAN           = c("\033[36m")
        self.WHITE          = c("\033[37m")

        self.LIGHT_RED      = c("\033[91m")
        self.LIGHT_GREEN    = c("\033[92m")
        self.LIGHT_YELLOW   = c("\033[93m")
        self.LIGHT_BLUE     = c("\033[94m")
        self.LIGHT_MAGENTA  = c("\033[95m")
        self.LIGHT_CYAN     = c("\033[96m")

        # Styles
        self.BOLD           = c("\033[1m")
        self.DIM            = c("\033[2m")
        self.UNDERLINE      = c("\033[4m")
        self.RESET          = c("\033[0m")

        # Alias sémantiques
        self.OK             = c("\033[32m")
        self.SUCCESS        = c("\033[32m")
        self.ERROR          = c("\033[31m")
        self.WARNING        = c("\033[33m")
        self.INFO           = c("\033[34m")
        self.VALUE          = c("\033[36m")
        self.KEY            = c("\033[37m")
        self.PROMPT         = c("\033[33m")
        self.HEADER         = c("\033[1;36m")
        self.TITLE          = c("\033[1;37m")

    # --- Formatage avec préfixe ---

    def success(self, text: str) -> str:
        return f"{self.GREEN}[OK]{self.RESET} {text}"

    def error(self, text: str) -> str:
        return f"{self.RED}[ERREUR]{self.RESET} {text}"

    def warning(self, text: str) -> str:
        return f"{self.YELLOW}[ATTENTION]{self.RESET} {text}"

    def info(self, text: str) -> str:
        return f"{self.BLUE}[INFO]{self.RESET} {text}"

    # --- Formatage inline ---

    def header(self, text: str) -> str:
        return f"{self.HEADER}{text}{self.RESET}"

    def title(self, text: str) -> str:
        return f"{self.TITLE}{text}{self.RESET}"

    def value(self, text: str) -> str:
        return f"{self.VALUE}{text}{self.RESET}"

    def key(self, text: str) -> str:
        return f"{self.KEY}{text}{self.RESET}"

    def prompt(self, text: str) -> str:
        return f"{self.PROMPT}{text}{self.RESET}"

    # --- Marqueurs isolés ---

    def ok_marker(self) -> str:
        return f"{self.GREEN}[OK]{self.RESET}"

    def error_marker(self) -> str:
        return f"{self.RED}[ERREUR]{self.RESET}"

    def warn_marker(self) -> str:
        return f"{self.YELLOW}[ATTENTION]{self.RESET}"

    # --- Éléments d'interface ---

    def separator(self, char: str = "-", width: int = 60) -> str:
        return f"{self.DIM}{char * width}{self.RESET}"

    def box_header(self, text: str, width: int = 70) -> str:
        """Boîte avec titre centré entre == (style section_header)."""
        border = "=" * width
        padding = width - 4
        centered = text.center(padding)
        return (
            f"{self.HEADER}{border}\n"
            f"  {centered}\n"
            f"{border}{self.RESET}"
        )

    def menu_option(self, number: str, text: str) -> str:
        return f"  {self.YELLOW}{number}{self.RESET}. {text}"

    def config_line(self, key: str, value: str, key_width: int = 25) -> str:
        return f"  {self.KEY}{key:<{key_width}}{self.RESET}: {self.VALUE}{value}{self.RESET}"


# ---------------------------------------------------------------------------
# Classe OutputFormatter
# ---------------------------------------------------------------------------

class OutputFormatter:
    """Rapports structurés : headers, stats alignées, fichiers générés."""

    def __init__(self, c: Colors | None = None):
        self.c = c or Colors()

    def print_section_header(self, title: str, width: int = 80):
        border = "=" * width
        print(f"\n{self.c.HEADER}{border}")
        print(title)
        print(f"{border}{self.c.RESET}\n")

    def print_section_divider(self, width: int = 80):
        print(f"{self.c.DIM}{'=' * width}{self.c.RESET}\n")

    def aligned_output(self, items: list[tuple[str, str]], indent: int = 2):
        if not items:
            return
        key_w = max(len(k) for k, _ in items) + 1
        for key, val in items:
            print(f"{' ' * indent}{self.c.KEY}{key:<{key_w}}{self.c.RESET}: {self.c.VALUE}{val}{self.c.RESET}")

    def print_summary_stats(self, stats: dict, title: str = "Statistiques"):
        print(f"\n{self.c.TITLE}{title}{self.c.RESET}")
        key_w = max(len(k) for k in stats) + 1
        for key, val in stats.items():
            print(f"  {self.c.KEY}{key:<{key_w}}{self.c.RESET}: {self.c.BOLD}{val}{self.c.RESET}")

    def print_summary_details(self, details: dict, title: str = "Détails"):
        print(f"\n{self.c.DIM}{title}{self.c.RESET}")
        key_w = max(len(k) for k in details) + 1
        for key, val in details.items():
            print(f"  {self.c.DIM}{key:<{key_w}}: {val}{self.c.RESET}")

    def print_files_generated(
        self,
        files: list[tuple[str, str, str]],
        output_dir: str = "",
        plugin_path: str = "",
    ):
        self.print_section_header("FICHIERS GÉNÉRÉS")
        if output_dir:
            rel = output_dir
            if plugin_path:
                try:
                    rel = str(Path(output_dir).relative_to(Path(plugin_path)))
                except ValueError:
                    pass  # output_dir n'est pas sous plugin_path
            print(f"  {self.c.DIM}Sortie :{self.c.RESET} {self.c.VALUE}{rel}{self.c.RESET}\n")
        for filename, detail, description in files:
            print(f"    {self.c.ok_marker()} {self.c.KEY}{filename:<35}{self.c.RESET} ({detail})")
            print(f"        {self.c.DIM}{description}{self.c.RESET}\n")


# ---------------------------------------------------------------------------
# Fonctions utilitaires
# ---------------------------------------------------------------------------

def clear_screen():
    if not (hasattr(sys.stdout, "isatty") and sys.stdout.isatty()):
        return
    if sys.platform == "win32":
        os.system("cls")
    else:
        sys.stdout.write("\033[2J\033[H")
        sys.stdout.flush()


def pause(c: Colors, message: str = "Appuyez sur ENTRÉE pour continuer..."):
    input(f"\n{c.DIM}{message}{c.RESET}")
