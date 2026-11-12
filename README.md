> This repo is vibe-coded, but AGENTS.md makes this repo stable and it works.

<p align="center">
  <img src="https://img.shields.io/badge/Easy%20Termux%20Pkg%20Manager-v5.3.1-000000?logo=termux" alt="Version">
  <img src="https://img.shields.io/badge/platform-Termux-4EAA25?logo=terminal" alt="Platform">
  <img src="https://img.shields.io/badge/tests-182%20passing-brightgreen" alt="Tests">
  <a href="https://github.com/Mark44928/Easy-Termux-Package-Manager/actions/workflows/ci.yml"><img src="https://github.com/Mark44928/Easy-Termux-Package-Manager/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/single%20file-%7E5.4k%20lines-9cf" alt="Single file">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome">
</p>

# Easy Termux Package Manager

Install, remove, inspect, back up, and repair packages on Termux — without ~ever~ touching a `pkg` or `apt` command ~again.~

Wait that's boring, let's try again.

`apt` or `pkg` for Newbies.

An **fzf-powered, interactive package manager** for [Termux](https://termux.dev) wrapped in one Bash script. Fuzzy-filter through a gorgeous menu, and let the script handle all the scary apt/pkg syntax for you.

```
    ________________  __  ___
   / ____/_  __/ __ \/  |/  /
  / __/   / / / /_/ / /|_/ / 
 / /___  / / / ____/ /  / /  
/_____/ /_/ /_/   /_/  /_/   
```

> The banner art is stored gzip-compressed in one line of `manager.sh` and decompressed at runtime — always pixel-accurate, never hand-drawn.

## ⚡ Quick start

> Up and running in **three commands**:

```bash
pkg install curl -y
curl -fsSL https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/install.sh | bash
pkg-manager
```

The installer drops the app at `$PREFIX/bin/pkg-manager`, then offers to install a **Nerd Font** so the menu glyphs render perfectly. That's it — no config, no fuss.

> **Security note:** the one-liner pipes a remote script straight into `bash`. If you prefer to review it first, use **Option 2 — Clone & run**, or download `install.sh`, read it, then run it.

---

## 📑 Table of Contents

- [Quick start](#-quick-start)
- [Highlights](#-highlights)
- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [fzf pickers](#-fzf-pickers)
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
| 🎛️ **57 menu entries** (57 numbered actions + Exit row) | 🔄 **Upgrade center** — refresh → pick → autoremove → clean in one flow |
| 👁️ **Simulate before changing** — dry-run previews (`apt -s`) | 📊 **Package stats & disk** — sizes, per-dir usage, biggest files, cache breakdown |
| 🗃️ **Cache manager** — clean all or outdated `.deb`s, browse | 🌳 **Dependency tools** — recursive tree + orphan finder |
| 🔍 **Package inspector** — info, deps, reverse deps, files, hold | 🩺 **Maintenance wizard** — on-demand or on-launch health pass |
| 📚 **Bulk operations** — many at once, or multi-select lists | ⭐ **Favorites** — bookmark, pin to menu, reinstall all in one tap |
| 🗂️ **Package groups** — curated bundles + your own saved ones | 📋 **History & log viewer** — filter, charts, errors, **undo** last removal |
| 🔒 **Quiet mode + safety lock** — skip or force all confirms | 💾 **Backup & restore** — your exact package set |
| 📤 **Export/import** — plain text or JSON | 🔗 **Deep-dive tools** — deps, reverse deps, sizes, file lists |
| 📌 **Pin/hold packages** — upgrades never break them | 🩹 **Self-healing** — fix broken dependencies with one tap |
| ⚙️ **Persistent settings** — stored in `~/.pkg-manager.conf` | 🎨 **16 themes** (9 truecolor) + Nerd Font or emoji icons |
| 🛟 **Plain-text fallback** — works without `fzf` | 📋 **Timestamped history** of every action |
| 🆕 **New 4.0** | **Recycle bin** (reinstall from `.deb` offline), **system audit** (health score), **mark manual/auto**, **mirror speed test** (all 65 official mirrors), **watchlist**, **history charts** | 43–47 |
| 🚀 **New 5.0** | **9 real truecolor themes** (Dracula, Catppuccin, Tokyo Night, Nord, Gruvbox, One Dark, Solarized, Everforest, Rosé Pine — official palettes) + **theme hub** (preview all, export to `~/.termux/colors.properties`), **essential toolkit** bundles, **system & network dashboard**, themed text mode, banner status strip, **fzf-first pickers** everywhere | 1–3, 42, 54–57, 58 |
| ⌨️ **Consistent ESC** | ESC cancels everywhere — submenus go back a level, the top menu exits with a goodbye, and the package pickers say `Canceled.` and return (no more typed-name detours). If fzf itself ever breaks, the app explains why and finishes the session in numbered text mode | all views |
| 🖥️ **New 5.1** | **Scriptable CLI**: `--check-updates` lists upgradable packages, `--quiet` prints just the count (for cron/status lines), `--doctor` runs the full system audit and exits — no menu needed | CLI |
| 🧰 **New 5.2** | **live package-info preview panes** in the install/uninstall pickers, a **not-installed-only** install list, uninstall's own finder, a **pre-flight batch preview** (aligned version column, installed-size total, already-present and not-found flags), a **banner that never hides** (it travels inside the picker as its header, so a terminal resize cannot wipe it), and a **text-mode fallback with an explanation** if fzf ever fails | 1, 2, all pickers |
| 🆕 **New 5.3/5.3.1** | the **screen clears** at startup · a **ghost hint** in every picker's input line (with live package counts where they matter) · the menu **list shows the bare action label** while the **preview panel** carries the description, **what the action actually runs** (`apt install …`, `apt purge …`, `dpkg -L …`) and its row number · picker rows **never scroll sideways**: overflow is capped to the pane and fzf itself gets `--no-hscroll --ellipsis=…`, so every row stays anchored at its start (name always readable) instead of showing a `···`-wrapped middle slice · **polished pickers**: whole-row highlight, a slim scrollbar, ranking that prefers matches on the *name* over the description, and **Ctrl-Y copies the highlighted package name** · **one list style everywhere**: text mode uses the same right-aligned `N)` numbering and `❯` prompt in the main menu and every submenu · every submenu picker ends with **⬅️ Back to main menu** and **🚪 Exit pkg-manager** rows (selecting packages and then Back still installs them), and **Ctrl-Q** quits from any picker | 1, 2, all pickers |
| 🔍 **fzf integration** | fzf is a first-class picker: **every package prompt** (reinstall, purge, hold, info, notes, watch, …) opens as a fuzzy finder with the live info preview (ESC cancels back to the menu), multi-select install/uninstall with a **live package-info preview pane** (dpkg status + size-humanized `apt-cache show`, `bat`-colored), an **info pane on the main menu and command palette** describing every entry, search-result multi-pick, and the text-mode menu — all theme-colored, all with ESC fallback to typing | 1–3, 43 |
| 📐 **Screen-adaptive** | the banner and status strip ride inside every picker (they are its header), so they survive a terminal resize; pickers still stay below 100% height (fullscreen fzf switches to the alternate screen and hides them), lists entries top-down in natural order, and moves the preview pane to the side on wide/landscape terminals or below on narrow ones | all fzf views |
| 🧹 **Clean install picker** | only packages you have **not** installed are offered (no more scrolling past 500 installed names); uninstall gets its own finder with installed-only rows and a removal-flavoured preview | 1, 2 |

## 🚀 Features

| Category | What you get | Menu |
|----------|--------------|:----:|
| 📦 **Basic** | Install, uninstall, reinstall/repair, upgrade center, clean cache, autoremove | 1–8 |
| 📜 **Upgradable** | live upgradable list with per-package actions | 17 |
| 👁️ **Preview** | Simulate install / remove / upgrade before doing anything | 24 |
| 📊 **Insight** | Package stats & disk drill-down, package inspector, sizes, files, owner | 11–13, 25, 30 |
| 🔗 **Relationships** | Dependency tree, dependencies, reverse dependencies, orphan finder | 9, 10, 50, 27 |
| 📌 **Maintenance** | Pin/hold, purge, fix-broken, maintenance wizard (on-demand or on-launch) | 14–16, 31 |
| 📚 **Bulk** | Install/remove many, multi-select from installed/upgradable lists, favorites (pinnable), groups | 28, 29, 32 |
| 💾 **Data** | Backup, restore, export (txt/JSON), import | 18–21 |
| 🔧 **Tooling** | Dependency doctor, cache manager, history & log viewer (filter/charts/undo/clear), settings | 22, 23–24, 26, 58 |
| 🆕 **New 3.0** | Local .deb, downgrade, download-only, hold version, file search, changelog, why, notes, snapshot, palette | 34–42 |
| 🆕🆕 **New 4.0** | Watchlist, mirror speed test, system audit, mark manual/auto, recycle bin | 43–47 |
| 🆕 **New 4.1** | Optional repositories, undo last batch, dependency tree, health dashboard, snapshot/diff hub | 48–52 |
| 🚀🚀 **New 5.0** | Real terminal themes (truecolor + Termux `colors.properties` export), theme preview hub, **fzf-first pickers** (install/uninstall multi-select with previews, palette, text menu), **CLI flags** (`--help --version --theme --list-themes --export-theme`), essential toolkit, system & network info, what's-new screen | 1–3, 42, 54–58 |

## 📋 Requirements

- [Termux](https://termux.dev) — F-Droid or the [GitHub builds](https://github.com/termux/termux-app/releases) (Google Play builds are deprecated)
- `bash` — preinstalled
- `apt` / `dpkg` — preinstalled
- `curl` — needed for the one-liner / manual install (install with `pkg install curl -y`)
- [`fzf`](https://github.com/junegunn/fzf) — **the UI**: fuzzy menu, multi-select install/uninstall with previews, palette, and every submenu. Auto-installed by `install.sh`. Disable with `FZF_ENABLED=0` (falls back to the numbered text lists).
- **Nerd Font** — **CaskaydiaCove** (recommended) or **FiraCode** (alternative), both bundled in this repo (`fonts/`); the installer lets you pick and installs it safely (atomic temp-file + rename, then `termux-reload-settings`). Without one, switch to emoji icons from **Settings → Icons**.

## 🛠️ Installation

### Option 1 — One-liner (recommended)

```bash
pkg install curl -y
curl -fsSL https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/install.sh | bash
```

This installs **fzf** (if missing), downloads the manager to the global **`$PREFIX/bin/pkg-manager`** (`/data/data/com.termux/files/usr/bin` in Termux), syntax-checks it, and asks which **Nerd Font** to install: **CaskaydiaCove** (recommended) or **FiraCode**. The font is written to a temp file and atomically renamed to `~/.termux/font.ttf` (never overwritten in place — that can crash the renderer), then settings are reloaded. From then on, just type `pkg-manager` to launch it. (When run through the pipe, the installer skips auto-launching — run `pkg-manager` yourself. To pick the font non-interactively, set `FONT=1`, `FONT=2`, or `FONT=skip`.)

Handy flags for scripted installs:

```bash
bash install.sh --yes                      # no prompts, don't launch the app
bash install.sh --theme dracula            # also write the terminal palette:
                                           #   ~/.termux/colors.properties
bash install.sh --yes --theme catppuccin   # both — for dotfiles / cron setups
```

> `--theme` accepts the truecolor themes only (`pkg-manager --list-themes` shows them all). The previous `colors.properties` is kept as `colors.properties.pkg-manager.bak`; remove it or use **Settings → Themes → Restore** to get your old palette back.

### Option 2 — Clone & run

```bash
pkg install git fzf curl -y
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

### ⌨️ Non-interactive flags

```bash
pkg-manager --help             # full help text
pkg-manager --version          # v5.3.1
pkg-manager --list-themes      # palette preview of all 16 themes
pkg-manager --theme dracula    # set the app theme (writes ~/.pkg-manager.conf)
pkg-manager --export-theme tokyo
                                # write that palette to ~/.termux/colors.properties,
                                # then run: termux-reload-settings
```

> `install.sh --theme <name>` does the export for you right after installing. `--export-theme` accepts truecolor themes only (the 9 "real" palettes); the 8 legacy 256-color themes can't be expressed as a full ANSI table.

### 🔍 fzf pickers

With **fzf** installed it *is* the UI — themed to match the current color scheme (backgrounds, pointer `➜`, marker `✓`). Toggle **Settings → fzf picker** to disable it (falls back to the numbered text lists).

| Where | What you get |
|-------|--------------|
| **Text-mode main menu** | no filter — a right-aligned numbered list (1–58, `0` exits); type a number and press Enter |
| **Install / Uninstall** (1, 2) | multi-select from the not-yet-installed packages (install) or installed packages (uninstall), with a live `apt-cache show` preview, then a batch preview before apt runs. **ESC** / **Back** returns to the menu |
| **Command palette** (42) | fuzzy-find any of the 57 actions |

```bash
fzf -m --layout=reverse --cycle --info=inline \
    --preview='apt-cache show {} | head -n 12' --preview-window='right:45%:wrap'
```

Disable it entirely with `FZF_ENABLED=0` in `~/.pkg-manager.conf` (or `NO_FZF=1` in the environment), or toggle **Settings → fzf picker**. The package list itself is cached under `~/.pkg-manager-fzf-cache` for ~30 minutes, so repeat picks open instantly.

### 📟 The menu at a glance

> **fzf** (installed by default) *is* the UI: type to filter, Enter to run. With neither fzf nor a TTY, just type the number and press Enter.

```text
 ✨ Easy Termux Package Manager · v5.3.1

 1) 📦 Install a package
 2) 🗑️ Uninstall a package
  ⋮
58) ⚙️ Settings
 0) 🚪 Exit
❯
```

### 🧭 Menu map

#### 📦 Core — everyday package actions (1–8)

| # | Option | What it does |
|:-:|--------|--------------|
| 1 | 📦 Install a package | `apt install -y <name>` |
| 2 | 🗑️  Uninstall a package | `apt remove -y <name>` |
| 3 | 📜 List installed packages | `apt list --installed` |
| 4 | 🔧 Reinstall / repair a package | `apt install --reinstall -y <name>` |
| 5 | 🔄 Upgrade center | `apt update`, pick what to upgrade, then `apt autoremove` + `apt clean` |
| 6 | 🧹 Clean download cache | `apt clean` |
| 7 | ℹ️  Show package info | `apt show <name>` |
| 8 | 🧽 Autoremove cleanup | `apt autoremove -y` |

#### 🔗 Relationships & files (9–13)

| # | Option | What it does |
|:-:|--------|--------------|
| 9 | 🔗 Dependencies | `apt depends <name>` |
| 10 | 🔃 Reverse deps | `apt rdepends <name>` |
| 11 | ⚖️  Package size | `apt-cache show <name>` |
| 12 | 📁 Installed files | `dpkg -L <name>` |
| 13 | 🏷️  File owner | `dpkg -S <path>` |

#### 📌 Maintenance & safety (14–16, 31)

| # | Option | What it does |
|:-:|--------|--------------|
| 14 | 📌 Pin / hold packages | `apt-mark hold/unhold` |
| 15 | 🧨 Purge a package | `apt purge -y <name>` |
| 16 | 🩹 Fix broken packages | `apt --fix-broken install -y` |
| 31 | 🩺 Maintenance wizard | health pass: optional `apt update` refresh, upgradable, orphans, broken packages, cache, held |

#### 💾 Data & backup (18–21)

| # | Option | What it does |
|:-:|--------|--------------|
| 18 | 💾 Backup installed packages | dump names to `~/pkg-backup-*.txt` |
| 19 | ♻️  Restore from backup | installs the listed packages (batched into one `apt install`, falls back to per-package reporting on failure) |
| 20 | 📤 Export package list | plain text, or JSON when `python3` is installed (else auto-falls back to text) |
| 21 | 📥 Import package list | install from any list file |

#### 🛠️ Tooling (22–24)

| # | Option | What it does |
|:-:|--------|--------------|
| 22 | 🔧 Dependency doctor | check/install `fzf`, `git`, `curl`, `figlet` |
| 23 | 📋 History & log viewer | view/filter the log (incl. **charts & statistics** — per-day bars, top actions), show errors, undo last removal, clear (undo reads the action log — keep “History log” enabled in Settings) |
| 24 | 👁️  Simulate a change | `apt install -s` / `remove -s` / `upgrade -s` dry-runs |

#### 📊 Insight & upgrades (17, 25–27, 30)

| # | Option | What it does |
|:-:|--------|--------------|
| 17 | 📈 Upgradable list | `apt list --upgradable` |
| 25 | 📊 Package stats & disk | overview, per-directory disk usage, largest files, cache breakdown |
| 26 | 🗃️  Cache manager | `apt clean`, `apt autoclean`, or browse cached `.deb` files |
| 27 | 🌳 Dependency tools | recursive dependency tree + orphan finder |
| 30 | 🔍 Package inspector | info + dependencies + reverse deps + installed files + hold status in one screen |

#### 📚 Bulk, favorites & groups (28–29, 32)

| # | Option | What it does |
|:-:|--------|--------------|
| 28 | 📚 Bulk operations | install/remove many, or multi-select from installed/upgradable lists |
| 29 | ⭐ Favorites | add/remove/show, install all, install one, pin to main menu |
| 32 | 🗂️  Package groups | curated bundles (web dev, python dev, media…) + custom groups |

#### 🆕 New in 3.0 — advanced (34–42)

| # | Option | What it does |
|:-:|--------|--------------|
| 33 | 📁 Local .deb install | `dpkg -i <file>` then `apt --fix-broken install -y` if needed |
| 34 | 🔧 Downgrade package | `apt install <pkg>=<ver>` from `apt-cache madison` |
| 35 | 🗃️ Download only | `apt download` or `apt install --download-only` to cache |
| 36 | 📌 Hold specific version | install chosen version then `apt-mark hold` |
| 37 | 🔎 File search (pre-install) | `apt-file search` / `pkgfile` or `dpkg -S` fallback |
| 38 | 📋 Changelog | `apt changelog` / `apt-get changelog` or `apt show` |
| 39 | 🔗 Why installed | `apt-mark showmanual/showauto` + `apt rdepends` |
| 40 | 📝 User notes | annotate packages in `~/.pkg-manager-notes` (`pkg::note`) |
| 41 | 💾 Snapshot / Diff | full device snapshot as tar (`pkg-list.txt` + favs/groups/conf/notes) to `~/pkg-snapshot-*.tar.gz`, then list/diff/restore/delete snapshots in one hub |
| 42 | 🪄 Command palette | fuzzy-find any of the 57 options with `fzf` |

#### 🆕🆕 New in 4.0 — watch, speed, audit, recycle (43–47)

| # | Option | What it does |
|:-:|--------|--------------|
| 43 | 👁️ Package watchlist | track packages in `~/.pkg-manager-watch`, compare installed vs candidate versions, `termux-notification` summary when updates appear |
| 44 | 🌐 Mirror speed test | times candidate mirrors (official + community), shows a ranked table, optionally rewrites the main repo line in `sources.list` (old file kept as `.bak`) and runs `apt update` |
| 45 | 🛡️ System audit | health score from upgrades, orphans, holds, leftover configs, cache weight and free disk — with a findings list |
| 46 | ☑️ Mark manual / auto | `apt-mark manual/auto`, show manual/auto lists, `apt satisfies` (what provides a virtual package) |
| 47 | 🗑️ Recycle bin | with **Settings → Recycle bin** on, every remove/purge first downloads the `.deb` into `~/pkg-trash/`; restore one or all of them later via `dpkg -i` (+ `apt --fix-broken install`) — no network needed |

> The mirror test only touches the **main** repo line; `root` and `x11` repos in `sources.list.d/` are never modified.

#### 🆕 New in 4.1 — repos, undo, graph, health, snapshot/diff (48–52)

| # | Option | What it does |
|:-:|--------|--------------|
| 48 | 📂 Optional repositories | add/remove `root` and `x11` snippet files under `sources.list.d/` (files are kept as `disabled.bak` before removal), peek the main line |
| 49 | 📋 Undo last batch | audit-logged replay/reverse of the last install/remove/purge batch — pick the entry to invert |
| 50 | 🔗 Dependency tree | colored dependency graph for one package: forward `Depends`/`Recommends`/`Suggests` tree, reverse dependents, and whether it was installed manually or pulled in as a dependency |
| 51 | 🛡️ Health dashboard | combined check: upgradables, broken deps, disk headroom, cache weight, stale locks, dpkg state — with repair suggestions |
| 52 | 💾 Snapshot / Diff | shortcut to the full snapshot hub (same as row 41) |

#### 🚀 New in 5.0 — self-update, toolkit, dashboards (53–57)

| # | Option | What it does |
|:-:|--------|--------------|
| 53 | ⬆️ Update pkg-manager | downloads the latest `manager.sh` from GitHub, syntax-checks it (`bash -n`), then atomically replaces the running copy |
| 54 | ⚡ Essential toolkit | one-tap bundles: Core (git, curl, wget, nano, termux-tools) · Dev (python, nodejs, jq) · Net & security (openssh, rsync, nmap) · Power utils (htop, ripgrep, fd, tree, bat) · or everything |
| 55 | 🌐 System & network info | read-only dashboard: kernel, CPU, RAM, disk, Termux version, batteries via `termux-battery-status`, public IP via curl |
| 56 | 🚀 What's new in v5.3.1 | the changelog screen for this release |

> Self-update replaces the script you are currently running (repo copy or `$PREFIX/bin/pkg-manager`) and asks first — restart the app to use the new version.

#### 🚪 Exit & pinned favorites

| # | Option | What it does |
|:-:|--------|--------------|
| 57 | ⚙️  Settings | backend, **Themes & terminal colors** (theme hub: pick / preview / export palette / restore), icons, toggles, quiet mode, safety lock |
| 60+ | 📍 Pinned: *name* | one-tap install of a pinned favorite (appears when Favorites are pinned) |
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

Inside **⚙️ Settings** (main menu 59, last item) you get: package manager, **Themes & terminal colors** (the single theme entry — opens the theme hub: pick / preview all / apply to Termux / export palette / restore), icons, safety confirms, history log, show config file, quiet mode, safety lock, maintenance on launch, recycle bin, **fzf picker** (on/off), and Back.

Settings are persisted to `~/.pkg-manager.conf`:

```ini
MGR=apt           # apt or pkg
THEME=green       # legacy 256-color: green, blue, purple, red, amber, teal, mono
                  # real truecolor themes (official palettes): nord, dracula, catppuccin,
                  # tokyo, gruvbox, onedark, solarized, everforest, rosepine
                  # truecolor themes can also be exported to ~/.termux/colors.properties
                  # from the theme hub (Settings → Themes & terminal colors) so the
                  # whole Termux terminal matches
CONFIRM=1         # ask before destructive actions
LOG_ENABLED=1     # write action history
ICONS=nerd        # nerd (font glyphs) or emoji
QUIET=0           # 1 = skip all confirmation prompts
LOCK=0            # 1 = always confirm destructive ops (blocks quiet mode)
STARTUP_CHECK=0   # 1 = run the maintenance wizard on every launch
FAVS_PINNED=0     # 1 = show favorite packages at the end of the main menu
RECYCLE=0         # 1 = keep a .deb in ~/pkg-trash before every remove/purge
FZF_ENABLED=1     # 1 = fzf-first pickers (install/uninstall/palette/menu)
```
> `NO_FZF=1` in the environment disables the same code paths without touching the config; handy for tests and slow terminals.

Changes made in **Settings** apply immediately; edits to the file itself apply on the next launch.

> The config is parsed as plain `KEY=VALUE` data (never executed), so a stray line, comment or even a CRLF/Windows-created file is harmless — unknown keys are ignored and invalid values fall back to the defaults above.

> **Icons:** the default `nerd` set uses Nerd Fonts glyphs and needs a Nerd Font installed in the terminal. If you see empty boxes, switch to `emoji` from **Settings → Icons** (or set `ICONS=emoji` above).

## 📁 Project Structure

```
Easy-Termux-Package-Manager/
├── fonts/          # CaskaydiaCove + FiraCode Nerd Fonts, Regular (bundled, ~5.4 MB total)
├── install.sh      # installer → global $PREFIX/bin/pkg-manager (uses local manager.sh, else downloads)
├── manager.sh      # the entire app (~5k lines, single file)
├── Makefile        # dev tasks: run / test / lint / check / install / uninstall / clean
├── tests/          # automated harness (fakebin stubs + 182 tests) — bash tests/run-tests.sh
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

Found a bug? Have an idea for another option? Open an [issue](https://github.com/Mark44928/Easy-Termux-Package-Manager/issues) or submit a PR — see also [CONTRIBUTING.md](CONTRIBUTING.md). All contributors follow the [Code of Conduct](CODE_OF_CONDUCT.md).

A few ground rules to keep the docs in sync:

- **Menu labels** in the README menu-map tables must keep the same text as the `OPTION_*` definitions in `manager.sh` (icons are swapped via the `ICONS` setting).
- **Icons:** new emoji → pick a Nerd Fonts v3 glyph, verify its codepoint against a patched font (all glyphs must exist in `fonts/`), and add it to both branches of `init_icons()` in `manager.sh`. Bash escapes: `$'\uXXXX'` accepts **4** hex digits only — use `$'\U000XXXXX'` (8 digits, zero-padded) for codepoints above U+FFFF, e.g. `md-hand_wave` is `$'\U000F1821'`.
- **Bumping the version** means updating every place the name appears: the badge, the menu snapshot, the installer banner (`install.sh`), the `VERSION` string in `manager.sh`, and the two README banner blocks. The banner art itself carries no version (the status strip prints it) — regenerate it only when the wordmark changes:
  ```bash
  art=$(figlet -f slant "ETPM" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
  b64=$(printf '%s' "$art" | gzip -9 | base64 -w0)
  # then replace BANNER_B64="..." in manager.sh with $b64
  ```
- Test locally by running `bash manager.sh` in a bare Termux — `fzf` is optional and the script degrades to numbered lists.
- Run `make lint` (`bash -n` + shellcheck) after every edit — it takes seconds.
- Run the full suite only at the end of a cross-cutting change: `bash tests/run-tests.sh` (fakebin stubs for `apt`/`dpkg`/`fzf` + 182 scenario tests, ~6 min). It has no per-test filter, so don't use it as a routine check.

### 🛠️ Make targets (developers)

Termux needs `pkg install make shellcheck` once. From the repo root:

| Command | What it does |
|---------|--------------|
| `make` / `make help` | list targets |
| `make run` | launch the app (`NO_FZF=1 make run` for text mode) |
| `make test` | full 182-test suite (~6 min, fakebin — no real apt) — **run it at the end, not per edit** |
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
    ________________  __  ___
   / ____/_  __/ __ \/  |/  /
  / __/   / / / /_/ / /|_/ / 
 / /___  / / / ____/ /  / /  
/_____/ /_/ /_/   /_/  /_/   
```

**Easy Termux Package Manager** · v5.3.1 · MIT

Made with ❤️ for the Termux community — found a bug? [open an issue](https://github.com/Mark44928/Easy-Termux-Package-Manager/issues), have an idea? ship a PR.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/Mark44928/Easy-Termux-Package-Manager/pulls)

</div>
