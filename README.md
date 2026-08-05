<p align="center">
  <img src="https://img.shields.io/badge/Termux%20Pkg%20Manager-v2.0-000000?logo=termux" alt="Version">
  <img src="https://img.shields.io/badge/platform-Termux-4EAA25?logo=terminal" alt="Platform">
  <img src="https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome">
</p>

# Easy Termux Package Manager

> Install, remove, search, inspect, back up, and repair packages on Termux — without ever touching a `pkg` or `apt` command again.

A **gum-powered, interactive package manager** for [Termux](https://termux.com) wrapped in one Bash script. Arrow-key through a gorgeous menu, and let the script handle all the scary apt/pkg syntax for you.

```
 _______ ______ _____  __  __ _    ___   __
|__   __|  ____|  __ \|  \/  | |  | \ \ / /
   | |  | |__  | |__) | \  / | |  | |\ V /
   | |  |  __| |  _  /| |\/| | |  | | > <
   | |  | |____| | \ \| |  | | |__| |/ . \
   |_|  |______|_|  \_\_|  |_|\____//_/ \_\
  ────── Easy Package Manager · v2.0 ──────
```

> With `gum` installed, the banner renders inside a double-border box in your chosen theme colors. The art is stored gzip-compressed in one line of `manager.sh` and decompressed at runtime — always pixel-accurate, never hand-drawn.

---

## 📑 Table of Contents

- [Highlights](#-highlights)
- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Backup / restore workflow](#-backup--restore-workflow)
- [Settings & config](#-settings--config)
- [Removing](#-removing)
- [Project Structure](#-project-structure)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ Highlights

- 🎛️ **37 menu entries** (36 package actions + exit, plus dynamically pinned favorites)
- 🔄 **Upgrade center** — one flow: refresh → pick what to upgrade → autoremove → clean cache
- 👁️ **Simulate before changing** — dry-run previews of install/remove/upgrade (`apt -s`)
- 📊 **Package stats & disk** — installed count, total size, biggest packages, per-directory disk usage, largest files, cache breakdown
- 🗃️ **Cache manager** — clean all or just outdated `.deb` files, browse the cache
- 🌳 **Dependency tools** — recursive dependency tree + orphan (unused package) finder
- 🔍 **Package inspector** — one-screen drill-down: info, dependencies, reverse deps, installed files, hold status
- 🩺 **Maintenance wizard** — on-demand (or on-launch) health pass: upgradable, orphans, broken packages, cache, held
- 📚 **Bulk operations** — install or remove many packages, or multi-select from the live installed/upgradable lists
- ⭐ **Favorites** — bookmark packages, pin them to the main menu, reinstall them all with one tap
- 🗂️ **Package groups** — curated bundles (web dev, python dev, media…) plus your own saved groups
- 📋 **History & log viewer** — filter the log, view errors, **undo** your last removal, re-run past actions
- 🔒 **Quiet mode + safety lock** — skip all confirms, or force confirmations on destructive ops
- 💾 **Backup & restore** your exact package set (perfect for device swaps)
- 📤 **Export/import** your package list as plain text or JSON
- 🔗 **Deep-dive tools** — dependencies, reverse deps, sizes, file lists
- 📌 **Pin/hold packages** so upgrades never break them
- 🩹 **Self-healing** — fix broken dependencies with one tap
- ⚙️ **Persistent settings** — backend, theme, quiet/lock, and safety toggles stored in `~/.pkg-manager.conf`
- 🎨 **4 color themes**, **Nerd Font or emoji icons**, ASCII banner, spinner, confirm dialogs, status banners
- 🛟 **Plain-text fallback** — works even before `gum` is installed (and auto-installs it for you)
- 📋 **Timestamped history** of every action you run

## 🚀 Features

| Category | What you get |
|----------|--------------|
| 📦 **Basic** | Install, uninstall, reinstall/repair, upgrade center, clean cache, autoremove |
| 🔎 **Search** | Smart search (installed markers + install-from-results), upgradable list |
| 👁️ **Preview** | Simulate install / remove / upgrade before doing anything |
| 📊 **Insight** | Package stats & disk drill-down, package inspector, sizes, files, owner |
| 🔗 **Relationships** | Dependency tree, dependencies, reverse dependencies, orphan finder |
| 📌 **Maintenance** | Pin/hold, purge, fix-broken, maintenance wizard (on-demand or on-launch) |
| 📚 **Bulk** | Install/remove many, multi-select from installed/upgradable lists, favorites (pinnable), groups |
| 💾 **Data** | Backup, restore, export (txt/JSON), import |
| 🔧 **Tooling** | Dependency doctor, cache manager, history & log viewer (filter/undo/clear), settings |

## 📋 Requirements

- [Termux](https://termux.dev) — F-Droid or the [GitHub builds](https://github.com/termux/termux-app/releases) (Google Play builds are deprecated)
- `bash` — preinstalled
- `apt` / `dpkg` — preinstalled
- `curl` — needed for the one-liner / manual install (install with `pkg install curl -y`)
- [`gum`](https://github.com/charmbracelet/gum) — **recommended** for the full fancy UI. Auto-detected, and the script can install it for you. Without gum it falls back to a clean text menu.
- **Nerd Font** — **CaskaydiaCove** (recommended) or **FiraCode** (alternative), both bundled in this repo (`fonts/`); the installer lets you pick and installs it safely (atomic temp-file + rename, then `termux-reload-settings`). Without one, switch to emoji icons from **Settings → Icons**.

## 🛠️ Installation

### Option 1 — One-liner (recommended)

```bash
pkg install curl -y
curl -fsSL https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/install.sh | bash
```

This installs `gum` (if missing), downloads the manager to the global **`$PREFIX/bin/pkg-manager`** (`/data/data/com.termux/files/usr/bin` in Termux), and asks which **Nerd Font** to install: **CaskaydiaCove** (recommended) or **FiraCode**. The font is written to a temp file and atomically renamed to `~/.termux/font.ttf` (never overwritten in place — that can crash the renderer), then settings are reloaded. From then on, just type `pkg-manager` to launch it. (When run through the pipe, the installer skips auto-launching — run `pkg-manager` yourself. To pick the font non-interactively, set `FONT=1`, `FONT=2`, or `FONT=skip`.)

### Option 2 — Clone & run

```bash
pkg install git gum curl -y
git clone https://github.com/Mark44928/Easy-Termux-Package-Manager.git
cd Easy-Termux-Package-Manager
chmod +x manager.sh
./manager.sh
```

### Option 3 — Manual

```bash
pkg install curl -y
curl -fsSL https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/manager.sh -o pkg-manager
chmod +x pkg-manager
mv pkg-manager "$PREFIX/bin/"
pkg-manager
```

## 🎮 Usage

Run it any way you like:

```bash
pkg-manager      # installed via install.sh / manual method
./manager.sh     # or run straight from the cloned repo
```

| # | Option | What it does |
|:-:|--------|--------------|
| 1 | 📦 Install a package | `apt install -y <name>` |
| 2 | 🗑️  Uninstall a package | `apt remove -y <name>` |
| 3 | 🔎 Search packages | `apt search <term>` |
| 4 | 📜 List installed packages | `apt list --installed` |
| 5 | 🔧 Reinstall / repair a package | `apt install --reinstall -y <name>` |
| 6 | 🔄 Upgrade center | `apt update`, pick what to upgrade, then `apt autoremove` + `apt clean` |
| 7 | 🧹 Clean download cache | `apt clean` |
| 8 | ℹ️  Show package info | `apt show <name>` |
| 9 | 🧽 Autoremove cleanup | `apt autoremove -y` |
| 10 | 🔗 Dependencies | `apt depends <name>` |
| 11 | 🔃 Reverse deps | `apt rdepends <name>` |
| 12 | ⚖️  Package size | `apt-cache show <name>` |
| 13 | 📁 Installed files | `dpkg -L <name>` |
| 14 | 🏷️  File owner | `dpkg -S <path>` |
| 15 | 📌 Pin / hold packages | `apt-mark hold/unhold` |
| 16 | 🧨 Purge a package | `apt purge -y <name>` |
| 17 | 🩹 Fix broken packages | `apt --fix-broken install -y` |
| 18 | 📈 Upgradable list | `apt list --upgradable` |
| 19 | 💾 Backup installed packages | dump names to `~/pkg-backup-*.txt` |
| 20 | ♻️  Restore from backup | `xargs apt install -y` |
| 21 | 📤 Export package list | plain text, or JSON when `python3` is installed (else auto-falls back to text) |
| 22 | 📥 Import package list | install from any list file |
| 23 | 🔧 Dependency doctor | check/install `gum`, `git`, `curl`, `figlet` |
| 24 | ⚙️  Settings | backend, theme, toggles, quiet mode, safety lock |
| 25 | 📋 History & log viewer | view/filter the log, show errors, undo last removal, clear |
| 26 | 👁️  Simulate a change | `apt install -s` / `remove -s` / `upgrade -s` dry-runs |
| 27 | 📊 Package stats & disk | overview, per-directory disk usage, largest files, cache breakdown |
| 28 | 🗃️  Cache manager | `apt clean`, `apt autoclean`, or browse cached `.deb` files |
| 29 | 🌳 Dependency tools | recursive dependency tree + orphan finder |
| 30 | 📚 Bulk operations | install/remove many, or multi-select from installed/upgradable lists |
| 31 | ⭐ Favorites | add/remove/show, install all, install one, pin to main menu |
| 32 | 🔍 Package inspector | info + dependencies + reverse deps + installed files + hold status in one screen |
| 33 | 🩺 Maintenance wizard | health pass: upgradable, orphans, broken packages, cache, held |
| 34 | 🗂️  Package groups | curated bundles (web dev, python dev, media…) + custom groups |
| 35+ | ⭐ Pinned: *name* | one-tap install of a pinned favorite (appears when Favorites are pinned) |
| 0 | 🚪 Exit | — |

> Labels below use emoji icons; in the app they render as Nerd Font glyphs by default (or emoji if `ICONS=emoji`). Keep the label *text* matching the `OPTION_*` definitions in `manager.sh` — if it changes, update this table too.
>
> Commands assume the default `apt` backend; switch to Termux's `pkg` wrapper anytime from **Settings → Package manager**. Note: the deep-dive & maintenance tools (dependencies, sizes, files, owner, hold, purge, fix-broken, doctor, stats, cache, dependency tree, orphan finder) always call `apt`/`dpkg` directly, even after switching to `pkg`.

### 🏁 First run

1. Install (any option above) and run `pkg-manager`
2. Pick **🔄 Upgrade center** first — refresh lists, upgrade, autoremove, and clean in one flow
3. Visit **⚙️  Settings** to pick your backend (`apt`/`pkg`), color theme, quiet mode, and safety lock
4. Optional: **💾 Backup installed packages** so you can restore later
5. Optional: ⭐ **Favorites** the packages you always want around — pin them to the main menu or reinstall them all from any fresh setup

### 💾 Backup / restore workflow

```bash
# Create a backup (option 19) → ~/pkg-backup-20260802-123456.txt
# On a fresh device:
#   Option 20 → pick the file → confirm → everything reinstalls
# Or restore with a one-liner:
xargs apt install -y < ~/pkg-backup-*.txt
```

### ⚙️ Settings & config

Settings are persisted to `~/.pkg-manager.conf`:

```ini
MGR=apt           # apt or pkg
THEME=green       # green, blue, purple, red
CONFIRM=1         # ask before destructive actions
LOG_ENABLED=1     # write action history
GUM_ENABLED=1     # use the fancy UI
ICONS=nerd        # nerd (font glyphs) or emoji
QUIET=0           # 1 = skip all confirmation prompts
LOCK=0            # 1 = always confirm destructive ops (blocks quiet mode)
STARTUP_CHECK=0   # 1 = run the maintenance wizard on every launch
FAVS_PINNED=0     # 1 = show favorite packages at the end of the main menu
```

Changes made in **Settings** apply immediately; edits to the file itself apply on the next launch.

> **Icons:** the default `nerd` set uses Nerd Fonts glyphs and needs a Nerd Font installed in the terminal. If you see empty boxes, switch to `emoji` from **Settings → Icons** (or set `ICONS=emoji` above).

## 📁 Project Structure

```
Easy-Termux-Package-Manager/
├── fonts/          # CaskaydiaCove + FiraCode Nerd Fonts, Regular (bundled, ~5.4 MB total)
├── install.sh      # installer → global $PREFIX/bin/pkg-manager (uses local manager.sh, else downloads)
├── manager.sh      # the entire app (~1900 lines, single file)
├── tests/          # automated harness (fakebin stubs + 85 tests) — bash tests/run-tests.sh
├── LICENSE         # MIT License
└── README.md       # Docs

~/.termux/font.ttf       # Termux app font (set by the installer's font prompt)
~/.pkg-manager.conf      # settings (created the first time you change a setting)
~/.pkg-manager.log       # action history (created on the first logged action)
~/.pkg-manager-favs      # favorites list (created by the Favorites option)
~/.pkg-manager-groups    # custom package groups (created by Package groups)
~/pkg-backup-*.txt       # backups (created by Backup option)
```

## 🧹 Removing

```bash
rm "$PREFIX/bin/pkg-manager"       # the app
rm ~/.pkg-manager.conf ~/.pkg-manager.log   # its settings & history (optional)
```

## 🤝 Contributing

Found a bug? Have an idea for another option? Open an [issue](https://github.com/Mark44928/Easy-Termux-Package-Manager/issues) or submit a PR. All contributions are welcome.

A few ground rules to keep the docs in sync:

- **Menu labels** in the README table must keep the same text as the `OPTION_*` definitions in `manager.sh` (icons are swapped via the `ICONS` setting).
- **Icons:** new emoji → pick a Nerd Fonts v3 glyph, verify its codepoint against a patched font, and add it to both branches of `init_icons()` in `manager.sh`.
- **Bumping the version** means updating all three: the badge at the top, the ASCII art line (`v2.0`), and the fallback string in `manager.sh` — then regenerate the compressed banner blob.
- Test locally by running `bash manager.sh` in a bare Termux — `gum` is optional and the script degrades gracefully.
- Run the automated suite with `bash tests/run-tests.sh` (fakebin stubs for `apt`/`dpkg`/`gum` + 85 scenario tests).

## 📜 License

Distributed under the [MIT License](LICENSE).

---

<p align="center">
  Made with ❤️ for the Termux community
</p>
