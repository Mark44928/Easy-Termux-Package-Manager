# AGENTS.md

## What this is

Single-file Bash app (`manager.sh`, ~2.3k lines) -- an interactive package manager for Termux. `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`, `apt`, and optionally `gum`.

> **This is Termux, not Linux.** Termux runs on Android without root, uses Bionic libc (not glibc), has no FHS-compliant filesystem, and packages live under `/data/data/com.termux/files/usr`. Every assumption about standard Linux paths, permissions, or system calls can break here.

## Run

```bash
bash manager.sh
```

## Test

```bash
bash tests/run-tests.sh
```

Uses fakebin stubs (`tests/fakebin/`) for `apt`, `dpkg`, `gum`, etc. -- no real Termux needed. Run from the `tests/` dir or from the repo root; the script `cd`s into its own directory. 120 scenario tests in text and gum modes. `tests/tmp/` is gitignored.

## Code structure

- `manager.sh` -- the entire app. Every menu option, every function.
- `install.sh` -- global installer, copies `manager.sh` to `$PREFIX/bin/pkg-manager`, offers Nerd Font install.
- `fonts/` -- bundled Nerd Font TTFs (CaskaydiaCove, FiraCode).
- `tests/fakebin/` -- stubs for `apt`, `dpkg`, `gum`, `curl`, etc. used by the test harness.
- `tests/seeds/` -- per-test seed data (copied into fake `$HOME`/`$PREFIX`).
- `tests/helps/` -- fake `gum` help output for test mode (validates flags against known-good lists).

## Key conventions

- **Config is never `source`d** -- `load_config()` parses `~/.pkg-manager.conf` as plain `KEY=VALUE` lines (line 48-84 in `manager.sh`). Never change this to source/exec user files.
- **Temp files use `mktemp`** -- `scratch_new()` creates unguessable names to prevent symlink attacks (line 31-43). Always use this pattern, never fixed temp paths.
- **Package name validation** -- `valid_pkg_name()` rejects leading `-` (option injection), spaces, shell metas. Use it before any user-supplied name hits `apt`/`dpkg`.
- **Icons** -- defined in `init_icons()` (line 126-186). Nerd Font codepoints above U+FFFF use 8-digit escapes: `$'\U000XXXXX'`. Emoji branch uses plain Unicode symbols.
- **`$MGR` variable** -- wraps either `apt` or `pkg`. Always use `"$MGR"` not hardcoded `apt` for install/remove/upgrade. Some operations (depends, purge, fix-broken, autoremove, dpkg queries) call `apt`/`dpkg` directly where `pkg` has no equivalent.
- **`$GUM` flag** -- 0 or 1. Every UI function has both a `gum` branch and a plain-text branch. New features must include both.
- **Menu labels** -- `OPTION_*` variables (line 263-298) must match README menu-map tables exactly.

## Architecture

### Config precedence

Env overrides (`MGR=... pkg-manager`) beat config file values. Config file values beat hardcoded defaults (line 8-24, 88-108). Both are validated with case statements that silently reset invalid values to defaults.

### Confirmation logic (three-layer)

- `CONFIRM=1` + `QUIET=0` -- normal: asks before destructive ops
- `QUIET=1` -- skips all confirms (used for scripting/batch)
- `LOCK=1` -- forces confirms even when QUIET is on (override safety lock)
- `confirm_danger()` checks LOCK first, then falls through to `confirm()`

### Main loop (line 2219-2269)

`while true` loop. On first iteration, if `STARTUP_CHECK=1`, runs `do_maintenance` before showing the menu. After each action, `pause` waits for Enter. Pinned favorites append to the menu items and are dispatched via glob match `*"Pinned:"*`.

### Multi-package operations

`run_multi_op()` (line 572-622): tries one batched `apt install/remove -y` first (fast path -- single resolver pass, single dpkg lock). If the batch fails, retries package-by-package to attribute individual failures. Returns 0 only if everything succeeded.

### Error hinting

`apt_hint()` (line 543-563) translates raw apt/dpkg output into friendly messages. Called after every install/remove/reinstall/purge/fix-broken/autoremove. Returns empty string for unrecognized output.

### Logging

- `log()` (line 397-400) -- timestamped success entries only, appended to `~/.pkg-manager.log`
- `log_err()` (line 404-407) -- timestamped `FAIL:` entries for real failures
- History viewer filters: all, errors only, install/remove actions only
- Undo reads the log: `grep -E '\] (remove |purge |bulk remove)'` and reinstalls those packages

## Data files

All in `$HOME`:

| File | Format | Created by |
|------|--------|------------|
| `~/.pkg-manager.conf` | `KEY=VALUE` lines (no comments) | `save_config()` |
| `~/.pkg-manager.log` | `[YYYY-MM-DD HH:MM:SS] action` or `FAIL: action` | `log()` / `log_err()` |
| `~/.pkg-manager-favs` | One package name per line | Favorites option |
| `~/.pkg-manager-groups` | `groupname::pkg1 pkg2 pkg3` (one group per line) | Package groups |
| `~/pkg-backup-*.txt` | One package name per line | Backup option |
| `~/pkg-export.{txt,json}` | Plain text or JSON `{"packages":[...]}` | Export option |

## Version bump

Three places: badge in README, ASCII art line (`v2.0`), fallback string in `manager.sh:237`. Then regenerate `BANNER_B64` (compressed blob).

## Gotchas

- The banner art is gzip-compressed, base64-encoded in `BANNER_B64` (line 231). Edit the source art, then compress+encode to update.
- `install.sh` uses atomic writes (`.tmp` then `mv`) for both the binary and the font -- never overwrite in place.
- `set -o pipefail` is active -- pipelines fail on the first command's error.
- `log()` only records successes; `log_err()` records failures (line 397-407).
- Tests set `ICONS=emoji` and `GUM_ENABLED` via env. The test harness feeds input via stdin (text mode) or base64-encoded queue files (gum mode).
- Custom groups file uses `::` as delimiter between group name and package list (line 2040-2054).
- Group names are sanitized: only `[A-Za-z0-9 _-]` allowed, others replaced with `_`.
- `FAVS_PINNED=1` triggers `build_menu()` after every favorites change to re-append pinned items to the menu.
- Export with JSON requires `python3`; falls back to plain text if missing.
- `list_upgradable()` returns apt's real exit code so callers can distinguish "none upgradable" from an apt failure.
- Dependency tree recursion depth is capped at 4 (`dep_tree()` line 1260).

## Termux-specific warnings and tips

### This is NOT standard Linux

- **No FHS** -- `/bin`, `/usr`, `/etc` don't exist at standard locations. Everything lives under `$PREFIX` (`/data/data/com.termux/files/usr`). `$HOME` is `/data/data/com.termux/files/home`.
- **No root** -- Termux is single-user. `sudo`, `su`, `setuid()`, `setgid()` are all unavailable or blocked. Android 9+ Seccomp blocks setuid syscalls.
- **Bionic libc, not glibc** -- fewer functions, different behavior. `iconv`, `gettext/libintl` require `libandroid-support`. No `glob.h` without `libandroid-glob`. `rindex()` does not exist (use `strrchr()`). POSIX regex from Bionic is BSD-derived, not GNU -- some patterns behave differently (e.g., `|` at start/end of alternation is invalid in Bionic's regex).
- **Seccomp blocks syscalls** -- Android 8+ blocks certain syscalls (`Bad system call` crashes). Android 8 blocks `tcsetattr()` with `TCSAFLUSH` (use `TCSANOW`). Android 9 blocks `setuid()`.
- **`/system/bin` is NOT in `$PATH`** by default -- Termux only exports its own `$PREFIX/bin`. If you need Android system commands, you must explicitly add `/system/bin` to PATH.
- **No SYSV shared memory or semaphores** -- need `libandroid-shmem` / `libandroid-posix-semaphore` packages.
- **Shebang limit** -- `#!` lines in scripts are capped at 128 chars (Linux <5.1) or 256 chars (Linux >=5.1). Termux's `LD_PRELOAD` termux-exec extends this to 340. Never hardcode `#!/bin/sh` -- use `#!/data/data/com.termux/files/usr/bin/sh` or let `termux-fix-shebang` handle it.
- **No execute on external storage** -- files on `/sdcard` can't be executed directly. Use `bash /sdcard/script.sh` as a workaround, but avoid it for security.
- **$PREFIX is long** -- `/data/data/com.termux/files/usr` (43 chars). UNIX socket paths are limited to 108 bytes. Deeply nested paths under `$TMPDIR` can hit this limit.

### apt/pkg gotchas specific to Termux

- **`pkg` is a wrapper around `apt`** -- it runs `apt update` automatically before installs, handles mirror selection, and gives friendlier errors. `apt` does not auto-update. For scripting, use `apt-get` instead of `apt` (apt warns "does not have a stable CLI interface").
- **`pkg` has no equivalent for** `apt purge`, `apt autoremove`, `apt list --upgradable`, `apt install -f`. These must call `apt` directly -- which this app already does for those operations.
- **dpkg lock errors** -- if a package operation is interrupted (phone dies, session killed), stale locks can block future operations. Recovery: `dpkg --configure -a` then `apt --fix-broken install`.
- **`apt upgrade` vs `apt full-upgrade`** -- plain `apt upgrade` can break Termux on rolling-release transitions (e.g., busybox to coreutils). Always prefer `pkg upgrade` or `apt full-upgrade` for real users. This app uses `"$MGR" upgrade -y` which maps correctly.
- **Busybox deprecation** -- Termux is replacing busybox symlinks with standalone packages (coreutils, findutils, tar). Removing busybox before installing its replacements breaks the package manager itself.
- **Config file prompts during upgrade** -- `dpkg` may prompt about modified config files. Use `-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"` for non-interactive upgrades.

### Effective methods for this codebase

- **Adding a new menu option**: add `OPTION_*` in `build_menu()`, add the case in the main loop, write the `do_*` function with both gum and text branches, update the README menu-map tables.
- **Adding a new icon**: add to both branches of `init_icons()`. Nerd Font codepoints above U+FFFF must use 8-digit hex escapes (`$'\U000XXXXX'`). Verify against the bundled fonts in `fonts/`.
- **Adding a new config key**: add default at top (line 15-24), add case in `load_config()`, add to `save_config()`, add validation case, add to Settings menu in `do_settings()`.
- **Adding a new test**: use the `T` helper for text/apt mode, `G` for gum/apt mode. Feed menu choices as newline-separated input. Check `tests/seeds/` for pre-seeded config/data.
- **Testing without Termux**: the fakebin stubs simulate apt/dpkg/gum behavior. Set `HOME`/`PREFIX` to a temp dir. No real packages are installed or removed.

### Reminders

- **Always quote `$MGR`** -- it expands to `apt` or `pkg`. Unquoted, it can break on word splitting.
- **Never use `source` on user config** -- `~/.pkg-manager.conf` is user-writable. Sourcing it would execute arbitrary code. `load_config()` parses it safely as key=value.
- **Both UI modes or nothing** -- every new feature must work in both `$GUM=1` (gum choose/input/confirm) and `$GUM=0` (numbered text menus + read). The test harness tests both.
- **`apt_hint()` must be called after every apt operation** -- it translates cryptic errors into user-friendly messages. Without it, users see raw dpkg/apt output.
- **Temp files via `scratch_new()` only** -- never use fixed paths like `/tmp/foo`. The EXIT trap cleans up all scratch files. This prevents symlink attacks on multi-user systems (relevant if Termux ever gains multi-user support).
- **`filter_pkgs()` before any user input hits apt/dpkg** -- it calls `valid_pkg_name()` and strips invalid names. Critical for preventing option injection via `-f`, `--force`, etc.
