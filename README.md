> This repo is vibe-coded, but AGENTS.md makes this repo stable and it works.

<p align="center">
  <img src="https://img.shields.io/badge/Easy%20Termux%20Pkg%20Manager-v4.0-000000?logo=termux" alt="Version">
  <img src="https://img.shields.io/badge/gum--powered-3DDC84?logo=gum" alt="gum powered">
  <img src="https://img.shields.io/badge/platform-Termux-4EAA25?logo=terminal" alt="Platform">
  <img src="https://img.shields.io/badge/tests-169%20passing-brightgreen" alt="Tests">
</p>
<p align="center">
  <img src="https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/single%20file-%7E2.7k%20lines-9cf" alt="Single file">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome">
</p>

# Easy Termux Package Manager

Install, remove, search, inspect, back up, and repair packages on Termux — without ~ever~ touching a `pkg` or `apt` command ~again.~

Wait that's boring, let's try again.

`apt` or `pkg` for Newbies.

A **gum-powered, interactive package manager** for [Termux](https://termux.dev) wrapped in one Bash script. Arrow-key through a gorgeous menu, and let the script handle all the scary apt/pkg syntax for you.

```
 _______ ______ _____  __  __ _    ___   __
|__   __|  ____|  __ \|  \/  | |  | \ \ / /
   | |  | |__  | |__) | \  / | |  | |\ V /
   | |  |  __| |  _  /| |\/| | |  | | > <
   | |  | |____| | \ \| |  | | |__| |/ . \
    |_|  |______|_|  \_\_|  |_|\____//_/ \_\
  ────── Easy Package Manager · v4.0 ────── 
```

> With `gum` installed, the banner renders inside a double-border box in your chosen theme colors. The art is stored gzip-compressed in one line of `manager.sh` and decompressed at runtime — always pixel-accurate, never hand-drawn.

## ⚡ Quick start

> Up and running in **three commands**:

```bash
pkg install curl -y
curl -fsSL https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/install.sh | bash
pkg-manager
```

The installer drops the app at `$PREFIX/bin/pkg-manager`, then offers to install a **Nerd Font** so the menu glyphs render perfectly. That's it — no dependencies, no config, no fuss.

---

## 📑 Table of Contents

- [Quick start](#-quick-start)
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

| | |
|--|--|
| 🎛️ **51 menu entries** (50 actions + exit, plus pinned favorites) | 🔄 **Upgrade center** — refresh → pick → autoremove → clean in one flow |
| 👁️ **Simulate before changing** — dry-run previews (`apt -s`) | 📊 **Package stats & disk** — sizes, per-dir usage, biggest files, cache breakdown |
| 🗃️ **Cache manager** — clean all or outdated `.deb`s, browse | 🌳 **Dependency tools** — recursive tree + orphan finder |
| 🔍 **Package inspector** — info, deps, reverse deps, files, hold | 🩺 **Maintenance wizard** — on-demand or on-launch health pass |
| 📚 **Bulk operations** — many at once, or multi-select lists | ⭐ **Favorites** — bookmark, pin to menu, reinstall all in one tap |
| 🗂️ **Package groups** — curated bundles + your own saved ones | 📋 **History & log viewer** — filter, charts, errors, **undo** last removal |
| 🔒 **Quiet mode + safety lock** — skip or force all confirms | 💾 **Backup & restore** — your exact package set |
| 📤 **Export/import** — plain text or JSON | 🔗 **Deep-dive tools** — deps, reverse deps, sizes, file lists |
| 📌 **Pin/hold packages** — upgrades never break them | 🩹 **Self-healing** — fix broken dependencies with one tap |
| ⚙️ **Persistent settings** — stored in `~/.pkg-manager.conf` | 🎨 **8 themes** + Nerd Font or emoji icons |
| 🛟 **Plain-text fallback** — works even before `gum` | 📋 **Timestamped history** of every action |
| 🆕 **New 4.0** | **Self-update**, **recycle bin** (reinstall from `.deb` offline), **system audit** (health score), **mark manual/auto**, **mirror speed test**, **watchlist**, **history charts** | 45–50 |

## 🚀 Features

| Category | What you get | Menu |
|----------|--------------|:----:|
| 📦 **Basic** | Install, uninstall, reinstall/repair, upgrade center, clean cache, autoremove | 1–9 |
| 🔎 **Search** | Smart search (installed markers + install-from-results), upgradable list | 3, 18 |
| 👁️ **Preview** | Simulate install / remove / upgrade before doing anything | 26 |
| 📊 **Insight** | Package stats & disk drill-down, package inspector, sizes, files, owner | 12–14, 27, 32 |
| 🔗 **Relationships** | Dependency tree, dependencies, reverse dependencies, orphan finder | 10, 11, 29 |
| 📌 **Maintenance** | Pin/hold, purge, fix-broken, maintenance wizard (on-demand or on-launch) | 15–17, 33 |
| 📚 **Bulk** | Install/remove many, multi-select from installed/upgradable lists, favorites (pinnable), groups | 30, 31, 34 |
| 💾 **Data** | Backup, restore, export (txt/JSON), import | 19–22 |
| 🔧 **Tooling** | Dependency doctor, cache manager, history & log viewer (filter/charts/undo/clear), settings | 23–25, 28 |
| 🆕 **New 3.0** | Local .deb, downgrade, download-only, hold version, file search, changelog, why, notes, snapshot, palette | 35–44 |
| 🆕🆕 **New 4.0** | Watchlist, mirror speed test, system audit, mark manual/auto, recycle bin, self-update | 45–50 |

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

### 📟 The menu at a glance

> With **gum** installed you arrow-key through the menu; without it, just type a number and press Enter.

```text
 ✨ Easy Termux Package Manager · v4.0

 [1]  📦 Install a package
 [2]  🗑️ Uninstall a package
 [3]  🔎 Search packages
  ⋮
 [44] 🪄 Command palette
 [0]  🚪 Exit
 Choose an option:
```

### 🧭 Menu map

#### 📦 Core — everyday package actions (1–9)

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

#### 🔗 Relationships & files (10–14)

| # | Option | What it does |
|:-:|--------|--------------|
| 10 | 🔗 Dependencies | `apt depends <name>` |
| 11 | 🔃 Reverse deps | `apt rdepends <name>` |
| 12 | ⚖️  Package size | `apt-cache show <name>` |
| 13 | 📁 Installed files | `dpkg -L <name>` |
| 14 | 🏷️  File owner | `dpkg -S <path>` |

#### 📌 Maintenance & safety (15–17, 33)

| # | Option | What it does |
|:-:|--------|--------------|
| 15 | 📌 Pin / hold packages | `apt-mark hold/unhold` |
| 16 | 🧨 Purge a package | `apt purge -y <name>` |
| 17 | 🩹 Fix broken packages | `apt --fix-broken install -y` |
| 33 | 🩺 Maintenance wizard | health pass: upgradable, orphans, broken packages, cache, held |

#### 💾 Data & backup (19–22)

| # | Option | What it does |
|:-:|--------|--------------|
| 19 | 💾 Backup installed packages | dump names to `~/pkg-backup-*.txt` |
| 20 | ♻️  Restore from backup | installs the listed packages (batched into one `apt install`, falls back to per-package reporting on failure) |
| 21 | 📤 Export package list | plain text, or JSON when `python3` is installed (else auto-falls back to text) |
| 22 | 📥 Import package list | install from any list file |

#### 🛠️ Tooling (23–26)

| # | Option | What it does |
|:-:|--------|--------------|
| 23 | 🔧 Dependency doctor | check/install `gum`, `git`, `curl`, `figlet` |
| 24 | ⚙️  Settings | backend, theme, toggles, quiet mode, safety lock |
| 25 | 📋 History & log viewer | view/filter the log (incl. **charts & statistics** — per-day bars, top actions), show errors, undo last removal, clear (undo reads the action log — keep “History log” enabled in Settings) |
| 26 | 👁️  Simulate a change | `apt install -s` / `remove -s` / `upgrade -s` dry-runs |

#### 📊 Insight & upgrades (18, 27–29, 32)

| # | Option | What it does |
|:-:|--------|--------------|
| 18 | 📈 Upgradable list | `apt list --upgradable` |
| 27 | 📊 Package stats & disk | overview, per-directory disk usage, largest files, cache breakdown |
| 28 | 🗃️  Cache manager | `apt clean`, `apt autoclean`, or browse cached `.deb` files |
| 29 | 🌳 Dependency tools | recursive dependency tree + orphan finder |
| 32 | 🔍 Package inspector | info + dependencies + reverse deps + installed files + hold status in one screen |

#### 📚 Bulk, favorites & groups (30–31, 34)

| # | Option | What it does |
|:-:|--------|--------------|
| 30 | 📚 Bulk operations | install/remove many, or multi-select from installed/upgradable lists |
| 31 | ⭐ Favorites | add/remove/show, install all, install one, pin to main menu |
| 34 | 🗂️  Package groups | curated bundles (web dev, python dev, media…) + custom groups |

#### 🆕 New in 3.0 — advanced (35–44)

| # | Option | What it does |
|:-:|--------|--------------|
| 35 | 📁 Local .deb install | `dpkg -i <file>` then `apt --fix-broken install -y` if needed |
| 36 | 🔧 Downgrade package | `apt install <pkg>=<ver>` from `apt-cache madison` |
| 37 | 🗃️ Download only | `apt download` or `apt install --download-only` to cache |
| 38 | 📌 Hold specific version | install chosen version then `apt-mark hold` |
| 39 | 🔎 File search (pre-install) | `apt-file search` / `pkgfile` or `dpkg -S` fallback |
| 40 | 📋 Changelog | `apt changelog` / `apt-get changelog` or `apt show` |
| 41 | 🔗 Why installed | `apt-mark showmanual/showauto` + `apt rdepends` |
| 42 | 📝 User notes | annotate packages in `~/.pkg-manager-notes` (`pkg::note`) |
| 43 | 💾 Full snapshot | tar `pkg-list.txt` + favs/groups/conf/notes to `~/pkg-snapshot-*.tar.gz` |
| 44 | 🪄 Command palette | `gum filter` fuzzy finder across all 50 options |

#### 🆕🆕 New in 4.0 — watch, speed, audit, recycle (45–50)

| # | Option | What it does |
|:-:|--------|--------------|
| 45 | 👁️ Package watchlist | track packages in `~/.pkg-manager-watch`, compare installed vs candidate versions, `termux-notification` summary when updates appear |
| 46 | 🌐 Mirror speed test | times candidate mirrors (official + community), shows a ranked table, optionally rewrites the main repo line in `sources.list` (old file kept as `.bak`) and runs `apt update` |
| 47 | 🛡️ System audit | health score from upgrades, orphans, holds, leftover configs, cache weight and free disk — with a findings list |
| 48 | ☑️ Mark manual / auto | `apt-mark manual/auto`, show manual/auto lists, `apt satisfies` (what provides a virtual package) |
| 49 | 🗑️ Recycle bin | with **Settings → Recycle bin** on, every remove/purge first downloads the `.deb` into `~/pkg-trash/`; restore one or all of them later via `dpkg -i` (+ `apt --fix-broken install`) — no network needed |
| 50 | ⬆️ Update pkg-manager | downloads the latest `manager.sh` from GitHub, syntax-checks it (`bash -n`), then atomically replaces the running copy |

> The mirror test only touches the **main** repo line; `root` and `x11` repos in `sources.list.d/` are never modified. Self-update replaces the script you are currently running (repo copy or `$PREFIX/bin/pkg-manager`) and asks first — restart the app to use the new version.

#### 🚪 Exit & pinned favorites

| # | Option | What it does |
|:-:|--------|--------------|
| 45+ | 📍 Pinned: *name* | one-tap install of a pinned favorite (appears when Favorites are pinned) |
| 0 | 🚪 Exit | — |

> Labels above use emoji icons; in the app they render as Nerd Font glyphs by default (or emoji if `ICONS=emoji`). Keep the label *text* matching the `OPTION_*` definitions in `manager.sh` — if it changes, update these tables too.
>
> Commands assume the default `apt` backend; switch to Termux's `pkg` wrapper anytime from **Settings → Package manager**. Note: the inspect & dependency tools (dependencies, sizes, files, owner, hold, purge, fix-broken, stats, cache, dependency tree, orphan finder, maintenance) call `apt`/`dpkg` directly where `pkg` has no equivalent subcommand; plain install/remove/upgrade/clean always respect your chosen backend.

### 🏁 First run

1. Install (any option above) and run `pkg-manager`
2. Pick **🔄 Upgrade center** first — refresh lists, upgrade, autoremove, and clean in one flow
3. Visit **⚙️  Settings** to pick your backend (`apt`/`pkg`), color theme, quiet mode, and safety lock
4. Optional: **💾 Backup installed packages** so you can restore later
5. Optional: ⭐ **Favorites** the packages you always want around — pin them to the main menu or reinstall them all from any fresh setup

### 💾 Backup / restore workflow

```bash
# Create a backup (option 19) → ~/pkg-backup-20260802-123456-<pid>.txt
# On a fresh device:
#   Option 20 → pick the file → confirm → everything reinstalls
# Or restore with a one-liner (the app batches the same way):
tr ' ' '\n' < ~/pkg-backup-*.txt | xargs apt install -y
```

### ⚙️ Settings & config

Settings are persisted to `~/.pkg-manager.conf`:

```ini
MGR=apt           # apt or pkg
THEME=green       # green, blue, purple, red, nord, amber, teal, mono
CONFIRM=1         # ask before destructive actions
LOG_ENABLED=1     # write action history
GUM_ENABLED=1     # use the fancy UI
ICONS=nerd        # nerd (font glyphs) or emoji
QUIET=0           # 1 = skip all confirmation prompts
LOCK=0            # 1 = always confirm destructive ops (blocks quiet mode)
STARTUP_CHECK=0   # 1 = run the maintenance wizard on every launch
FAVS_PINNED=0     # 1 = show favorite packages at the end of the main menu
RECYCLE=0         # 1 = keep a .deb in ~/pkg-trash before every remove/purge
```

Changes made in **Settings** apply immediately; edits to the file itself apply on the next launch.

> The config is parsed as plain `KEY=VALUE` data (never executed), so a stray line, comment or even a CRLF/Windows-created file is harmless — unknown keys are ignored and invalid values fall back to the defaults above.

> **Icons:** the default `nerd` set uses Nerd Fonts glyphs and needs a Nerd Font installed in the terminal. If you see empty boxes, switch to `emoji` from **Settings → Icons** (or set `ICONS=emoji` above).

## 📁 Project Structure

```
Easy-Termux-Package-Manager/
├── fonts/          # CaskaydiaCove + FiraCode Nerd Fonts, Regular (bundled, ~5.4 MB total)
├── install.sh      # installer → global $PREFIX/bin/pkg-manager (uses local manager.sh, else downloads)
├── manager.sh      # the entire app (~3.4k lines, single file)
├── Makefile        # dev tasks: run / test / lint / check / install / uninstall / clean
├── tests/          # automated harness (fakebin stubs + 169 tests) — bash tests/run-tests.sh
├── LICENSE         # MIT License
└── README.md       # Docs

~/.termux/font.ttf       # Termux app font (set by the installer's font prompt)
~/.pkg-manager.conf      # settings (created the first time you change a setting)
~/.pkg-manager.log       # action history (created on the first logged action)
~/.pkg-manager-favs      # favorites list (created by the Favorites option)
~/.pkg-manager-groups    # custom package groups (created by Package groups)
~/.pkg-manager-notes     # user notes (created by User notes option)
~/.pkg-manager-watch     # watchlist, one package per line (created by Package watchlist)
~/pkg-trash/*.deb        # recycle bin: .debs kept before removals (created by removals when RECYCLE=1)
~/pkg-backup-*.txt       # backups (created by Backup option)
~/pkg-snapshot-*.tar.gz  # full snapshots (created by Full snapshot option)
```

## 🧹 Removing

```bash
rm "$PREFIX/bin/pkg-manager"       # the app
rm ~/.pkg-manager.conf ~/.pkg-manager.log   # its settings & history (optional)
```

## 🤝 Contributing

Found a bug? Have an idea for another option? Open an [issue](https://github.com/Mark44928/Easy-Termux-Package-Manager/issues) or submit a PR. All contributions are welcome.

A few ground rules to keep the docs in sync:

- **Menu labels** in the README menu-map tables must keep the same text as the `OPTION_*` definitions in `manager.sh` (icons are swapped via the `ICONS` setting).
- **Icons:** new emoji → pick a Nerd Fonts v3 glyph, verify its codepoint against a patched font (all glyphs must exist in `fonts/`), and add it to both branches of `init_icons()` in `manager.sh`. Bash escapes: `$'\uXXXX'` accepts **4** hex digits only — use `$'\U000XXXXX'` (8 digits, zero-padded) for codepoints above U+FFFF, e.g. `md-hand_wave` is `$'\U000F1821'`.
- **Bumping the version** means updating every place the name appears: the badge, both ASCII art lines, the menu snapshot, the installer banner (`install.sh`), and the fallback string in `manager.sh` — then regenerate the compressed banner blob.
- Test locally by running `bash manager.sh` in a bare Termux — `gum` is optional and the script degrades gracefully.
- Run the automated suite with `bash tests/run-tests.sh` (fakebin stubs for `apt`/`dpkg`/`gum` + 169 scenario tests).

### 🛠️ Make targets (developers)

Termux needs `pkg install make shellcheck` once. From the repo root:

| Command | What it does |
|---------|--------------|
| `make` / `make help` | list targets |
| `make run` | launch the app (`GUM_ENABLED=0 make run` for text mode) |
| `make test` | full 169-test suite (~3 min, fakebin — no real apt) |
| `make lint` | `bash -n` + `shellcheck --severity=style` on every shell script |
| `make check` | lint + test |
| `make install` | run `install.sh` → `$PREFIX/bin/pkg-manager` |
| `make uninstall` | remove `$PREFIX/bin/pkg-manager` |
| `make clean` | delete `tests/tmp/` artifacts |

## 📜 License

Distributed under the [MIT License](LICENSE).

---

<div align="center">

```
 _______ ______ _____  __  __ _    ___   __
|__   __|  ____|  __ \|  \/  | |  | \ \ / /
   | |  | |__  | |__) | \  / | |  | |\ V /
   | |  |  __| |  _  /| |\/| | |  | | > <
   | |  | |____| | \ \| |  | | |__| |/ . \
    |_|  |______|_|  \_\_|  |_|\____//_/ \_\
  ────── Easy Package Manager · v4.0 ────── 
```

**Easy Termux Package Manager** · v4.0 · MIT

Made with ❤️ for the Termux community — found a bug? [open an issue](https://github.com/Mark44928/Easy-Termux-Package-Manager/issues), have an idea? ship a PR.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/Mark44928/Easy-Termux-Package-Manager/pulls)

</div>
