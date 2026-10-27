# AGENTS.md — Easy-Termux-Package-Manager

> **This is Termux, not Linux.** Bionic libc (not glibc), no FHS filesystem, no root. `$PREFIX` = `/data/data/com.termux/files/usr`. All standard Linux assumptions can break here. `manager.sh` is a single-file Bash app (~3.5k lines); `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`/`apt`/optionally `gum`. CI: `.github/workflows/ci.yml` (tests gated to Termux runners).

## Make

| Target | What |
|--------|------|
| `make run` | Launch app (`GUM_ENABLED=0 make run` = text mode) |
| `make test` | Full test suite (169 tests, ~3 min, text + gum modes) |
| `make lint` | `bash -n` + `shellcheck` (0 findings; SC2015/SC2119/SC2120 ignored) |
| `make check` | Lint + test |
| `make install` / `make uninstall` | Via `install.sh` / `rm $PREFIX/bin/pkg-manager` |
| `make clean` | Delete `tests/tmp/` |

```bash
export TMPDIR=/data/data/com.termux/files/usr/tmp
bash manager.sh
bash tests/run-tests.sh
```

Tests use `tests/fakebin/` stubs for `apt`/`dpkg`/`gum` — no real Termux or package changes. 169 scenario tests; `tests/tmp/` is gitignored.

## Hard Rules

- **Config is never `source`d** — `load_config()` parses `~/.pkg-manager.conf` as text KEY=VALUE (`manager.sh:50-88`). Never `source` user files (option injection / RCE risk).
- **Temp files via `scratch_new()` only** — uses `mktemp`, cleaned by EXIT trap. Never `/tmp/foo`.
- **Package name validation via `valid_pkg_name()`** — rejects leading `-`, spaces, shell metacharacters. Use before ANY user name hits `apt`/`dpkg`.
- **Always quote `$MGR`** (apt or pkg) — unquoted breaks on word splitting.
- **Both UI modes or nothing** — every feature needs a `$GUM=1` and `$GUM=0` branch. Tests check both.
- **Call `apt_hint()` after every apt operation** — translates raw apt/dpkg errors to friendly messages (`manager.sh:586-608`).
- **Run `filter_pkgs()` before any user input hits apt** — calls `valid_pkg_name()`, strips invalid names. Critical for preventing option injection.
- **Never `set -e`** — `manager.sh` uses `set -o pipefail` only; `set -e` breaks the menu loop.

## Code Structure

| File | Role |
|------|------|
| `manager.sh` | The entire app (~3.5k lines) |
| `install.sh` | Installer (atomic writes: `.tmp` → `mv`), offers Nerd Font |
| `Makefile` | Dev targets (`run`/`test`/`lint`/`check`/`install`/`uninstall`/`clean`) |
| `fonts/` | Bundled Nerd Font TTFs (CaskaydiaCove, FiraCode) |
| `tests/fakebin/` | Stubs for `apt`, `dpkg`, `gum`, `curl`, etc. |
| `tests/seeds/` | Per-test seed data |
| `tests/helps/` | Fake `gum` help output (flag validation allowlists) |

## Architecture

- **Config precedence:** env overrides → config file → hardcoded defaults (`manager.sh:18-27`, `90-110`), all validated via case statements.
- **Confirmation (3-layer):** `CONFIRM=1` (normal) → `QUIET=1` (skip all) → `LOCK=1` (force even if QUIET). `confirm_danger()` checks LOCK first.
- **Main loop** (`manager.sh:3495-3544`): `while true`; first iteration runs `do_maintenance` if `STARTUP_CHECK=1`; `pause` after each action. Pinned favorites dispatched via `*"Pinned:"*` glob.
- **`run_multi_op()`** (`manager.sh:615-665`): batch fast path (single `apt install/remove -y`), falls back to per-package retry on failure. `RECYCLE=1` + remove → `archive_pkg()` first.
- **Logging:** `log()` successes only, `log_err()` failures (`manager.sh:431-441`, both to `~/.pkg-manager.log`). Undo reads log via `grep`.
- **`$GUM` flag (0/1):** every UI function has both branches. New features need both.

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

## Key Functions

| Function | Purpose |
|----------|---------|
| `load_config()` | Parse KEY=VALUE from `~/.pkg-manager.conf` |
| `save_config()` | Write config file |
| `valid_pkg_name()` | Reject option-injection / shell metachars |
| `filter_pkgs()` | Call `valid_pkg_name()`, strip invalid names |
| `run_multi_op()` | Batch apt install/remove with per-package fallback |
| `useAmmo(id)` | **Always** decrement ammo (direct dec = NaN) |
| `apt_hint()` | Translate apt/dpkg errors to friendly messages |
| `scratch_new()` | mktemp-based temp file creation (EXIT trap cleanup) |
| `build_menu()` | Rebuild menu (called after favs change if `FAVS_PINNED=1`) |
| `dep_tree()` | Dependency resolver, depth capped at 4 (`manager.sh:1386`) |

## Gotchas

- Banner art is gzip-compressed, base64 in `BANNER_B64` (`manager.sh:246`). Re-compress after editing.
- `install.sh` uses atomic writes (`.tmp` → `mv`) — never overwrite in place.
- `set -o pipefail` active — pipelines fail on first error.
- `log()` records successes only; `log_err()` for failures.
- Tests set `ICONS=emoji`, `GUM_ENABLED` via env. Input via stdin (text) or base64 queue files (gum).
- Group delimiter is `::` (`manager.sh:2250-2260`), names sanitized to `[A-Za-z0-9 _-]`.
- `FAVS_PINNED=1` triggers `build_menu()` after favorites changes.
- JSON export requires `python3`; falls back to text.
- `cycleAmmo()` "+"` skips `0` rung (∞→1); "− "` on ∞ is a no-op.
- Imported ammo values snapped to `VALS` (7→6, 9→8).
- `list_upgradable()` returns apt's real exit code — distinguish empty from failure.
- Every projectile needs `p.fuse!==undefined` check in `updateProj()`.
- Unlimited-in-`SCH` weapons still call `useAmmo(id)` — direct decrement → NaN.

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

## gum CLI Specifics

- `gum confirm` exits 1 on "No" — not an error. `if gum confirm; then` handles it.
- Interactive gum needs a TTY — piped stdin/stdout fails/hangs. Probe: `gum style "probe"`.
- `gum spin` swallows output — use `--show-output` to surface it. `run_spin()` returns exit code; preserve that contract.
- `gum choose` prints selections one per line. Fake gum pops one base64 line per call from `GUM_QUEUE`.
- **Flag allowlists:** tests validate every `-flag` against `tests/helps/{choose,input,confirm,file,style,pager,spin,filter}`. New gum usage = update allowlists or tests fail.

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
2. Inspect `tests/tmp/<name>/run.log` + `calls`/`validate` files for fake-gum flag errors.
3. Only then run `bash manager.sh` manually (text mode: `GUM_ENABLED=0 bash manager.sh`).
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
