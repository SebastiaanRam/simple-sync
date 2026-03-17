#!/usr/bin/env bash
set -euo pipefail

# ─── simple-sync setup ────────────────────────────────────────────────────────
# Checks required dependencies, then walks through creating a config file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/simple-sync"
CONFIG_FILE="$CONFIG_DIR/config"

info()  { echo "[info]  $*"; }
ok()    { echo "[ ok ]  $*"; }
warn()  { echo "[warn]  $*"; }
fail()  { echo "[err]   $*" >&2; exit 1; }

# ─── Dependencies ─────────────────────────────────────────────────────────────

echo "=== Checking dependencies ==="
echo ""

# rsync (required)
if command -v rsync &>/dev/null; then
  ok "rsync found"
else
  if [[ "$(uname)" == "Darwin" ]]; then
    fail "rsync not found. Install with: brew install rsync"
  else
    fail "rsync not found. Install with: sudo apt install rsync  (or equivalent)"
  fi
fi

# file watcher (optional but needed for continuous watch mode)
if command -v fswatch &>/dev/null; then
  ok "fswatch found (continuous watching enabled)"
elif command -v inotifywait &>/dev/null; then
  ok "inotifywait found (continuous watching enabled)"
else
  warn "No file watcher found — sync.sh will run one-shot only."
  echo ""
  if [[ "$(uname)" == "Darwin" ]]; then
    read -rp "  Install fswatch via Homebrew now? [y/N] " ans
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      command -v brew &>/dev/null || fail "Homebrew not found. Install from https://brew.sh first."
      brew install fswatch
      ok "fswatch installed"
    fi
  else
    info "Install inotify-tools: sudo apt install inotify-tools"
  fi
fi

# ─── Config ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Config ==="
echo ""

if [[ -f "$CONFIG_FILE" ]]; then
  ok "Config already exists at $CONFIG_FILE"
  read -rp "  Overwrite? [y/N] " ans
  [[ "$ans" != "y" && "$ans" != "Y" ]] && { info "Keeping existing config."; echo ""; echo "Done. Run ./sync.sh"; exit 0; }
fi

read -rp "  Local repos root [$HOME/Github]: " SOURCE_BASE
SOURCE_BASE="${SOURCE_BASE:-$HOME/Github}"

echo ""
echo "  Target examples:"
echo "    /Volumes/server/username/github   (local volume)"
echo "    user@hostname:/remote/path/github  (SSH)"
while true; do
  read -rp "  Sync target: " TARGET_BASE
  [[ -n "$TARGET_BASE" ]] && break
  warn "Target is required."
done

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
# simple-sync configuration — generated $(date '+%Y-%m-%d')
# See config.example for all options.

SOURCE_BASE="$SOURCE_BASE"
TARGET_BASE="$TARGET_BASE"
EOF

ok "Config written to $CONFIG_FILE"

# ─── Repo list ────────────────────────────────────────────────────────────────

echo ""
if [[ -f "$SCRIPT_DIR/repositories.txt" ]]; then
  ok "repositories.txt already exists"
else
  warn "repositories.txt not found — creating a template."
  cat > "$SCRIPT_DIR/repositories.txt" <<'EOF'
# One repo name per line (relative to SOURCE_BASE). Lines starting with # are ignored.
# Example:
# my-project
# another-repo
EOF
  info "Edit $SCRIPT_DIR/repositories.txt to add your repos."
fi

# ─── Executable bit ───────────────────────────────────────────────────────────

chmod +x "$SCRIPT_DIR/sync.sh"
ok "sync.sh is executable"

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Setup complete ==="
echo "  Config: $CONFIG_FILE"
echo "  Repos:  $SCRIPT_DIR/repositories.txt"
echo ""
echo "Run ./sync.sh to start."
