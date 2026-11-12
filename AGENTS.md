# AGENTS.md — Easy-Termux-Package-Manager

> **This is Termux, not Linux.** Bionic libc (not glibc), no FHS filesystem, no root. `$PREFIX` = `/data/data/com.termux/files/usr`. All standard Linux assumptions can break here. `manager.sh` is a single-file Bash app (~5.3k lines); `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`/`apt`/`fzf`. CI: `.github/workflows/ci.yml` (lint + tests on ubuntu-latest — the suite is hermetic).

## Make

| Target | What |
|--------|------|
| `make run` | Launch app (text mode: `NO_FZF=1 make run`) |
| `make test` | **Full** suite — 182 tests, **~6 min**. NOT a routine check: see [Verification workflow](#verification-workflow--read-first) |
| `make lint` | `bash -n` + `shellcheck --severity=style` (0 findings; SC2015/SC2119/SC2120 excluded) |
| `make check` | lint **+ full suite** — only at the end of a cross-cutting change |
| `make install` / `make uninstall` | Via `install.sh` / `rm $PREFIX/bin/pkg-manager` |
| `make clean` | Delete `tests/tmp/` |

```bash
export TMPDIR=/data/data/com.termux/files/usr/tmp
bash manager.sh                # run the app
make lint                      # after every edit — seconds, not minutes
```

Tests use `tests/fakebin/` stubs for `apt`/`pkg`/`dpkg`/`dpkg-query`/`apt-cache`/`apt-mark`/`fzf`/`curl`/`python3` — no real Termux or package changes. 182 scenario tests; `tests/tmp/` is gitignored. fzf answers come from `FZF_QUEUE` (plain lines, `MULTI:` prefix splits into several selections; fake aborts with exit 1 when empty = ESC → typed fallback).

## Hard Rules

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as text KEY=VALUE (`manager.sh:94-142`). Never `source` user files (option injection / RCE risk).
- **Temp files via `scratch_new()` only** — uses `mktemp`, cleaned by EXIT trap. Never `/tmp/foo`.
- **Package name validation via `valid_pkg_name()`** — rejects leading `-`, spaces, shell metacharacters. Use before ANY user name hits `apt`/`dpkg`.
- **Always quote `$MGR`** (apt or pkg) — unquoted breaks on word splitting.
- **fzf or text** — every feature works with fzf (default) or the numbered text lists (when fzf is disabled). Tests check both paths.
- **Call `apt_hint()` after every apt operation** — translates raw apt/dpkg errors to friendly messages (`manager.sh:1105`).
- **Run `filter_pkgs()` before any user input hits apt** — calls `valid_pkg_name()`, strips invalid names. Critical for preventing option injection.
- **Never `set -e`** — `manager.sh` uses `set -o pipefail` only; `set -e` breaks the menu loop.

## Code Structure

| File | Role |
|------|------|
| `manager.sh` | The entire app (~5.4k lines) |
| `install.sh` | Installer (atomic writes, derives VERSION from `manager.sh`, smoke-tests the installed binary), offers Nerd Font |
| `Makefile` | Dev targets (`run`/`test`/`lint`/`check`/`install`/`uninstall`/`clean`) |
| `fonts/` | Bundled Nerd Font TTFs (CaskaydiaCove, FiraCode) |
| `tests/fakebin/` | Stubs for `apt`, `apt-cache`, `apt-mark`, `dpkg`, `dpkg-query`, `pkg`, `fzf`, `curl`, `git`, `figlet`, `python3` |
| `tests/seeds/` | Per-test seed data |


## Architecture

- **Config precedence:** env overrides → config file → hardcoded defaults (`manager.sh:18-28` (defaults), `94-142` (load_config)), all validated via case statements. Config keys: `MGR THEME CONFIRM LOG_ENABLED ICONS QUIET LOCK STARTUP_CHECK FAVS_PINNED RECYCLE FZF_ENABLED`.
- **Confirmation (3-layer):** `CONFIRM=1` (normal) → `QUIET=1` (skip all) → `LOCK=1` (force even if QUIET). `confirm_danger()` checks LOCK first.
- **Main loop** (`manager.sh:5226+`): clears the screen first when stdout is a tty (`printf '\033[2J\033[H'` — piped runs stay clean for tests/scripts), then `while true`; first iteration runs `do_maintenance` if `STARTUP_CHECK=1`; `banner_refresh` per iteration (caches the `BANNER_BLOCK` text, so the dpkg-query behind the status strip runs once, not once per picker), prints the banner only when `have_fzf` is false; `pause` after each action. Pinned favorites dispatched via `*"Pinned:"*` glob. Menu items 1–57 (Settings last, at 57) + pinned at 58+; the theme hub is the ONE theme row in Settings (`do_theme`, pick/preview/export/restore) — it is not in the main menu.
- **`run_multi_op()`** (`manager.sh:1134`): batch fast path (single `apt install/remove -y`), falls back to per-package retry on failure. `RECYCLE=1` + remove → `archive_pkg()` first.
- **Logging:** `log()` successes only, `log_err()` failures (`manager.sh:878-887`, both to `~/.pkg-manager.log`). Undo reads log via `grep`.
- **Text-mode lists share one style:** every numbered list goes through `list_numbered <extra_rows> <item>...`, which right-aligns the number column to the total row count (`9 rows -> "1)"`, `12 rows -> " 1)"`) and leaves the width in `LIST_NUM_W` for the trailing Exit row. Every selection prompt is `❯ ` (the same glyph as the fzf prompt) — `ask_name` prefixes it too, so the whole app asks questions the same way. Confirmations keep their `… [y/N]` form. The main menu uses the same style as the submenus (`0) Exit` stays row 0).
- **Two UI modes, both first-class:** `UI_MODE` is `fzf` (default) or `text` (numbered lists). They are separate code paths, not one UI with a degraded fallback — every picker has a complete text branch. If fzf itself breaks mid-session (exit ≥ 2), the app says so ONCE and every later picker behaves as text mode for the rest of the session (a `$FZF_BROKEN_FLAG` file). `term_size()` supplies real terminal geometry to both.
- **Package manager:** `MGR` ∈ `apt|pkg` only — nala support was removed (it shipped broken in Termux). Mutating operations that bypass `run_multi_op` call `apt` directly; queries use `apt-cache`/`apt-mark`. A mid-session manager change takes effect immediately because `MGR` is read at each call.
- **fzf layer:** `have_fzf()` checks `FZF_ENABLED=1` + `NO_FZF!=1` + `command -v fzf` (plus a `$FZF_BROKEN_FLAG` session file). fzf is the sole interactive UI (gum is gone): `main_menu`, `do_palette`, `do_install`/`do_uninstall` (via `use_fzf_for_op`), and every submenu via `pick_menu`/`pick_multi`/`pick_one`. **ESC contract (v5.2):** ESC cancels, everywhere.
 Top-level menu → exits with the farewell; submenus (`pick_menu`/`pick_multi`/`pick_one`) → return 1 so the `do_*` caller goes back a level; the install/uninstall picker prints `Canceled.` and returns to the menu — there is deliberately NO typed-name detour anymore. The only way to reach the typed name prompt is the text-mode menu (or `NO_FZF=1`). A *fzf failure* (exit ≥ 2) is a different thing: it prints the error and touches a per-session `$FZF_BROKEN_FLAG`; every later `have_fzf()` returns false and each picker falls through to its numbered list for the rest of the session. Theme via `fzf_theme()`/`fzf_select()`. Uninstall picks from `dpkg-query` (installed only), install from a cached not-installed-only list at `~/.pkg-manager-fzf-cache` (30 min TTL). Settings row 11 toggles `FZF_ENABLED` (on/off).
- **v5.1/v5.2/v5.3 fzf details:**
  - Rows are `name|display` (package pickers) / `label\x1fdescription\x1frow\x1fdetail` (menu + palette). `fzf_select` reads the optional globals `FZF_PREVIEW` (preview shell command), `FZF_NTH` (extra field flags) and `FZF_GHOST` (input-line hint) — callers set what they need, then reset all three to `""` after the call.
  - Field flags: `--delimiter=| --nth=1,2 --with-nth=2` on 2-field rows (search covers both, the pretty column is shown, answer parsed with `cut -d'|' -f1`). **Never `--nth=2` alone** — fzf 0.74 then matches nothing.
  - The menu/palette show field **1** of four, and fzf's `--with-nth` leaves a delimiter marker for hidden fields, so their separator must be **invisible**: rows are joined with `$'\x1f'` and `FZF_NTH="--delimiter=\x1f --nth=1,2 --with-nth=1"` (the regex escape works; a literal `|` printed a `|` at the end of every row). fzf returns the ORIGINAL row, so the label is recovered with `${sel%%$'\x1f'*}` — `${sel%%|*}` silently returns the whole row and breaks dispatch.
  - Preview placeholders: use fzf's field placeholder `{1}` (the bare name). A literal `{\}` in the preview string is NOT substituted and leaks `=== {} ===` into the pane. The menu preview uses `{1} {2} {4} {3}` (label, description, detail, row); search results are single-field so **no** `FZF_NTH` (a `--with-nth=2` there would show an empty column).
  - **Ghost:** `FZF_GHOST` is only passed after `fzf_supports_ghost()` confirms fzf ≥ 0.61 — an unknown flag makes fzf exit 2, which the app reads as "fzf broke" and drops to text mode. The probe runs with `FZF_QUEUE='' FZF_CALL_LOG=/dev/null`, because the test-suite fake fzf pops a queued answer on every call.
  - Geometry is screen-adaptive: `fzf_layout()` picks `right:45%:wrap:border-left` on wide/landscape terminals and `down:45%:wrap:border-top` otherwise; `fzf_height()` keeps the window below 100%; `fzf_disp_max()` returns the widest display column a picker may use.
  - **Picker polish flags (all in `fzf_select()`):** `--no-hscroll --ellipsis="…"` (overflow rows are cut at the right edge, never H-scrolled into a `··…··` middle slice), `--tiebreak=begin,length,index` (a match near the START of the row — the package/action NAME — wins over an equal-scoring match in the description), and, when the installed fzf supports them, `--highlight-line` (whole current row) + `--scrollbar='▏'`. The capability probe runs ONCE per session into the **exported** `APP_INIT_CAPS` (before `FIRST_LOOP=1`): `fzf_select` always runs inside a command substitution, where a local variable would die with the subshell and every picker would pay two `fzf --help` forks.
  - **Ctrl-Y copies the highlighted name** (`termux-clipboard-set`, Termux:API). The bind is only added when that binary exists, so the key is simply unbound otherwise. `{1}` is the bare name (field 1 of the original row), never the display column.
- **Banner visibility (v5.2):** the banner + status strip travel **INSIDE the fzf window** — they are its `--header`. Text printed *above* an fzf window is static: on a terminal resize fzf re-anchors its window and the static text above it is wiped for good (fzf cannot repaint it). Inside the window fzf owns the text and redraws it on every resize. `fzf_select()` builds the header as `banner_header` + the caller's own header (a caller `--header=` is **merged**, never replaces the banner), and the main loop prints the banner statically only in text mode (`have_fzf || banner`) — printing it in fzf mode as well would show it twice. `banner_header()` drops the 5-line art below 20 rows so the picker keeps list rows (the strip stays). Height must stay **below 100%** (`fzf_height()` = `(lines-1)*100/lines`, capped 50–95): at 100% fzf enters fullscreen and switches to the **alternate screen**, which hides the picker. `--layout=reverse` keeps natural top-down order (bottom-anchored layout reads like `tac`). fzf also clears its whole managed area, margins included, so never try to preserve content with `--margin`. `term_size()` trusts `tput` only when attached to a tty (a non-tty `tput` happily returns the terminfo default 80), then `COLUMNS`/`LINES`, then 80×24.
  - Package previews (`pkg_preview_cmd <install|remove>`) show the dpkg status line, a mode-specific line (candidate version / "WILL BE REMOVED") plus a size-humanized `apt-cache show` record, colored by `bat` when installed. The install picker lists **not-installed** packages only (filtered against `dpkg-query`); uninstall gets its own prompt/header/footer and installed-only rows.
  - Prompt glyph is `❯ ` everywhere (menus, palette, package pickers).
  - `main_menu` has exactly ONE fzf block — a duplicate call made ESC reopen the menu (fixed in v5.1); the `menu_unique` test guards the row set.
- **CLI mode:** `--help --version --list-themes --theme <n> --export-theme <n>` are parsed before the main loop. v5.1 adds `--check-updates` (list upgradable), `--quiet` (count only, machine-readable) and `--doctor` (full audit, then exit) — all non-interactive (`CLI_MODE`) and exit before `FIRST_LOOP`. `install.sh --theme <n>` calls `pkg-manager --export-theme <n>` so palettes live in one place.
- **Upgrade center fzf picker** (`do_upgrade_center`): instead of printing the list and
  wiping it with the picker, rows are `【 】 name  installed → candidate` (US-separated,
  search covers label+description) with a dedicated preview — the from→to transition is
  always visible; the `All packages` row is the first row. ESC/Back returns to the menu.
- **`ask_name()` is fuzzy too (v5.3.1):** every `pkghint="pkg"` prompt on a tty opens a
  single-select fzf picker over `apt-cache pkgnames` with the shared info preview;
  `--bind=enter:accept-non-empty` (probed via `--accept-nth` in `--help`) keeps a stray
  Enter from accepting the first alphabetical row; ESC / Back row cancels one level
  (the typed prompt is the no-fzf path), the Exit row leaves the app. Gated on
  `[ -t 0 ]`, so test feeds never trigger it — the typed path is what the suite covers.
- **installed-kind prompts** (uninstall/reinstall/purge/hold+unhold/downgrade/"mark as"/
  explain/installed-files — keyword-matched) fuzzy-search the INSTALLED list, and the typed
  fallback is guarded: an uninstalled name gets "'X' is not installed" instead of raw
  apt-mark/dpkg errors (real apt: `apt-mark manual X` → "can not be marked as it is not
  installed", `apt-mark hold X` on uninstalled "succeeds" meaninglessly). Guard checks
  `list_installed_names | grep -Fxq` so the fake apt stub covers it in tests.
- **Two ways out of a submenu (v5.3.1):** every submenu picker appends TWO trailing rows — `OPTION_SUB_EXIT` ("⬅️ Back to main menu") and `OPTION_APP_EXIT` ("🚪 Exit pkg-manager") — plus **Ctrl-Q** in any fzf picker. Back = one level up (rc 1, exactly like ESC; the row is stripped, and other selections still go through). Exit = leave the APP: it sets `~/.pkg-manager-exit` (`request_app_exit()`), the main loop answers it with the farewell and breaks, and the EXIT trap removes the flag. The request MUST travel through that file: picker code always runs inside a command substitution, where a variable would die with the subshell. Back must NEVER quit the app (a v5.3 release made one row do both, which was confusing); the main menu's own `OPTION_EXIT` row and ESC-on-main-menu are the other app exits. `fzf_select` is the single chokepoint that strips both rows and adds the `ctrl-q:execute-silent(touch $APP_EXIT_FLAG)+abort` bind.

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
| `~/.pkg-manager-exit` | presence = "submenu Exit / Ctrl-Q was picked" | `request_app_exit()` / `app_exit_wanted()` (removed by the EXIT trap; the main loop answers it) |
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
| `dep_tree()` | Dependency resolver, depth capped at 4 (`manager.sh:1881`) |
| `do_depgraph()` | Colored forward/reverse dependency graph + manual-vs-dependency check (`manager.sh:5021`) — menu row 50, distinct from `do_deptools()` (row 27) |
| `pkg_preview_cmd()` | fzf preview per mode (`manager.sh:4758`): dpkg status + candidate/removal line + size-humanized `apt-cache show` — shared by the install, uninstall AND search pickers |
| `batch_preview()` / `human_size()` | Pre-flight install summary (`manager.sh:4850` / `4840`): aligned version column, total installed size, already-present and not-found flags |
| `term_size()` / `fzf_layout()` / `fzf_height()` / `fzf_margin()` / `fzf_disp_max()` | screen-adaptive geometry (`manager.sh:4472`-`4506`, `fzf_disp_max()` at `4301`); height stays below 100% so fzf never switches to the alternate screen, and `fzf_disp_max()` is the widest display column a picker's rows may use |
| `fzf_supports_ghost()` | 1 when fzf ≥ 0.61 understands `--ghost` (guards the whole ghost feature) |
| `refresh_fzf_cache()` (`manager.sh:4392`) | Rebuilds the `name\|description` picker cache (installed-only rows removed); the display column is built and capped when the list is READ, so a resize can't invalidate it; install rows are NOT-installed packages only |
| `banner_text()` / `banner_refresh()` / `banner()` / `banner_header()` | banner art + status strip as text; cached per menu iteration (`BANNER_BLOCK`); `banner()` prints it (text mode), `banner_header()` returns it for the fzf header |
| `MENU_DESC` / `MENU_DETAIL` | per-action one-liner + what the action actually runs; both keyed by the final label, both asserted complete by a test |
| `list_numbered()` | one numbered-list renderer for every text-mode list: right-aligned number column + `LIST_NUM_W` for the trailing row |
| `request_app_exit()` / `app_exit_wanted()` (`manager.sh:88` / `89`) | write / test the submenu-exit flag file; the request must ride a file because pickers run inside command substitutions |
| `refuse_symlink()` / `safe_cp()` (`manager.sh:71` / `78`) | symlink-attack guards for fixed-path `>`/`>>` writes and backup destinations |
| `have_fzf()` (`manager.sh:344`) | FZF_ENABLED + NO_FZF + `$FZF_BROKEN_FLAG` file + command lookup — the broken-session demotion survives the `$(...)` that pickers run inside — gate for every fzf path |
| `fzf_theme()` / `fzf_select()` (`manager.sh:4438` / `4536`) | theme-colored picker: merges the caller `--header=`, adds the banner/ghost/polish flags, and strips BOTH trailing rows — `Back to main menu` (lone pick returns rc 1 = back one level) and `Exit pkg-manager` (sets the exit flag for the main loop) |
| `pick_menu()` / `pick_multi()` / `pick_one()` | submenu pickers (fixed items / multi list / stdin list) — fzf first, then the original numbered text list |
| `fzf_pick_pkgs()` / `use_fzf_for_op()` | package pickers; ESC prints `Canceled.` and returns (no typed-name detour) |
| `paint()` / `set_theme()` / `theme_ansi()` | color engine: 256-index + `#RRGGBB` truecolor |
| `apply_termux_theme()` | export palette to `~/.termux/colors.properties` (backup first) |
| `do_theme()` | The theme hub (pick / preview all / apply to Termux / restore) — the ONE theme row, inside Settings only |
| `set_theme_pick()` / `theme_preview()` / `apply_termux_theme()` | theme label list, swatch preview, Termux palette export |
| `do_essentials()` / `do_sysinfo()` / `do_whatsnew()` | v5.0 hubs (menu rows 54–56) |

## Gotchas

 - Banner art is gzip-compressed, base64 in `BANNER_B64` (`manager.sh:390`). Re-compress after editing.
 - **Never reuse an `OPTION_*` variable name** — a shadowed assignment once made two menu rows render identically and left `do_depgraph()` unreachable (bash `case` takes the first match). The `menu_unique` test asserts 58 unique menu rows (57 options + Exit), so CI catches a repeat instantly.
- `install.sh` uses atomic writes (`.tmp` → `mv`) — never overwrite in place.
- `set -o pipefail` active — pipelines fail on first error.
- `log()` records successes only; `log_err()` for failures.
- Tests set `ICONS=emoji` via env. Input via stdin (text). `NO_FZF=1` is the default; only the `F()` tests unset it and feed `FZF_QUEUE`.
- Group delimiter is `::` (`manager.sh:2727`), names sanitized to `[A-Za-z0-9 _-]`.
- `FAVS_PINNED=1` triggers `build_menu()` after favorites changes.
- JSON export requires `python3`; falls back to text.
- Bash functions must be DEFINED before `FIRST_LOOP=1` — the `while true` loop only executes top-level code linearly, so anything defined after it is undefined inside the loop. The MAX-4.1 block (fzf cache, `do_repos`, `do_undo`, `do_health`, `do_snapshot`) was moved above the loop in v5.0; keep new handlers there.
- Settings rows: text-menu `case "$choice"` numbers 1–12 (2 = the theme hub, 11 = fzf picker on/off, 12 = Back). Adding/removing a row reshuffles all numbers — update both the fzf item list and the text list, plus every test that feeds a number.
- `have_fzf` returns false for every test unless `NO_FZF` is unset, so the real fzf never blocks the suite; `tests/fakebin/fzf` answers `FZF_QUEUE` (one line per call, `MULTI:` = several), and exits 1 with no output to emulate ESC.

- `list_upgradable()` returns apt's real exit code — distinguish empty from failure.

## Symlink-Attack Guards (v5.3.1)

- Every fixed-path write to `$HOME` is either validated before it happens or refused through a symlink:
  - `refuse_symlink()` (`manager.sh:71`) blocks `: >`/`>>` on `~/.pkg-manager-exit`, `~/.pkg-manager-watch`, `~/.pkg-manager.log`.
  - `safe_cp()` (`manager.sh:78`) refuses to copy onto an existing symlink, used for every `.bak` write (conf, colors, sources.list, repo backup, self-update).
  - `.pkg-restore` staging: snapshot restore extracts into a scratch dir, gates every member against an allowlist (`pkg-list.txt`, `.pkg-manager-favs`, `.pkg-manager-groups`, `.pkg-manager.conf`, `.pkg-manager-notes`), rejects `..`/absolute paths and symlinks/devices, backs up each existing target before overwrite.
- Preview/Ctrl-Y quotes `{1}` via fzf's single-quoted substitution — safe; Ctrl-Q path is `%q`-escaped.
- Installed snapshots from another host are arbitrary-write-attacks by construction; only this app's snapshot allowlist is trusted.

## Version Bump

1. `VERSION="5.3.1"` in `manager.sh:17` — the single source of truth (`install.sh` derives its banner from it; nothing else hardcodes a version).
2. README: version badge, the `vX.Y.Z highlights` line in whatsnew, and the two banner blocks stay version-free (the status strip prints the version).
3. `BANNER_B64` (`manager.sh:390`) holds the **ETPM** figlet wordmark with no version in it — regenerate only when the wordmark changes:
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
- `local` is a bash/zsh extension — fine here: the app is invoked as `bash manager.sh`, so the
  `#!/bin/bash` shebang line is never used. Don't run scripts by direct path (`./manager.sh`)
  — on Termux `/bin` is Android's toolbox, not a shell directory.

## fzf CLI Specifics

- `fzf` reads the candidate list on stdin and prints the selection on stdout. Exit codes: **0** = picked, **1** = abort (ESC → cancel), **≥ 2** = fzf itself failed (the app prints the error and switches to text mode). `fzf -m` enables multi-select.
- `fzf --color=...` accepts the themed palette string built by `fzf_theme()` (works for 256-index and `#RRGGBB`).
- The fake fzf in `tests/fakebin/fzf` pops one line per call from `FZF_QUEUE` (`MULTI:` prefix = several selections); empty queue → exit 1 (ESC). It answers `--version` (0.61.0) and `--help` (a capability list) **without popping the queue**, so the feature probes in the app behave exactly like they do against the real fzf.

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

## Verification workflow — READ FIRST

**Do not run the full test suite by default.** It takes ~6 minutes on this device, runs against
every path, and wastes that time on a one-path change. `make test` / `make check` are END-of-work
gates for cross-cutting changes, not a routine check.

Default loop:

1. `make lint` — `bash -n` + shellcheck on every script, a few seconds. **After every edit.**
2. One focused exercise of the path you changed (below) — seconds, not minutes.
3. Full suite **only** when the change is cross-cutting: the main loop, `fzf_select`, `pick_menu`,
   `pick_one`/`pick_multi`, `fzf_pick_pkgs`, or anything every picker passes through.

### Fast focused check (~2 s) — fzf mode, no suite needed

`tests/fakebin/fzf` pops one answer per call from a queue file, so a whole menu → picker →
confirm flow can be driven directly. Set `FZF_CALL_LOG` to a **file** (not /dev/null) to inspect
exactly what a picker was passed:

```bash
h="$TMPDIR/pkmgr-probe"; rm -rf "$h"; mkdir -p "$h/var/cache/apt/archives"
touch "$h/var/cache/apt/archives/python3_3.12_arm64.deb"      # seeds the fake dpkg db
printf '\xf0\x9f\x93\xa6 Install a package\npython3\ny\n' > "$h/queue"   # one line per fzf call
FZF_QUEUE="$h/queue" FZF_CALL_LOG="$h/calls" HOME="$h" PREFIX="$h" MGR=apt ICONS=emoji \
    PATH="$PWD/tests/fakebin:$PATH" env -u NO_FZF bash manager.sh < /dev/null
```

- The queue is consumed in call order; once it runs dry the fake fzf exits 1 (= ESC), which is how
  abort paths get exercised.
- `ICONS=emoji` matters: menu labels embed the icon, so queued answers must match it.
- `HOME`/`PREFIX` point at a temp dir — nothing real is installed or configured.
- Text mode: `printf '3\n' | NO_FZF=1 TERM=dumb bash manager.sh` (numbered menus, same `do_*` bodies).
- One function in isolation: `bash -c 'source <(sed -n "/^fzf_select()/,/^}/p" manager.sh); ...'`.

### When the full suite is actually required

Cross-cutting changes (shared chokepoints), before declaring work finished, or when a test you
added is the point: `make test`. Then run `make check` (lint + suite) once at the very end.

The runner has **no per-test filter** — `bash tests/run-tests.sh` always runs all 182 tests.

## Debugging Workflow

1. Verify targeted, not globally (see above): lint + one direct exercise of the changed path.
2. Reproduce in the harness: add a `T`/`F` case, or inspect `tests/tmp/<name>/run.log` + `fzf-calls` for picker errors.
3. Interactive check last: `bash manager.sh` manually.
4. Never test destructive paths (purge, autoremove) on a real device — extend the fakebin stubs instead.
5. When you report back, say which gates you ran: "lint OK + the two focused tests" is a better answer than silently paying 4 minutes.

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
- Dep tree depth capped at 4 (`dep_tree()`, `manager.sh:1881`).
- `list_upgradable()` propagates apt exit code.
- Menu rebuild on favs change is O(57 items) with no external calls — instant.

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
| Banner disappears in the picker | Old build: the banner was static text above the window and a resize wiped it. It now rides inside the picker (its header), so fzf redraws it — upgrade and make sure the header still carries the banner |
| A picker row shows a `··…··`-wrapped middle slice | Old build: rows wider than the pane were H-scrolled to keep fzf's match + hscroll-off visible. Now the row is capped to the pane (`fzf_disp_max()`) — and the picker itself passes `--no-hscroll --ellipsis="…"`, so an overflow cuts the TAIL at the right edge instead of scrolling. The full text is also always in the preview pane |
| "possible misspelling: ICON_XXX" from shellcheck | The icon does not exist in `init_icons()` (both branches) — use a real one or add it to both 

## Termux Ecosystem

- **Termux:Boot** — scripts in `~/.termux/boot/`, sorted order. Start with `termux-wake-lock`.
- **Termux:API** — `termux-notification`, `termux-toast`, `termux-clipboard-set`, etc. Requires main app + API app same signature. Notification actions run in `dash -c` — set PATH explicitly.
- **termux-reload-settings** — applies `~/.termux/termux.properties` changes. Run `pkg upgrade` first on fresh installs (older termux-tools had a bug).
- **termux-change-repo** — interactive mirror selector; `pkg` auto-rotates mirrors.
- **termux-setup-storage** — creates `~/storage/` symlinks. May fail silently if permission not granted — revoke + re-grant in Android Settings.
