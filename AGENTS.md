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
- `tests/helps/` — fake `gum` help output for test mode.

## Key conventions

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as plain `KEY=VALUE` lines (line 48-84 in `manager.sh`). Never change this to source/exec user files.
- **Temp files use `mktemp`** — `scratch_new()` creates unguessable names to prevent symlink attacks (line 31-43). Always use this pattern, never fixed temp paths.
- **Package name validation** — `valid_pkg_name()` rejects leading `-` (option injection), spaces, shell metas. Use it before any user-supplied name hits `apt`/`dpkg`.
- **Icons** — defined in `init_icons()` (line 126-186). Nerd Font codepoints above U+FFFF use 8-digit escapes: `$'\U000XXXXX'`. Emoji branch uses plain Unicode symbols.
- **`$MGR` variable** — wraps either `apt` or `pkg`. Always use `"$MGR"` not hardcoded `apt` for install/remove/upgrade. Some operations (depends, purge, fix-broken, autoremove, dpkg queries) call `apt`/`dpkg` directly where `pkg` has no equivalent.
- **`$GUM` flag** — 0 or 1. Every UI function has both a `gum` branch and a plain-text branch. New features must include both.
- **Menu labels** — `OPTION_*` variables (line 263-298) must match README menu-map tables exactly.

## Version bump

Three places: badge in README, ASCII art line (`v2.0`), fallback string in `manager.sh:237`. Then regenerate `BANNER_B64` (compressed blob).

## Gotchas

- The banner art is gzip-compressed, base64-encoded in `BANNER_B64` (line 231). Edit the source art, then compress+encode to update.
- `install.sh` uses atomic writes (`.tmp` then `mv`) for both the binary and the font — never overwrite in place.
- `set -o pipefail` is active — pipelines fail on the first command's error.
- `log()` only records successes; `log_err()` records failures (line 397-407).
- Tests set `ICONS=emoji` and `GUM_ENABLED` via env. The test harness feeds input via stdin (text mode) or base64-encoded queue files (gum mode).
