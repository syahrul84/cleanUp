# CleanUp

A native macOS cleanup utility (Swift + SwiftUI), similar in spirit to CleanMyMac.

## Features

- **App Uninstaller** — removes an app plus its leftovers (Application Support, Caches, Preferences, Containers, Launch Agents, saved state), with a preview before anything moves.
- **Junk Cleaner** — scans user caches, logs, Xcode/simulator junk, developer caches (npm, pip, Homebrew, Gradle…), browser caches, old iOS backups and the Trash. Risky categories (iOS backups, Trash) are deselected by default.
- **Duplicate Finder** — exact duplicates in folders you choose, via size → partial hash → full SHA-256. No false positives. Auto-selects all but the first copy in each group.
- **Large & Old Files** — files over 50 MB in chosen folders, with last-opened dates.
- **Leftover Finder** — reverse-DNS entries in `~/Library` that belong to no installed app (Apple's own files are always excluded). Nothing selected by default.
- **Smart Scan** — one-click overview of junk, leftovers and Trash with a single clean action.
- **Speed** — honest performance help: a health checklist (disk headroom, swap, startup items, uptime), live CPU/memory hogs with polite Quit, reversible UI-animation tweaks, and maintenance actions (DNS flush, Finder/Dock restart, Spotlight re-import). No RAM-purge snake oil.
- **Startup Items** — list launch agents/daemons; reversibly disable your own launch agents.
- **Menu bar widget** — live CPU, memory and disk stats, launch-at-login toggle, quick Smart Scan.

## Safety model

Every removal uses `FileManager.trashItem` — **everything goes to the Trash**, nothing is permanently deleted, and every action shows a confirmation first.

## Install on macOS

### 1. Requirements

- macOS 14 (Sonoma) or newer
- Apple's Command Line Tools (no full Xcode needed). If you don't have them:

```sh
xcode-select --install
```

### 2. Build and install

```sh
git clone https://github.com/syahrul84/cleanUp.git
cd cleanUp
./build_app.sh
cp -R dist/CleanUp.app /Applications/
```

### 3. First launch

The app is ad-hoc signed (not notarized by Apple), so the very first time you
should launch it via right-click:

1. Open **Finder → Applications**
2. **Right-click `CleanUp.app` → Open**, then click **Open** in the dialog

After that it opens normally from Launchpad/Spotlight like any other app.

> If macOS still refuses to open it (quarantine flag from a browser download),
> clear the flag with:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/CleanUp.app
> ```

### 4. Grant Full Disk Access (recommended)

For complete scans (Safari data, Mail caches, etc.):
**System Settings → Privacy & Security → Full Disk Access** → add `CleanUp.app`.
The app shows a hint in its sidebar until access is granted.

## Development

```sh
swift build             # quick compile check
./build_app.sh          # release build + packages dist/CleanUp.app
open dist/CleanUp.app   # run without installing
```

