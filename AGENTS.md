# AGENTS.md

## What this is

Single-file Bash app (`manager.sh`, ~2.9k lines) -- an interactive package manager for Termux. `install.sh` copies it to `$PREFIX/bin/pkg-manager`. No build step, no dependencies beyond `bash`, `apt`, and optionally `gum`.

> **This is Termux, not Linux.** Termux runs on Android without root, uses Bionic libc (not glibc), has no FHS-compliant filesystem, and packages live under `/data/data/com.termux/files/usr`. Every assumption about standard Linux paths, permissions, or system calls can break here.

## Make

`make` is not preinstalled in Termux -- `pkg install make shellcheck` once.

| Target | Does |
|--------|------|
| `make run` | launch app (`GUM_ENABLED=0 make run` = text mode) |
| `make test` | full 130-test suite (~2 min) |
| `make lint` | `bash -n` + `shellcheck --severity=style` on all shell scripts (must stay at 0 findings; the one intentional `SC2034` in `tests/fakebin/apt` carries an inline disable) |
| `make check` | lint + test |
| `make install` / `make uninstall` | via `install.sh` / `rm $PREFIX/bin/pkg-manager` |
| `make clean` | delete `tests/tmp/` |

## Run

```bash
bash manager.sh
```

## Test

```bash
bash tests/run-tests.sh
```

Uses fakebin stubs (`tests/fakebin/`) for `apt`, `dpkg`, `gum`, etc. -- no real Termux needed. Run from the `tests/` dir or from the repo root; the script `cd`s into its own directory. 130 scenario tests in text and gum modes. `tests/tmp/` is gitignored.

## Code structure

- `manager.sh` -- the entire app. Every menu option, every function.
- `install.sh` -- global installer, copies `manager.sh` to `$PREFIX/bin/pkg-manager`, offers Nerd Font install.
- `Makefile` -- dev targets: `run`, `test`, `lint`, `check`, `install`, `uninstall`, `clean`. `lint` must stay at 0 findings.
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
| `~/.pkg-manager-notes` | `pkg::note` (one per line) | User notes |
| `~/pkg-snapshot-*.tar.gz` | tar of `pkg-list.txt` + favs/groups/conf/notes | Full snapshot |

## Version bump

Three places: badge in README, ASCII art line (`v3.0`), fallback string in `manager.sh:238`. Then regenerate `BANNER_B64` (compressed blob).

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

### Environment variable traps

- **Never set `LD_LIBRARY_PATH` globally** -- it overrides Android's built-in library search path and breaks packages like `mpd`, `mpv`, `pulseaudio`. Set it per-binary with `LD_LIBRARY_PATH=/your/path ./binary` if needed at all. Modern Termux uses `DT_RUNPATH` ELF sections instead.
- **`TMPDIR` may not be set in SSH sessions** -- Termux sets it in the app, but SSH/logins may miss it. Export `TMPDIR=$HOME/tmp` in `~/.profile` as a safety net. Many programs silently fall back to `/tmp` which does not exist.
- **`$PREFIX` is deprecated in favor of `$TERMUX__PREFIX`** -- double underscore is the new namespace. The old `$PREFIX` still works but may be removed in a future Termux 1.0. For scripts targeting the package build system, use `@TERMUX_PREFIX@` placeholders (replaced at build time), not runtime variables.
- **Cron jobs run with a stripped environment** -- `cronie` only inherits `USER`, `HOME`, `LOGNAME`, `PATH`, `LANG`, `SHELL`, `PWD`. It lacks `TMPDIR`, `TZ`, `LD_PRELOAD`, `PREFIX`, `ANDROID_ROOT`. Source `~/.profile` in cron entries: `* * * * * . $HOME/.profile; your-command`.
- **`/system/bin` not in PATH, and that is intentional** -- Termux deliberately excludes it to avoid ABI conflicts. Adding it globally can cause `CANNOT LINK EXECUTABLE` errors when Termux binaries pick up incompatible system libraries.

### Background processes and battery

- **Android kills background apps aggressively** -- without wake lock, `crond` and background processes freeze when the screen is off. Enable wake lock via the Termux notification (expand and tap WAKE) or `termux-wake-lock`.
- **Cronie needs the app open** -- `crond` must be started manually (`crond &`), and the Termux app must stay in memory. Closing Termux from Recents kills all child processes.
- **`nohup` is not enough** -- use `nohup cmd &` but also ensure wake lock is on, or Android will freeze the process regardless.
- **`termux-job-scheduler`** uses Android's JobScheduler API -- works even without an active session, but only runs when Android decides (battery optimization, charging state, etc.). Check Settings > Apps > Termux > Battery to disable optimization.

### Storage and file access

- **External storage is mounted `noexec`** -- binaries cannot execute from `/sdcard` or `~/storage/shared`. Copy them to `$PREFIX/bin` or use a wrapper like `noexec` (ByteJoseph/noexec) to automate the copy-run-delete cycle.
- **Android 11+ scoped storage** -- `Android/data` and `Android/obb` are restricted. Even with "All Files" permission, direct shell access to other apps' `Android/data` is blocked. Only `Android/data/com.termux` is accessible (created via `termux-setup-storage` which uses Android APIs).
- **`~/storage` is symlinks, not bind mounts** -- `~/storage/shared` points to `/storage/emulated/0`, `~/storage/downloads` to `~/storage/shared/Download`, etc. Access is gated by Android's FUSE layer on Android 11+.
- **`termux-setup-storage` may fail silently** -- on some devices/configs, the permission prompt does not appear. Revoke and re-grant storage permission in Android Settings, then re-run the command.
- **Never `rm -rf ~/storage/shared/*`** -- this deletes the user's actual phone files. Always quote paths carefully and double-check before destructive operations on paths outside `$PREFIX`.

### What to never do in this codebase

- Do not `source` or `eval` anything from `~/.pkg-manager.conf`.
- Do not use `/tmp` -- use `scratch_new()` with the EXIT trap.
- Do not assume `gum` is installed -- always have the text-mode fallback.
- Do not hardcode `/usr/bin`, `/bin`, `/etc` -- use `$PREFIX`.
- Do not use `sudo` or assume root access exists.
- Do not pipe untrusted input to `bash -c` or `eval` -- the search function's install-from-results uses `run_multi_op` with validated names only.
- Do not use `set -e` in `manager.sh` -- it intentionally uses `set -o pipefail` only; `set -e` would break the menu loop.

### Termux ecosystem tools and companions

- **Termux:Boot** -- run scripts at device boot from `~/.termux/boot/`. Scripts execute in sorted order. Always start with `termux-wake-lock` to keep the device awake. The app must be launched once manually after install for its receiver to register.
- **Termux:API** -- provides `termux-notification`, `termux-toast`, `termux-vibrate`, `termux-clipboard-set`, `termux-battery-status`, `termux-wifi-connectioninfo`, etc. Requires both the main Termux app and the API app to be installed, signed with the same key. Notification actions run in `dash -c` (not bash), and inherit a different environment -- set `PATH` explicitly in action scripts.
- **termux-reload-settings** -- applies changes to `~/.termux/termux.properties` (extra keys, bell behavior, colors, etc.) without restarting the app. Required after editing the properties file. On fresh installs, run `pkg upgrade` first as older `termux-tools` had a bug where this command aborts.
- **termux-change-repo** -- interactive mirror selector for `apt` repositories. `pkg` handles mirror rotation automatically, but this script lets you pin a specific mirror or mirror group. Useful when `apt update` fails due to a dead mirror.
- **termux-setup-storage** -- creates `~/storage/` symlinks to Android shared storage. Uses Android APIs, not shell, to create `Android/data/com.termux`. May fail silently if storage permission is not granted -- revoke and re-grant in Android Settings, then re-run.

### Bash behavior quirks in Termux

- **`~/.bashrc` may be sourced twice** -- Termux's `$PREFIX/etc/profile` sources `~/.bashrc` even for login shells. On standard Linux, login shells do not source `.bashrc`. If you use `readonly` or `export PATH` in `.bashrc`, it will error on re-source. Guard with `if ! shopt -q login_shell; then ... fi` or check `BASH_SOURCE`.
- **Bash regex uses Bionic's POSIX regex, not GNU** -- `[[ "$var" =~ (a|b) ]]` works on glibc but fails on Bionic if the alternation starts or ends with `|`. Use `[[ "$var" =~ a|b ]]` or `[[ "$var" =~ (a|b|) ]]` with care. Bionic's regex is BSD-derived.
- **`echo` does not interpret escape sequences by default** -- use `printf '%b\n'` instead of `echo -e`. Bionic's `echo` built-in ignores `-e` unless POSIXLY_CORRECT is not set.
- **`read -p` is a bashism** -- POSIX `read` has no `-p` prompt flag. This app uses `printf` + `read -r` everywhere for portability across shells (sh, dash, bash).
- **`local` is not POSIX** -- it is a bash/zsh extension. Works in Termux because `manager.sh` explicitly uses `#!/bin/bash`, but don't assume it works in all shell scripts on the device.

### Security considerations for this codebase

- **No eval on user input** -- `run_multi_op` builds the apt argument list via validated array expansion, never through string interpolation. Never change this to `eval "$MGR install $pkgs"`.
- **Symlink attack prevention** -- `scratch_new()` uses `mktemp` to create temp files with random names. The EXIT trap (`cleanup_tmp`) removes them all. Never create temp files with predictable names like `/tmp/pkg-manager-$$.log`.
- **Package name validation before every apt call** -- `valid_pkg_name()` is called in `ask_name()`, `filter_pkgs()`, `pin_install()`, `do_favs()`, and `run_multi_op()` dedup. This prevents injection of `-f`, `--force`, `--purge`, or shell metacharacters.
- **Config file is not executable** -- `load_config()` reads it as text, never `source`s it. A malicious `~/.pkg-manager.conf` containing `$(malicious command)` is harmless.
- **The installer uses atomic writes** -- `install.sh` writes to a `.tmp` file, then `mv`s it into place. This prevents a partial write from corrupting the installed binary. The font install uses the same pattern for `~/.termux/font.ttf`.
- **Test harness isolates every test** -- each test gets its own `$HOME`/`$PREFIX` under `tests/tmp/`. Tests cannot affect each other or the real system. The EXIT trap cleans up scratch files even on Ctrl-C.

### Performance and reliability

- **`run_multi_op` batch optimization** -- the fast path runs one `apt install/remove -y` for all packages (single resolver pass, single dpkg lock, single progress display). Only on batch failure does it fall back to per-package retry. This makes favorites restore and bulk installs fast.
- **`apt_hint()` is O(n) on output length** -- it's a case statement that matches substrings. For normal apt output (< 100 lines) this is instant. Don't worry about it.
- **Dependency tree depth cap at 4** -- `dep_tree()` (line 1260) stops recursion at depth 4 to prevent runaway on circular deps or massive trees. This is intentional, not a bug.
- **`list_upgradable()` propagates apt's exit code** -- callers can distinguish "no packages upgradable" (exit 0, empty output) from "apt failed" (non-zero exit). Check `$?` after calling it.
- **Menu rebuild on favorites change** -- `FAVS_PINNED=1` triggers `build_menu()` after add/remove/pin/unpin. This is O(n) on the number of menu items but n is always ~35, so it's instant.

### gum CLI specifics (the UI layer)

- **`gum confirm` exits 1 on "No"** -- it is not an error; `if gum confirm ...; then` handles it. Never wrap in `set -e` context without expecting the non-zero path.
- **Interactive gum commands require a TTY** -- piped stdin/stdout or CI contexts make them fail or hang. This app's `refresh_gum()` probes gum with `gum style "probe"` before trusting it; keep that probe when touching UI init.
- **`gum spin` swallows child output by default** -- use `--show-output` if output must survive. This app uses `run_spin()` which returns the wrapped command's exit code -- preserve that contract.
- **`gum choose` prints selection(s) to stdout, one per line** with `--no-limit`. The fake `gum` in tests pops one base64-encoded line from `GUM_QUEUE` per call -- adding new gum flag usage requires updating `tests/helps/<subcommand>` allowlists or tests fail with `UNKNOWN FLAG`.
- **Flags are validated against known-good lists in tests** -- every `-flag` passed to gum is grepped against `tests/helps/{choose,input,confirm,file,style,pager,spin,filter}`; unknown flags fail the suite.

### Terminal rendering quirks in Termux

- **ANSI SGR quirks** -- Termux supports truecolor (`\e[38;2;R;G;Bm`, semicolon form) and colon-separated CSI params since v0.118-era fixes. Blink (SGR 5) is NOT supported. Empty SGR params (`\e[31;m`) are parsed as reset-to-default, matching ECMA-48.
- **User color themes override your colors** -- `~/../usr/etc/colors.properties` remaps the 16-color palette; a "blue" foreground may render red on customized installs. This app uses 256-color codes (46, 45, 212...) which are also themeable but more predictable than named ANSI colors.
- **Escape sequences across `\n` in prompts** -- styling applied before a newline may not persist after it during pinch-zoom redraws. Not relevant inside this app (it styles whole strings via gum), but relevant if hand-rolling prompt-like output.
- **The app never emits raw ANSI itself** -- all styling goes through `gum style --foreground <256-color>` or plain text. Keep it that way so both UI modes render identically.

### Termux app variants and signing

- **Three mutually incompatible install sources** -- F-Droid, GitHub, and Google Play builds each have different APK signing keys. Plugins (Termux:API, Termux:Boot) must match the main app's signature or they cannot communicate. Users cannot mix sources; switching requires full uninstall of app + all plugins.
- **Play Store builds are deprecated/divergent** -- functionally equivalent to v0.108, missing years of fixes, and lack RUN_COMMAND intent. Official sources are F-Droid and GitHub only. Do not test assumptions against Play Store builds.
- **`TERMUX_APK_RELEASE` env var** -- set to `F_DROID`, `GITHUB` (or `GITHUB_DEBUG_BUILD`), `GOOGLE_PLAY_STORE`, or `UNKNOWN`; useful for diagnosing which variant a bug report comes from. Also available: `TERMUX_VERSION`, `TERMUX_APP_PACKAGE_MANAGER`, `TERMUX_IS_DEBUGGABLE_BUILD`.
- **This repo only depends on bash/apt/dpkg/gum** -- none of the plugin apps are required. But font install via installer touches `~/.termux/font.ttf` which the main app reads; Termux:Styling is NOT needed for that path.

### Debugging and diagnostics

- **`termux-info`** -- dumps Termux variables, architecture, subscribed repos, updatable packages, Android/kernel versions. First thing to request in a user bug report.
- **`logcat`** -- Android log stream viewable from inside Termux. Set app log level via Termux Settings > Debugging > Log Level (Normal/Debug/Verbose) first; verbose logs can contain private data.
- **Built-in Report Issue** -- long-press in terminal > More... > Report Issue generates a full report with system info + logcat dump. Ask users for its complete output; partial screenshots get issues closed.
- **Test failures show the manager's own output** -- `tests/tmp/<test-name>/run.log` holds stdout+stderr of the failed run; `calls` and `validate` files hold the fake-gum call log and flag validation errors. Check these before guessing.

### Effective debugging workflow for this repo

1. Reproduce with the harness: add a `T`/`G` case mirroring the user flow, run `bash tests/run-tests.sh`.
2. Inspect `tests/tmp/<name>/run.log` for raw output; the harness already flags `command not found`, bash line errors, and timeouts.
3. Only then run `bash manager.sh` manually (text mode: `GUM_ENABLED=0 bash manager.sh`) -- real apt calls hit the network and modify the device.
4. Never test destructive paths (purge, autoremove) against a real device; extend the fakebin stub instead.

### Locale, timezone, and DNS (not standard Linux)

- **Only two locales exist** -- Bionic provides just `C`/`POSIX` and `C.UTF-8` (aliased `en_US.UTF-8`). No other locale will ever resolve; `LC_*` variables are mostly ignored by Bionic's `setlocale`. Do not add locale-dependent logic expecting glibc behavior.
- **`TZ` is not exported by default** -- `date` reads the Android system timezone via Bionic, so timestamps are usually right, but programs that read `$TZ` directly (emacs, Go binaries, some Python libs) can show UTC. Workaround if ever needed: `export TZ=$(getprop persist.sys.timezone)` in a wrapper, never globally.
- **No `/etc/resolv.conf`** -- Android has none. Programs that hardcode that path fail with DNS errors (`read udp [::1]:53: connection refused`). The optional `resolv-conf` package installs `$PREFIX/etc/resolv.conf`; `termux-chroot`/`proot-distro` bind-mount it into place. This app never resolves DNS itself, so it is unaffected.
- **No `/etc/localtime` or `/usr/share/zoneinfo`** -- Android keeps tzdata at `/system/usr/share/tzdata`. There is no `tzdata` Termux package and `dpkg-reconfigure tzdata` does not exist.

### Filesystem layout mapping ($PREFIX)

| Standard Linux | Termux equivalent |
|----------------|-------------------|
| `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin` | `$PREFIX/bin` |
| `/etc` | `$PREFIX/etc` |
| `/tmp`, `/var/tmp` | `$PREFIX/tmp` (erased on every app restart) |
| `/run` | `$PREFIX/var/run` |
| `/var/lib/dpkg/status` | `$PREFIX/var/lib/dpkg/status` |
| `/var/cache/apt/archives` | `$PREFIX/var/cache/apt/archives` |
| `/etc/apt/sources.list` | `$PREFIX/etc/apt/sources.list` |

- Repos beyond `main`: `root-repo` and `x11-repo` packages drop `.sources`/`.list` files into `$PREFIX/etc/apt/sources.list.d/`.
- Because `$PREFIX/tmp` is wiped when the Termux app restarts, nothing long-lived may live there -- another reason this app keeps scratch files in `$HOME`.

### User-facing failure playbook (support scenarios)

- **"command not found" right after install** -- `$PREFIX/bin` was not on PATH in the current shell; user must open a new session. Not a bug.
- **Icons render as empty boxes** -- no Nerd Font installed. Tell users to switch Settings > Icons > emoji, or install a font from `fonts/`.
- **Font installed but not applied** -- `termux-reload-settings` reloads most things, but a full app kill is sometimes required: `am force-stop com.termux` (or type `exit`), then reopen. Swiping from Recents does NOT kill it.
- **Stuck dpkg locks / interrupted operations** -- recovery order: `dpkg --configure -a`, then `apt --fix-broken install`, then retry. Never delete lock files while another apt process might be running.
- **"Unable to locate package" on fresh installs** -- stale lists; run Upgrade center (apt update) first. `pkg` auto-updates, raw `apt` does not.
- **Upgrade breaks mid-way (busybox/coreutils transition)** -- do NOT abort; let it finish. If broken: `pkg upgrade` again, then `dpkg --configure -a`. Removing busybox before coreutils/findutils/tar are installed bricks the environment.

### Codebase-specific path audit (verified safe)

- Scratch files: `$HOME/.pkg-manager.XXXXXX` via mktemp -- survives `$PREFIX/tmp` wipes, cleaned by EXIT trap.
- Data files: all in `$HOME` -- unaffected by app restarts and `$PREFIX/tmp` cleanup.
- Cache stats: reads `$PREFIX/var/cache/apt/archives` with `du` -- correct Termux location, guarded with `2>/dev/null` fallbacks.
- Log timestamps: `date '+%Y-%m-%d %H:%M:%S'` -- correct on Android without TZ set; do not switch to `date -u`.
- Installer shebang fix: `sed -i "1s|^#!.*|#!$(command -v bash)|"` in install.sh -- handles the non-FHS interpreter path; keep it when editing install.sh.
