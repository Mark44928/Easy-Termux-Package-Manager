# AGENTS.md — Easy-Termux-Package-Manager

> **This is Termux, not Linux.** Bionic libc (not glibc), no FHS filesystem, no root. `$PREFIX` = `/data/data/com.termux/files/usr`. All standard Linux assumptions can break here. `manager.sh` is a single-file Bash app (~4.5k lines); `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`/`apt`/`fzf`. CI: `.github/workflows/ci.yml` (lint + tests on ubuntu-latest — the suite is hermetic).

## Make

| Target | What |
|--------|------|
| `make run` | Launch app (text mode: `NO_FZF=1 make run`) |
| `make test` | Full test suite (175 tests, ~3 min, text + fzf modes) |
| `make lint` | `bash -n` + `shellcheck --severity=style` (0 findings; SC2015/SC2119/SC2120 excluded) |
| `make check` | Lint + test |
| `make install` / `make uninstall` | Via `install.sh` / `rm $PREFIX/bin/pkg-manager` |
| `make clean` | Delete `tests/tmp/` |

```bash
export TMPDIR=/data/data/com.termux/files/usr/tmp
bash manager.sh
bash tests/run-tests.sh
```

Tests use `tests/fakebin/` stubs for `apt`/`pkg`/`dpkg`/`dpkg-query`/`apt-cache`/`apt-mark`/`fzf`/`curl`/`python3` — no real Termux or package changes. 175 scenario tests; `tests/tmp/` is gitignored. fzf answers come from `FZF_QUEUE` (plain lines, `MULTI:` prefix splits into several selections; fake aborts with exit 1 when empty = ESC → typed fallback).

## Hard Rules

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as text KEY=VALUE (`manager.sh:52-93`). Never `source` user files (option injection / RCE risk).
- **Temp files via `scratch_new()` only** — uses `mktemp`, cleaned by EXIT trap. Never `/tmp/foo`.
- **Package name validation via `valid_pkg_name()`** — rejects leading `-`, spaces, shell metacharacters. Use before ANY user name hits `apt`/`dpkg`.
- **Always quote `$MGR`** (apt or pkg) — unquoted breaks on word splitting.
- **fzf or text** — every feature works with fzf (default) or the numbered text lists (when fzf is disabled). Tests check both paths.
- **Call `apt_hint()` after every apt operation** — translates raw apt/dpkg errors to friendly messages (`manager.sh:836`).
- **Run `filter_pkgs()` before any user input hits apt** — calls `valid_pkg_name()`, strips invalid names. Critical for preventing option injection.
- **Never `set -e`** — `manager.sh` uses `set -o pipefail` only; `set -e` breaks the menu loop.

## Code Structure

| File | Role |
|------|------|
| `manager.sh` | The entire app (~4.5k lines) |
| `install.sh` | Installer (atomic writes, derives VERSION from `manager.sh`, smoke-tests the installed binary), offers Nerd Font |
| `Makefile` | Dev targets (`run`/`test`/`lint`/`check`/`install`/`uninstall`/`clean`) |
| `fonts/` | Bundled Nerd Font TTFs (CaskaydiaCove, FiraCode) |
| `tests/fakebin/` | Stubs for `apt`, `apt-cache`, `apt-mark`, `dpkg`, `dpkg-query`, `pkg`, `fzf`, `curl`, `git`, `figlet`, `python3` |
| `tests/seeds/` | Per-test seed data |


## Architecture

- **Config precedence:** env overrides → config file → hardcoded defaults (`manager.sh:18-28`, `95-140`), all validated via case statements. Config keys: `MGR THEME CONFIRM LOG_ENABLED ICONS QUIET LOCK STARTUP_CHECK FAVS_PINNED RECYCLE FZF_ENABLED`.
- **Confirmation (3-layer):** `CONFIRM=1` (normal) → `QUIET=1` (skip all) → `LOCK=1` (force even if QUIET). `confirm_danger()` checks LOCK first.
- **Main loop** (`manager.sh:4454+`): `while true`; first iteration runs `do_maintenance` if `STARTUP_CHECK=1`; `pause` after each action. Pinned favorites dispatched via `*"Pinned:"*` glob. Menu items 1–59 (Settings last, at 59) + pinned at 60+; the theme hub is the ONE theme row in Settings (`do_theme`, pick/preview/export/restore) — it is not in the main menu.
- **`run_multi_op()`** (`manager.sh:865`): batch fast path (single `apt install/remove -y`), falls back to per-package retry on failure. `RECYCLE=1` + remove → `archive_pkg()` first.
- **Logging:** `log()` successes only, `log_err()` failures (`manager.sh:617-630`, both to `~/.pkg-manager.log`). Undo reads log via `grep`.
- **Two UI modes, both first-class:** `UI_MODE` is `fzf` (default) or `text` (numbered lists). They are separate code paths, not one UI with a degraded fallback — every picker has a complete text branch. If fzf itself breaks mid-session (exit ≥ 2), the app says so ONCE, sets `UI_MODE=text`/`FZF_BROKEN=1`, and completes the session in text mode. `term_size()` supplies real terminal geometry to both.
- **Package manager:** `MGR` ∈ `apt|pkg` only — nala support was removed (it shipped broken in Termux). Mutating operations that bypass `run_multi_op` call `apt` directly; queries use `apt-cache`/`apt-mark`. A mid-session manager change takes effect immediately because `MGR` is read at each call.
- **fzf layer:** `have_fzf()` checks `FZF_ENABLED=1` + `NO_FZF!=1` + `command -v fzf`. fzf is the sole interactive UI (gum is gone): `main_menu`, `do_palette`, `do_search` result pick, `do_install`/`do_uninstall` (via `use_fzf_for_op`), and every submenu via `pick_menu`/`pick_multi`/`pick_one`. **ESC contract (v5.2):** ESC cancels, everywhere. Top-level menu → exits with the farewell; submenus (`pick_menu`/`pick_multi`/`pick_one`) → return 1 so the `do_*` caller goes back a level; the install/uninstall picker prints `Canceled.` and returns to the menu — there is deliberately NO typed-name detour anymore. The only way to reach the typed name prompt is the text-mode menu (or `NO_FZF=1`). A *fzf failure* (exit ≥ 2) is a different thing: it prints the error, sets `UI_MODE=text`/`FZF_BROKEN=1`, and every picker falls through to its numbered list for the rest of the session. Theme via `fzf_theme()`/`fzf_select()`. Uninstall picks from `dpkg-query` (installed only), install from a cached not-installed-only list at `~/.pkg-manager-fzf-cache` (30 min TTL). Settings row 11 toggles `FZF_ENABLED` (on/off).
- **v5.1/v5.2 fzf details:**
  - Rows are `name|display` / `label|description`; `fzf_select` reads the optional globals `FZF_PREVIEW` (preview shell command) and `FZF_NTH` (extra field flags) — callers set both, then reset both to `""` after the call.
  - Field flags are `--delimiter=| --nth=1,2 --with-nth=2`: search covers both columns, only the pretty column is shown, and callers parse the answer with `${sel%%|*}` / `cut -d'|' -f1`. **Never use `--nth=2` alone** — that combination makes fzf 0.74 match nothing.
  - Preview placeholders: use fzf's field placeholder `{1}` (the bare name). A literal `{\}` in the preview string is NOT substituted and leaks `=== {} ===` into the pane.
  - Geometry is screen-adaptive: `fzf_layout()` picks `right:45%:wrap:border-left` on wide/landscape terminals and `down:45%:wrap:border-top` otherwise.
- **Banner visibility (v5.2):** fzf height must stay **below 100%** (`fzf_height()` = `(lines-7)*100/lines`, capped 50–95). At 100% fzf enters fullscreen and switches to the **alternate screen**, which hides everything printed above it — that is what kept "wiping" the banner. Below 100% fzf renders in place and the banner + status strip stay on screen. `--layout=reverse` keeps natural top-down order (bottom-anchored layout reads like `tac`). fzf also clears its whole managed area, margins included, so never try to preserve content with `--margin`. `term_size()` trusts `tput` only when attached to a tty (a non-tty `tput` happily returns the terminfo default 80), then `COLUMNS`/`LINES`, then 80×24.
  - Package previews (`pkg_preview_cmd <install|remove>`) show the dpkg status line, a mode-specific line (candidate version / "WILL BE REMOVED") plus a size-humanized `apt-cache show` record, colored by `bat` when installed. The install picker lists **not-installed** packages only (filtered against `dpkg-query`); uninstall gets its own prompt/header/footer and installed-only rows.
  - Prompt glyph is `❯ ` everywhere (menus, palette, package pickers).
  - `main_menu` has exactly ONE fzf block — a duplicate call made ESC reopen the menu (fixed in v5.1); the `menu_unique` test guards the row set.
- **CLI mode:** `--help --version --list-themes --theme <n> --export-theme <n>` are parsed before the main loop. v5.1 adds `--check-updates` (list upgradable), `--quiet` (count only, machine-readable) and `--doctor` (full audit, then exit) — all non-interactive (`CLI_MODE`) and exit before `FIRST_LOOP`. `install.sh --theme <n>` calls `pkg-manager --export-theme <n>` so palettes live in one place.

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
 | `dep_tree()` | Dependency resolver, depth capped at 4 (`manager.sh:1603`) |
 | `do_depgraph()` | Colored forward/reverse dependency graph + manual-vs-dependency check (`manager.sh:4273`) — menu row 51, distinct from `do_deptools()` (row 28) |
 | `refresh_fzf_cache()` | Rebuilds the `name|display` picker cache (`manager.sh:3811`) — install rows are NOT-installed packages only |
 | `pkg_preview_cmd()` | fzf preview per mode (`manager.sh:4019`): dpkg status + candidate/removal line + size-humanized `apt-cache show` |
 | `batch_preview()` / `human_size()` | Pre-flight install summary (`manager.sh:4096` / `4086`): aligned version column, total installed size, already-present and not-found flags |
 | `term_size()` / `fzf_layout()` / `fzf_height()` / `fzf_margin()` | screen-adaptive geometry (`manager.sh:3851`-`3900`); height stays below 100% so the banner is never hidden |
| `have_fzf()` | FZF_ENABLED + NO_FZF + command lookup — gate for every fzf path |
| `fzf_theme()` / `fzf_select()` | theme-colored picker + generic multi-select |
| `pick_menu()` / `pick_multi()` / `pick_one()` | submenu pickers (fixed items / multi list / stdin list) — fzf first, then the original numbered text list |
| `fzf_pick_pkgs()` / `use_fzf_for_op()` | package pickers; ESC prints `Canceled.` and returns (no typed-name detour) |
| `paint()` / `set_theme()` / `theme_ansi()` | color engine: 256-index + `#RRGGBB` truecolor |
| `apply_termux_theme()` | export palette to `~/.termux/colors.properties` (backup first) |
| `do_theme()` | The theme hub (pick / preview all / apply to Termux / restore) — the ONE theme row, inside Settings only |
| `set_theme_pick()` / `theme_preview()` / `apply_termux_theme()` | theme label list, swatch preview, Termux palette export |
| `do_essentials()` / `do_sysinfo()` / `do_whatsnew()` | v5.0 hubs (menu rows 56–58) |

## Gotchas

 - Banner art is gzip-compressed, base64 in `BANNER_B64` (`manager.sh:338`). Re-compress after editing.
 - **Never reuse an `OPTION_*` variable name** — a shadowed assignment once made two menu rows render identically and left `do_depgraph()` unreachable (bash `case` takes the first match). The `menu_unique` test asserts 60 unique menu rows, so CI catches a repeat instantly.
- `install.sh` uses atomic writes (`.tmp` → `mv`) — never overwrite in place.
- `set -o pipefail` active — pipelines fail on first error.
- `log()` records successes only; `log_err()` for failures.
- Tests set `ICONS=emoji` via env. Input via stdin (text). `NO_FZF=1` is the default; only the `F()` tests unset it and feed `FZF_QUEUE`.
- Group delimiter is `::` (`manager.sh:2424-2425`), names sanitized to `[A-Za-z0-9 _-]`.
- `FAVS_PINNED=1` triggers `build_menu()` after favorites changes.
- JSON export requires `python3`; falls back to text.
- Bash functions must be DEFINED before `FIRST_LOOP=1` — the `while true` loop only executes top-level code linearly, so anything defined after it is undefined inside the loop. The MAX-4.1 block (fzf cache, `do_repos`, `do_undo`, `do_health`, `do_auto_mirror`, `do_snapshot`) was moved above the loop in v5.0; keep new handlers there.
- Settings rows: text-menu `case "$choice"` numbers 1–12 (2 = the theme hub, 11 = fzf picker on/off, 12 = Back). Adding/removing a row reshuffles all numbers — update both the fzf item list and the text list, plus every test that feeds a number.
- `have_fzf` returns false for every test unless `NO_FZF` is unset, so the real fzf never blocks the suite; `tests/fakebin/fzf` answers `FZF_QUEUE` (one line per call, `MULTI:` = several), and exits 1 with no output to emulate ESC.

- `list_upgradable()` returns apt's real exit code — distinguish empty from failure.

## Version Bump

1. `VERSION="5.3"` in `manager.sh:17` — the single source of truth (`install.sh` derives its banner from it; nothing else hardcodes a version).
2. README: version badge, the `vX.Y.Z highlights` line in whatsnew, and the two banner blocks stay version-free (the status strip prints the version).
3. `BANNER_B64` (`manager.sh:338`) holds the **ETPM** figlet wordmark with no version in it — regenerate only when the wordmark changes:
   ```bash
   art=$(figlet -f slant "ETPM" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
   b64=$(printf '%s' "$art" | gzip -9 | base64 -w0)
   # then replace BANNER_B64="..." in manager.sh with $b64
   ```

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

- `fzf` reads the candidate list on stdin and prints the selection on stdout. Exit codes: **0** = picked, **1** = abort (ESC → cancel), **≥ 2** = fzf itself failed (the app prints the error and switches to text mode). `fzf -m` enables multi-select.
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

1. **Verify targeted, not globally.** For a change to one path, run the repo's own fast gates — `make lint` — plus ONE direct exercise of the changed path (text mode: `printf '59\n2\n' | NO_FZF=1 bash manager.sh`, or a piped fzf-mode run). The full 175-test suite costs ~3–4 minutes and runs against everything; reserve it for session end or when a cross-cutting change lands.
2. Reproduce in the harness: add a `T`/`F` case, or inspect `tests/tmp/<name>/run.log` + `fzf-calls` for picker errors.
3. Interactive check last: `bash manager.sh` manually.
4. Never test destructive paths (purge, autoremove) on a real device — extend the fakebin stubs instead.

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
- **Self-update integrity gate** — `do_selfupdate()` runs `bash -n` + a content check on the download, then verifies its SHA-256 against a published companion `manager.sh.sha256` when the release provides one (mismatch refuses the update; missing checksum file skips only that step).
- **Test isolation** — each test gets its own `$HOME`/`$PREFIX` under `tests/tmp/`.

## Performance

- `run_multi_op` batches to single `apt` call (fast path). Per-package retry only on failure.
- `apt_hint()` = O(n) case statement on output; instant for <100 lines.
- Dep tree depth capped at 4 (`dep_tree()`, `manager.sh:1603`).
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
| ESC opens a numbered list instead of cancelling | Old build — ESC now cancels everywhere; the extended list means fzf exited ≥ 2 and the app fell back to text mode (the reason is printed) |
| Picker shows installed packages when installing | Stale `~/.pkg-manager-fzf-cache` (30 min TTL) — delete it or wait for the refresh |
| Banner disappears in the picker | Terminal forced fullscreen (some wrappers ignore `--height`) — the app already stays below 100%; nothing to fix |
| "possible misspelling: ICON_XXX" from shellcheck | The icon does not exist in `init_icons()` (both branches) — use a real one or add it to both 

## Termux Ecosystem

- **Termux:Boot** — scripts in `~/.termux/boot/`, sorted order. Start with `termux-wake-lock`.
- **Termux:API** — `termux-notification`, `termux-toast`, `termux-clipboard-set`, etc. Requires main app + API app same signature. Notification actions run in `dash -c` — set PATH explicitly.
- **termux-reload-settings** — applies `~/.termux/termux.properties` changes. Run `pkg upgrade` first on fresh installs (older termux-tools had a bug).
- **termux-change-repo** — interactive mirror selector; `pkg` auto-rotates mirrors.
- **termux-setup-storage** — creates `~/storage/` symlinks. May fail silently if permission not granted — revoke + re-grant in Android Settings.
