# Video Toolkit — src package

import subprocess
import sys

# Évite le flash d'une fenêtre console sur Windows quand lancé depuis un process GUI
SUBPROCESS_FLAGS: dict = (
    {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}
)
