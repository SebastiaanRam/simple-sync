#!/usr/bin/env bash
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/simple-sync/config"

# Defaults (overridden by config)
SOURCE_BASE="$HOME/Github"
TARGET_BASE=""
REPOS_FILE="$SCRIPT_DIR/repositories.txt"
FULL_SYNC_INTERVAL=300  # seconds between periodic full syncs (for deletion cleanup)
DEBOUNCE_SECS=1

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/config" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/config"
fi

# ─── Validation ───────────────────────────────────────────────────────────────

if [[ -z "$TARGET_BASE" ]]; then
  echo "Error: TARGET_BASE is not set."
  echo "Copy config.example to $CONFIG_FILE and set your paths."
  exit 1
fi

if [[ ! -f "$REPOS_FILE" ]]; then
  echo "Error: repo list not found at $REPOS_FILE"
  exit 1
fi

# ─── Repo picker ──────────────────────────────────────────────────────────────

repos=()
while IFS= read -r line; do
  repos+=("$line")
done < <(grep -v '^\s*#' "$REPOS_FILE" | grep -v '^\s*$')

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "Error: $REPOS_FILE is empty."
  exit 1
fi

echo "Select a repository to sync:"
for i in "${!repos[@]}"; do
  printf "  [%d] %s\n" "$((i + 1))" "${repos[$i]%%::*}"
done

while true; do
  read -rp "Enter number [1-${#repos[@]}]: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#repos[@]} )); then
    entry="${repos[$((choice - 1))]}"
    break
  fi
  echo "Invalid selection, try again."
done

# Entry format: "repo-name" or "repo-name::/custom/parent/path"
REPO="${entry%%::*}"
if [[ "$entry" == *::* ]]; then
  # Reuse SSH host from TARGET_BASE (empty for local paths)
  if [[ "$TARGET_BASE" != /* ]]; then
    TARGET_HOST="${TARGET_BASE%%:*}:"
  else
    TARGET_HOST=""
  fi
  TARGET_DIR="${TARGET_HOST}${entry#*::}/$REPO"
else
  TARGET_DIR="$TARGET_BASE/$REPO"
fi

SOURCE_DIR="$SOURCE_BASE/$REPO"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory not found: $SOURCE_DIR"
  exit 1
fi

# ─── Sync helpers ─────────────────────────────────────────────────────────────

RSYNC_OPTS=(-avh --no-perms --no-owner --no-group --no-times --exclude='.git/' --exclude='__pycache__/' --exclude='*.pyc' --exclude='.DS_Store')

full_sync() {
  echo "[$(date '+%H:%M:%S')] Full sync: $REPO"
  rsync "${RSYNC_OPTS[@]}" --delete "$SOURCE_DIR/" "$TARGET_DIR/"
}

sync_file() {
  local abs_path="$1"
  # Compute path relative to SOURCE_DIR
  local rel_path="${abs_path#$SOURCE_DIR/}"

  # Skip if the path is outside SOURCE_DIR (can happen with fswatch)
  if [[ "$rel_path" == "$abs_path" ]]; then
    return
  fi

  # Skip git internals and editor temp files
  if [[ "$rel_path" == .git/* ]] || [[ "$rel_path" == *~ ]] || [[ "$rel_path" == .#* ]]; then
    return
  fi

  if [[ -f "$abs_path" ]]; then
    echo "[$(date '+%H:%M:%S')] Sync: $rel_path"
    rsync "${RSYNC_OPTS[@]}" "$abs_path" "$TARGET_DIR/$rel_path"
  fi
  # Deletions are handled by the periodic full sync
}

# ─── Watcher detection ────────────────────────────────────────────────────────

detect_watcher() {
  if command -v fswatch &>/dev/null; then
    echo "fswatch"
  elif command -v inotifywait &>/dev/null; then
    echo "inotifywait"
  else
    echo "none"
  fi
}

# ─── Watch loop ───────────────────────────────────────────────────────────────

cleanup() {
  echo ""
  echo "[$(date '+%H:%M:%S')] Stopping sync for $REPO."
  # Kill the background periodic-sync job if running
  [[ -n "${PERIODIC_PID:-}" ]] && kill "$PERIODIC_PID" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

periodic_sync_loop() {
  while true; do
    sleep "$FULL_SYNC_INTERVAL"
    full_sync
  done
}

watch_fswatch() {
  echo "[$(date '+%H:%M:%S')] Watching with fswatch (press Ctrl+C to stop)"
  local last_sync=0
  local pending_file=""

  # fswatch outputs one path per line; -l sets latency (debounce)
  while IFS= read -r changed_file; do
    local now
    now=$(date +%s)
    if (( now - last_sync >= DEBOUNCE_SECS )); then
      sync_file "$changed_file"
      last_sync=$now
    fi
  done < <(fswatch -r -l "$DEBOUNCE_SECS" --event Created --event Updated --event Removed --event Renamed "$SOURCE_DIR")
}

watch_inotifywait() {
  echo "[$(date '+%H:%M:%S')] Watching with inotifywait (press Ctrl+C to stop)"
  while IFS= read -r line; do
    # inotifywait -m --format '%w%f' outputs the full path
    sync_file "$line"
    sleep "$DEBOUNCE_SECS"
  done < <(inotifywait -m -r -q --format '%w%f' \
    -e close_write -e create -e delete -e moved_to "$SOURCE_DIR")
}

# ─── Main ─────────────────────────────────────────────────────────────────────

echo "Syncing: $SOURCE_DIR"
echo "     to: $TARGET_DIR"
echo ""

# Initial full sync
full_sync

WATCHER=$(detect_watcher)

if [[ "$WATCHER" == "none" ]]; then
  echo ""
  echo "Warning: no file watcher found. Install fswatch (macOS: brew install fswatch)"
  echo "         or inotifywait (Linux: apt install inotify-tools)."
  echo "Running one-shot sync only."
  exit 0
fi

# Start periodic full sync in background (handles deletions)
periodic_sync_loop &
PERIODIC_PID=$!

case "$WATCHER" in
  fswatch)      watch_fswatch ;;
  inotifywait)  watch_inotifywait ;;
esac
