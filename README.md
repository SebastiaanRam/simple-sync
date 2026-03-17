# simple-sync

A one-command tool to sync a local repository to a remote target. Pick a repo interactively, get an initial full sync, then watch for changes and sync only the files that change.

Delegates all actual transfer to **rsync** and file watching to **fswatch** (macOS) or **inotifywait** (Linux). No reimplementation of sync logic.

## Features

- Interactive repo picker backed by a plain-text list
- Initial full sync on start
- Incremental sync — only changed files are transferred after the first sync
- Periodic full sync every 5 minutes to clean up deletions
- Works with local volume targets and SSH targets transparently (`rsync` handles both)
- macOS and Linux support

## Dependencies

| Tool | Install |
|------|---------|
| `rsync` | pre-installed on macOS and most Linux distros |
| `fswatch` | macOS: `brew install fswatch` |
| `inotifywait` | Linux: `apt install inotify-tools` |

## Setup

1. **Configure paths**

   ```bash
   mkdir -p ~/.config/simple-sync
   cp config.example ~/.config/simple-sync/config
   # Edit SOURCE_BASE and TARGET_BASE in the config
   ```

   `TARGET_BASE` can be a local path or an SSH target:
   ```bash
   TARGET_BASE="/Volumes/username/github"   # local volume
   TARGET_BASE="user@hostname:/remote/path/github"    # SSH
   ```

2. **List your repos**

   Edit `repositories.txt` — one repo name per line, relative to `SOURCE_BASE`:
   ```
   my-project
   another-project
   ```

   To sync a repo under a different parent directory instead of `TARGET_BASE`, append `::` followed by the absolute parent path:
   ```
   cpg-scripts::/data/pathology/projects/sebastiaan
   ```
   This syncs to `/data/pathology/projects/sebastiaan/cpg-scripts`.

3. **Make the script executable**

   ```bash
   chmod +x sync.sh
   ```

## Usage

```bash
./sync.sh
```

You will be prompted to pick a repository. After the initial sync, the script watches for changes and syncs them incrementally. Press `Ctrl+C` to stop.

## How it works

```
pick repo → full rsync → watch loop ─┐
                 ↑                    │ file changed → rsync single file
                 └────────────────────┘ (+ full sync every 5 min for deletions)
```

Deletions are not tracked per-file. Instead, a full sync with `--delete` runs every `FULL_SYNC_INTERVAL` seconds (default 300s) to remove files at the target that no longer exist locally.
