# AGENTS.md

## What this is

Single-file Bash app (`manager.sh`, ~2.3k lines) — an interactive package manager for Termux. `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`, `apt`, and optionally `gum`.

## Run

```bash
bash manager.sh
```

## Test

```bash
bash tests/run-tests.sh
```

Uses fakebin stubs (`tests/fakebin/`) for `apt`, `dpkg`, `gum`, etc. — no real Termux needed. Run from the `tests/` dir or from the repo root; the script `cd`s into its own directory. 120 scenario tests in text and gum modes. `tests/tmp/` is gitignored.

## Code structure

- `manager.sh` — the entire app. Every menu option, every function.
- `install.sh` — global installer, copies `manager.sh` to `$PREFIX/bin/pkg-manager`, offers Nerd Font install.
- `fonts/` — bundled Nerd Font TTFs (CaskaydiaCove, FiraCode).
- `tests/fakebin/` — stubs for `apt`, `dpkg`, `gum`, `curl`, etc. used by the test harness.
- `tests/seeds/` — per-test seed data (copied into fake `$HOME`/`$PREFIX`).
- `tests/helps/` — fake `gum` help output for test mode (validates flags against known-good lists).

## Key conventions

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as plain `KEY=VALUE` lines (line 48-84 in `manager.sh`). Never change this to source/exec user files.
- **Temp files use `mktemp`** — `scratch_new()` creates unguessable names to prevent symlink attacks (line 31-43). Always use this pattern, never fixed temp paths.
- **Package name validation** — `valid_pkg_name()` rejects leading `-` (option injection), spaces, shell metas. Use it before any user-supplied name hits `apt`/`dpkg`.
- **Icons** — defined in `init_icons()` (line 126-186). Nerd Font codepoints above U+FFFF use 8-digit escapes: `$'\U000XXXXX'`. Emoji branch uses plain Unicode symbols.
- **`$MGR` variable** — wraps either `apt` or `pkg`. Always use `"$MGR"` not hardcoded `apt` for install/remove/upgrade. Some operations (depends, purge, fix-broken, autoremove, dpkg queries) call `apt`/`dpkg` directly where `pkg` has no equivalent.
- **`$GUM` flag** — 0 or 1. Every UI function has both a `gum` branch and a plain-text branch. New features must include both.
- **Menu labels** — `OPTION_*` variables (line 263-298) must match README menu-map tables exactly.

## Architecture

### Config precedence

Env overrides (`MGR=... pkg-manager`) beat config file values. Config file values beat hardcoded defaults (line 8-24, 88-108). Both are validated with case statements that silently reset invalid values to defaults.

### Confirmation logic (three-layer)

- `CONFIRM=1` + `QUIET=0` — normal: asks before destructive ops
- `QUIET=1` — skips all confirms (used for scripting/batch)
- `LOCK=1` — forces confirms even when QUIET is on (override safety lock)
- `confirm_danger()` checks LOCK first, then falls through to `confirm()`

### Main loop (line 2219-2269)

`while true` loop. On first iteration, if `STARTUP_CHECK=1`, runs `do_maintenance` before showing the menu. After each action, `pause` waits for Enter. Pinned favorites append to the menu items and are dispatched via glob match `*"Pinned:"*`.

### Multi-package operations

`run_multi_op()` (line 572-622): tries one batched `apt install/remove -y` first (fast path — single resolver pass, single dpkg lock). If the batch fails, retries package-by-package to attribute individual failures. Returns 0 only if everything succeeded.

### Error hinting

`apt_hint()` (line 543-563) translates raw apt/dpkg output into friendly messages. Called after every install/remove/reinstall/purge/fix-broken/autoremove. Returns empty string for unrecognized output.

### Logging

- `log()` (line 397-400) — timestamped success entries only, appended to `~/.pkg-manager.log`
- `log_err()` (line 404-407) — timestamped `FAIL:` entries for real failures
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
- `install.sh` uses atomic writes (`.tmp` then `mv`) for both the binary and the font — never overwrite in place.
- `set -o pipefail` is active — pipelines fail on the first command's error.
- `log()` only records successes; `log_err()` records failures (line 397-407).
- Tests set `ICONS=emoji` and `GUM_ENABLED` via env. The test harness feeds input via stdin (text mode) or base64-encoded queue files (gum mode).
- Custom groups file uses `::` as delimiter between group name and package list (line 2040-2054).
- Group names are sanitized: only `[A-Za-z0-9 _-]` allowed, others replaced with `_`.
- `FAVS_PINNED=1` triggers `build_menu()` after every favorites change to re-append pinned items to the menu.
- Export with JSON requires `python3`; falls back to plain text if missing.
- `list_upgradable()` returns apt's real exit code so callers can distinguish "none upgradable" from an apt failure.
- Dependency tree recursion depth is capped at 4 (`dep_tree()` line 1260).

## Test harness details

### How input is fed

- **Text mode** (`T`, `P` helpers): stdin is a here-string of newline-separated menu choices and package names
- **Gum mode** (`G`, `GP` helpers): `GUM_QUEUE` file contains base64-encoded lines, one per `gum choose`/`gum input`/`gum confirm` call. The fake `gum` pops from this queue.

### Key env vars in tests

| Var | Purpose |
|-----|---------|
| `HOME` / `PREFIX` | Pointed to per-test temp dir |
| `GUM_ENABLED` | 0 for text tests, 1 for gum tests |
| `ICONS` | Set to `emoji` (avoids Nerd Font dependency) |
| `GUM_QUEUE` | Path to base64-encoded input queue (gum mode) |
| `GUM_CALL_LOG` | Records which `gum` subcommands were called |
| `GUM_VALIDATE_LOG` | Records unknown flags (test fails if any) |
| `FAKE_UPGRADABLE` | Set to `empty` to simulate "all up to date" |
| `FAKE_ORPHANS` | Set to `1` to simulate orphaned packages |
| `FAKE_UPGRAD_FAIL` | Set to `1` to simulate apt list failure |

### Fakebin stubs

- `tests/fakebin/apt` — handles install/remove/purge/upgrade/clean/autoclean/autoremove/search/list/show/depends/rdepends. Recognizes `invalidpkg` as not-found, `nospace`/`heldpkg`/`confpkg` as specific failures. Sim mode (`-s`) returns simulated output.
- `tests/fakebin/gum` — pops from `GUM_QUEUE`, validates flags against `tests/helps/*`, logs calls to `GUM_CALL_LOG`.
- `tests/fakebin/dpkg` — provides `dpkg -L` (files) and `dpkg -S` (owner) responses.
- `tests/fakebin/dpkg-query` — provides size data.
- `tests/fakebin/apt-cache` — provides `apt-cache show` and `apt-cache depends`.
- `tests/fakebin/apt-mark` — provides hold/unhold/showhold.
