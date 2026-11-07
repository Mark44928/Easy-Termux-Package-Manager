# AGENTS.md — Easy-Termux-Package-Manager

> **This is Termux, not Linux.** Bionic libc (not glibc), no FHS filesystem, no root. `$PREFIX` = `/data/data/com.termux/files/usr`. All standard Linux assumptions can break here. `manager.sh` is a single-file Bash app (~4.4k lines); `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`/`apt`/`fzf`. CI: `.github/workflows/ci.yml` (lint + tests on ubuntu-latest — the suite is hermetic).

## Make

| Target | What |
|--------|------|
| `make run` | Launch app (text mode: `NO_FZF=1 make run`) |
| `make test` | Full test suite (159 tests, ~3 min, text + fzf modes) |
| `make lint` | `bash -n` + `shellcheck` (0 findings; SC2015/SC2119/SC2120 ignored) |
| `make check` | Lint + test |
| `make install` / `make uninstall` | Via `install.sh` / `rm $PREFIX/bin/pkg-manager` |
| `make clean` | Delete `tests/tmp/` |

```bash
export TMPDIR=/data/data/com.termux/files/usr/tmp
bash manager.sh
bash tests/run-tests.sh
```

Tests use `tests/fakebin/` stubs for `apt`/`pkg`/`dpkg`/`dpkg-query`/`apt-cache`/`apt-mark`/`fzf`/`curl`/`python3` — no real Termux or package changes. 160 scenario tests; `tests/tmp/` is gitignored. fzf answers come from `FZF_QUEUE` (plain lines, `MULTI:` prefix splits into several selections; fake aborts with exit 1 when empty = ESC → typed fallback).

## Hard Rules

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as text KEY=VALUE (`manager.sh:50-88`). Never `source` user files (option injection / RCE risk).
- **Temp files via `scratch_new()` only** — uses `mktemp`, cleaned by EXIT trap. Never `/tmp/foo`.
- **Package name validation via `valid_pkg_name()`** — rejects leading `-`, spaces, shell metacharacters. Use before ANY user name hits `apt`/`dpkg`.
- **Always quote `$MGR`** (apt or pkg) — unquoted breaks on word splitting.
- **fzf or text** — every feature works with fzf (default) or the numbered text lists (when fzf is disabled). Tests check both paths.
- **Call `apt_hint()` after every apt operation** — translates raw apt/dpkg errors to friendly messages (`manager.sh:586-608`).
- **Run `filter_pkgs()` before any user input hits apt** — calls `valid_pkg_name()`, strips invalid names. Critical for preventing option injection.
- **Never `set -e`** — `manager.sh` uses `set -o pipefail` only; `set -e` breaks the menu loop.

## Code Structure

| File | Role |
|------|------|
| `manager.sh` | The entire app (~4.4k lines) |
| `install.sh` | Installer (atomic writes: `.tmp` → `mv`), offers Nerd Font |
| `Makefile` | Dev targets (`run`/`test`/`lint`/`check`/`install`/`uninstall`/`clean`) |
| `fonts/` | Bundled Nerd Font TTFs (CaskaydiaCove, FiraCode) |
| `tests/fakebin/` | Stubs for `apt`, `dpkg`, `fzf`, `curl`, etc. |
| `tests/seeds/` | Per-test seed data |


## Architecture

- **Config precedence:** env overrides → config file → hardcoded defaults (`manager.sh:18-27`, `90-140`), all validated via case statements. Config keys: `MGR THEME CONFIRM LOG_ENABLED ICONS QUIET LOCK STARTUP_CHECK FAVS_PINNED RECYCLE FZF_ENABLED`.
- **Confirmation (3-layer):** `CONFIRM=1` (normal) → `QUIET=1` (skip all) → `LOCK=1` (force even if QUIET). `confirm_danger()` checks LOCK first.
- **Main loop** (`manager.sh:4284+`): `while true`; first iteration runs `do_maintenance` if `STARTUP_CHECK=1`; `pause` after each action. Pinned favorites dispatched via `*"Pinned:"*` glob. Menu items 1–59 (Settings last, at 59) + pinned at 60+; the theme hub lives in Settings as its own row (`OPTION_THEME`, `do_theme`), not in the main menu.
- **`run_multi_op()`** (`manager.sh:615-665`): batch fast path (single `apt install/remove -y`), falls back to per-package retry on failure. `RECYCLE=1` + remove → `archive_pkg()` first.
- **Logging:** `log()` successes only, `log_err()` failures (`manager.sh:431-441`, both to `~/.pkg-manager.log`). Undo reads log via `grep`.
- **UI:** fzf is the sole interactive picker. Every `do_*` submenu routes through `pick_menu`/`pick_multi`/`pick_one`, which prefer fzf then fall back to the original numbered text lists — so text-mode output and numbering are unchanged.
- **Submenus:** every `do_*` submenu routes through `pick_menu`/`pick_multi`/`pick_one`, which prefer fzf then fall back to the original numbered text lists — so text-mode output and numbering are unchanged.
- **fzf layer:** `have_fzf()` checks `FZF_ENABLED=1` + `NO_FZF!=1` + `command -v fzf`. fzf is the sole interactive UI (gum is gone): `main_menu`, `do_palette`, `do_search` result pick, `do_install`/`do_uninstall` (via `use_fzf_for_op`), and every submenu via `pick_menu`/`pick_multi`/`pick_one`. Abort (ESC) returns `FZF_ABORTED=1` so install/uninstall fall back to the typed-name prompt, and menus fall back to numbers. Theme via `fzf_theme()`/`fzf_select()`. Uninstall picks from `dpkg-query`, install from a cached `~/.pkg-manager-fzf-cache` (30 min TTL). Settings row 12 toggles `FZF_ENABLED` (on/off).
- **CLI mode:** `--help --version --list-themes --theme <n> --export-theme <n>` are parsed before the main loop (`CLI_MODE`) and exit before `FIRST_LOOP`. `install.sh --theme <n>` calls `pkg-manager --export-theme <n>` so palettes live in one place.

## Data Files (all in `$HOME`)

| File | Format | Source |
|------|--------|--------|
| `~/.pkg-manager.conf` | KEY=VALUE | `save_config()` |
| `~/.pkg-manager.log` | `[datetime] action` / `FAIL: action` | `log()` |
| `~/.pkg-manager-favs` | One pkg/line | Favorites |
| `~/.pkg-manager-groups` | `name::pkg1 pkg2` | Package groups |
| `~/pkg-backup-*.txt` | One pkg/line | Backup |
| `~/pkg-export.{txt,json}` | Text or `{"packages":[...]}` | Export |
| `~/.pkg-manager-notes` | `pkg::note` | Notes |
| `~/.pkg-manager-watch` | One pkg/line | Watchlist |
| `~/pkg-trash/*.deb` | .deb files | Recycle bin (RECYCLE=1) |
| `~/pkg-snapshot-*.tar.gz` | tar of all | Full snapshot |
| `~/.pkg-manager-fzf-cache` | available-package list | fzf picker cache (30 min TTL) |
| `~/.pkg-manager-audit.log` | `batch_start/end` lines | Undo engine |
| `~/.termux/colors.properties` | Termux palette | Theme hub export (`.pkg-manager.bak` = previous) |

## Key Functions

| Function | Purpose |
|----------|---------|
| `load_config()` | Parse KEY=VALUE from `~/.pkg-manager.conf` |
| `save_config()` | Write config file |
| `valid_pkg_name()` | Reject option-injection / shell metachars |
| `filter_pkgs()` | Call `valid_pkg_name()`, strip invalid names |
| `run_multi_op()` | Batch apt install/remove with per-package fallback |
| `apt_hint()` | Translate apt/dpkg errors to friendly messages |
| `scratch_new()` | mktemp-based temp file creation (EXIT trap cleanup) |
| `build_menu()` | Rebuild menu (called after favs change if `FAVS_PINNED=1`) |
| `dep_tree()` | Dependency resolver, depth capped at 4 (`manager.sh:1386`) |
| `have_fzf()` | FZF_ENABLED + NO_FZF + command lookup — gate for every fzf path |
| `fzf_theme()` / `fzf_select()` | theme-colored picker + generic multi-select |
| `pick_menu()` / `pick_multi()` / `pick_one()` | submenu pickers (fixed items / multi list / stdin list) — fzf first, then the original numbered text list |
| `fzf_pick_pkgs()` / `use_fzf_for_op()` | package pickers; sets `FZF_ABORTED` on ESC |
| `paint()` / `set_theme()` / `theme_ansi()` | color engine: 256-index + `#RRGGBB` truecolor |
| `apply_termux_theme()` | export palette to `~/.termux/colors.properties` (backup first) |
| `do_theme()` / `do_essentials()` / `do_sysinfo()` / `do_whatsnew()` | v5.0 hubs (55–58; theme hub also in Settings) |

## Gotchas

- Banner art is gzip-compressed, base64 in `BANNER_B64` (`manager.sh:246`). Re-compress after editing.
- `install.sh` uses atomic writes (`.tmp` → `mv`) — never overwrite in place.
- `set -o pipefail` active — pipelines fail on first error.
- `log()` records successes only; `log_err()` for failures.
- Tests set `ICONS=emoji` via env. Input via stdin (text). `NO_FZF=1` is the default; only the `F()` tests unset it and feed `FZF_QUEUE`.
- Group delimiter is `::` (`manager.sh:2250-2260`), names sanitized to `[A-Za-z0-9 _-]`.
- `FAVS_PINNED=1` triggers `build_menu()` after favorites changes.
- JSON export requires `python3`; falls back to text.
- Bash functions must be DEFINED before `FIRST_LOOP=1` — the `while true` loop only executes top-level code linearly, so anything defined after it is undefined inside the loop. The MAX-4.1 block (fzf cache, `do_repos`, `do_undo`, `do_health`, `do_auto_mirror`, `do_snapshot`) was moved above the loop in v5.0; keep new handlers there.
- Settings rows: text-menu `case "$choice"` numbers 1–13 (11 = fzf picker on/off, 12 = Themes & terminal colors, 13 = Back). Adding a row reshuffles all numbers — update both branches and every test that feeds one.
- `have_fzf` returns false for every test unless `NO_FZF` is unset, so the real fzf never blocks the suite; `tests/fakebin/fzf` answers `FZF_QUEUE` (one line per call, `MULTI:` = several), and exits 1 with no output to emulate ESC.

- `list_upgradable()` returns apt's real exit code — distinguish empty from failure.

## Version Bump

Update version string in: README badges + ASCII art (×2) + menu snapshot text, `install.sh` banner, and fallback string (`manager.sh:251`). Then regenerate `BANNER_B64` (compressed blob).

## Termux: Critical Path Mapping

| Linux FHS | Termux (`$PREFIX`) |
|-----------|---------------------|
| `/bin`, `/usr/bin` | `$PREFIX/bin` |
| `/etc` | `$PREFIX/etc` |
| `/tmp` | `$PREFIX/tmp` (wiped on app restart) |
| `/var/lib/dpkg/status` | `$PREFIX/var/lib/dpkg/status` |
| `/var/cache/apt/archives` | `$PREFIX/var/cache/apt/archives` |

**Three app variants exist** (F-Droid, GitHub, Play Store) — mutually incompatible APK signing keys. Plugins must match. Play Store builds are deprecated (equivalent to v0.108). Official sources: F-Droid + GitHub only.

## apt/pkg Gotchas

- `pkg` wraps `apt`: auto-runs `apt update` before installs, handles mirrors. `apt` does not auto-update. Use `apt-get` for scripting.
- `pkg` has no equivalent for `purge`, `autoremove`, `list --upgradable`, `install -f` — must call `apt` directly (this app already does).
- **dpkg lock errors:** interrupted ops leave stale locks. Recover: `dpkg --configure -a` → `apt --fix-broken install`.
- **`apt upgrade`** can break Termux on transitions. Prefer `pkg upgrade` or `apt full-upgrade`.
- **Busybox deprecation:** Termux replacing busybox with standalone packages. Removing busybox before replacements installed = broken environment.
- Config prompts during upgrade: use `-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"`.

## Shell Behavior (Termux/Bionic)

- `~/.bashrc` may source twice — guard with `if ! shopt -q login_shell`.
- Bash regex = Bionic POSIX (BSD-derived), not GNU: `|` at start/end of alternation is invalid. Use `(a|b)` carefully.
- `echo` ignores `-e` — use `printf '%b\n'` instead.
- `read -p` is a bashism — this app uses `printf` + `read -r`.
- `local` is a bash/zsh extension — works here because shebang is `#!/bin/bash`.

## fzf CLI Specifics

- `fzf` reads the candidate list on stdin and prints the selection on stdout; exit 1 = abort (ESC). `fzf -m` enables multi-select.
- `fzf --color=...` accepts the themed palette string built by `fzf_theme()` (works for 256-index and `#RRGGBB`).
- The fake fzf in `tests/fakebin/fzf` pops one line per call from `FZF_QUEUE` (`MULTI:` prefix = several selections); empty queue → exit 1 (ESC).

## Environment & Filesystem

- **Never set `LD_LIBRARY_PATH` globally** — breaks `mpd`/`mpv`/`pulseaudio`. Set per-binary only.
- **`$PREFIX` long (43 chars)** — UNIX socket paths capped at 108 bytes. Avoid deep nesting.
- **Cron environment stripped** — only USER/HOME/LOGNAME/PATH/LANG/SHELL/PWD. Missing: TMPDIR/TZ/LD_PRELOAD/PREFIX/ANDROID_ROOT. Source `~/.profile` in cron entries.
- **`/system/bin` not in PATH** — intentional. Adding globally causes `CANNOT LINK EXECUTABLE`.
- **External storage `noexec`** — `/sdcard` can't execute binaries. Copy to `$PREFIX/bin`.
- **Android 11+ scoped storage** — `Android/data` restricted. Only `Android/data/com.termux` accessible.
- **Never `rm -rf ~/storage/shared/*`** — deletes user's phone files.
- **`$PREFIX/tmp` wiped on app restart** — nothing long-lived there.

## Background Processes & Battery

- Android kills background apps aggressively — use `termux-wake-lock` for persistent processes.
- `crond` needs the app open; `nohup` alone is insufficient.
- `termux-job-scheduler` uses Android's JobScheduler — runs on Android's schedule (battery/charging).

## Debugging Workflow

1. Reproduce with harness: add `T`/`G` test case, run `bash tests/run-tests.sh`.
2. Inspect `tests/tmp/<name>/run.log` + `fzf-calls` for picker errors.
3. Only then run `bash manager.sh` manually (text mode: `NO_FZF=1 bash manager.sh`).
4. Never test destructive paths (purge, autoremove) on a real device — extend fakebin stubs.

## Locale / Timezone / DNS

- Only `C`/`POSIX` and `C.UTF-8` exist — no other locales resolve. `LC_*` mostly ignored by Bionic `setlocale`.
- `TZ` not exported by default — `date` reads Android system tz. Programs reading `$TZ` directly may show UTC. Fix per-command, not globally.
- No `/etc/resolv.conf` — optional `resolv-conf` package installs `$PREFIX/etc/resolv.conf`; `proot-distro` bind-mounts it.
- No `/etc/localtime` or `/usr/share/zoneinfo` — Android keeps tzdata at `/system/usr/share/tzdata`.

## Security Model

- **No eval on user input** — `run_multi_op` builds args via array expansion, never `eval "$MGR install $pkgs"`.
- **Symlink attack prevention** — `scratch_new()` + EXIT trap. Never fixed temp names.
- **Package validation before every apt call** — `valid_pkg_name()` in `ask_name()`, `filter_pkgs()`, `pin_install()`, `do_favs()`, `run_multi_op()` dedup.
- **Config not executable** — `load_config()` reads as text, never sources. `$(malicious command)` in config is harmless.
- **Installer atomic writes** — `.tmp` → `mv` prevents corruption.
- **Test isolation** — each test gets its own `$HOME`/`$PREFIX` under `tests/tmp/`.

## Performance

- `run_multi_op` batches to single `apt` call (fast path). Per-package retry only on failure.
- `apt_hint()` = O(n) case statement on output; instant for <100 lines.
- Dep tree depth capped at 4 (`dep_tree()`, `manager.sh:1386`).
- `list_upgradable()` propagates apt exit code.
- Menu rebuild on favs change is O(35) — instant.

## User-Facing Support Playbook

| Symptom | Fix |
|---------|-----|
| "command not found" after install | New session needed (PATH not set in current shell) |
| Icons as empty boxes | No Nerd Font — switch Settings→Icons→emoji or install from `fonts/` |
| Font installed but not applied | `termux-reload-settings`; full app kill may be needed (`am force-stop com.termux`) |
| Stuck dpkg locks | `dpkg --configure -a` → `apt --fix-broken install` → retry. Never delete locks while apt runs. |
| "Unable to locate package" | Stale lists — run Upgrade center first |
| Upgrade breaks mid-way | Do NOT abort; finish, then `pkg upgrade` again + `dpkg --configure -a` |

## Termux Ecosystem

- **Termux:Boot** — scripts in `~/.termux/boot/`, sorted order. Start with `termux-wake-lock`.
- **Termux:API** — `termux-notification`, `termux-toast`, `termux-clipboard-set`, etc. Requires main app + API app same signature. Notification actions run in `dash -c` — set PATH explicitly.
- **termux-reload-settings** — applies `~/.termux/termux.properties` changes. Run `pkg upgrade` first on fresh installs (older termux-tools had a bug).
- **termux-change-repo** — interactive mirror selector; `pkg` auto-rotates mirrors.
- **termux-setup-storage** — creates `~/storage/` symlinks. May fail silently if permission not granted — revoke + re-grant in Android Settings.
