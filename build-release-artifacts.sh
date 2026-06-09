#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LR_PLUGIN_DIR="$ROOT_DIR/piwigoPublish.lrplugin"
# Server plugin now lives in a separate repo; set SERVER_PLUGIN_DIR to include it in the build.
# e.g. SERVER_PLUGIN_DIR=/path/to/PiwigoPublish-CompanionPlugin/piwigoPublish-lrc-plugin
SERVER_PLUGIN_DIR="${SERVER_PLUGIN_DIR:-}"
DIST_DIR="$ROOT_DIR/dist"

RELEASE_VERSION=""

usage() {
  cat <<'EOF'
Build release artifacts for both Lightroom and server-side plugins.

Usage:
  ./build-release-artifacts.sh [--version X.Y.Z] [--server-plugin-dir PATH]

Options:
  --version          Version label used in output filenames.
                     If omitted, defaults to YYYYMMDD-HHMMSS.
  --server-plugin-dir  Absolute path to the companion server plugin directory.
                     If omitted (and SERVER_PLUGIN_DIR env var not set), the
                     server plugin steps are skipped.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --version" >&2
        exit 1
      fi
      RELEASE_VERSION="$2"
      shift 2
      ;;
    --server-plugin-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --server-plugin-dir" >&2
        exit 1
      fi
      SERVER_PLUGIN_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$RELEASE_VERSION" ]]; then
  RELEASE_VERSION="$(date +%Y%m%d-%H%M%S)"
fi

if [[ ! -d "$LR_PLUGIN_DIR" ]]; then
  echo "Lightroom plugin directory missing: $LR_PLUGIN_DIR" >&2
  exit 1
fi
if [[ -n "$SERVER_PLUGIN_DIR" && ! -d "$SERVER_PLUGIN_DIR" ]]; then
  echo "Server plugin directory not found: $SERVER_PLUGIN_DIR" >&2
  exit 1
fi
if [[ -z "$SERVER_PLUGIN_DIR" ]]; then
  echo "(Server plugin dir not set — server plugin steps will be skipped)"
fi

if ! command -v luac >/dev/null 2>&1; then
  echo "luac is required for Lua syntax checks but was not found on PATH." >&2
  exit 1
fi
if ! command -v php >/dev/null 2>&1; then
  echo "php is required for PHP syntax checks but was not found on PATH." >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to build artifacts but was not found on PATH." >&2
  exit 1
fi

echo "==> Running Lua syntax checks"
while IFS= read -r -d '' lua_file; do
  luac -p "$lua_file"
done < <(find "$LR_PLUGIN_DIR" -type f -name '*.lua' -print0)

if [[ -n "$SERVER_PLUGIN_DIR" ]]; then
  echo "==> Running PHP syntax checks"
  while IFS= read -r -d '' php_file; do
    php -l "$php_file" >/dev/null
  done < <(find "$SERVER_PLUGIN_DIR" -type f \( -name '*.php' -o -name '*.inc.php' \) -print0)

  if grep -q "define('PP_PIWIGO_LRC_DEBUG', true);" "$SERVER_PLUGIN_DIR/main.inc.php" 2>/dev/null; then
    echo "WARNING: Server plugin debug logging is enabled in main.inc.php"
  fi
fi

mkdir -p "$DIST_DIR"

LR_ZIP="$DIST_DIR/piwigoPublish-lrplugin-${RELEASE_VERSION}.zip"
SERVER_ZIP=""
if [[ -n "$SERVER_PLUGIN_DIR" ]]; then
  SERVER_ZIP="$DIST_DIR/piwigoPublish-lrc-plugin-${RELEASE_VERSION}.zip"
fi

rm -f "$LR_ZIP"
[[ -n "$SERVER_ZIP" ]] && rm -f "$SERVER_ZIP"

echo "==> Building Lightroom plugin ZIP"
pushd "$ROOT_DIR" >/dev/null
zip -rq "$LR_ZIP" "$(basename "$LR_PLUGIN_DIR")" \
  -x '*/.DS_Store' '*/__MACOSX/*' '*/.git/*'
popd >/dev/null

if [[ -n "$SERVER_PLUGIN_DIR" && -n "$SERVER_ZIP" ]]; then
  echo "==> Building server plugin ZIP"
  pushd "$(dirname "$SERVER_PLUGIN_DIR")" >/dev/null
  zip -rq "$SERVER_ZIP" "$(basename "$SERVER_PLUGIN_DIR")" \
    -x '*/.DS_Store' '*/__MACOSX/*' '*/.git/*'
  popd >/dev/null
fi

echo "==> Artifacts created"
echo "  $LR_ZIP"
[[ -n "$SERVER_ZIP" ]] && echo "  $SERVER_ZIP"

if command -v shasum >/dev/null 2>&1; then
  echo "==> SHA256"
  shasum -a 256 "$LR_ZIP" ${SERVER_ZIP:+"$SERVER_ZIP"}
fi

if [[ -n "$SERVER_ZIP" ]]; then
cat <<EOF

Next steps (server deploy example):
  scp "$SERVER_ZIP" <user>@<host>:/tmp/
  ssh <user>@<host>
  sudo cp -a /var/www/html/piwigo/plugins/piwigoPublish-lrc-plugin \
    "/var/www/html/piwigo/plugins/piwigoPublish-lrc-plugin.backup.$(date +%Y%m%d-%H%M%S)"
  sudo unzip -o /tmp/$(basename "$SERVER_ZIP") -d /var/www/html/piwigo/plugins/

EOF
fi
