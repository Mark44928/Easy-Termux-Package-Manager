#!/bin/bash
# shellcheck disable=SC2218,SC2034,SC2155,SC2207,SC2012,SC2086,SC2001,SC2016,SC2181

# Every pipeline must report the failure of its first command, or "apt foo |
# tail" would let real errors look like success.
set -o pipefail

# Optional env overrides (e.g. NO_FZF=1 pkg-manager) — conf file still wins otherwise.
[ -v MGR ] && MGR_ENV=$MGR || MGR_ENV=""
[ -v THEME ] && THEME_ENV=$THEME || THEME_ENV=""
[ -v CONFIRM ] && CONFIRM_ENV=$CONFIRM || CONFIRM_ENV=""
[ -v LOG_ENABLED ] && LOG_ENABLED_ENV=$LOG_ENABLED || LOG_ENABLED_ENV=""
[ -v ICONS ] && ICONS_ENV=$ICONS || ICONS_ENV=""
[ -v RECYCLE ] && RECYCLE_ENV=$RECYCLE || RECYCLE_ENV=""
[ -v FZF_ENABLED ] && FZF_ENABLED_ENV=$FZF_ENABLED || FZF_ENABLED_ENV=""

VERSION="5.3.1"
MGR="apt"
THEME="green"
CONFIRM=1
LOG_ENABLED=1
ICONS="nerd"
QUIET=0
LOCK=0
STARTUP_CHECK=0
FAVS_PINNED=0
RECYCLE=0
FZF_ENABLED=1

# Scratch files: use mktemp (unique, unguessable names) so a predictable
# fixed path can't be pre-planted as a symlink to truncate a victim via the
# ">" redirect (TOCTOU / symlink attack). Track them so the EXIT trap cleans
# up even on Ctrl-C, and so writers can confirm success before mv.
_SCRATCH=()
scratch_new() {
    local f
    f=$(mktemp "$HOME/.pkg-manager.XXXXXX" 2>/dev/null) || return 1
    _SCRATCH+=("$f")
    printf '%s\n' "$f"
}
# fzf's rc signals: 0 picked, 1 ESC/back, >=2 broken. Pickers are always run
# under $(...), so state must cross the subshell through a file, like
# request_app_exit. A session-scoped broken marker flip has_fzf() false for
# the rest of the session (the app's "finish in text mode" design).
FZF_BROKEN_FLAG="$HOME/.pkg-manager-fzf-broken"
rm -f "$FZF_BROKEN_FLAG" 2>/dev/null || true
cleanup_tmp() {
    local f
    for f in "${_SCRATCH[@]:-}"; do
        [ -n "$f" ] && rm -rf -- "$f" 2>/dev/null
    done
    _SCRATCH=()
    # An exit request must never outlive the session that made it.
    rm -f -- "${APP_EXIT_FLAG:-}" 2>/dev/null
    rm -f -- "${FZF_BROKEN_FLAG:-}" 2>/dev/null
}

trap cleanup_tmp EXIT


# print_safe <s> — strip C0/C1 controls and DEL from a string before display.
# Terminal escape sequences embedded in user-editable logs/notes could plant
# hyperlinks, clear-screen, or fake text in the user's tty.
print_safe() {
    printf '%s' "$1" | sed -e 's/[[:cntrl:]\x7f]//g'
}

# refuse_symlink <path> — stop fixed-path writes being used as a symlink-
# redirection channel (shell trap: planted symlink in $HOME points the append
# or truncation at a victim file).
refuse_symlink() {
    [ -L "$1" ] && { err "Refusing to write through symlink: $1"; return 1; }
    return 0
}

# safe_cp <src> <dst> — like cp -p, but refuses to overwrite a symlink at
# dst (a planted symlink could redirect the write to a victim file).
safe_cp() {
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then err "Refusing to overwrite symlink: $dst"; return 1; fi
    cp -p -- "$src" "$dst"
}


# request_app_exit / app_exit_wanted — the "quit the app from a submenu"
# request. It MUST travel through a flag file: picker code always runs inside
# a command substitution, where a shell variable would die with the subshell.
request_app_exit() { : > "${APP_EXIT_FLAG:-/dev/null}" 2>/dev/null || true; }
app_exit_wanted() { [ -f "${APP_EXIT_FLAG:-}" ]; }
APP_EXIT_FLAG="$HOME/.pkg-manager-exit"

# Load .pkg-manager.conf as plain KEY=VALUE data, never `source`d: the file
# may be planted / hand-edited, and sourcing it would run arbitrary code.
load_config() {
    local line k v
    local c_mgr c_theme c_confirm c_log c_icons c_quiet c_lock c_startup c_favs c_recycle c_fzf
    [ -f "$HOME/.pkg-manager.conf" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        case "$line" in
            *=*) k="${line%%=*}" v="${line#*=}" ;;
            *) continue ;;
        esac
        case "$k" in
            MGR)            c_mgr=$v ;;
            THEME)          c_theme=$v ;;
            CONFIRM)        c_confirm=$v ;;
            LOG_ENABLED)    c_log=$v ;;
            ICONS)          c_icons=$v ;;
            QUIET)          c_quiet=$v ;;
            LOCK)           c_lock=$v ;;
            STARTUP_CHECK)  c_startup=$v ;;
            FAVS_PINNED)    c_favs=$v ;;
            RECYCLE)        c_recycle=$v ;;
            FZF_ENABLED)    c_fzf=$v ;;
        esac
    done < "$HOME/.pkg-manager.conf"
    [ -n "$c_mgr" ] && MGR=$c_mgr
    [ -n "$c_theme" ] && THEME=$c_theme
    [ -n "$c_confirm" ] && CONFIRM=$c_confirm
    [ -n "$c_log" ] && LOG_ENABLED=$c_log
    [ -n "$c_icons" ] && ICONS=$c_icons
    [ -n "$c_quiet" ] && QUIET=$c_quiet
    [ -n "$c_lock" ] && LOCK=$c_lock
    [ -n "$c_startup" ] && STARTUP_CHECK=$c_startup
    [ -n "$c_favs" ] && FAVS_PINNED=$c_favs
    [ -n "$c_recycle" ] && RECYCLE=$c_recycle
    [ -n "$c_fzf" ] && FZF_ENABLED=$c_fzf
    return 0
}
load_config

# Honor an explicit PREFIX first (tests and older scripts rely on it), then the
# modern Termux variable, then the official Termux default.
PREFIX="${PREFIX:-${TERMUX__PREFIX:-/data/data/com.termux/files/usr}}"
export PREFIX

# env overrides win over the config file
[ -n "$MGR_ENV" ] && MGR=$MGR_ENV
[ -n "$THEME_ENV" ] && THEME=$THEME_ENV
[ -n "$CONFIRM_ENV" ] && CONFIRM=$CONFIRM_ENV
[ -n "$LOG_ENABLED_ENV" ] && LOG_ENABLED=$LOG_ENABLED_ENV
[ -n "$ICONS_ENV" ] && ICONS=$ICONS_ENV
[ -n "$RECYCLE_ENV" ] && RECYCLE=$RECYCLE_ENV
[ -n "$FZF_ENABLED_ENV" ] && FZF_ENABLED=$FZF_ENABLED_ENV

# validate both the config file and any env override with the same guards
case "$MGR" in apt|pkg) ;; *) MGR="apt" ;; esac
# APT_BIN is re-evaluated per use so a mid-session MGR change (settings menu)
# takes effect immediately.

# apt prints an interactive-use nag on stderr ("apt does not have a stable
# CLI interface ... Use with caution in scripts") on every scripted run.
# Wrap it once: the two exact lines are stripped from stderr for EVERY
# apt invocation (including the "$MGR" style), nothing else is touched.
apt() {
    command apt "$@" 2> >(grep -vE '^WARNING: apt does not have a stable CLI interface\. Use with caution in scripts\.$' >&2)
}
case "$THEME" in green|blue|purple|red|nord|amber|teal|mono|dracula|catppuccin|tokyo|gruvbox|onedark|solarized|everforest|rosepine) ;; *) THEME="green" ;; esac
case "$CONFIRM" in 0|1) ;; *) CONFIRM=1 ;; esac
case "$LOG_ENABLED" in 0|1) ;; *) LOG_ENABLED=1 ;; esac
case "$ICONS" in nerd|emoji) ;; *) ICONS="nerd" ;; esac
case "$QUIET" in 0|1) ;; *) QUIET=0 ;; esac
case "$LOCK" in 0|1) ;; *) LOCK=0 ;; esac
case "$STARTUP_CHECK" in 0|1) ;; *) STARTUP_CHECK=0 ;; esac
case "$FAVS_PINNED" in 0|1) ;; *) FAVS_PINNED=0 ;; esac
case "$RECYCLE" in 0|1) ;; *) RECYCLE=0 ;; esac
case "$FZF_ENABLED" in 0|1) ;; *) FZF_ENABLED=1 ;; esac
unset MGR_ENV THEME_ENV CONFIRM_ENV LOG_ENABLED_ENV ICONS_ENV RECYCLE_ENV FZF_ENABLED_ENV

# Color engine — every theme sets six roles: CYAN (accent/headers), PINK
# (cursor/borders), GREEN (ok), YELLOW (warn), RED (err), DIM (muted).
# Legacy themes use 256-color numbers; the real terminal themes below use
# official #RRGGBB truecolor hex from the upstream palettes (draculatheme.com,
# catppuccin.com, tokyonight.org, nordtheme.com, gruvbox, One Dark, solarized,
# everforest, rosepinetheme.com).
GREEN=46
CYAN=45
PINK=212
RED=196
YELLOW=220
DIM=240

THEME_NAMES=(green blue purple red nord amber teal mono dracula catppuccin tokyo gruvbox onedark solarized everforest rosepine)

# paint <color> <text...> — wrap text in an ANSI escape for a 256-color number
# or a #RRGGBB hex value (text mode).
paint() {
    local c="$1"; shift
    local s="$*" hex
    case "$c" in
        \#*)
            hex="${c#\#}"
            printf '\033[38;2;%d;%d;%dm%s\033[0m' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))" "$s"
            ;;
        *)
            printf '\033[38;5;%sm%s\033[0m' "$c" "$s"
            ;;
    esac
}

set_theme() {
    case "$THEME" in
        # Legacy 256-color themes: both dominant roles (CYAN accents/headers,
        # PINK cursor/selection) stay in the color family the title names —
        # "blue" used to select in ORANGE, "green" was teal+hot-pink, and "mono"
        # made errors darker than normal text. Values verified against the
        # xterm-256 chart (jonasjacek.github.io/colors).
        blue)       CYAN=33;        PINK=81;        GREEN=76;   YELLOW=117;    RED=69;       DIM=245 ;;
        purple)     CYAN=99;        PINK=141;       GREEN=48;   YELLOW=220;    RED=196;      DIM=245 ;;
        red)        CYAN=203;       PINK=211;       GREEN=46;   YELLOW=220;    RED=196;      DIM=245 ;;
        nord)       CYAN="#88C0D0"; PINK="#B48EAD"; GREEN="#A3BE8C"; YELLOW="#EBCB8B"; RED="#BF616A"; DIM="#4C566A" ;;
        amber)      CYAN=179;       PINK=216;       GREEN=114;  YELLOW=214;    RED=203;      DIM=245 ;;
        teal)       CYAN=80;        PINK=116;       GREEN=79;   YELLOW=191;    RED=203;      DIM=245 ;;
        mono)       CYAN=248;       PINK=246;       GREEN=252;  YELLOW=250;    RED=255;      DIM=240 ;;
        dracula)    CYAN="#8BE9FD"; PINK="#FF79C6"; GREEN="#50FA7B"; YELLOW="#F1FA8C"; RED="#FF5555"; DIM="#6272A4" ;;
        catppuccin) CYAN="#94E2D5"; PINK="#CBA6F7"; GREEN="#A6E3A1"; YELLOW="#F9E2AF"; RED="#F38BA8"; DIM="#6C7086" ;;
        tokyo)      CYAN="#7DCFFF"; PINK="#BB9AF7"; GREEN="#9ECE6A"; YELLOW="#E0AF68"; RED="#F7768E"; DIM="#565F89" ;;
        gruvbox)    CYAN="#8EC07C"; PINK="#D3869B"; GREEN="#B8BB26"; YELLOW="#FABD2F"; RED="#FB4934"; DIM="#928374" ;;
        onedark)    CYAN="#56B6C2"; PINK="#C678DD"; GREEN="#98C379"; YELLOW="#E5C07B"; RED="#E06C75"; DIM="#5C6370" ;;
        solarized)  CYAN="#2AA198"; PINK="#D33682"; GREEN="#859900"; YELLOW="#B58900"; RED="#DC322F"; DIM="#586E75" ;;
        everforest) CYAN="#83C092"; PINK="#D699B6"; GREEN="#A7C080"; YELLOW="#DBBC7F"; RED="#E67E80"; DIM="#859289" ;;
        rosepine)   CYAN="#9CCFD8"; PINK="#C4A7E7"; GREEN="#31748F"; YELLOW="#F6C177"; RED="#EB6F92"; DIM="#6E6A86" ;;
        green|*)    CYAN=40;        PINK=119;       GREEN=46;   YELLOW=220;    RED=196;      DIM=245 ;;
    esac
}
set_theme

# theme_ansi <name> — full 18-color terminal palette (bg fg color0..color15) as
# bare hex for the real terminal themes, so they can be exported to
# ~/.termux/colors.properties. Legacy 256-color themes have no table (return 1).
theme_ansi() {
    case "$1" in
        dracula)    printf '%s\n' 282A36 F8F8F2 21222C FF5555 50FA7B F1FA8C BD93F9 FF79C6 8BE9FD F8F8F2 6272A4 FF6E6E 69FF94 FFFFA5 D6ACFF FF92DF A4FFFF FFFFFF ;;
        catppuccin) printf '%s\n' 1E1E2E CDD6F4 45475A F38BA8 A6E3A1 F9E2AF 89B4FA F5C2E7 94E2D5 BAC2DE 585B70 F38BA8 A6E3A1 F9E2AF 89B4FA F5C2E7 94E2D5 A6ADC8 ;;
        tokyo)      printf '%s\n' 1A1B26 C0CAF5 414868 F7768E 9ECE6A E0AF68 7AA2F7 BB9AF7 7DCFFF A9B1D6 545C7E F7768E 9ECE6A E0AF68 7AA2F7 BB9AF7 7DCFFF C0CAF5 ;;
        nord)       printf '%s\n' 2E3440 D8DEE9 3B4252 BF616A A3BE8C EBCB8B 5E81AC B48EAD 88C0D0 E5E9F0 4C566A BF616A A3BE8C EBCB8B 81A1C1 B48EAD 8FBCBB ECEFF4 ;;
        gruvbox)    printf '%s\n' 282828 EBDBB2 282828 CC241D 98971A D79921 458588 B16286 689D6A A89984 928374 FB4934 B8BB26 FABD2F 83A598 D3869B 8EC07C EBDBB2 ;;
        onedark)    printf '%s\n' 282C34 ABB2BF 1E2127 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 ABB2BF 5C6370 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 FFFFFF ;;
        solarized)  printf '%s\n' 002B36 839496 073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 073642 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3 ;;
        everforest) printf '%s\n' 2D353B D3C6AA 475258 E67E80 A7C080 DBBC7F 7FBBB3 D699B6 83C092 D3C6AA 7A8478 E67E80 A7C080 DBBC7F 7FBBB3 D699B6 83C092 9DA9A0 ;;
        rosepine)   printf '%s\n' 191724 E0DEF4 26233A EB6F92 31748F F6C177 9CCFD8 C4A7E7 EBBCBA E0DEF4 6E6A86 EB6F92 31748F F6C177 9CCFD8 C4A7E7 EBBCBA E0DEF4 ;;
        *) return 1 ;;
    esac
}

init_icons() {
    if [ "$ICONS" = "emoji" ]; then
        ICON_INSTALL="📦";      ICON_UNINSTALL="🗑️"
        ICON_SEARCH="🔎";       ICON_LIST="📜"
        ICON_REINSTALL="🔧";    ICON_UPDATE="🔄"
        ICON_CLEAN="🧹";        ICON_INFO="ℹ️"
        ICON_AUTOREMOVE="🧽";   ICON_DEPENDS="🔗"
        ICON_RDEPENDS="🔃";     ICON_SIZE="⚖️"
        ICON_FILES="📁";        ICON_OWNER="🏷️"
        ICON_HOLD="📌";         ICON_PURGE="🧨"
        ICON_FIXBROKEN="🩹";    ICON_UPGRADABLE="📈"
        ICON_BACKUP="💾";       ICON_RESTORE="♻️"
        ICON_EXPORT="📤";       ICON_IMPORT="📥"
        ICON_DOCTOR="🔧";       ICON_SETTINGS="⚙️"
        ICON_HISTORY="📋";      ICON_EXIT="🚪"
        ICON_THEME="🎨";        ICON_SLIDERS="🎛️"
        ICON_SHIELD="🛡️";      ICON_MEMO="📝"
        ICON_FOLDER="📂";       ICON_WAND="🪄"
        ICON_WAVE="👋";         ICON_UP="⬆️"
        ICON_BACK="⬅️";        ICON_PAINT="🖌️"
        ICON_EYE="👁️";          ICON_CHART="📊"
        ICON_CACHE="🗃️";         ICON_TREE="🌳"
        ICON_BULK="📚";         ICON_STAR="⭐"
        ICON_INSPECT="🔍";      ICON_MAINT="🩺"
        ICON_GROUPS="🗂️";       ICON_PIN="📍"
        ICON_DISK="💽";         ICON_MOON="🌙"
        ICON_LOCK="🔒";         ICON_ERROR="🚫"
        ICON_UNDO="↩️";          ICON_PLAY="▶️"
        ICON_CHECKBOX="☑️"
        ICON_BUG="🐞";          ICON_TRASH="🗑️"
        ICON_BOLT="⚡";         ICON_GLOBE="🌐"
        ICON_ROCKET="🚀"
    else
        ICON_INSTALL=$'\uEB29'; ICON_UNINSTALL=$'\uEA81'
        ICON_SEARCH=$'\uEA6D';  ICON_LIST=$'\uEB84'
        ICON_REINSTALL=$'\uF0AD'; ICON_UPDATE=$'\uEB37'
        ICON_CLEAN=$'\uEDE4';   ICON_INFO=$'\uEA74'
        ICON_AUTOREMOVE=$'\uF1F8'; ICON_DEPENDS=$'\uF0C1'
        ICON_RDEPENDS=$'\uF0EC'; ICON_SIZE=$'\uF24E'
        ICON_FILES=$'\uF07B';   ICON_OWNER=$'\uF02B'
        ICON_HOLD=$'\uF08D';    ICON_PURGE=$'\uF1E2'
        ICON_FIXBROKEN=$'\uED74'; ICON_UPGRADABLE=$'\uEBFF'
        ICON_BACKUP=$'\uF0C7';  ICON_RESTORE=$'\uF2EA'
        ICON_EXPORT=$'\uF0EE';  ICON_IMPORT=$'\uF0ED'
        ICON_DOCTOR=$'\uF0F1';  ICON_SETTINGS=$'\uF013'
        ICON_HISTORY=$'\uF1DA'; ICON_EXIT=$'\uEDF5'
        ICON_THEME=$'\uEFCC';   ICON_SLIDERS=$'\uF1DE'
        ICON_SHIELD=$'\uEB53';  ICON_MEMO=$'\uED7B'
        ICON_FOLDER=$'\uF07C';  ICON_WAND=$'\uEBCF'
        ICON_WAVE=$'\U000F1821'; ICON_UP=$'\uF062'
        ICON_BACK=$'\uF060';    ICON_PAINT=$'\uF1FC'
        ICON_EYE=$'\uF06E';     ICON_CHART=$'\uF201'
        ICON_CACHE=$'\uF1C0';   ICON_TREE=$'\uF1BB'
        ICON_BULK=$'\uF0AE';    ICON_STAR=$'\uF005'
        ICON_INSPECT=$'\uF1E5'; ICON_MAINT=$'\uF0FA'
        ICON_GROUPS=$'\uF1B3';  ICON_PIN=$'\uF276'
        ICON_DISK=$'\uF0A0';    ICON_MOON=$'\uF186'
        ICON_LOCK=$'\uF023';    ICON_ERROR=$'\uF071'
        ICON_UNDO=$'\uF0E2';    ICON_PLAY=$'\uF04B'
        ICON_CHECKBOX=$'\uF046'
        ICON_BUG=$'\uF188';     ICON_TRASH=$'\uF014'
        ICON_BOLT=$'\uF0E7';    ICON_GLOBE=$'\uF0AC'
        ICON_ROCKET=$'\uF135'
    fi
}
init_icons

LOG_FILE="$HOME/.pkg-manager.log"
FAVS_FILE="$HOME/.pkg-manager-favs"
GROUPS_FILE="$HOME/.pkg-manager-groups"
WATCH_FILE="$HOME/.pkg-manager-watch"
TRASH_DIR="$HOME/pkg-trash"
UPDATE_URL="https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/manager.sh"

# fzf_label — three-state label for the settings row:
#   off → on
fzf_label() {
    if [ "$FZF_ENABLED" != "1" ]; then
        printf 'off'
    else
        printf 'on'
    fi
}

# have_fzf — fzf is optional but first-class: it powers the package picker, the
# command palette and the menu. FZF_ENABLED=0 (or NO_FZF=1) disables it.
# The test harness uses NO_FZF=1 for hermetic runs.
# Two first-class UI modes: "fzf" (fuzzy picker, default) and "text" (numbered
# lists). They are separate code paths, not one UI with a degraded fallback:
# every picker has a complete text branch. If fzf itself breaks mid-session
# (bad flag, crash, terminal too small) the app says so ONCE and completes the
# session in text mode instead of silently misbehaving.
UI_MODE="fzf"          # fzf | text — text is a full mode, not an error state
# fzf writes $FZF_BROKEN_FLAG on rc>=2 (see fzf_select); have_fzf() honors it

have_fzf() {
    # fzf broke once this session: stay in text mode (marker survives the
    # $(...) that a picker always runs inside)
    [ -e "${FZF_BROKEN_FLAG:-/dev/null}" ] && return 1
    [ "$UI_MODE" = "fzf" ] || return 1
    [ "$FZF_ENABLED" = "1" ] || return 1
    [ "${NO_FZF:-0}" = "1" ] && return 1
    command -v fzf >/dev/null 2>&1
}

# fzf_supports_ghost — 1 when the installed fzf understands --ghost (0.61+).
# An unknown flag makes fzf exit 2, which the app reads as "fzf broke" and
# answers by dropping to text mode — so the ghost is opt-in per version.
FZF_GHOST_OK=""
fzf_supports_ghost() {
    if [ -z "$FZF_GHOST_OK" ]; then
        local v major minor
        # The probe runs with the harness queue/log neutralized: the stubbed
        # fzf of the test suite would otherwise pop a test's answer — although
        # --version/--help probes are now answered without popping, the
        # real-fzf call still must not touch them.
        v=$(FZF_QUEUE='' FZF_CALL_LOG=/dev/null fzf --version 2>/dev/null | head -n1)
        v="${v%%[^0-9.]*}"
        major="${v%%.*}"
        minor="${v#*.}"; minor="${minor%%.*}"
        case "${major}${minor}" in
            ''|*[!0-9]*) FZF_GHOST_OK=0 ;;
            *) if [ "$major" -gt 0 ] || [ "$minor" -ge 61 ]; then FZF_GHOST_OK=1; else FZF_GHOST_OK=0; fi ;;
        esac
    fi
    [ "$FZF_GHOST_OK" = "1" ]
}

# CLI mode — non-interactive flags (--help --version --theme --export-theme
# --list-themes) are detected here and handled after all functions are defined (before FIRST_LOOP).
case "${1:-}" in
    -h|--help|help)           CLI_MODE="help" ;;
    -V|--version|version)     CLI_MODE="version" ;;
    --list-themes)            CLI_MODE="list-themes" ;;
    --theme)                  CLI_MODE="set-theme" ;;
    --export-theme)           CLI_MODE="export-theme" ;;
    --check-updates)          CLI_MODE="check-updates" ;;
    --quiet)                  CLI_MODE="check-updates-quiet" ;;
    --doctor)                 CLI_MODE="doctor" ;;
    "")                       CLI_MODE="" ;;
    *)                        CLI_MODE="unknown:$1" ;;
esac


# Output helpers — text mode paints via ANSI escapes.
# (256 number or hex), plain text mode gets a real ANSI escape via paint().
say()  { printf '%s\n' "$(paint "$CYAN" "$1")"; }
ok()   { printf '%s\n' "$(paint "$GREEN" "✓ $1")"; }
err()  { printf '%s\n' "$(paint "$RED" "✗ $1")"; }
warn() { printf '%s\n' "$(paint "$YELLOW" "⚠ $1")"; }
dim()  { printf '%s\n' "$(paint "$DIM" "$1")"; }

# hr — a full-width themed rule; section — a themed sub-header
hr() {
    local w line
    w=$(tput cols 2>/dev/null || echo 0)
    case "$w" in ''|*[!0-9]*) w=0 ;; esac
    [ "$w" -lt 24 ] && w=60
    line=$(printf '─%.0s' $(seq 1 "$w"))
    printf '%s\n' "$(paint "$DIM" "$line")"
}
section() {
    printf '%s\n' "$(paint "$PINK" "── $1 ──")"
}

BANNER_B64="H4sIAAAAAAACA12MwQ0AIAgD/0xxG3QhExZxeKX1JYQCVwJAfzHEtK4p2zKYmSXYt1Qx5SNnW7dbGcyjmP6CslLqB14RzXgAFZPjhpUAAAA="

# banner_text — the banner block (art + status strip) as plain text. Split
# out of banner() because the same text is embedded in the fzf header: text
# printed ABOVE an fzf window is static, and a terminal resize makes fzf
# re-anchor its window, so whatever was above it is wiped and never
# repainted. Inside the window, fzf owns it and redraws it every time.
banner_text() {
    local art n favs
    if ! art=$(printf '%s' "$BANNER_B64" | base64 -d 2>/dev/null | gzip -d 2>/dev/null); then
        art="TERMUX Pkg Manager v$VERSION"
    fi
    # Multi-hue banner: ramp the art's lines across the theme's four accent
    # hues (CYAN → GREEN → YELLOW → PINK) instead of one flat color, then
    # color each status-strip value from the same palette.
    local total i=0 line idx
    local hues=("$CYAN" "$GREEN" "$YELLOW" "$PINK")
    total=$(printf '%s\n' "$art" | wc -l | tr -d ' ')
    [ "$total" -ge 2 ] || total=2
    while IFS= read -r line; do
        if [ -z "$line" ]; then printf '\n'; else
            idx=$(( i * 4 / total ))
            printf '%s\n' "$(paint "${hues[$idx]}" "$line")"
        fi
        i=$((i+1))
    done <<< "$art"
    # status strip: manager · theme · installed count · version
    n="${1:-}"
    [ -n "$n" ] || n=$(dpkg-query -W 2>/dev/null | wc -l | tr -d ' ')
    favs=0
    if [ -s "$FAVS_FILE" ]; then favs=$(grep -c . "$FAVS_FILE" 2>/dev/null) || favs=0; fi
    printf '%s\n' \
        "$(paint "$CYAN" "  pkg-manager v$VERSION")$(paint "$DIM" " · manager: ")$(paint "$GREEN" "$MGR")$(paint "$DIM" " · theme: ")$(paint "$PINK" "$THEME")$(paint "$DIM" " · installed: ")$(paint "$YELLOW" "${n:-?}")$(paint "$DIM" " · favorites: ")$(paint "$YELLOW" "$favs")"
}

# BANNER_BLOCK — cached banner text. Refreshed once per menu iteration so
# the dpkg-query behind the status strip runs once, not once per picker.
BANNER_BLOCK=""

banner_refresh() {
    local n
    n=$(dpkg-query -W 2>/dev/null | wc -l | tr -d ' ')
    BANNER_BLOCK="$(banner_text "$n")"
}

# banner — print the banner above the menu. Text mode only: in fzf mode the
# banner rides inside the picker window (see banner_header).
banner() {
    [ -n "$BANNER_BLOCK" ] || banner_refresh
    printf '%s\n' "$BANNER_BLOCK"
}

# banner_header — the banner block for an fzf header. On short terminals the
# 5-line art is dropped so the picker keeps its rows for the list.
banner_header() {
    [ -n "$BANNER_BLOCK" ] || banner_refresh
    if [ "$(term_size lines)" -lt 20 ]; then
        printf '%s\n' "$BANNER_BLOCK" | tail -n 1
    else
        printf '%s\n' "$BANNER_BLOCK"
    fi
}

# valid_pkg_name — 1 if "$1" is a safe package token for apt/dpkg: starts with
# an alphanumeric (blocks leading "-" option injection) and contains only
# package-safe characters. Rejects empty / whitespace / globs / shell metas.
valid_pkg_name() {
    case "$1" in
        ""|-*|*" "*|*'|'*|*';'*|*'&'*) return 1 ;;
    esac
    printf '%s\n' "$1" | grep -qE '^[A-Za-z0-9][A-Za-z0-9+:._~-]*$'
}

# filter_pkgs — read newline-separated names on stdin, print only valid ones
filter_pkgs() {
    local p
    while IFS= read -r p || [ -n "$p" ]; do
        valid_pkg_name "$p" && printf '%s\n' "$p"
    done
}

build_menu() {
    OPTION_INSTALL="$ICON_INSTALL Install a package"
    OPTION_UNINSTALL="$ICON_UNINSTALL Uninstall a package"
    OPTION_LIST="$ICON_LIST List installed packages"
    OPTION_REINSTALL="$ICON_REINSTALL Reinstall / repair a package"
    OPTION_UPDATE="$ICON_UPDATE Upgrade center"
    OPTION_CLEAN="$ICON_CLEAN Clean download cache"
    OPTION_INFO="$ICON_INFO Show package info"
    OPTION_AUTOREMOVE="$ICON_AUTOREMOVE Autoremove cleanup"
    OPTION_DEPENDS="$ICON_DEPENDS Dependencies"
    OPTION_RDEPENDS="$ICON_RDEPENDS Reverse deps"
    OPTION_SIZE="$ICON_SIZE Package size"
    OPTION_FILES="$ICON_FILES Installed files"
    OPTION_OWNER="$ICON_OWNER File owner"
    OPTION_HOLD="$ICON_HOLD Pin / hold packages"
    OPTION_PURGE="$ICON_PURGE Purge a package"
    OPTION_FIXBROKEN="$ICON_FIXBROKEN Fix broken packages"
    OPTION_UPGRADABLE="$ICON_UPGRADABLE Upgradable list"
    OPTION_BACKUP="$ICON_BACKUP Backup installed packages"
    OPTION_RESTORE="$ICON_RESTORE Restore from backup"
    OPTION_EXPORT="$ICON_EXPORT Export package list"
    OPTION_IMPORT="$ICON_IMPORT Import package list"
    OPTION_DOCTOR="$ICON_DOCTOR Dependency doctor"
    OPTION_SETTINGS="$ICON_SETTINGS Settings"
    OPTION_HISTORY="$ICON_HISTORY History & log viewer"
    OPTION_SIMULATE="$ICON_EYE Simulate a change"
    OPTION_STATS="$ICON_CHART Package stats & disk"
    OPTION_CACHE="$ICON_CACHE Cache manager"
    OPTION_DEPTREE="$ICON_TREE Dependency tools"
    OPTION_BULK="$ICON_BULK Bulk operations"
    OPTION_FAVS="$ICON_STAR Favorites"
    OPTION_INSPECT="$ICON_INSPECT Package inspector"
    OPTION_MAINT="$ICON_MAINT Maintenance wizard"
    OPTION_GROUPS="$ICON_GROUPS Package groups"
    OPTION_LOCALDEB="$ICON_FILES Local .deb install"
    OPTION_DOWNGRADE="$ICON_REINSTALL Downgrade package"
    OPTION_DLONLY="$ICON_CACHE Download only"
    OPTION_HOLDVER="$ICON_HOLD Hold specific version"
    OPTION_FILESEARCH="$ICON_SEARCH File search (pre-install)"
    OPTION_CHANGELOG="$ICON_HISTORY Changelog"
    OPTION_WHY="$ICON_DEPENDS Why installed"
    OPTION_NOTES="$ICON_MEMO User notes"
    OPTION_SNAPSHOT="$ICON_BACKUP Full snapshot"
    OPTION_PALETTE="$ICON_WAND Command palette"
    OPTION_WATCH="$ICON_EYE Package watchlist"
    OPTION_MIRROR="$ICON_PLAY Mirror speed test"
    OPTION_AUDIT="$ICON_SHIELD System audit"
    OPTION_MARKS="$ICON_CHECKBOX Mark manual / auto"
    OPTION_RECYCLE="$ICON_TRASH Recycle bin"
    OPTION_REPOS="$ICON_FOLDER Optional repositories"
    OPTION_UNDO="$ICON_HISTORY Undo last batch"
    OPTION_DEPTREE_GRAPH="$ICON_DEPENDS Dependency tree"
    OPTION_HEALTH="$ICON_SHIELD Health dashboard"
    OPTION_SNAPSHOT_DIFF="$ICON_BACKUP Snapshot / Diff"
    OPTION_THEME="$ICON_WAND Themes & terminal colors"
    OPTION_SELFUPDATE="$ICON_UP Update pkg-manager"
    OPTION_ESSENTIALS="$ICON_BOLT Essential toolkit"
    OPTION_SYSINFO="$ICON_GLOBE System & network info"
    OPTION_WHATSNEW="$ICON_ROCKET What's new in v$VERSION"
    OPTION_EXIT="$ICON_EXIT Exit"

    # Submenu pickers append an explicit Exit row, so the app can be left from
    # any depth without walking back level by level with ESC. Every picker
    # code path runs inside a command substitution (its stdout is captured),
    # so a shell variable set there cannot carry the request out — a flag FILE
    # is the one thing that survives the subshell. The main loop reads it
    # after each action, prints the farewell and breaks; every do_* level
    # unwinds normally in the meantime.
    OPTION_SUB_EXIT="$ICON_BACK Back to main menu"
    OPTION_APP_EXIT="$ICON_EXIT Exit pkg-manager"

    # One-line descriptions for the fzf preview panel, keyed by the final label
    # so they survive nerd/emoji icon switches.
    declare -gA MENU_DESC=()
    _menu_desc() { MENU_DESC["$1"]="$2"; }
    _menu_desc "$OPTION_INSTALL"       "Install one or more packages (fzf multi-select with a live apt-cache info preview)"
    _menu_desc "$OPTION_UNINSTALL"     "Remove installed packages, keeping .deb copies in the recycle bin first"
    _menu_desc "$OPTION_LIST"          "Show every installed package, or filter by a substring"
    _menu_desc "$OPTION_REINSTALL"     "Re-download and reinstall a package to repair a broken one"
    _menu_desc "$OPTION_UPDATE"        "Upgrade center: refresh lists, preview, then upgrade all or selected"
    _menu_desc "$OPTION_CLEAN"         "Delete cached .deb archives to free storage"
    _menu_desc "$OPTION_INFO"          "Full apt-cache record for a package: version, size, dependencies, description"
    _menu_desc "$OPTION_AUTOREMOVE"    "Remove orphaned dependencies nothing needs any more"
    _menu_desc "$OPTION_DEPENDS"       "List what a package needs (direct dependencies)"
    _menu_desc "$OPTION_RDEPENDS"      "List which installed packages need this one"
    _menu_desc "$OPTION_SIZE"          "Download size and installed size of a package"
    _menu_desc "$OPTION_FILES"         "Every file a package installed on disk"
    _menu_desc "$OPTION_OWNER"         "Find which package owns a given file path"
    _menu_desc "$OPTION_HOLD"          "Hold/unhold packages so upgrades skip them"
    _menu_desc "$OPTION_PURGE"         "Remove a package together with its configuration files"
    _menu_desc "$OPTION_FIXBROKEN"     "Repair an interrupted dpkg state (apt install -f)"
    _menu_desc "$OPTION_UPGRADABLE"    "List packages that have a newer version available"
    _menu_desc "$OPTION_BACKUP"        "Save the installed package list to a timestamped file"
    _menu_desc "$OPTION_RESTORE"       "Reinstall everything from a backup list"
    _menu_desc "$OPTION_EXPORT"        "Write the package list as text or JSON"
    _menu_desc "$OPTION_IMPORT"        "Read a package list file and install what it names"
    _menu_desc "$OPTION_DOCTOR"        "Diagnose missing dependencies and broken packages"
    _menu_desc "$OPTION_SETTINGS"      "Manager, theme, icons, confirmations, fzf toggle, theme hub"
    _menu_desc "$OPTION_HISTORY"       "Browse and chart the action log (installs, removes, failures)"
    _menu_desc "$OPTION_SIMULATE"      "Dry-run an install/remove/upgrade without touching the system"
    _menu_desc "$OPTION_STATS"         "Storage totals, largest files and cache breakdown"
    _menu_desc "$OPTION_CACHE"         "Clean all or only outdated cached packages, or list them"
    _menu_desc "$OPTION_DEPTREE"       "Recursive dependency tree (depth-capped) plus orphan finder"
    _menu_desc "$OPTION_BULK"          "Install, remove or upgrade many packages in one batch"
    _menu_desc "$OPTION_FAVS"          "Curated favorites: add, remove, install all, pin to the menu"
    _menu_desc "$OPTION_INSPECT"       "One-screen overview: version, status, size, deps, files summary"
    _menu_desc "$OPTION_MAINT"         "Maintenance wizard: update, autoremove, clean, health checks"
    _menu_desc "$OPTION_GROUPS"        "Named package bundles you can create, install and delete"
    _menu_desc "$OPTION_LOCALDEB"      "Install a .deb file straight from storage"
    _menu_desc "$OPTION_DOWNGRADE"     "Install an older version of a package from the cache"
    _menu_desc "$OPTION_DLONLY"        "Download a package without installing it"
    _menu_desc "$OPTION_HOLDVER"       "Pin a package to its exact current version"
    _menu_desc "$OPTION_FILESEARCH"    "Find which package provides a file before you install"
    _menu_desc "$OPTION_CHANGELOG"     "Show the upstream changelog of a package"
    _menu_desc "$OPTION_WHY"           "Explain why a package is installed (manual or pulled in)"
    _menu_desc "$OPTION_NOTES"         "Attach personal notes to packages"
    _menu_desc "$OPTION_SNAPSHOT"      "Full snapshot of packages, favorites, groups, notes as a tar.gz"
    _menu_desc "$OPTION_PALETTE"       "Command palette: fuzzy-filter all 59 menu entries"
    _menu_desc "$OPTION_WATCH"         "Watchlist: get told when watched packages change version"
    _menu_desc "$OPTION_MIRROR"         "Time every mirror and switch to the fastest one"
    _menu_desc "$OPTION_AUDIT"         "System audit with a health score and repair suggestions"
    _menu_desc "$OPTION_MARKS"         "Mark packages as manually or automatically installed"
    _menu_desc "$OPTION_RECYCLE"       "Browse and restore .deb files kept from earlier removals"
    _menu_desc "$OPTION_REPOS"         "Enable/disable the root and x11 optional repositories"
    _menu_desc "$OPTION_UNDO"          "Reverse the last recorded install/remove batch"
    _menu_desc "$OPTION_DEPTREE_GRAPH" "Colored forward/reverse dependency graph for one package"
    _menu_desc "$OPTION_HEALTH"        "Dashboard: upgradables, orphans, disk headroom, locks, dpkg state"
    _menu_desc "$OPTION_SNAPSHOT_DIFF" "Create, list, diff, restore or delete full snapshots"
    _menu_desc "$OPTION_THEME"         "Theme hub: preview every theme, export the palette to Termux"
    _menu_desc "$OPTION_SELFUPDATE"    "Update pkg-manager itself (SHA-256 verified download)"
    _menu_desc "$OPTION_ESSENTIALS"    "One-tap curated bundles of everyday tools"
    _menu_desc "$OPTION_SYSINFO"       "Kernel, CPU, RAM, storage, battery, DNS and public IP"
    _menu_desc "$OPTION_WHATSNEW"      "The changelog screen for this release"
    _menu_desc "$OPTION_EXIT"          "Leave pkg-manager"

    # Second line of the preview panel: what the action actually runs or
    # touches. Verified against each do_* implementation (grep the command),
    # never invented — this is the "more info" the preview panel exists for.
    declare -gA MENU_DETAIL=()
    _menu_detail() { MENU_DETAIL["$1"]="$2"; }
    _menu_detail "$OPTION_INSTALL"      "runs: apt install <pkgs> — one batch call"
    _menu_detail "$OPTION_UNINSTALL"    "runs: apt remove <pkgs> (archives the .deb first if RECYCLE=1)"
    _menu_detail "$OPTION_LIST"         "runs: apt list --installed / dpkg-query, optional substring filter"
    _menu_detail "$OPTION_REINSTALL"    "runs: apt install --reinstall <pkg>"
    _menu_detail "$OPTION_UPDATE"       "runs: apt update, then apt upgrade (all or picked)"
    _menu_detail "$OPTION_CLEAN"        "runs: apt clean — frees the archive cache"
    _menu_detail "$OPTION_INFO"         "runs: apt-cache show <pkg>"
    _menu_detail "$OPTION_AUTOREMOVE"   "runs: apt autoremove -y (orphaned dependencies)"
    _menu_detail "$OPTION_DEPENDS"      "runs: apt depends <pkg>"
    _menu_detail "$OPTION_RDEPENDS"     "runs: apt rdepends <pkg>"
    _menu_detail "$OPTION_SIZE"         "runs: apt-cache show <pkg> (download + installed size)"
    _menu_detail "$OPTION_FILES"        "runs: dpkg -L <pkg>"
    _menu_detail "$OPTION_OWNER"        "runs: dpkg -S <file>"
    _menu_detail "$OPTION_HOLD"         "runs: apt-mark hold / unhold"
    _menu_detail "$OPTION_PURGE"        "runs: apt purge <pkg> (removes config files too)"
    _menu_detail "$OPTION_FIXBROKEN"    "runs: apt --fix-broken install"
    _menu_detail "$OPTION_UPGRADABLE"   "runs: apt list --upgradable"
    _menu_detail "$OPTION_BACKUP"       "writes ~/pkg-backup-<date>.txt (installed list)"
    _menu_detail "$OPTION_RESTORE"      "runs: apt install for every name in a backup file"
    _menu_detail "$OPTION_EXPORT"       "writes ~/pkg-export.txt or ~/pkg-export.json"
    _menu_detail "$OPTION_IMPORT"       "runs: apt install for every name in a list file"
    _menu_detail "$OPTION_DOCTOR"       "runs: apt-cache depends/rdepends against the installed set"
    _menu_detail "$OPTION_SETTINGS"     "reads/writes ~/.pkg-manager.conf (KEY=VALUE, never sourced)"
    _menu_detail "$OPTION_HISTORY"      "reads ~/.pkg-manager.log and charts it"
    _menu_detail "$OPTION_SIMULATE"     "dry run only — nothing is installed or removed"
    _menu_detail "$OPTION_STATS"        "runs: dpkg-query sizes + du of $PREFIX/var/cache/apt/archives"
    _menu_detail "$OPTION_CACHE"        "runs: apt clean / autoclean, or lists the cached .deb files"
    _menu_detail "$OPTION_DEPTREE"      "runs: apt-cache depends/rdepends, depth capped at 4"
    _menu_detail "$OPTION_BULK"         "runs: one apt call for a whole list of names"
    _menu_detail "$OPTION_FAVS"         "reads/writes ~/.pkg-manager-favs (one package per line)"
    _menu_detail "$OPTION_INSPECT"      "runs: apt-cache + dpkg-query for a one-screen overview"
    _menu_detail "$OPTION_MAINT"        "runs: apt update, autoremove, clean + health checks"
    _menu_detail "$OPTION_GROUPS"       "reads/writes ~/.pkg-manager-groups (name::pkg1 pkg2)"
    _menu_detail "$OPTION_LOCALDEB"     "runs: dpkg -i <file.deb>, then apt --fix-broken install"
    _menu_detail "$OPTION_DOWNGRADE"    "runs: apt-cache madison/policy, then apt install <pkg>=<version>"
    _menu_detail "$OPTION_DLONLY"       "runs: apt download <pkg> (installs nothing)"
    _menu_detail "$OPTION_HOLDVER"      "runs: apt-mark hold <pkg> on the version you picked"
    _menu_detail "$OPTION_FILESEARCH"   "runs: apt-file search <file> (needs the apt-file package)"
    _menu_detail "$OPTION_CHANGELOG"    "runs: apt changelog / apt-get changelog <pkg>"
    _menu_detail "$OPTION_WHY"          "runs: apt rdepends + apt-mark showmanual/showauto"
    _menu_detail "$OPTION_NOTES"        "reads/writes ~/.pkg-manager-notes (pkg::note)"
    _menu_detail "$OPTION_SNAPSHOT"     "runs: tar -czf ~/pkg-snapshot-<date>.tar.gz (all app state)"
    _menu_detail "$OPTION_PALETTE"      "fuzzy-filters every menu entry"
    _menu_detail "$OPTION_WATCH"        "reads/writes ~/.pkg-manager-watch, compares versions"
    _menu_detail "$OPTION_MIRROR"       "times every mirror with curl and offers the fastest"
    _menu_detail "$OPTION_AUDIT"        "runs: dpkg -l + apt checks, prints a health score"
    _menu_detail "$OPTION_MARKS"        "runs: apt-mark manual / auto"
    _menu_detail "$OPTION_RECYCLE"      "browses and restores ~/pkg-trash/*.deb from earlier removals"
    _menu_detail "$OPTION_REPOS"        "runs: apt install root-repo / x11-repo + apt update"
    _menu_detail "$OPTION_UNDO"         "reads the batch_start log lines and reverses the last batch"
    _menu_detail "$OPTION_DEPTREE_GRAPH" "runs: apt-cache depends/rdepends + apt-mark, colored graph"
    _menu_detail "$OPTION_HEALTH"       "runs: apt list --upgradable, apt-mark showauto, dpkg-query + du"
    _menu_detail "$OPTION_SNAPSHOT_DIFF" "runs: tar snapshots, then diffs or restores them"
    _menu_detail "$OPTION_THEME"        "writes ~/.termux/colors.properties (backup kept)"
    _menu_detail "$OPTION_SELFUPDATE"   "downloads the release, checks SHA-256, replaces the script"
    _menu_detail "$OPTION_ESSENTIALS"   "insts curated bundles of everyday tools"
    _menu_detail "$OPTION_SYSINFO"      "reads /proc, battery, DNS and the public IP"
    _menu_detail "$OPTION_WHATSNEW"     "the changelog screen for this release"
    _menu_detail "$OPTION_EXIT"         "leaves pkg-manager"

    MENU_ITEMS=(
        "$OPTION_INSTALL" "$OPTION_UNINSTALL" "$OPTION_LIST" "$OPTION_REINSTALL"
        "$OPTION_UPDATE" "$OPTION_CLEAN" "$OPTION_INFO" "$OPTION_AUTOREMOVE"
        "$OPTION_DEPENDS" "$OPTION_RDEPENDS" "$OPTION_SIZE" "$OPTION_FILES" "$OPTION_OWNER"
        "$OPTION_HOLD" "$OPTION_PURGE" "$OPTION_FIXBROKEN" "$OPTION_UPGRADABLE"
        "$OPTION_BACKUP" "$OPTION_RESTORE" "$OPTION_EXPORT" "$OPTION_IMPORT"
        "$OPTION_DOCTOR" "$OPTION_HISTORY"
        "$OPTION_SIMULATE" "$OPTION_STATS" "$OPTION_CACHE"
        "$OPTION_DEPTREE" "$OPTION_BULK" "$OPTION_FAVS"
        "$OPTION_INSPECT" "$OPTION_MAINT" "$OPTION_GROUPS"
        "$OPTION_LOCALDEB" "$OPTION_DOWNGRADE" "$OPTION_DLONLY" "$OPTION_HOLDVER" "$OPTION_FILESEARCH"
        "$OPTION_CHANGELOG" "$OPTION_WHY" "$OPTION_NOTES" "$OPTION_SNAPSHOT" "$OPTION_PALETTE"
        "$OPTION_WATCH" "$OPTION_MIRROR" "$OPTION_AUDIT" "$OPTION_MARKS" "$OPTION_RECYCLE" "$OPTION_REPOS"
        "$OPTION_UNDO" "$OPTION_DEPTREE_GRAPH" "$OPTION_HEALTH" "$OPTION_SNAPSHOT_DIFF" "$OPTION_SELFUPDATE"
        "$OPTION_ESSENTIALS" "$OPTION_SYSINFO" "$OPTION_WHATSNEW" "$OPTION_SETTINGS"
    )

    FAVPIN=()
    if [ "$FAVS_PINNED" = "1" ] && [ -s "$FAVS_FILE" ]; then
        local p_pin seen=" "
        while IFS= read -r p_pin || [ -n "$p_pin" ]; do
            p_pin=${p_pin#"${p_pin%%[![:space:]]*}"}
            p_pin=${p_pin%"${p_pin##*[![:space:]]}"}
            if [ -n "$p_pin" ] && valid_pkg_name "$p_pin" \
                && [[ "$seen" != *" $p_pin "* ]]; then
                seen="$seen $p_pin "
                FAVPIN+=("$p_pin")
            fi
        done < "$FAVS_FILE"
    fi
}
build_menu

main_menu() {
    local opts=( "${MENU_ITEMS[@]}" )
    local p i
    for p in "${FAVPIN[@]}"; do
        opts+=( "$ICON_PIN Pinned: $p" )
    done
    # fzf-first: fuzzy menu whenever fzf is available and preferred (default).
    # Rows are "label\x1fdescription\x1frow\x1fdetail": the LIST shows the
    # bare action label only, the search still covers label + description,
    # and the preview pane carries the description, what the action runs and
    # the row number (so the text-mode number is one glance away). \x1f is an
    # invisible separator: fzf's --with-nth leaves a delimiter marker for the
    # hidden fields, and a visible one would print it at the end of every row.
    if have_fzf; then
        local us=$'\x1f'
        local -a rows=()
        local o d det i=0
        for o in "${opts[@]}"; do
            i=$((i + 1))
            d="${MENU_DESC[$o]:-}"
            det="${MENU_DETAIL[$o]:-}"
            case "$o" in
                "$ICON_PIN"*)
                    d="Pinned favourite — opens straight to it."
                    det="stored in ~/.pkg-manager-favs"
                    ;;
            esac
            [ -n "$d" ] || d="Open this action."
            [ -n "$det" ] || det="menu action"
            rows+=("$o$us$d$us$i$us$det")
        done
        # Exit is row 0 in text mode. Braces around $us matter: "$us0" would
        # parse as the (undefined) variable us0, not separator + "0".
        rows+=("$OPTION_EXIT${us}${MENU_DESC[$OPTION_EXIT]}${us}0${us}${MENU_DETAIL[$OPTION_EXIT]}")
        # Bold label, dim context. The ESC bytes live INSIDE the single-quoted
        # format string: as unquoted arguments they would be glob-parsed by
        # whatever shell fzf runs the preview with (zsh rejects them outright).
        local e_bold e_dim e_off
        e_bold=$'\033[1m'; e_dim=$'\033[2m'; e_off=$'\033[0m'
        FZF_PREVIEW="printf '\n  ${e_bold}%s${e_off}\n  ───────────────────────────────\n\n  %s\n\n  ${e_dim}%s${e_off}\n  ${e_dim}row %s${e_off}\n' {1} {2} {4} {3}"
        FZF_NTH="--delimiter=\x1f --nth=1,2 --with-nth=1"
        FZF_GHOST="type to filter the actions"
        local sel
        sel=$(printf '%s\n' "${rows[@]}" | fzf_select \
            "pkg-manager v$VERSION — filter & pick (ESC to exit)" "❯ " 0 \
            --header="? preview · / search · ESC exit" \
            --footer="${#opts[@]} entries + Exit │ ? preview · Y copy · ESC exit · ^Q quit" \
            --marker="▶" --gutter=" " --no-separator) || sel=""
        FZF_PREVIEW=""; FZF_NTH=""; FZF_GHOST=""
        if [ -n "$sel" ]; then
            # fzf hands back the ORIGINAL row, separator and all — split at
            # the US separator to recover the bare label.
            printf '%s\n' "${sel%%$'\x1f'*}"
            return
        fi
        # ESC with a healthy fzf cancels (the REPL loop treats it as Exit).
        # Only fall through to the numbered list when fzf actually broke
        # (have_fzf() sees the $FZF_BROKEN_FLAG file fzf_select writes).
        have_fzf && return 1
    fi
    printf '\n' >&2
        printf '%s\n' "$(paint "$PINK" "  ═══ MAIN MENU ═══")" >&2
        # Same list style as the submenu pickers: right-aligned numbers, a
        # separator after the number, and the ❯ prompt. Exit stays row 0.
        local _n=${#opts[@]}
        local w=${#_n}
        list_numbered 1 "${opts[@]}"
        num_row 0 "$OPTION_EXIT" >&2
        printf '%s\n' "$(paint "$DIM" "  ───────────────")" >&2
        printf '❯ ' >&2
        if ! read -r n; then
            echo "$OPTION_EXIT"
            return
        fi
        if [[ "$n" =~ ^[0-9]+$ ]]; then
            if [ "$n" -eq 0 ]; then
                echo "$OPTION_EXIT"
                return
            fi
            if [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ]; then
                echo "${opts[$((n-1))]}"
                return
            fi
        fi
        echo "__INVALID__"
}

# ask_name <prompt> <pkghint> — read a value into PKG_NAME. With pkghint="pkg"
# (default for package prompts) the value is validated with valid_pkg_name;
# pass "path" to skip validation for e.g. file paths, or "any" for free text.
# With fzf available on a tty, a pkg prompt becomes a fuzzy finder over the
# package list with the same live info preview the install picker shows; ESC
# falls back to typing, the Exit row leaves the app. Not a tty (test feeds,
# pipes): plain typed prompt, exactly as before.
#
# List kind — prompts that only make sense for an INSTALLED package (uninstall,
# reinstall, purge, hold/unhold, downgrade, mark, why/explain, installed files)
# fuzzy-search the installed list; everything else searches all known packages.
# The typed fallback for installed-kind prompts is guarded too: an uninstalled
# name gets a clear "not installed" message instead of a raw apt-mark/dpkg error.
ask_name() {
    local prompt="$1" mode="${2:-pkg}"
    PKG_NAME=""
    local kind="all"
    case "$prompt" in
        *nstalled*|*unhold*|*uninstall*|*reinstall*|*purge*|*hold*|*downgrade*|*"mark as"*|*explain*) kind="installed" ;;
    esac
    if [ "$mode" = "pkg" ] && [ -t 0 ] && have_fzf; then
        local list sel rc
        case "$kind" in
            installed) list=$(list_installed_names) ;;
            *)         list=$(apt-cache pkgnames 2>/dev/null | LC_ALL=C sort) ;;
        esac
        if [ -n "$list" ]; then
            local -a extra=()
            # Enter on an EMPTY query must not accept the first alphabetical
            # row (a stray Enter would silently pick e.g. the first package
            # for purge/reinstall). accept-non-empty exists since fzf 0.24;
            # --accept-nth in --help is the probe proxy (0.58+ ⊃ 0.24).
            case "${APP_INIT_CAPS:-}" in
                *'--accept-nth'*) extra+=(--bind='enter:accept-non-empty') ;;
            esac
            FZF_PREVIEW=$(pkg_preview_cmd install)
            FZF_GHOST="type to filter · ESC back"
            sel=$(printf '%s\n' "$list" "$OPTION_SUB_EXIT" "$OPTION_APP_EXIT" | fzf_select "$prompt" "❯ " 0 "${extra[@]}")
            rc=$?
            FZF_PREVIEW=""; FZF_GHOST=""
            if [ "$rc" -eq 0 ] && [ -n "$sel" ] && [ "$sel" != "$OPTION_APP_EXIT" ] && [ "$sel" != "$OPTION_SUB_EXIT" ]; then
                PKG_NAME=$sel
                return
            fi
            # Exit row / ctrl-q: cancel the action, the flag rides to the loop;
            # ESC / Back row (rc 1, exactly alike): cancel the action, one level back
            app_exit_wanted && return
            [ "$rc" -eq 1 ] && return
        fi
    fi
    printf '❯ %s: ' "$prompt" >&2
    read -r PKG_NAME
    # normalize: trim surrounding whitespace and CR
    PKG_NAME=$(printf '%s\n' "$PKG_NAME" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ "$mode" = "pkg" ] && [ -n "$PKG_NAME" ] && ! valid_pkg_name "$PKG_NAME"; then
        warn "Invalid package name: '$PKG_NAME'"
        PKG_NAME=""
        return
    fi
    # installed-kind prompts must name an actually-installed package: a typed
    # name that is only in the repo would otherwise die later with raw
    # apt-mark/dpkg errors ("can not be marked as it is not installed")
    if [ -n "$PKG_NAME" ] && [ "$kind" = "installed" ] \
       && ! list_installed_names | grep -Fxq -- "$PKG_NAME"; then
        warn "'$PKG_NAME' is not installed."
        PKG_NAME=""
    fi
}

run_spin() {
    local title="$1"
    shift
    printf '%s\n' "[*] $title"
    "$@"
    return $?
}

log() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    refuse_symlink "$LOG_FILE" || return 0
    printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# log_err — record a real failure so the history "Errors & failures" filter is
# meaningful (log() only records successful actions and never reaches these paths).
log_err() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    refuse_symlink "$LOG_FILE" || return 0
    printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: $1" >> "$LOG_FILE"
}

onoff() { [ "$1" = "1" ] && printf 'on' || printf 'off'; }

confirm() {
    if [ "$CONFIRM" = "1" ] && [ "$QUIET" != "1" ]; then
        printf '%s [y/N]: ' "$1" >&2
        read -r _a
        [ "${_a,,}" = "y" ]
    else
        return 0
    fi
}

confirm_danger() {
    if [ "$LOCK" = "1" ]; then
        printf '%s [y/N]: ' "$1" >&2
        read -r _a
        [ "${_a,,}" = "y" ]
    else
        confirm "$1"
    fi
}

list_installed_names() {
    if [ "$MGR" = "pkg" ]; then
        pkg list-installed 2>/dev/null | grep -E '^[^/[:space:]]+/' | awk '{print $1}' | cut -d/ -f1
    else
        apt list --installed 2>/dev/null | grep -E '^[^/[:space:]]+/' | cut -d/ -f1
    fi
}

pick_file() {
    local title="$1" f=""
    printf '%s (full path): ' "$title" >&2
    read -r f
    printf '%s\n' "$f"
}

save_config() {
    local tmp
    if ! tmp=$(scratch_new); then
        err "Could not create a temp file to save config."
        return 1
    fi
    {
        printf 'MGR=%s\n' "$MGR"
        printf 'THEME=%s\n' "$THEME"
        printf 'CONFIRM=%s\n' "$CONFIRM"
        printf 'LOG_ENABLED=%s\n' "$LOG_ENABLED"
        printf 'ICONS=%s\n' "$ICONS"
        printf 'QUIET=%s\n' "$QUIET"
        printf 'LOCK=%s\n' "$LOCK"
        printf 'STARTUP_CHECK=%s\n' "$STARTUP_CHECK"
        printf 'FAVS_PINNED=%s\n' "$FAVS_PINNED"
        printf 'RECYCLE=%s\n' "$RECYCLE"
        printf 'FZF_ENABLED=%s\n' "$FZF_ENABLED"
    } > "$tmp" || { err "Could not write config temp file."; rm -f "$tmp"; return 1; }
    if ! [ -s "$tmp" ]; then err "Config temp file is empty — leaving your settings alone."; rm -f "$tmp"; return 1; fi
    # keep the previous config — hand-edits should survive a settings toggle
    if [ -f "$HOME/.pkg-manager.conf" ] && [ ! -f "$HOME/.pkg-manager.conf.pkg-manager.bak" ]; then
        safe_cp "$HOME/.pkg-manager.conf" "$HOME/.pkg-manager.conf.pkg-manager.bak" || err "Could not back up settings (writing anyway)."
    fi
    if mv -f "$tmp" "$HOME/.pkg-manager.conf"; then
        printf '✓ Settings saved → %s\n' "$HOME/.pkg-manager.conf"
        return 0
    fi
    err "Failed to save settings to $HOME/.pkg-manager.conf"
    return 1
}

set_mgr() {
    local m
    if have_fzf; then
        m=$(pick_menu "$ICON_SLIDERS  Select package manager" "apt (default, recommended)" "pkg (Termux wrapper)")
    else
        printf '1) apt\n2) pkg\n❯ ' >&2
        read -r m
        case "$m" in
            1) m="apt (default, recommended)" ;;
            2) m="pkg (Termux wrapper)" ;;
            *) return ;;
        esac
    fi
    [ -n "$m" ] || return
    case "$m" in
        apt*) MGR="apt" ;;
        pkg*) MGR="pkg" ;;
        *) return ;;
    esac
    save_config
}

set_theme_pick() {
    local t i
    # Parenthetical = the two dominant roles (accent/headers · cursor/selection),
    # described with colors the themes ACTUALLY use now — the old labels
    # ("blue (blue/orange)", "green (cyan/pink)") described pre-retune pairs.
    local labels=(
        "green (green/lime)" "blue (blue/sky)" "purple (violet/orchid)" "red (coral/salmon)"
        "nord (icy/rose · truecolor)" "amber (gold/peach)" "teal (teal/aqua)" "mono (grayscale)"
        "dracula (truecolor)" "catppuccin (truecolor)" "tokyo-night (truecolor)" "gruvbox (truecolor)"
        "one-dark (truecolor)" "solarized (truecolor)" "everforest (truecolor)" "rose-pine (truecolor)"
    )
    if have_fzf; then
        t=$(pick_menu "$ICON_THEME  Select theme (current: $THEME)" "${labels[@]}")
    else
        list_numbered 0 "${labels[@]}"
        printf '❯ ' >&2
        read -r t
        case "$t" in
            [1-9]|1[0-6]) t="${labels[$((t-1))]}" ;;
            *) return ;;
        esac
    fi
    [ -n "$t" ] || return
    case "$t" in
        green*)     THEME="green" ;;
        blue*)      THEME="blue" ;;
        purple*)    THEME="purple" ;;
        red*)       THEME="red" ;;
        nord*)      THEME="nord" ;;
        amber*)     THEME="amber" ;;
        teal*)      THEME="teal" ;;
        mono*)      THEME="mono" ;;
        dracula*)   THEME="dracula" ;;
        catppuccin*) THEME="catppuccin" ;;
        tokyo*)     THEME="tokyo" ;;
        gruvbox*)   THEME="gruvbox" ;;
        one-dark*)  THEME="onedark" ;;
        solarized*) THEME="solarized" ;;
        everforest*) THEME="everforest" ;;
        rose*)      THEME="rosepine" ;;
        *) return ;;
    esac
    set_theme
    save_config
    ok "Theme set to $THEME"
}

# theme_preview — one swatch line per theme so you can eyeball them all at once
theme_preview() {
    local n sw saved="$THEME"
    section "Theme preview — ■■■■■ = accent/secondary/ok/warn/err"
    for n in "${THEME_NAMES[@]}"; do
        THEME="$n"
        set_theme
        sw="$(paint "$CYAN" "■")$(paint "$PINK" "■")$(paint "$GREEN" "■")$(paint "$YELLOW" "■")$(paint "$RED" "■")"
        printf '  %-11s %s  %s\n' "$n" "$sw" "$(paint "$DIM" "The quick brown fox 0123")"
    done
    THEME="$saved"
    set_theme
}

# apply_termux_theme — export the current theme's full ANSI palette to
# ~/.termux/colors.properties so the whole Termux terminal matches the app.
# The previous file is kept once as colors.properties.pkg-manager.bak.
apply_termux_theme() {
    local t="${1:-$THEME}" dir="$HOME/.termux" tmp i
    local vals
    vals=$(theme_ansi "$t") || {
        warn "Theme '$t' is a legacy 256-color theme with no full ANSI table."
        say "Pick a truecolor theme first: nord, dracula, catppuccin, tokyo, gruvbox, onedark, solarized, everforest, rosepine."
        return 1
    }
    mkdir -p "$dir" || { err "Cannot create $dir"; return 1; }
    if [ -f "$dir/colors.properties" ]; then
        if ! safe_cp "$dir/colors.properties" "$dir/colors.properties.pkg-manager.bak"; then
            err "Could not back up $dir/colors.properties — aborting."
            return 1
        fi
        dim "  existing colors backed up → $dir/colors.properties.pkg-manager.bak"
    fi
    tmp=$(scratch_new) || { err "Could not create a temp file."; return 1; }
    local -a v
    mapfile -t v <<< "$vals"
    {
        printf 'background=#%s\n' "${v[0]}"
        printf 'foreground=#%s\n' "${v[1]}"
        for i in $(seq 0 15); do
            printf 'color%d=#%s\n' "$i" "${v[$((i+2))]}"
        done
    } > "$tmp" || { err "Could not write the palette temp file."; rm -f "$tmp"; return 1; }
    if ! [ -s "$tmp" ]; then err "Palette temp file is empty — colors.properties unchanged."; rm -f "$tmp"; return 1; fi
    if mv -f "$tmp" "$dir/colors.properties"; then
        ok "Wrote $dir/colors.properties (theme: $t)"
        log "termux colors ← theme $t"
        say "Run 'termux-reload-settings' (or restart Termux) to apply it to the terminal."
        return 0
    fi
    err "Failed to write $dir/colors.properties"
    return 1
}

restore_termux_theme() {
    local dir="$HOME/.termux"
    [ -f "$dir/colors.properties.pkg-manager.bak" ] || { warn "No backup found ($dir/colors.properties.pkg-manager.bak)."; return; }
    if ! confirm_danger "Restore the pre-export $dir/colors.properties? (the current one will be replaced)"; then
        say "Canceled — colors.properties unchanged."
        return
    fi
    mv -f "$dir/colors.properties.pkg-manager.bak" "$dir/colors.properties" \
        && ok "Restored previous $dir/colors.properties" \
        || err "Restore failed"
}

pause() {
    printf '\n%s' "$(paint "$DIM" "Press Enter to continue… ")"
    if ! read -r _; then
        return 1
    fi
    clear 2>/dev/null || true
}

# Read apt/dpkg output and return a friendly explanation (empty = unknown).
apt_hint() {
    local out="$1"
    case "$out" in
        *"Unable to locate package"*)           echo "Package not found — check the name (use Search to find it)." ;;
        *"has no installation candidate"*)      echo "Package not found in the repositories." ;;
        *"is already the newest version"*)      echo "Package is already installed and up to date." ;;
        *"already installed"*)                  echo "Package is already installed." ;;
        *"is held back"*)                       echo "Package is held back and won't be upgraded." ;;
        *"not installed, so not removed"*)      echo "Package is not installed — nothing to remove or purge." ;;
        *"is not installed"*)                   echo "Package is not installed." ;;
        *"is not going to be installed"*)       echo "Cannot install — broken or conflicting dependencies." ;;
        *"trying to overwrite"*)                echo "File conflict between packages." ;;
        *"No space left"*|*"no space left"*)   echo "Not enough disk space to complete the operation." ;;
        *"Permission denied"*)                  echo "Permission denied." ;;
        *"Could not get lock"*|*"dpkg was locked"*|*"dpkg is locked"*) echo "Another package operation is running — wait a moment and retry." ;;
        *"Failed to fetch"*)                    echo "Network or repository error while downloading." ;;
        *"held broken packages"*)               echo "Held or broken packages blocked the fix — try Pin/hold or fix manually." ;;
        *"Unable to correct problems"*)         echo "Dependency problems prevent this action." ;;
        *"depends on"*|*"has unmet dependencies"*) echo "Unmet dependencies — run Fix broken packages." ;;
        *)                                      echo "" ;;
    esac
}

# run_multi_op — install/remove a list of packages with clear per-package
# results. Tries ONE batched apt invocation first (a single resolver pass and
# dpkg lock — the fast path for big favorites/restores); only if the batch
# fails does it retry package-by-package to attribute the failure.
# Returns 0 if everything succeeded, 1 otherwise.
# Usage: run_multi_op <install|remove> <pkg1> [pkg2...]
run_multi_op() {
    local op="$1" out hint
    shift
    local total=$# ok=0 fail=0
    local -a failed=() uniq=()
    local p seen_str=" "
    for p in "$@"; do
        case " $seen_str " in
            *" $p "*) continue ;;
        esac
        seen_str="$seen_str $p "
        uniq+=("$p")
    done
    total=${#uniq[@]}
    [ "$total" -eq 0 ] && return 0
    if [ "${DRYRUN:-0}" = "1" ]; then
        say "[DRYRUN] Would run: $MGR $op -y ${uniq[*]}"
        audit_log "dryrun" "$op ${uniq[*]}"
        return 0
    fi
    if [ "$op" = "remove" ] && [ "$RECYCLE" = "1" ]; then
        for p in "${uniq[@]}"; do
            archive_pkg "$p"
        done
    fi
    if [ "$total" -eq 1 ]; then
        if out=$("$MGR" "$op" -y "${uniq[0]}" 2>&1); then
            hint=$(apt_hint "$out")
            log "$op ${uniq[0]}"
            if [ -n "$hint" ]; then
                ok "$hint"
            else
                ok "${uniq[0]}"
            fi
            return 0
        fi
        hint=$(apt_hint "$out")
        err "${uniq[0]} — ${hint:-$op failed}"
        log_err "$op ${uniq[0]}: ${hint:-$op failed}"
        return 1
    fi
    if out=$("$MGR" "$op" -y "${uniq[@]}" 2>&1); then
        for p in "${uniq[@]}"; do ok "$p"; done
        log "$op ${uniq[*]}"
        return 0
    fi
    for pkg in "${uniq[@]}"; do
        if out=$("$MGR" "$op" -y "$pkg" 2>&1); then
            ok=$((ok+1))
            log "$op $pkg"
            ok "$pkg"
        else
            fail=$((fail+1)); failed+=("$pkg")
            hint=$(apt_hint "$out")
            err "$pkg — ${hint:-$op failed}"
            log_err "$op $pkg: ${hint:-$op failed}"
        fi
    done
    if [ "$fail" -eq 0 ]; then
        return 0
    fi
    warn "$ok of $total succeeded, $fail failed (${failed[*]})"
    return 1
}

# list_upgradable — print apt-get "pkg/ver arch" lines (header dropped),
# and return apt's real exit code so callers can tell "none" apart from an
# apt failure (avoid a false "all up to date!" when apt errored).
list_upgradable() {
    local rc out
    out=$(apt list --upgradable 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        return "$rc"
    fi
    printf '%s\n' "$out" | grep -E '^[^/[:space:]]+/'
    return 0
}

do_install() {
        if have_fzf; then
        use_fzf_for_op install
        local rc=$?
        return $rc   # ESC cancels back to the main menu
    fi
    ask_name "Package name to install"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    say "$ICON_INSTALL Installing $PKG_NAME..."
    local out hint
    if out=$("$MGR" install -y "$PKG_NAME" 2>&1); then
        log "install $PKG_NAME"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "$PKG_NAME installed!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Failed to install $PKG_NAME."
        fi
        log_err "install $PKG_NAME: ${hint:-install failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_uninstall() {
        if have_fzf; then
        use_fzf_for_op remove
        local rc=$?
        return $rc   # ESC cancels back to the main menu
    fi
    ask_name "Package name to uninstall"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm_danger "$ICON_UNINSTALL  Really uninstall $PKG_NAME?"; then
        say "Canceled."
        return
    fi
    [ "$RECYCLE" = "1" ] && archive_pkg "$PKG_NAME"
    say "$ICON_UNINSTALL  Removing $PKG_NAME..."
    local out hint
    if out=$("$MGR" remove -y "$PKG_NAME" 2>&1); then
        log "remove $PKG_NAME"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "$PKG_NAME removed!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Failed to remove $PKG_NAME."
        fi
        log_err "remove $PKG_NAME: ${hint:-remove failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_list() {
    log "list installed packages"
    local out n
    if [ "$MGR" = "pkg" ]; then
        out=$(pkg list-installed 2>/dev/null | grep -E '^[^/[:space:]]+/' | awk '{print $1}' | cut -d/ -f1)
    else
        out=$(apt list --installed 2>/dev/null | grep -E '^[^/[:space:]]+/' | cut -d/ -f1)
    fi
    if [ -n "$out" ]; then
        n=$(printf '%s\n' "$out" | grep -c .)
        say "$ICON_LIST Installed packages ($n):"
        dim "  ────────────────────────────"
        printf '%s\n' "$out"
    else
        err "Could not list installed packages"
    fi
}

do_reinstall() {
    ask_name "Package to reinstall / repair"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm "$ICON_REINSTALL Reinstall $PKG_NAME?"; then
        say "Canceled."
        return
    fi
    say "$ICON_REINSTALL Reinstalling $PKG_NAME..."
    local out hint
    if out=$("$MGR" install --reinstall -y "$PKG_NAME" 2>&1); then
        log "reinstall $PKG_NAME"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "$PKG_NAME reinstalled!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Failed to reinstall $PKG_NAME."
        fi
        log_err "reinstall $PKG_NAME: ${hint:-reinstall failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_upgrade_center() {
    log "upgrade center"
    say "$ICON_UPDATE Upgrade center"
    if ! run_spin "Refreshing package lists..." "$MGR" update; then
        err "Update failed — not upgrading."
        return
    fi
    local list pkgs n choice sel
    if ! list=$(list_upgradable); then
        err "Could not check for upgrades — another package operation may be running, or the sources failed."
        return
    fi
    if [ -z "$list" ]; then
        ok "All packages are up to date!"
        return
    fi
    pkgs=$(printf '%s\n' "$list" | cut -d/ -f1)
    n=$(printf '%s\n' "$pkgs" | awk 'NF' | wc -l)
    if have_fzf; then
        local us=$'\x1f' row pkg ver from disp
        local -a urows=()
        urows+=("All packages${us}【 】 All packages — upgrade all $n${us}0${us}every upgradable package")
        while IFS= read -r row; do
            [ -n "$row" ] || continue
            pkg=${row%%/*}
            ver=$(printf '%s\n' "$row" | awk '{print $2}')
            from=$(printf '%s\n' "$row" | sed -n 's/.*upgradable from: *//p' | sed 's/].*//')
            urows+=("$pkg${us}【 】 $pkg  ${from:-?} → $ver${us}${us}installed ${from:-?} → candidate $ver")
        done <<< "$list"
        FZF_PREVIEW=$(pkg_preview_cmd install)
        FZF_NTH="--delimiter=\x1f --nth=1,2 --with-nth=2"
        FZF_GHOST="type to filter $n package(s) · Tab multi"
        local usel
        usel=$(printf '%s\n' "${urows[@]}" "$OPTION_SUB_EXIT${us}$OPTION_SUB_EXIT${us}$us" "$OPTION_APP_EXIT${us}$OPTION_APP_EXIT${us}$us" | fzf_select "$n package(s) have updates — select what to upgrade (SPACE toggles, ESC back)" "upd ❯ " 1 \
            --header="＋ upgrade · Tab multi · ESC back · ctrl-q quits" --footer="? preview · $n updates │ ESC back · ^Q quit")
        FZF_PREVIEW=""; FZF_NTH=""; FZF_GHOST=""
        [ -n "$usel" ] || { app_exit_wanted || say "Canceled."; return; }
        if printf '%s\n' "$usel" | cut -d$'\x1f' -f1 | grep -qx "All packages"; then
            choice="All packages"
        else
            choice=$(printf '%s\n' "$usel" | cut -d$'\x1f' -f1 | sort -u)
        fi
        # fzf rows carry the version transition inline, so the list stays readable in the picker
    else
        say "$ICON_UPGRADABLE $n package(s) have updates:"
        printf '%s\n' "$list"
        printf '\nUpgrade all [a], none [n], or pick some (space-separated names): ' >&2
        read -r choice
        case "$choice" in
            a|A|all|All|ALL) choice="All packages" ;;
            n|N|"")           say "Canceled."; return ;;
            *)                choice=$(printf '%s\n' "$choice" | tr ' ' '\n') ;;
        esac
    fi
    [ -n "$choice" ] || { say "Canceled."; return; }
    if [ "$choice" = "All packages" ]; then
        say "$ICON_UP  Upgrading all packages..."
        local out hint
        if out=$(run_spin "Upgrading..." "$MGR" upgrade -y 2>&1); then
            log "upgrade all"
            hint=$(apt_hint "$out")
            ok "${hint:-Upgrade complete!}"
        else
            hint=$(apt_hint "$out")
            err "${hint:-Upgrade failed.}"
            log_err "upgrade all: ${hint:-failed}"
            printf '%s\n' "$out" | tail -n 4
        fi
    else
        sel=$(printf '%s\n' "$choice" | filter_pkgs)
        [ -n "$sel" ] || { app_exit_wanted || say "Nothing selected."; return; }
        say "$ICON_UP  Upgrading selected packages..."
        local -a _pkgs=()
        mapfile -t _pkgs <<< "$sel"
        if run_multi_op install "${_pkgs[@]}"; then
            log "upgrade: $(printf '%s' "$sel" | tr '\n' ' ')"
        fi
    fi
    if confirm_danger "$ICON_AUTOREMOVE Remove now-unused dependencies?"; then
        local out hint
        if out=$(apt autoremove -y 2>&1); then
            hint=$(apt_hint "$out")
            ok "${hint:-Autoremoved unused dependencies.}"
        else
            hint=$(apt_hint "$out")
            err "${hint:-Autoremove failed.}"
            log_err "autoremove: ${hint:-failed}"
            printf '%s\n' "$out" | tail -n 4
        fi
    fi
    if confirm_danger "$ICON_CLEAN Clean the download cache?"; then
        local out hint
        if out=$("$MGR" clean 2>&1); then
            hint=$(apt_hint "$out")
            ok "${hint:-Cache cleaned!}"
        else
            hint=$(apt_hint "$out")
            err "${hint:-Failed to clean cache.}"
            log_err "clean cache: ${hint:-failed}"
            printf '%s\n' "$out" | tail -n 4
        fi
    fi
}

do_clean() {
    if ! confirm_danger "$ICON_CLEAN Clear the download cache?"; then
        say "Canceled."
        return
    fi
    local out hint
    if out=$(run_spin "Cleaning cache..." "$MGR" clean 2>&1); then
        log "clean cache"
        hint=$(apt_hint "$out")
        ok "${hint:-Cache cleaned!}"
    else
        hint=$(apt_hint "$out")
        err "${hint:-Failed to clean cache}"
        log_err "clean cache: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_info() {
    ask_name "Package name to inspect"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "show $PKG_NAME"
    say "$ICON_INFO  Info for \"$PKG_NAME\":"
    local out
    out=$("$MGR" show "$PKG_NAME" 2>/dev/null | grep -v '^WARNING:')
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        err "Package not found — check the name or run $ICON_UPDATE Upgrade center first?"
    fi
}

do_autoremove() {
    if ! confirm_danger "$ICON_AUTOREMOVE Remove orphaned dependencies?"; then
        say "Canceled."
        return
    fi
    local out hint
    if out=$(apt autoremove -y 2>&1); then
        log "autoremove"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "System cleaned!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Autoremove failed."
        fi
        log_err "autoremove: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_depends() {
    ask_name "Package name"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "depends $PKG_NAME"
    say "$ICON_DEPENDS Dependencies of $PKG_NAME:"
    apt depends "$PKG_NAME" 2>/dev/null || err "Could not read dependencies"
}

do_rdepends() {
    ask_name "Package name"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "rdepends $PKG_NAME"
    say "$ICON_RDEPENDS Packages that depend on $PKG_NAME:"
    local out
    out=$(apt rdepends "$PKG_NAME" 2>/dev/null | grep -v '^WARNING:')
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        err "No reverse dependencies found — package not found or has no dependents"
    fi
}

do_size() {
    ask_name "Package name"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "size $PKG_NAME"
    say "$ICON_SIZE  Sizes for $PKG_NAME:"
    local out hint
    out=$(apt-cache show "$PKG_NAME" 2>&1 \
        | grep -E '^(Package|Version|Size|Installed-Size):')
    if [ -n "$out" ]; then
        # Bytes and KiB become human sizes; the aligned columns keep the
        # record readable on a phone (Size is bytes, Installed-Size is KiB).
        printf '%s\n' "$out" | awk -v pkg="$PKG_NAME" '
            function human(b,   u, i, v) {
                split("B KB MB GB TB", u, " "); v=b+0; i=1
                while (v >= 1024 && i < 5) { v /= 1024; i++ }
                return sprintf("%.1f %s", v, u[i])
            }
            /^Package:/     { sub(/^Package:[[:space:]]*/, ""); pkg=$0
                               printf "  %-18s %s\n", "Package", $0; next }
            /^Version:/     { sub(/^Version:[[:space:]]*/, "")
                               printf "  %-18s %s\n", "Version", $0; next }
            /^Size:/        { sub(/^Size:[[:space:]]*/, "")
                               printf "  %-18s %s\n", "Download size", human($0); next }
            /^Installed-Size:/ { sub(/^Installed-Size:[[:space:]]*/, "")
                               printf "  %-18s %s\n", "Installed size", human($0*1024); next }
            { print }'
    else
        hint=$(apt_hint "$out")
        err "${hint:-Package not in cache — run $ICON_UPDATE Upgrade center first?}"
        [ -n "$hint" ] && log_err "size $PKG_NAME: $hint"
    fi
}

do_files() {
    ask_name "Installed package name"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "files $PKG_NAME"
    say "$ICON_FILES Files installed by $PKG_NAME:"
    local out hint
    # dpkg -L prints NO header — it starts with "/."; there is no first line to drop
    out=$(dpkg -L "$PKG_NAME" 2>/dev/null)
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        hint=$(apt_hint "$out")
        err "${hint:-Package may not be installed}"
        [ -n "$hint" ] && log_err "files $PKG_NAME: $hint"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_owner() {
    local file
    ask_name "File path (e.g. $PREFIX/bin/python)" path
    file="$PKG_NAME"
    [ -n "$file" ] || { warn "No file given."; return; }
    case "$file" in -*)
        err "Invalid file path — must not start with '-'."
        return ;;
    esac
    log "owner $file"
    say "$ICON_OWNER  Which package owns $file:"
    dpkg -S -- "$file" 2>/dev/null || err "No installed package owns that file"
}

do_hold() {
    local a
    a=$(pick_menu "$ICON_HOLD  Pin / hold" "Hold a package" "Unhold a package" "Show held packages")
    [ -n "$a" ] || return
    case "$a" in
        Hold*)
            ask_name "Package to hold"
            [ -n "$PKG_NAME" ] || return
            local out hint
            if out=$(apt-mark hold "$PKG_NAME" 2>&1); then
                log "hold $PKG_NAME"
                hint=$(apt_hint "$out")
                ok "${hint:-$PKG_NAME is now held}"
            else
                hint=$(apt_hint "$out")
                err "${hint:-Failed to hold $PKG_NAME}"
                log_err "hold $PKG_NAME: ${hint:-failed}"
                printf '%s\n' "$out" | tail -n 4
            fi
            ;;
        Unhold*)
            ask_name "Package to unhold"
            [ -n "$PKG_NAME" ] || return
            local out hint
            if out=$(apt-mark unhold "$PKG_NAME" 2>&1); then
                log "unhold $PKG_NAME"
                hint=$(apt_hint "$out")
                ok "${hint:-$PKG_NAME is no longer held}"
            else
                hint=$(apt_hint "$out")
                err "${hint:-Failed to unhold $PKG_NAME}"
                log_err "unhold $PKG_NAME: ${hint:-failed}"
                printf '%s\n' "$out" | tail -n 4
            fi
            ;;
        Show*)
            say "$ICON_HOLD Held packages:"
            local held
            held=$(apt-mark showhold 2>/dev/null)
            if [ -n "$held" ]; then
                printf '%s\n' "$held"
            else
                say "None"
            fi
            ;;
    esac
}

do_purge() {
    ask_name "Package to purge"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm_danger "$ICON_PURGE Purge $PKG_NAME (remove + config)?"; then
        say "Canceled."
        return
    fi
    [ "$RECYCLE" = "1" ] && archive_pkg "$PKG_NAME"
    say "$ICON_PURGE Purging $PKG_NAME..."
    local out hint
    if out=$(apt purge -y "$PKG_NAME" 2>&1); then
        log "purge $PKG_NAME"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "$PKG_NAME purged!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Failed to purge $PKG_NAME."
        fi
        log_err "purge $PKG_NAME: ${hint:-purge failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_fixbroken() {
    if ! confirm_danger "$ICON_FIXBROKEN Run apt --fix-broken install?"; then
        say "Canceled."
        return
    fi
    say "$ICON_FIXBROKEN Fixing broken packages..."
    local out hint
    if out=$(apt --fix-broken install -y 2>&1); then
        log "fix-broken"
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "Dependency problems fixed!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Fix-broken failed."
        fi
        log_err "fix-broken: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_upgradable() {
    log "upgradable list"
    local out n
    if ! out=$(list_upgradable); then
        err "Could not read the upgradable list — run $ICON_UPDATE Upgrade center first?"
        return
    fi
    if [ -n "$out" ]; then
        n=$(printf '%s\n' "$out" | grep -cv '^$')
        say "$ICON_UPGRADABLE Packages with available updates ($n):"
        dim "  ────────────────────────────"
        printf '%s\n' "$out"
    else
        ok "All packages are up to date!"
    fi
}

do_simulate() {
    local a
    a=$(pick_menu "$ICON_EYE  Simulate a change" "Simulate install" "Simulate remove" "Simulate upgrade all")
    [ -n "$a" ] || return
    case "$a" in
        *install*)
            ask_name "Package name to preview"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            log "simulate install $PKG_NAME"
            say "$ICON_EYE  Dry-run — what installing $PKG_NAME would change:"
            local out hint
            if ! out=$("$MGR" install -s "$PKG_NAME" 2>&1); then
                hint=$(apt_hint "$out")
                err "${hint:-Could not simulate install}"
                printf '%s\n' "$out" | tail -n 4
            else
                printf '%s\n' "$out"
            fi
            ;;
        *remove*)
            ask_name "Package name to preview"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            log "simulate remove $PKG_NAME"
            say "$ICON_EYE  Dry-run — what removing $PKG_NAME would change:"
            local out hint
            if ! out=$("$MGR" remove -s "$PKG_NAME" 2>&1); then
                hint=$(apt_hint "$out")
                err "${hint:-Could not simulate remove}"
                printf '%s\n' "$out" | tail -n 4
            else
                printf '%s\n' "$out"
            fi
            ;;
        *upgrade*)
            log "simulate upgrade"
            say "$ICON_EYE  Dry-run — full system upgrade preview:"
            local out hint
            if ! out=$("$MGR" upgrade -s 2>&1); then
                hint=$(apt_hint "$out")
                err "${hint:-Could not simulate upgrade}"
                printf '%s\n' "$out" | tail -n 4
            else
                printf '%s\n' "$out"
            fi
            ;;
    esac
}

do_stats() {
    local a
    a=$(pick_menu "$ICON_CHART  Package stats & disk" "Overview" "Disk usage by directory" "Largest files" "Cache breakdown" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Overview)
            log "package stats"
            say "$ICON_CHART  Package stats"
            local count sizes total cache installed
            if ! installed=$(list_installed_names 2>/dev/null); then
                err "Could not read the installed package list."
                return
            fi
            count=$(printf '%s\n' "$installed" | awk 'NF' | wc -l)
            ok "Installed packages: $count"
            sizes=$(dpkg-query -W -f='${Installed-Size}\t${Package}\n' 2>/dev/null)
            if [ -n "$sizes" ]; then
                total=$(printf '%s\n' "$sizes" | awk '{s+=$1} END {printf "%.1f MiB", s/1024}')
                say "Total installed size: $total"
                say "Largest packages:"
                printf '%s\n' "$sizes" | sort -rn | head -10 | awk '{printf "  %6.1f MiB  %s\n", $1/1024, $2}'
            else
                warn "Size data unavailable — could not read dpkg status."
            fi
            cache=$(du -sh "$PREFIX/var/cache/apt/archives" 2>/dev/null | cut -f1)
            if [ -n "$cache" ]; then
                say "Download cache: $cache"
            else
                warn "Could not read cache size."
            fi
            ;;
        Disk*)
            log "disk usage by directory"
            say "$ICON_DISK  Disk usage by directory ($PREFIX):"
            local dustmp
            dustmp=$(mktemp "$HOME/.pkg-manager-du.XXXXXX" 2>/dev/null) || dustmp=""
            if [ -n "$dustmp" ]; then
                du -h -d1 "$PREFIX" > "$dustmp" 2>/dev/null
                sort -rh "$dustmp" | head -20
                rm -f "$dustmp"
            else
                du -h -d1 "$PREFIX" 2>/dev/null | sort -rh | head -20 || warn "Could not scan $PREFIX."
            fi
            ;;
        *Largest*)
            log "largest files"
            say "$ICON_DISK  Largest files under $PREFIX:"
            local ltmp
            ltmp=$(mktemp "$HOME/.pkg-manager-find.XXXXXX" 2>/dev/null) || ltmp=""
            if [ -n "$ltmp" ]; then
                find "$PREFIX" -type f -printf '%s\t%p\n' > "$ltmp" 2>/dev/null
                sort -rn "$ltmp" | head -20 \
                    | awk '{ printf "  %6.1f MiB  %s\n", $1/1048576, substr($0, index($0,"\t")+1) }'
                rm -f "$ltmp"
            else
                find "$PREFIX" -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 \
                    | awk '{ printf "  %6.1f MiB  %s\n", $1/1048576, substr($0, index($0,"\t")+1) }'
            fi
            ;;
        Cache*)
            log "cache breakdown"
            local dir="$PREFIX/var/cache/apt/archives"
            say "$ICON_DISK  Cache breakdown:"
            if [ -d "$dir" ]; then
                local dtmp
                dtmp=$(mktemp "$HOME/.pkg-manager-du.XXXXXX" 2>/dev/null) || dtmp=""
                if [ -n "$dtmp" ]; then
                    du -ah "$dir" > "$dtmp" 2>/dev/null
                    sort -rh "$dtmp" | head -20
                    rm -f "$dtmp"
                else
                    du -ah "$dir" 2>/dev/null | sort -rh | head -20 || ls -lh "$dir"
                fi
                say "Total: $(du -sh "$dir" 2>/dev/null | cut -f1)"
            else
                say "No cache directory yet."
            fi
            ;;
        *) return ;;
    esac
}

do_cache() {
    local dir="$PREFIX/var/cache/apt/archives" size a
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    if [ -n "$size" ]; then
        say "$ICON_CACHE  Download cache: $size"
    else
        warn "$ICON_CACHE  Could not read cache size."
    fi
    a=$(pick_menu "$ICON_CACHE  Cache manager" "Clean all cached files (apt clean)" "Remove only outdated .deb (autoclean)" "Show cached files" "Back")
    [ -n "$a" ] || return
    case "$a" in
        *"Clean all"*)
            if confirm_danger "$ICON_CACHE  Delete every cached .deb?"; then
                local out hint
                if out=$(run_spin "Cleaning cache..." "$MGR" clean 2>&1); then
                    log "apt clean"
                    hint=$(apt_hint "$out")
                    ok "${hint:-Cache cleaned!}"
                else
                    hint=$(apt_hint "$out")
                    err "${hint:-Failed to clean cache.}"
                    log_err "apt clean: ${hint:-failed}"
                    printf '%s\n' "$out" | tail -n 4
                fi
            fi
            ;;
        *"outdated"*)
            if confirm_danger "$ICON_CACHE  Remove outdated .deb files only?"; then
                local out hint
                if out=$(run_spin "Autocleaning..." apt autoclean 2>&1); then
                    log "apt autoclean"
                    hint=$(apt_hint "$out")
                    ok "${hint:-Outdated packages cleaned!}"
                else
                    hint=$(apt_hint "$out")
                    err "${hint:-Autoclean failed.}"
                    log_err "apt autoclean: ${hint:-failed}"
                    printf '%s\n' "$out" | tail -n 4
                fi
            fi
            ;;
        *"Show"*)
            log "show cache files"
            if [ -d "$dir" ]; then
                ls -lh "$dir" 2>/dev/null || ls -l "$dir"
            else
                say "No cache directory yet."
            fi
            ;;
        *) return ;;
    esac
}

DEPTREE_VISITED=""

dep_tree() {
    local pkg="$1" depth="$2" d deps
    [ "$depth" -gt 4 ] && return
    case " $DEPTREE_VISITED " in
        *" $pkg "*) return ;;
    esac
    DEPTREE_VISITED="$DEPTREE_VISITED $pkg"
    deps=$(apt-cache depends "$pkg" 2>/dev/null | grep -E '^  (Depends|PreDepends|Recommends):' | sed 's/.*: //' | cut -d' ' -f1 | grep -v '^<')
    for d in $deps; do
        printf '%*s- %s\n' $((depth*2)) "" "$d"
        dep_tree "$d" $((depth+1))
    done
}

do_deptools() {
    local a block orphans n
    a=$(pick_menu "$ICON_TREE  Dependency tools" "Dependency tree" "Orphan finder" "Back")
    [ -n "$a" ] || return
    case "$a" in
        *"tree"*)
            ask_name "Package name"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            log "dependency tree $PKG_NAME"
            say "$ICON_TREE  Dependency tree of $PKG_NAME:"
            DEPTREE_VISITED=""
            printf '%s\n' "$PKG_NAME"
            dep_tree "$PKG_NAME" 1
            ;;
        *"Orphan"*)
            log "orphan finder"
            say "$ICON_TREE  Searching for orphaned packages (installed but no longer needed)..."
            if block=$(apt autoremove --simulate -y 2>&1); then
                orphans=$(printf '%s\n' "$block" | awk '
                    /will be REMOVED:/ {on=1; next}
                    on && /upgraded|newly installed|not upgraded|after this operation/ {on=0}
                    on { for (i=1;i<=NF;i++)
                            if ($i ~ /^[A-Za-z][A-Za-z0-9+.:~-]*$/ && $i !~ /^[0-9][0-9.:-]+$/) print $i }
                ')
                if [ -n "$orphans" ]; then
                    n=$(printf '%s\n' "$orphans" | wc -l)
                    say "Found $n orphaned package(s):"
                    printf '%s\n' "$orphans"
                    if confirm_danger "$ICON_AUTOREMOVE  Autoremove them?"; then
                        log "autoremove orphans"
                        local out hint
                        if out=$(apt autoremove -y 2>&1); then
                            hint=$(apt_hint "$out")
                            ok "${hint:-Orphans removed!}"
                        else
                            hint=$(apt_hint "$out")
                            err "${hint:-Autoremove failed.}"
                            log_err "autoremove orphans: ${hint:-failed}"
                            printf '%s\n' "$out" | tail -n 4
                        fi
                    fi
                else
                    ok "No orphaned packages found!"
                fi
            else
                err "Could not check for orphaned packages."
            fi
            ;;
        *) return ;;
    esac
}

do_bulk() {
    local a names n sel
    a=$(pick_menu "$ICON_BULK  Bulk operations" "Install multiple packages" "Remove multiple packages" "Remove (pick from installed list)" "Upgrade (pick from upgradable list)" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Install*)
            printf '❯ Packages (space-separated): ' >&2
            read -r names
            names=$(printf '%s\n' "$names" | tr ' ' '\n' | filter_pkgs)
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            [ "$n" -gt 0 ] || { warn "No valid package names."; return; }
            if confirm_danger "$ICON_INSTALL Install $n packages ($(printf '%s' "$names" | tr '\n' ' '))?"; then
                say "$ICON_INSTALL Installing $n packages..."
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                if run_multi_op install "${_pkgs[@]}"; then
                    log "bulk install: $(printf '%s' "$names" | tr '\n' ' ')"
                fi
            fi
            ;;
        Remove*multiple*)
            printf '❯ Packages (space-separated): ' >&2
            read -r names
            names=$(printf '%s\n' "$names" | tr ' ' '\n' | filter_pkgs)
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            [ "$n" -gt 0 ] || { warn "No valid package names."; return; }
            if confirm_danger "$ICON_UNINSTALL Remove $n packages ($(printf '%s' "$names" | tr '\n' ' '))?"; then
                say "$ICON_UNINSTALL Removing $n packages..."
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                if run_multi_op remove "${_pkgs[@]}"; then
                    log "bulk remove: $(printf '%s' "$names" | tr '\n' ' ')"
                fi
            fi
            ;;
        *"installed list"*)
            names=$(pick_names "$ICON_UNINSTALL Pick packages to remove (SPACE toggles)")
            [ -n "$names" ] || { say "Nothing selected."; return; }
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            if confirm_danger "$ICON_UNINSTALL Remove $n package(s) from the installed list?"; then
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                if run_multi_op remove "${_pkgs[@]}"; then
                    log "bulk remove picked: $(printf '%s' "$names" | tr '\n' ' ')"
                fi
            fi
            ;;
        *"upgradable list"*)
            names=$(pick_upgradable)
            [ -n "$names" ] || { say "Nothing selected."; return; }
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            if confirm_danger "$ICON_UP  Upgrade $n package(s)?"; then
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                if run_multi_op install "${_pkgs[@]}"; then
                    log "bulk upgrade picked: $(printf '%s' "$names" | tr '\n' ' ')"
                fi
            fi
            ;;
        *) return ;;
    esac
}

pick_names() {
    local header="$1" tmp n i sel
    if have_fzf; then
        list_installed_names | pick_multi "$header" || return 1
    else
        if ! tmp=$(scratch_new); then
            warn "Could not create a temp file to list packages."
            return 1
        fi
        list_installed_names > "$tmp"
        n=$(wc -l < "$tmp")
        [ "$n" -gt 0 ] || { rm -f "$tmp"; warn "No packages to pick from."; return 1; }
        nl -w2 -s') ' "$tmp" >&2
        printf '❯ Numbers (space-separated): ' >&2
        read -r sel
        for i in $sel; do
            case "$i" in ''|*[!0-9]*) continue ;; esac
            if [ "$i" -ge 1 ] && [ "$i" -le "$n" ]; then
                printf '%s\n' "$(sed -n "${i}p" "$tmp")"
            fi
        done
        rm -f "$tmp"
    fi
}

pick_upgradable() {
    local header list tmp n i sel
    header="${1:-$ICON_CHECKBOX Pick packages to upgrade}"
    if ! list=$(list_upgradable); then
        err "Could not read the upgradable list — another package operation may be running."
        return 1
    fi
    list=$(printf '%s\n' "$list" | cut -d/ -f1)
    [ -n "$list" ] || return 1
    if have_fzf; then
        printf '%s\n' "$list" | pick_multi "$header" || return 1
    else
        if ! tmp=$(scratch_new); then
            err "Could not create a temp file to list upgradable packages."
            return 1
        fi
        printf '%s\n' "$list" > "$tmp"
        n=$(wc -l < "$tmp")
        nl -w2 -s') ' "$tmp" >&2
        printf '❯ Numbers (space-separated): ' >&2
        read -r sel
        for i in $sel; do
            case "$i" in ''|*[!0-9]*) continue ;; esac
            if [ "$i" -ge 1 ] && [ "$i" -le "$n" ]; then
                printf '%s\n' "$(sed -n "${i}p" "$tmp")"
            fi
        done
        rm -f "$tmp"
    fi
}

do_favs() {
    local a name n
    if have_fzf; then
        a=$(pick_menu "$ICON_STAR  Favorites" "Add favorite" "Remove favorite" "Show favorites" "Install all favorites" "Pin favorites to main menu: $(onoff "$FAVS_PINNED")" "Install one favorite" "Back")
    else
        printf '1) Add favorite\n2) Remove favorite\n3) Show favorites\n4) Install all favorites\n5) Pin favorites to main menu: %s\n6) Install one favorite\n7) Back\n> ' "$(onoff "$FAVS_PINNED")" >&2
        read -r a
        case "$a" in
            1) a="Add favorite" ;;
            2) a="Remove favorite" ;;
            3) a="Show favorites" ;;
            4) a="Install all favorites" ;;
            5) a="Pin favorites to main menu: $(onoff "$FAVS_PINNED")" ;;
            6) a="Install one favorite" ;;
            7) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        Add*)
            ask_name "Package name to favorite"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            if [ ! -f "$FAVS_FILE" ]; then
                if tmp=$(scratch_new); then printf '%s\n' "$PKG_NAME" > "$tmp" && mv -f "$tmp" "$FAVS_FILE" && log "favorite add $PKG_NAME" && ok "$PKG_NAME added to favorites ($FAVS_FILE)"; else err "Could not create temp file for favorites."; fi
                return
            fi
            if grep -Fxq "$PKG_NAME" "$FAVS_FILE"; then
                warn "$PKG_NAME is already a favorite."
            else
                if tmp=$(scratch_new); then
                    if [ -f "$FAVS_FILE" ] && ! cp "$FAVS_FILE" "$tmp"; then
                        err "Could not read favorites — leaving them unchanged."
                        rm -f "$tmp"; return
                    fi
                    if printf '%s\n' "$PKG_NAME" >> "$tmp" && mv -f "$tmp" "$FAVS_FILE" && log "favorite add $PKG_NAME"; then
                        ok "$PKG_NAME added to favorites"
                    else
                        err "Could not save favorites."; rm -f "$tmp"
                    fi
                    else
                        err "Could not create temp file for favorites."
                    fi
            fi
            [ "$FAVS_PINNED" = "1" ] && build_menu
            ;;
        Remove*)
            [ -s "$FAVS_FILE" ] || { warn "No favorites yet."; return; }
            if have_fzf; then
                local -a _favs=()
                mapfile -t _favs < "$FAVS_FILE"
                name=$(printf '%s\n' "${_favs[@]}" | pick_one "$ICON_STAR  Pick favorite to remove")
            else
                printf 'Favorites:\n' >&2
                nl -w2 -s') ' "$FAVS_FILE" >&2
                printf '❯ Pick number (0 = cancel): ' >&2
                read -r a
                case "$a" in
                    [1-9]|[1-9][0-9]) name=$(sed -n "${a}p" "$FAVS_FILE") ;;
                    *) return ;;
                esac
            fi
            [ -n "$name" ] || return
            if grep -Fxq -- "$name" "$FAVS_FILE"; then
                if tmp=$(scratch_new); then
                    grep -Fxv -- "$name" "$FAVS_FILE" > "$tmp" || [ $? -le 1 ] || { rm -f "$tmp"; err "Could not read favorites — leaving them unchanged."; return; }
                    if mv -f "$tmp" "$FAVS_FILE"; then
                        log "favorite remove $name"
                        ok "$name removed from favorites."
                    else
                        err "Failed to update favorites."
                    fi
                fi
            fi
            [ "$FAVS_PINNED" = "1" ] && build_menu
            ;;
        Show*)
            if [ ! -s "$FAVS_FILE" ]; then
                say "No favorites yet — add some first!"
                return
            fi
            n=$(awk 'NF' "$FAVS_FILE" | wc -l)
            say "$ICON_STAR $n favorite(s):"
            awk 'NF' "$FAVS_FILE"
            ;;
        *"Install all"*)
            [ -s "$FAVS_FILE" ] || { warn "No favorites yet."; return; }
            n=$(awk 'NF' "$FAVS_FILE" | wc -l)
            if confirm_danger "$ICON_STAR Install all $n favorite(s)?"; then
                log "favorite install all"
                say "$ICON_STAR Installing favorites..."
                if install_from_list "$FAVS_FILE" "Favorites"; then
                    ok "Favorites installed!"
                fi
            fi
            ;;
        Pin*)
            if [ "$FAVS_PINNED" = "1" ]; then
                FAVS_PINNED=0
            else
                if [ -s "$FAVS_FILE" ]; then
                    FAVS_PINNED=1
                else
                    warn "Add favorites first, then pin them."
                    return
                fi
            fi
            save_config
            build_menu
            if [ "$FAVS_PINNED" = "1" ]; then
                ok "Favorites pinned to the main menu."
            else
                say "Favorites removed from the main menu."
            fi
            ;;
        *"one favorite"*)
            [ -s "$FAVS_FILE" ] || { warn "No favorites yet."; return; }
            if have_fzf; then
                local -a _favs=()
                mapfile -t _favs < <(awk 'NF' "$FAVS_FILE")
                name=$(printf '%s\n' "${_favs[@]}" | pick_one "$ICON_STAR  Pick favorite to install")
            else
                printf 'Favorites:\n' >&2
                nl -w2 -s') ' "$FAVS_FILE" >&2
                printf '❯ Pick number (0 = cancel): ' >&2
                read -r a
                case "$a" in
                    [1-9]|[1-9][0-9]) name=$(sed -n "${a}p" "$FAVS_FILE") ;;
                    *) return ;;
                esac
            fi
            [ -n "$name" ] || return
            if ! valid_pkg_name "$name"; then
                err "Skipping invalid favorite name '$name'."
                return
            fi
            if confirm_danger "$ICON_STAR Install favorite $name?"; then
                local out hint
                if out=$("$MGR" install -y "$name" 2>&1); then
                    log "favorite install $name"
                    hint=$(apt_hint "$out")
                    if [ -n "$hint" ]; then
                        ok "$hint"
                    else
                        ok "$name installed!"
                    fi
                else
                    hint=$(apt_hint "$out")
                    err "${hint:-"Failed to install $name."}"
                    log_err "favorite install $name: ${hint:-install failed}"
                fi
            fi
            ;;
        *) return ;;
    esac
}

do_backup() {
    local file tmp
    file="$HOME/pkg-backup-$(date +%Y%m%d-%H%M%S)-$$.txt"
    say "$ICON_BACKUP Backing up installed packages..."
    if ! tmp=$(scratch_new); then err "Could not create temp file for backup."; return; fi
    if list_installed_names > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv -f "$tmp" "$file"; then
        log "backup → $file"
        ok "Backed up $(wc -l < "$file") packages → $file"
    else
        rm -f "$tmp" "$file"
        err "Backup failed"
    fi
}

install_from_list() {
    local file="$1" action="$2" list
    list=$(awk 'NF' "$file" | filter_pkgs)
    [ -n "$list" ] || { err "No valid package names in $file"; return 1; }
    local -a _pkgs=()
    mapfile -t _pkgs <<< "$list"
    say "$action — installing ${#_pkgs[@]} package(s)..."
    run_multi_op install "${_pkgs[@]}"
}

do_restore() {
    local file
    file=$(pick_file "Select a backup file")
    case "$file" in
        -* ) err "Invalid path — must not start with '-'."; return ;;
    esac
    [ -n "$file" ] && [ -f "$file" ] || { warn "No file selected."; return; }
    if ! confirm "$ICON_RESTORE  Restore $(awk 'NF' "$file" | filter_pkgs | wc -l) packages from $(basename "$file")?"; then
        say "Canceled."
        return
    fi
    log "restore ← $file"
    say "$ICON_RESTORE  Restoring packages..."
    if install_from_list "$file" "Restore"; then
        ok "Restore complete!"
    fi
}

do_export() {
    local fmt file ext list count
    fmt=$(pick_menu "$ICON_EXPORT  Export format" "Plain text (.txt)" "JSON (.json)")
    [ -n "$fmt" ] || return
    case "$fmt" in
        *JSON*) ext="json" ;;
        *)      ext="txt" ;;
    esac
    if [ "$ext" = "json" ] && ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found — exporting as plain text instead"
        ext="txt"
    fi
    printf 'Save path [%s]: ' "$HOME/pkg-export.$ext"
    read -r file
    [ -n "$file" ] || file="$HOME/pkg-export.$ext"
    case "$file" in
        -* ) err "Invalid path — must not start with '-'."; return ;;
    esac
    if [ -e "$file" ] && ! confirm_danger "$ICON_EXPORT  File $file exists — overwrite it?"; then
        say "Canceled."
        return
    fi
    if ! list=$(list_installed_names); then
        err "Could not read the installed list — not exporting."
        return
    fi
    count=$(printf '%s\n' "$list" | awk 'NF' | wc -l)
    if ! tmp=$(scratch_new); then
        err "Could not create a temp file for the export."
        return
    fi
    local ok_write=1
    if [ "$ext" = "json" ]; then
        if command -v python3 >/dev/null 2>&1; then
            if ! printf '%s\n' "$list" | python3 -c 'import sys,json; p=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps({"packages":p}, indent=2))' > "$tmp"; then
                ok_write=0
            fi
        else
            if ! printf '%s\n' "$list" > "$tmp"; then ok_write=0; fi
        fi
    else
        if ! printf '%s\n' "$list" > "$tmp"; then ok_write=0; fi
    fi
    if [ "$ok_write" = "1" ] && mv -f "$tmp" "$file"; then
        log "export → $file"
        ok "Exported $count packages → $file"
    else
        err "Failed to write export to $file"
    fi
}

do_import() {
    local file
    file=$(pick_file "Select a package list file")
    case "$file" in
        -* ) err "Invalid path — must not start with '-'."; return ;;
    esac
    [ -n "$file" ] && [ -f "$file" ] || { warn "No file selected."; return; }
    if ! confirm "$ICON_IMPORT Install $(awk 'NF' "$file" | filter_pkgs | wc -l) packages from $(basename "$file")?"; then
        say "Canceled."
        return
    fi
    log "import ← $file"
    say "$ICON_IMPORT Importing packages..."
    if install_from_list "$file" "Import"; then
        ok "Import complete!"
    fi
}

do_doctor() {
    local missing=() dep  # fzf is checked even when FZF_ENABLED=0 — doctor reports availability
    say "$ICON_DOCTOR Checking helper tools..."
    for dep in fzf git curl figlet; do
        if command -v "$dep" >/dev/null 2>&1; then
            ok "$dep"
        else
            warn "$dep missing"
            missing+=("$dep")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        if confirm "Install: ${missing[*]} ?"; then
            log "install helpers: ${missing[*]}"
            local out hint
            if out=$("$MGR" install -y "${missing[@]}" 2>&1); then
                hint=$(apt_hint "$out")
                ok "${hint:-Installed: ${missing[*]}}"
            else
                hint=$(apt_hint "$out")
                err "${hint:-Install failed}"
                log_err "install helpers ${missing[*]}: ${hint:-failed}"
                printf '%s\n' "$out" | tail -n 4
            fi
        fi
    else
        say "All helper tools present!"
    fi
}

do_settings() {
    local choice
    local settings_items=(
        "$ICON_SLIDERS  Package manager: $MGR"
        "$ICON_THEME  Themes & terminal colors: $THEME"
        "$ICON_PAINT  Icons: $ICONS"
        "$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")"
        "$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")"
        "$ICON_FOLDER  Show config file"
        "$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")"
        "$ICON_LOCK  Safety lock: $(onoff "$LOCK")"
        "$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")"
        "$ICON_TRASH  Recycle bin (archive on remove): $(onoff "$RECYCLE")"
        "$ICON_SEARCH  fzf picker: $(fzf_label)"
        "$ICON_BACK  Back")
    if have_fzf; then
        choice=$(pick_menu "$ICON_SETTINGS  Settings" "${settings_items[@]}")
    else
        printf '1) Package manager: %s\n2) Themes & terminal colors: %s\n3) Icons: %s\n4) Safety confirms: %s\n5) History log: %s\n6) Show config file\n7) Quiet mode (skip confirms): %s\n8) Safety lock: %s\n9) Maintenance on launch: %s\n10) Recycle bin (archive on remove): %s\n11) fzf picker: %s\n12) Back\n> ' \
            "$MGR" "$THEME" "$ICONS" "$(onoff "$CONFIRM")" "$(onoff "$LOG_ENABLED")" "$(onoff "$QUIET")" "$(onoff "$LOCK")" "$(onoff "$STARTUP_CHECK")" "$(onoff "$RECYCLE")" "$(fzf_label)" >&2
        read -r choice
        case "$choice" in
             1) choice="$ICON_SLIDERS  Package manager: $MGR" ;;
             2) choice="$ICON_THEME  Themes & terminal colors: $THEME" ;;
             3) choice="$ICON_PAINT  Icons: $ICONS" ;;
             4) choice="$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")" ;;
             5) choice="$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")" ;;
             6) choice="$ICON_FOLDER  Show config file" ;;
             7) choice="$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")" ;;
             8) choice="$ICON_LOCK  Safety lock: $(onoff "$LOCK")" ;;
             9) choice="$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")" ;;
             10) choice="$ICON_TRASH  Recycle bin (archive on remove): $(onoff "$RECYCLE")" ;;
             11) choice="$ICON_SEARCH  fzf picker: $(fzf_label)" ;;
             12) choice="$ICON_BACK  Back" ;;
             *) return ;;
        esac
    fi
    [ -n "$choice" ] || return
    case "$choice" in
        *"Package manager"*) set_mgr ;;
        *"Themes & terminal colors"*) do_theme ;;
        *"Icons"*)           if [ "$ICONS" = "nerd" ]; then ICONS="emoji"; else ICONS="nerd"; fi; init_icons; build_menu; save_config ;;
        *"Safety confirms"*) CONFIRM=$((1-CONFIRM)); save_config ;;
        *"History log"*)     LOG_ENABLED=$((1-LOG_ENABLED)); save_config ;;
        *"Show config"*)     cat "$HOME/.pkg-manager.conf" 2>/dev/null || say "No config yet." ;;
        *"Quiet mode"*)      QUIET=$((1-QUIET)); save_config ;;
        *"Safety lock"*)     LOCK=$((1-LOCK)); save_config ;;
        *"Maintenance on launch"*) STARTUP_CHECK=$((1-STARTUP_CHECK)); save_config ;;
        *"Recycle bin"*)          RECYCLE=$((1-RECYCLE)); save_config ;;
        # on/off toggle
        *"fzf picker"*)
            if [ "$FZF_ENABLED" != "1" ]; then
                FZF_ENABLED=1
            else
                FZF_ENABLED=0
            fi
            say "$ICON_SEARCH fzf: $(fzf_label)"
            save_config ;;
        *) return ;;
    esac
}

undo_last_remove() {
    local line rest
    line=$(grep -E '\] (remove |purge |bulk remove)' "$LOG_FILE" | tail -n1)
    [ -n "$line" ] || { say "No previous removal found in history."; return; }
    rest=$(printf '%s\n' "$line" | sed -E 's/^.*\] (remove |purge |bulk remove picked: |bulk remove: )//')
    rest=$(printf '%s\n' "$rest" | tr ' ' '\n' | filter_pkgs)
    [ -n "$rest" ] || { say "Nothing to undo."; return; }
    say "$ICON_UNDO Last removal was: $(printf '%s' "$rest" | tr '\n' ' ')"
    if confirm_danger "$ICON_UNDO Reinstall these packages to undo?"; then
        log "undo reinstall: $(printf '%s' "$rest" | tr '\n' ' ')"
        say "$ICON_UNDO Reinstalling..."
        local -a _pkgs=()
        mapfile -t _pkgs <<< "$rest"
        if run_multi_op install "${_pkgs[@]}"; then
            ok "Undo complete!"
        fi
    fi
}

# show_charts — ASCII bar charts built from the action log: actions per day
# (last 14 days, scaled to fit) and the most frequent action verbs.
show_charts() {
    if [ ! -f "$LOG_FILE" ]; then
        say "No history yet — run some actions first!"
        return
    fi
    local total fails
    total=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    fails=$(grep -c 'FAIL:' "$LOG_FILE" 2>/dev/null || true)
    say "$ICON_CHART  Charts & statistics — ${total:-0} logged actions, ${fails:-0} failures"
    say ""
    printf '  Actions per day (last 14 days, # = 1+):\n'
    grep -oE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}' "$LOG_FILE" 2>/dev/null | tr -d '[' | sort | uniq -c | tail -n 14 | awk '
        { if ($1 > max) max = $1; rows[NR] = $0; n = NR }
        END {
            if (n == 0) exit
            for (i = 1; i <= n; i++) {
                split(rows[i], a, " ")
                w = int(a[1] * 40 / max)
                if (w < 1) w = 1
                bar = ""
                for (j = 0; j < w; j++) bar = bar "#"
                printf "    %s  %5d  %s\n", a[2], a[1], bar
            }
        }'
    say ""
    printf '  Most frequent actions:\n'
    sed -E 's/^\[[^]]*\] //' "$LOG_FILE" 2>/dev/null | grep -v '^FAIL:' | awk '{print $1}' \
        | sort | uniq -c | sort -rn | head -n 8 | awk '{printf "    %5d  %s\n", $1, $2}'
    if [ "$fails" != "0" ] && [ -n "$fails" ]; then
        say ""
        printf '  Failures by action:\n'
        grep '^.*FAIL:' "$LOG_FILE" 2>/dev/null | sed -E 's/^\[[^]]*\] FAIL: //; s/:.*//' | awk '{print $1}' \
            | sort | uniq -c | sort -rn | head -n 8 | awk '{printf "    %5d  %s\n", $1, $2}'
    fi
}

do_history() {
    local a tmp
    if [ ! -f "$LOG_FILE" ]; then
        say "No history yet — run some actions first!"
        return
    fi
    a=$(pick_menu "$ICON_HISTORY  History & log viewer" "Show all history" "Show errors & failures" "Show installs / removals" "Charts & statistics" "Undo last removal" "Clear history" "Back")
    [ -n "$a" ] || return
    case "$a" in
        *"all history"*)
            local lines
            lines=$(grep -c . "$LOG_FILE" 2>/dev/null) || lines=0
            say "$ICON_HISTORY Action history — $lines entr$( [ "$lines" = "1" ] && echo y || echo ies) ($LOG_FILE)"
            dim "  ────────────────────────────"
            grep -n . "$LOG_FILE" | tail -n 60 | while IFS= read -r _l; do print_safe "$_l"; printf '\n'; done
            ;;
        *errors*)
            say "$ICON_ERROR Errors & failures in the log:"
            local errs
            errs=$(grep -E 'FAIL:|failed|✗' "$LOG_FILE" || true)
            if [ -n "$errs" ]; then
                printf '%s\n' "$errs"
            else
                ok "No errors in the log."
            fi
            ;;
        *installs*)
            say "$ICON_PLAY  Install / remove actions:"
            grep -E '\] (install|remove|purge|reinstall|upgrade|bulk|favorite|autoremove)' "$LOG_FILE" || say "None yet."
            ;;
        *Charts*)
            show_charts
            ;;
        *Undo*)
            undo_last_remove
            ;;
        *Clear*)
            if confirm_danger "$ICON_ERROR  Clear the entire history log?"; then
                refuse_symlink "$LOG_FILE" || return
                : > "$LOG_FILE"
                ok "History cleared."
            fi
            ;;
        *) return ;;
    esac
}

do_inspect() {
    ask_name "Package name to inspect"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "inspect $PKG_NAME"
    local tmp
    if ! tmp=$(scratch_new); then
        err "Could not create a temp file for the inspection."
        return
    fi
    {
        printf '%s\n' "$ICON_INSPECT  Inspecting $PKG_NAME:"
        printf '═══ Info ═══\n'
        "$MGR" show "$PKG_NAME" 2>/dev/null | grep -E '^(Package|Version|Architecture|Size|Installed-Size|Depends|Homepage|Maintainer|Description):' | grep -v '^WARNING:'
        printf '\n═══ Dependencies ═══\n'
        apt-cache depends "$PKG_NAME" 2>/dev/null | grep -E '^  (Depends|PreDepends|Recommends|Suggests):' | sed 's/^  //' || echo "(none)"
        printf '\n═══ Reverse dependencies ═══\n'
        apt rdepends "$PKG_NAME" 2>/dev/null | grep -v '^WARNING:' || echo "(none)"
        printf '\n═══ Installed files ═══\n'
        if out=$(dpkg -L "$PKG_NAME" 2>/dev/null); then
            printf '%s\n' "$out"
        else
            echo "(not installed — no file list)"
        fi
        printf '\n═══ Hold status ═══\n'
        if heldlist=$(apt-mark showhold 2>/dev/null); then
            if grep -Fxq -- "$PKG_NAME" <<< "$heldlist"; then
                echo "$PKG_NAME is held."
            else
                echo "$PKG_NAME is not held."
            fi
        else
            echo "$PKG_NAME — hold status unknown (apt-mark failed)"
        fi
    } > "$tmp"
    cat "$tmp"
    rm -f "$tmp"
}

do_maintenance() {
    log "maintenance wizard"
    say "$ICON_MAINT  Maintenance wizard — checking your system..."
    local up orphans n broken cache held issues=0
    if confirm "$ICON_UPDATE  Refresh package lists (apt update) first?"; then
        local hint
        if output=$("$MGR" update 2>&1); then
            log "maintenance update"
            hint=$(apt_hint "$output")
            [ -n "$hint" ] && ok "$hint"
            printf '%s\n' "$output" | tail -n 3
        else
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 3
            err "${hint:-apt update failed.}"
            log_err "maintenance update: ${hint:-failed}"
        fi
    fi
    if ! up=$(list_upgradable); then
        err "Could not read the upgradable list."
        issues=$((issues+1))
    elif [ -n "$up" ]; then
        n=$(grep -cv '^$' <<< "$up")
        warn "$ICON_UP  $n package(s) can be upgraded."
        issues=$((issues+1))
    else
        ok "All packages are up to date."
    fi
    local simout
    if simout=$(apt autoremove --simulate -y 2>&1); then
        orphans=$(printf '%s\n' "$simout" | awk '
            /will be REMOVED:/ {on=1; next}
            on && /upgraded|newly installed|not upgraded|after this operation/ {on=0}
            on { for (i=1;i<=NF;i++)
                    if ($i ~ /^[A-Za-z][A-Za-z0-9+.:~-]*$/ && $i !~ /^[0-9][0-9.:-]+$/) print $i }
        ')
        if [ -n "$orphans" ]; then
            n=$(printf '%s\n' "$orphans" | wc -l)
            warn "$ICON_AUTOREMOVE  $n orphaned package(s) found."
            issues=$((issues+1))
        else
            ok "No orphaned packages."
        fi
    else
        err "Could not check for orphaned packages."
        issues=$((issues+1))
    fi
    if broken=$(dpkg --audit 2>&1); then
        if [ -n "$broken" ]; then
            warn "$ICON_BUG Broken packages found:"
            printf '%s\n' "$broken"
            issues=$((issues+1))
        else
            ok "No broken packages."
        fi
    else
        if [ -n "$broken" ]; then
            warn "$ICON_BUG Broken packages found:"
            printf '%s\n' "$broken"
            issues=$((issues+1))
        else
            err "Could not audit packages for breakage."
            issues=$((issues+1))
        fi
    fi
    cache=$(du -sh "$PREFIX/var/cache/apt/archives" 2>/dev/null | cut -f1)
    if [ -n "$cache" ]; then
        say "Download cache: $cache"
    else
        say "Download cache: empty"
    fi
    if heldlist=$(apt-mark showhold 2>/dev/null); then
        held=$(grep -cv '^$' <<< "$heldlist")
        say "Held packages: $held"
    else
        err "Could not read held packages."
        issues=$((issues+1))
    fi
    if [ "$issues" -eq 0 ]; then
        ok "System looks healthy!"
        return
    fi
    warn "$issues issue(s) found."
    say "$ICON_WAND  Offer to fix them..."
    if confirm_danger "$ICON_FIXBROKEN  Run apt fix-broken now?"; then
        local hint
        if output=$(apt --fix-broken install -y 2>&1); then
            log "maintenance fix-broken"
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            [ -n "$hint" ] && ok "$hint"
        else
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            err "${hint:-apt fix-broken failed.}"
            log_err "fix-broken: ${hint:-failed}"
            issues=$((issues+1))
        fi
    fi
    if confirm_danger "$ICON_AUTOREMOVE  Remove orphaned packages now?"; then
        local hint
        if output=$(apt autoremove -y 2>&1); then
            log "maintenance autoremove"
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            [ -n "$hint" ] && ok "$hint"
        else
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            err "${hint:-apt autoremove failed.}"
            log_err "autoremove: ${hint:-failed}"
            issues=$((issues+1))
        fi
    fi
    if confirm_danger "$ICON_UP  Upgrade all packages now?"; then
        local hint
        if output=$("$MGR" upgrade -y 2>&1); then
            log "maintenance upgrade"
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            [ -n "$hint" ] && ok "$hint"
        else
            hint=$(apt_hint "$output")
            printf '%s\n' "$output" | tail -n 5
            err "${hint:-upgrade failed.}"
            log_err "upgrade all: ${hint:-failed}"
            issues=$((issues+1))
        fi
    fi
    if confirm "$ICON_CLEAN  Clean the download cache?"; then
        local out hint
        if out=$("$MGR" clean 2>&1); then
            log "maintenance clean cache"
            hint=$(apt_hint "$out")
            ok "${hint:-Cache cleaned.}"
        else
            hint=$(apt_hint "$out")
            err "${hint:-Failed to clean cache.}"
            log_err "clean cache: ${hint:-failed}"
            printf '%s\n' "$out" | tail -n 4
        fi
    fi
}

declare -A PKG_GROUPS
load_groups() {
    PKG_GROUPS=(
        ["web dev"]="nodejs npm nginx"
        ["python dev"]="python python-pip python-pipx"
        ["media tools"]="ffmpeg imagemagick"
        ["git tools"]="git git-lfs"
        ["network tools"]="curl wget openssh nmap"
    )
    if [ -f "$GROUPS_FILE" ]; then
        local line name pkgs pkgs_clean
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "$line" ] || continue
            case "$line" in
                *::*) name="${line%%::*}" pkgs="${line#*::}" ;;
                *) continue ;;   # malformed line: no "::" delimiter
            esac
            [ -n "$name" ] || continue
            case "$name" in
                *[!-[:space:]A-Za-z0-9_]*) continue ;;   # name must match create-time sanitization
            esac
            pkgs_clean=$(printf '%s\n' "$pkgs" | tr ' ' '\n' | filter_pkgs | tr '\n' ' ')
            [ -n "$pkgs_clean" ] || continue
            PKG_GROUPS["$name"]="$pkgs_clean"
        done < "$GROUPS_FILE"
    fi
}
load_groups

group_names() {
    local n
    for n in "${!PKG_GROUPS[@]}"; do
        printf '%s\n' "$n"
    done | sort
}

do_groups() {
    local a gname gpkgs line n
    a=$(pick_menu "$ICON_GROUPS  Package groups" "Show all groups" "Install a group" "Remove a group's packages" "Create custom group" "Delete custom group" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Show*)
            say "$ICON_GROUPS  Package groups:"
            if [ "${#PKG_GROUPS[@]}" -eq 0 ]; then
                say "No groups defined."
                return
            fi
            while IFS= read -r n; do
                [ -n "$n" ] || continue
                printf '  %s  %s (%s packages)\n' "$ICON_GROUPS" "$n" "$(wc -w <<< "${PKG_GROUPS[$n]}")"
            done < <(group_names)
            ;;
        Install*)
            gname=$(pick_group "Pick a group to install")
            [ -n "$gname" ] || { say "Canceled."; return; }
            gpkgs=${PKG_GROUPS[$gname]}
            n=$(wc -w <<< "$gpkgs")
            if confirm_danger "$ICON_INSTALL Install group \"$gname\" ($n packages)?"; then
                log "group install $gname: $gpkgs"
                say "$ICON_INSTALL Installing group \"$gname\"..."
                local -a _pkgs=()
                read -ra _pkgs <<< "$gpkgs"
                run_multi_op install "${_pkgs[@]}"
            fi
            ;;
        Remove*)
            gname=$(pick_group "Pick a group to remove")
            [ -n "$gname" ] || { say "Canceled."; return; }
            gpkgs=${PKG_GROUPS[$gname]}
            n=$(wc -w <<< "$gpkgs")
            if confirm_danger "$ICON_UNINSTALL Remove group \"$gname\" ($n packages)?"; then
                log "group remove $gname: $gpkgs"
                say "$ICON_UNINSTALL Removing group \"$gname\"..."
                local -a _pkgs=()
                read -ra _pkgs <<< "$gpkgs"
                run_multi_op remove "${_pkgs[@]}"
            fi
            ;;
        Create*)
            ask_name "Group name" any
            [ -n "$PKG_NAME" ] || { warn "No name given."; return; }
            gname=$(printf '%s' "$PKG_NAME" | tr -c 'A-Za-z0-9 _-' '_')
            ask_name "Packages (space-separated)" any
            gpkgs=$(printf '%s\n' "$PKG_NAME" | tr ' ' '\n' | filter_pkgs)
            [ -n "$gpkgs" ] || { warn "No valid package names."; return; }
            if [ -f "$GROUPS_FILE" ] && awk -F:: -v g="$gname" '$1==g{found=1; exit} END{exit !found}' "$GROUPS_FILE"; then
                warn "A group named \"$gname\" already exists."
                return
            fi
            if tmp=$(scratch_new); then
                if [ -f "$GROUPS_FILE" ] && ! cp "$GROUPS_FILE" "$tmp"; then
                    err "Could not read groups — leaving them unchanged."
                    rm -f "$tmp"; return
                fi
                if printf '%s::%s\n' "$gname" "$(printf '%s' "$gpkgs" | tr '\n' ' ')" >> "$tmp" && mv -f "$tmp" "$GROUPS_FILE"; then
                    load_groups; log "group create $gname"; ok "Group \"$gname\" created."
                else
                    err "Failed to create group"; rm -f "$tmp"
                fi
            else
                err "Could not create temp file for groups."
            fi
            ;;
        Delete*)
            if [ ! -s "$GROUPS_FILE" ]; then
                warn "No custom groups to delete."
                return
            fi
            mapfile -t custom_names < <(sed 's/::.*//' "$GROUPS_FILE" | grep -E '^[A-Za-z0-9 _-]+$')
            if have_fzf; then
                gname=$(printf '%s\n' "${custom_names[@]}" | pick_one "$ICON_TRASH  Pick custom group to delete")
            else
                printf 'Custom groups:\n' >&2
                nl -w2 -s') ' "$GROUPS_FILE" | sed 's/::/ /' >&2
                printf '❯ Pick number (0 = cancel): ' >&2
                read -r a
                case "$a" in
                    [1-9]|[1-9][0-9]) gname=$(sed -n "${a}p" "$GROUPS_FILE" | sed 's/::.*//') ;;
                    *) return ;;
                esac
            fi
            [ -n "$gname" ] || return
            case "$gname" in
                *[!-[:space:]A-Za-z0-9_]*) err "Invalid group name."; return ;;
            esac
            if confirm_danger "$ICON_TRASH  Delete custom group \"$gname\"?"; then
                if tmp=$(scratch_new); then
                    if ! awk -F:: -v g="$gname" '$1 != g' "$GROUPS_FILE" > "$tmp"; then
                        err "Could not read groups — leaving them unchanged."
                        rm -f "$tmp"; return
                    fi
                    if mv -f "$tmp" "$GROUPS_FILE"; then
                        load_groups
                        log "group delete $gname"
                        ok "Group \"$gname\" deleted."
                    else
                        err "Failed to update groups file."
                    fi
                fi
            fi
            ;;
        *) return ;;
    esac
}

pick_group() {
    local header="$1" a gnames
    mapfile -t gnames < <(group_names)
    if have_fzf; then
        printf '%s\n' "${gnames[@]}" | pick_one "$header"
    else
        printf 'Groups:\n' >&2
        local n
        mapfile -t _gnames < <(group_names)
        list_numbered 0 "${_gnames[@]}"
        printf '❯ Pick number (0 = cancel): ' >&2
        read -r a
        case "$a" in
            [1-9]|[1-9][0-9]) group_names | sed -n "${a}p" ;;
            *) return ;;
        esac
    fi
}

do_localdeb() {
    local file
    file=$(pick_file "Select .deb file")
    case "$file" in -* ) err "Invalid path — must not start with '-'."; return ;; esac
    [ -n "$file" ] && [ -f "$file" ] || { warn "No file selected."; return; }
    case "$file" in *.deb) ;; *) warn "Not a .deb file: $file"; return ;; esac
    if ! confirm_danger "$ICON_FILES Install local package $file?"; then say "Canceled."; return; fi
    log "localdeb $file"
    say "$ICON_FILES Installing $file..."
    local out hint
    if out=$(dpkg -i -- "$file" 2>&1); then
        ok "Installed $file"
    else
        hint=$(apt_hint "$out")
        warn "${hint:-dpkg failed, trying to fix deps...}"
        printf '%s\n' "$out" | tail -n 4
        if out=$(apt --fix-broken install -y 2>&1); then
            ok "Dependencies fixed and $file installed!"
        else
            hint=$(apt_hint "$out")
            err "${hint:-Fix-broken failed for $file}"
            log_err "localdeb $file: ${hint:-fix-broken failed}"
            printf '%s\n' "$out" | tail -n 4
            return 1
        fi
    fi
}

do_downgrade() {
    ask_name "Package to downgrade"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "downgrade $PKG_NAME"
    say "$ICON_REINSTALL Available versions for $PKG_NAME:"
    local vers out
    vers=$(apt-cache madison "$PKG_NAME" 2>/dev/null | awk '{print $3}' | head -20)
    if [ -z "$vers" ]; then vers=$(apt-cache policy "$PKG_NAME" 2>/dev/null | sed -nE 's/^[[:space:]]*(\*\*\*[[:space:]]+)?([A-Za-z0-9._+~:-]*[A-Za-z0-9._+~-])[[:space:]]+[0-9]+[[:space:]]*$/\2/p' | head -20); fi
    if [ -z "$vers" ]; then err "No versions found — check name or run Upgrade center."; return; fi
    printf '%s\n' "$vers"
    local picked
    if have_fzf; then
        picked=$(printf '%s\n' "$vers" | pick_one "Pick version to downgrade to")
    else
        if ! tmp=$(scratch_new); then warn "Could not create temp file."; return; fi
        printf '%s\n' "$vers" > "$tmp"
        nl -w2 -s') ' "$tmp" >&2
        printf '❯ Pick number (0 = cancel): ' >&2
        read -r picked
        case "$picked" in [1-9]|[1-9][0-9]) picked=$(sed -n "${picked}p" "$tmp") ;; *) rm -f "$tmp"; return ;; esac
        rm -f "$tmp"
    fi
    [ -n "$picked" ] || { say "Canceled."; return; }
    case "$picked" in -* ) err "Invalid version."; return ;; esac
    if ! printf '%s\n' "$vers" | grep -Fxq -- "$picked"; then err "Invalid version selection."; return; fi
    if ! printf '%s\n' "$picked" | grep -qE '^[A-Za-z0-9._+~:-]+$'; then err "Invalid version format."; return; fi
    if ! confirm_danger "$ICON_REINSTALL Downgrade $PKG_NAME to $picked?"; then say "Canceled."; return; fi
    say "$ICON_REINSTALL Downgrading $PKG_NAME=$picked..."
    if out=$("$MGR" install -y "$PKG_NAME=$picked" 2>&1); then
        hint=$(apt_hint "$out")
        ok "${hint:-$PKG_NAME downgraded to $picked!}"
    else
        hint=$(apt_hint "$out")
        err "${hint:-Failed to downgrade $PKG_NAME}"
        log_err "downgrade $PKG_NAME=$picked: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_dlonly() {
    ask_name "Package to download (no install)"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm "$ICON_CACHE Download $PKG_NAME without installing?"; then say "Canceled."; return; fi
    say "$ICON_CACHE Downloading $PKG_NAME..."
    local out hint dir sz
    dir="$PREFIX/var/cache/apt/archives"
    if out=$(apt download -- "$PKG_NAME" 2>&1); then
        log "download $PKG_NAME"
        ok "Downloaded $PKG_NAME to $(pwd)"
        # shellcheck disable=SC2012
        ls -lh ./*.deb 2>/dev/null | tail -5 || { sz=$(du -sh "$dir" 2>/dev/null | cut -f1); [ -n "$sz" ] && say "Cache now: $sz"; }
    elif out=$("$MGR" install --download-only -y "$PKG_NAME" 2>&1); then
        log "download $PKG_NAME"
        ok "Downloaded $PKG_NAME to cache $dir"
        # shellcheck disable=SC2012
        ls -lh "$dir"/*.deb 2>/dev/null | tail -5 || true
    else
        hint=$(apt_hint "$out")
        err "${hint:-Failed to download $PKG_NAME}"
        log_err "download $PKG_NAME: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_holdver() {
    local a
    a=$(pick_menu "$ICON_HOLD  Hold specific version" "Hold current version" "Hold to chosen version" "Show held packages" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Hold*current*)
            ask_name "Package to hold at current version"
            [ -n "$PKG_NAME" ] || return
            local out hint
            if out=$(apt-mark hold "$PKG_NAME" 2>&1); then
                log "holdver $PKG_NAME current"
                hint=$(apt_hint "$out")
                ok "${hint:-$PKG_NAME held at current version}"
            else
                hint=$(apt_hint "$out")
                err "${hint:-Failed to hold $PKG_NAME}"
                log_err "holdver $PKG_NAME current: ${hint:-failed}"
                printf '%s\n' "$out" | tail -n 4
            fi
            ;;
        Hold*chosen*)
            ask_name "Package to hold at specific version"
            [ -n "$PKG_NAME" ] || return
            local vers picked out hint
            vers=$(apt-cache madison "$PKG_NAME" 2>/dev/null | awk '{print $3}' | head -20)
            [ -n "$vers" ] || { err "No versions found."; return; }
            if have_fzf; then
                picked=$(printf '%s\n' "$vers" | pick_one "Pick version to hold")
            else
                printf '%s\n' "$vers" >&2; printf '❯ Version: ' >&2; read -r picked
            fi
            [ -n "$picked" ] || return
            case "$picked" in -* ) err "Invalid version."; return ;; esac
            if ! printf '%s\n' "$vers" | grep -Fxq -- "$picked"; then err "Invalid version selection."; return; fi
            if ! printf '%s\n' "$picked" | grep -qE '^[A-Za-z0-9._+~:-]+$'; then err "Invalid version format."; return; fi
            say "Installing $PKG_NAME=$picked then holding..."
            if out=$("$MGR" install -y "$PKG_NAME=$picked" 2>&1) && apt-mark hold "$PKG_NAME" 2>/dev/null; then log "holdver $PKG_NAME=$picked"; ok "$PKG_NAME held at $picked"; else err "Failed to hold $PKG_NAME at $picked"; log_err "holdver $PKG_NAME=$picked failed"; fi
            ;;
        Show*)
            say "$ICON_HOLD Held packages (with versions):"
            local held
            held=$(apt-mark showhold 2>/dev/null)
            if [ -n "$held" ]; then
                while IFS= read -r p; do
                    [ -n "$p" ] || continue
                    ver=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || echo "?")
                    printf '  %s  %s\n' "$p" "$ver"
                done <<< "$held"
            else
                say "None"
            fi
            ;;
    esac
}

do_filesearch() {
    local pat
    printf '❯ File pattern to search (e.g. bin/python): ' >&2
    read -r pat
    pat=$(printf '%s\n' "$pat" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$pat" ] || { warn "No pattern given."; return; }
    case "$pat" in -* ) err "Invalid pattern."; return ;; esac
    log "filesearch $pat"
    say "$ICON_SEARCH Searching for file: $pat"
    local out
    if command -v apt-file >/dev/null 2>&1; then
        out=$(apt-file search -- "$pat" 2>/dev/null | head -40)
        if [ -n "$out" ]; then printf '%s\n' "$out"; else say "No match via apt-file."; fi
    elif command -v pkgfile >/dev/null 2>&1; then
        out=$(pkgfile -- "$pat" 2>/dev/null | head -40)
        if [ -n "$out" ]; then printf '%s\n' "$out"; else say "No match via pkgfile."; fi
    else
        say "apt-file/pkgfile not installed — searching installed files (dpkg -S):"
        out=$(dpkg -S -- "$pat" 2>/dev/null | head -40)
        if [ -n "$out" ]; then printf '%s\n' "$out"; else err "No installed package owns '$pat' (install apt-file for pre-install search)"; fi
    fi
}

do_changelog() {
    ask_name "Package for changelog"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "changelog $PKG_NAME"
    say "$ICON_HISTORY Changelog for $PKG_NAME:"
    local out
    if out=$(apt changelog "$PKG_NAME" 2>&1) && [ -n "$out" ]; then
        printf '%s\n' "$out" | sed -n '1,80p'
    elif out=$(apt-get changelog "$PKG_NAME" 2>&1) && [ -n "$out" ]; then
        printf '%s\n' "$out" | sed -n '1,80p' 
    else
        out=$("$MGR" show "$PKG_NAME" 2>/dev/null | grep -v '^WARNING:')
        if [ -n "$out" ]; then
            printf '%s\n' "$out" | head -40
            say "— no changelog available, showing package info"
        else
            err "Package not found"
        fi
    fi
}

do_why() {
    ask_name "Package to explain"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "why $PKG_NAME"
    say "$ICON_DEPENDS Why is $PKG_NAME installed?"
    local manual auto
    if apt-mark showmanual 2>/dev/null | grep -Fxq "$PKG_NAME"; then manual=1; else manual=0; fi
    if apt-mark showauto 2>/dev/null | grep -Fxq "$PKG_NAME"; then auto=1; else auto=0; fi
    if [ "$manual" = "1" ]; then ok "$PKG_NAME was manually installed"; elif [ "$auto" = "1" ]; then warn "$PKG_NAME was auto-installed as dependency"; else say "Install status unknown (not in manual/auto lists)"; fi
    say "Reverse dependencies (who needs it):"
    local out
    out=$(apt rdepends "$PKG_NAME" 2>/dev/null | grep -v '^WARNING:' | head -30)
    if [ -n "$out" ]; then printf '%s\n' "$out"; else say "(none or package not found)"; fi
    if dpkg -s "$PKG_NAME" >/dev/null 2>&1; then
        out=$(apt-cache rdepends --installed "$PKG_NAME" 2>/dev/null | head -20)
        if [ -n "$out" ]; then say "Installed reverse deps:"; printf '%s\n' "$out"; fi
    fi
}

do_notes() {
    local NOTES_FILE="$HOME/.pkg-manager-notes"
    local a
    a=$(pick_menu "$ICON_MEMO  User notes" "Add note" "Remove note" "Show all notes" "Search notes" "Show note for package" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Add*)
            ask_name "Package to annotate"
            [ -n "$PKG_NAME" ] || return
            local note
            printf '❯ Note for %s: ' "$PKG_NAME" >&2; read -r note
            note=$(printf '%s\n' "$note" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/::/--/g')
            [ -n "$note" ] || { warn "No note given."; return; }
            if [ -f "$NOTES_FILE" ] && awk -F:: -v pkg="$PKG_NAME" '$1==pkg{found=1; exit} END{exit !found}' "$NOTES_FILE"; then
                if tmp=$(scratch_new); then
                    if ! awk -F:: -v pkg="$PKG_NAME" '$1!=pkg' "$NOTES_FILE" > "$tmp"; then
                        err "Could not read notes — leaving them unchanged."
                        rm -f "$tmp"; return
                    fi
                    if printf '%s::%s\n' "$PKG_NAME" "$note" >> "$tmp" && mv -f "$tmp" "$NOTES_FILE"; then
                        ok "Note updated for $PKG_NAME"; log "note add $PKG_NAME"
                    else
                        err "Could not save notes."; rm -f "$tmp"
                    fi
                else err "Could not create temp file for notes."; fi
            else
                if tmp=$(scratch_new); then
                    if [ -f "$NOTES_FILE" ] && ! cp "$NOTES_FILE" "$tmp"; then
                        err "Could not read notes — leaving them unchanged."
                        rm -f "$tmp"; return
                    fi
                    if printf '%s::%s\n' "$PKG_NAME" "$note" >> "$tmp" && mv -f "$tmp" "$NOTES_FILE"; then
                        ok "Note added for $PKG_NAME"; log "note add $PKG_NAME"
                    else
                        err "Could not save notes."; rm -f "$tmp"
                    fi
                else
                    err "Could not create temp file for notes."
                fi
            fi
            ;;
        Remove*)
            [ -s "$NOTES_FILE" ] || { warn "No notes yet."; return; }
            ask_name "Package to remove note"
            [ -n "$PKG_NAME" ] || return
            if awk -F:: -v pkg="$PKG_NAME" '$1==pkg{found=1; exit} END{exit !found}' "$NOTES_FILE"; then
                if tmp=$(scratch_new); then
                    if ! awk -F:: -v pkg="$PKG_NAME" '$1!=pkg' "$NOTES_FILE" > "$tmp"; then
                        err "Could not read notes — leaving them unchanged."
                        rm -f "$tmp"; return
                    fi
                    if mv -f "$tmp" "$NOTES_FILE"; then ok "Note removed for $PKG_NAME"; log "note remove $PKG_NAME"; else err "Could not save notes."; fi
                fi
            else
                warn "No note for $PKG_NAME"
            fi
            ;;
        Show*all*)
            if [ ! -s "$NOTES_FILE" ]; then say "No notes yet."; return; fi
            say "$ICON_MEMO User notes:"
            cat "$NOTES_FILE"
            ;;
        Search*)
            [ -s "$NOTES_FILE" ] || { warn "No notes yet."; return; }
            local q
            printf '❯ Search: ' >&2; read -r q
            [ -n "$q" ] || return
            grep -iF -- "$q" "$NOTES_FILE" || say "No matches."
            ;;
        Show*package*)
            ask_name "Package to show note"
            [ -n "$PKG_NAME" ] || return
            if [ -f "$NOTES_FILE" ]; then
                if ! awk -F:: -v pkg="$PKG_NAME" '$1==pkg{found=1; print substr($0, index($0,"::")+2); exit} END{exit !found}' "$NOTES_FILE"; then say "No note for $PKG_NAME"; fi
            else
                say "No notes yet."
            fi
            ;;
    esac
}

do_snapshot() {
    local a
    a=$(pick_menu "$ICON_BACKUP  Full snapshot" "Create snapshot" "List snapshots" "Diff snapshots" "Restore snapshot" "Delete snapshot" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Create*)
            local file tmp stage
            file="$HOME/pkg-snapshot-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
            say "$ICON_BACKUP Creating snapshot $file..."
            if ! tmp=$(scratch_new); then err "No temp file."; return; fi
            if ! list_installed_names > "$tmp" 2>/dev/null; then
                err "Could not read the installed list — snapshot aborted."
                rm -f "$tmp"; return
            fi
            if [ ! -s "$tmp" ]; then err "No packages to snapshot."; rm -f "$tmp"; return; fi
            stage=$(mktemp -d "$HOME/.pkg-snapshot.XXXXXX" 2>/dev/null) || { err "No stage dir"; rm -f "$tmp"; return; }
            _SCRATCH+=("$stage")
            mv -f "$tmp" "$stage/pkg-list.txt"
            [ -f "$FAVS_FILE" ] && cp "$FAVS_FILE" "$stage/" 2>/dev/null || true
            [ -f "$GROUPS_FILE" ] && cp "$GROUPS_FILE" "$stage/" 2>/dev/null || true
            [ -f "$HOME/.pkg-manager.conf" ] && cp "$HOME/.pkg-manager.conf" "$stage/" 2>/dev/null || true
            [ -f "$HOME/.pkg-manager-notes" ] && cp "$HOME/.pkg-manager-notes" "$stage/" 2>/dev/null || true
            if tar -czf "$file" -C "$stage" . 2>/dev/null && [ -f "$file" ]; then
                log "snapshot create $file"
                ok "Snapshot created: $file"
                ls -lh "$file" 2>/dev/null || true
            else
                err "Snapshot failed"
                rm -f "$file"
            fi
            rm -rf "$stage" 2>/dev/null
            _SCRATCH=("${_SCRATCH[@]/$stage/}")
            ;;
        List*)
            say "$ICON_BACKUP Snapshots in $HOME:"
            # shellcheck disable=SC2012
            if ! ls -lh "$HOME"/pkg-snapshot-* 2>/dev/null; then
                if compgen -G "$HOME/pkg-snapshot-*.tar.gz" >/dev/null 2>&1; then
                    ls -lh "$HOME"/pkg-snapshot-*.tar.gz 2>/dev/null || true
                else
                    say "No snapshots yet."
                fi
            fi
            ;;
        Diff*)
            local -a snap_files=()
            local f
            for f in "$HOME"/pkg-snapshot-*.tar.gz; do
                [ -f "$f" ] && snap_files+=("$f")
            done
            [ "${#snap_files[@]}" -ge 1 ] || { warn "No snapshots."; return; }
            if have_fzf; then
                picked=$(printf '%s\n' "${snap_files[@]}" | pick_multi "Pick 2 snapshots to diff")
                # fzf path now actually diffs (was dead code — picked was discarded)
                mapfile -t _sel < <(printf '%s\n' "$picked" | awk 'NF')
                if [ "${#_sel[@]}" -ge 2 ]; then
                    diff -u <(tar -tzf "${_sel[0]}" 2>/dev/null | sort) <(tar -tzf "${_sel[1]}" 2>/dev/null | sort) | awk 'NR<=60' || true
                else
                    say "Need 2 snapshots to diff."
                fi
            else
                printf 'Snapshots:\n' >&2
                list_numbered 0 "${snap_files[@]}"
                printf '❯ Pick 2 (space-separated numbers): ' >&2
                read -r picked
                picked=$(printf '%s\n' "$picked" | tr ' ' '\n' | while read -r n; do
                    # reject non-numeric n before arithmetic ever sees it
                    case "$n" in [0-9]|[0-9][0-9]) printf '%s\n' "${snap_files[$((n-1))]}" ;; esac
                done | tr '\n' ' ')
                mapfile -t _sel < <(printf '%s\n' "$picked" | tr ' ' '\n' | awk 'NF')
                [ ${#_sel[@]} -ge 2 ] || { say "Need 2 snapshots."; return; }
                diff -u <(tar -tzf "${_sel[0]}" 2>/dev/null | sort) <(tar -tzf "${_sel[1]}" 2>/dev/null | sort) | awk 'NR<=60' || true
            fi
            ;;
        Restore*)
            local file
            file=$(pick_file "Select snapshot")
            case "$file" in -* ) err "Invalid path."; return ;; esac
            [ -n "$file" ] && [ -f "$file" ] || { warn "No file."; return; }
            if ! confirm_danger "$ICON_RESTORE Restore from $file? This may overwrite pkg-list.txt, favs, groups, config and notes."; then say "Canceled."; return; fi
            log "snapshot restore $file"
            say "$ICON_RESTORE Restoring $file..."
            # capture the listing first, THEN scan — grep -q can exit before
            # tar finishes writing, and pipefail would flag tar's SIGPIPE as
            # a failure and make the guard a no-op
            local listfile
            listfile=$(mktemp "$HOME/.pkg-manager-restore.XXXXXX" 2>/dev/null) || { err "mktemp failed"; return; }
            if ! tar -tzf "$file" > "$listfile" 2>/dev/null; then
                rm -f "$listfile"
                err "Cannot read archive — aborting restore"
                return
            fi
            if grep -E '(^/|^\.\./|\.\./)' "$listfile" | head -1 >/dev/null; then
                rm -f "$listfile"
                err "Archive contains unsafe paths — aborting restore"
                return
            fi
            rm -f "$listfile"
            # NEVER extract straight into $HOME (symlink attack). Stage into
            # a scratch dir, gate every member against the allowlist, then
            # copy back file-by-file with backups.
            local stage_d
            stage_d=$(mktemp -d "$HOME/.pkg-restore.XXXXXX" 2>/dev/null) || { err "No restore dir"; return; }
            _SCRATCH+=("$stage_d")
            if ! tar -xzf "$file" -C "$stage_d" --no-same-owner --no-same-permissions 2>/dev/null; then
                err "Restore failed (tar could not unpack it)"
                rm -rf "$stage_d"
                _SCRATCH=("${_SCRATCH[@]/"$stage_d"/}")
                return
            fi
            # gate every extracted member
            local f base ok=1 bad=""
            while IFS= read -r -d '' f; do
                base=${f##*/}
                case "$base" in
                    pkg-list.txt|.pkg-manager-favs|.pkg-manager-groups|.pkg-manager.conf|.pkg-manager-notes) ;;
                    *) ok=0; bad="$base"; break ;;
                esac
                if [ ! -f "$f" ] || [ -L "$f" ]; then
                    ok=0; bad="$base (not a regular file)"; break
                fi
            done < <(find "$stage_d" -mindepth 1 -maxdepth 1 -print0)
            if [ "$ok" != "1" ]; then
                err "Archive contains an unexpected member: $bad — refusing to restore"
                rm -rf "$stage_d"
                _SCRATCH=("${_SCRATCH[@]/"$stage_d"/}")
                return
            fi
            # copy back one by one, backing up existing files first
            local bak_count=0
            local file_rel
            for f in "$stage_d"/* "$stage_d"/.[A-Za-z0-9]*; do
                [ -f "$f" ] || continue
                base=${f##*/}
                [ -f "$HOME/$base" ] && {
                    safe_cp "$HOME/$base" "$HOME/$base.pkg-manager.bak" 2>/dev/null && bak_count=$((bak_count+1))
                }
                safe_cp "$f" "$HOME/$base" || { err "Failed to write $HOME/$base"; continue; }
            done
            rm -rf "$stage_d"
            _SCRATCH=("${_SCRATCH[@]/"$stage_d"/}")
            [ "$bak_count" -gt 0 ] && dim "  Backed up $bak_count existing file(s) to *.pkg-manager.bak"
            ok "Snapshot restored to $HOME"

            ;;
        Delete*)
            local file
            file=$(pick_file "Select snapshot to delete")
            [ -n "$file" ] && [ -f "$file" ] || { warn "No file."; return; }
            if confirm_danger "$ICON_TRASH Delete $file?"; then
                if rm -f "$file"; then ok "Deleted $file"; log "snapshot delete $file"; else err "Failed to delete"; fi
            fi
            ;;
    esac
}

# archive_pkg — download the currently-installed (or newest available) version
# of "$1" into $TRASH_DIR so it can be reinstalled later from the .deb.
# Best-effort: a failed download must never block the actual removal.
archive_pkg() {
    local pkg="$1" ver stage deb moved=0
    valid_pkg_name "$pkg" || return 1
    if ! command -v apt >/dev/null 2>&1; then
        warn "apt not found — cannot archive $pkg."
        return 1
    fi
    ver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null | head -n1)
    say "$ICON_TRASH  Archiving $pkg to the recycle bin..."
    stage=$(mktemp -d "$HOME/.pkg-archive.XXXXXX" 2>/dev/null) || { warn "Could not create a temp dir for the archive."; return 1; }
    _SCRATCH+=("$stage")
    if [ -n "$ver" ] && (cd "$stage" && apt download -- "$pkg=$ver" >/dev/null 2>&1); then
        :
    elif ! (cd "$stage" && apt download -- "$pkg" >/dev/null 2>&1); then
        rm -rf "$stage"
        warn "Could not download $pkg for the recycle bin (no longer in the repos?)."
        return 1
    fi
    if ! mkdir -p "$TRASH_DIR" 2>/dev/null; then
        rm -rf "$stage"
        warn "Could not create $TRASH_DIR."
        return 1
    fi
    for deb in "$stage"/*.deb; do
        [ -e "$deb" ] || continue
        if mv -f -- "$deb" "$TRASH_DIR/"; then moved=1; fi
    done
    rm -rf "$stage"
    _SCRATCH=("${_SCRATCH[@]/$stage/}")
    if [ "$moved" = "1" ]; then
        log "recycle archive $pkg"
        ok "$pkg archived to the recycle bin ($TRASH_DIR)."
        return 0
    fi
    warn "No .deb was produced for $pkg — nothing archived."
    return 1
}

# install_deb — install one local .deb file (recycle bin restore path),
# fixing dependencies first the same way the Local .deb option does.
install_deb() {
    local file="$1" out hint
    [ -f "$file" ] || { err "File not found: $file"; return 1; }
    say "$ICON_TRASH Restoring $file..."
    if out=$(dpkg -i -- "$file" 2>&1); then
        log "recycle restore $file"
        ok "Restored $(basename -- "$file")"
        return 0
    fi
    hint=$(apt_hint "$out")
    warn "${hint:-dpkg failed, trying to fix deps...}"
    printf '%s\n' "$out" | tail -n 4
    if out=$(apt --fix-broken install -y 2>&1); then
        log "recycle restore $file (fixed deps)"
        ok "Restored $(basename -- "$file") with dependency fixes."
        return 0
    fi
    hint=$(apt_hint "$out")
    err "${hint:-Restore failed for $file}"
    log_err "recycle restore $file: ${hint:-fix-broken failed}"
    printf '%s\n' "$out" | tail -n 4
    return 1
}

do_recycle() {
    local a debs n
    if [ ! -d "$TRASH_DIR" ] || ! compgen -G "$TRASH_DIR/*.deb" >/dev/null 2>&1; then
        say "The recycle bin is empty ($TRASH_DIR)."
        say "Turn on Settings -> Recycle bin, and removals will keep a copy of each .deb here."
        return
    fi
    a=$(pick_menu "$ICON_TRASH  Recycle bin" "Restore a package" "Restore everything" "Show recycle bin" "Empty recycle bin" "Back")
    [ -n "$a" ] || return
    case "$a" in
        Restore\ a*)
            mapfile -t debs < <(for _d in "$TRASH_DIR"/*.deb; do [ -e "$_d" ] && basename -- "$_d"; done 2>/dev/null)
            say "$ICON_TRASH Pick a .deb to restore:"
            if have_fzf; then
                a=$(printf '%s\n' "${debs[@]}" | pick_one "$ICON_TRASH  Restore which package?")
            else
                printf 'Archived .deb files:\n' >&2
                printf '%s\n' "${debs[@]}" >&2
                printf 'Pick file (name or full path): ' >&2
                read -r a
            fi
            [ -n "$a" ] || { say "Canceled."; return; }
            local picked="$TRASH_DIR/$a"
            case "$a" in /*) picked="$a" ;; esac
            case "$picked" in /*.deb) ;; *) err "Pick a .deb from the recycle bin."; return ;; esac
            if confirm_danger "$ICON_TRASH Reinstall from $picked?"; then
                install_deb "$picked"
            else
                say "Canceled."
            fi
            ;;
        Restore\ everything*)
            if confirm_danger "$ICON_TRASH Reinstall every .deb in the recycle bin?"; then
                local f fail=0
                for f in "$TRASH_DIR"/*.deb; do
                    [ -e "$f" ] || continue
                    install_deb "$f" || fail=$((fail+1))
                done
                if [ "$fail" -eq 0 ]; then
                    ok "Recycle bin fully restored!"
                else
                    warn "$fail file(s) failed to restore."
                fi
            else
                say "Canceled."
            fi
            ;;
        Show*)
            say "$ICON_TRASH Recycle bin contents ($TRASH_DIR):"
            ls -lh "$TRASH_DIR"/*.deb 2>/dev/null || say "(empty)"
            ;;
        Empty*)
            if confirm_danger "$ICON_TRASH  Delete every .deb in the recycle bin?"; then
                rm -f "$TRASH_DIR"/*.deb
                log "recycle empty"
                ok "Recycle bin emptied."
            else
                say "Canceled."
            fi
            ;;
        *) return ;;
    esac
}

do_mark() {
    local mode="$1" out hint
    ask_name "Package to mark as $mode"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    say "$ICON_CHECKBOX Marking $PKG_NAME as $mode..."
    if out=$(apt-mark "$mode" "$PKG_NAME" 2>&1); then
        log "mark $mode $PKG_NAME"
        hint=$(apt_hint "$out")
        ok "${hint:-$PKG_NAME marked as $mode.}"
    else
        hint=$(apt_hint "$out")
        err "${hint:-Could not mark $PKG_NAME as $mode.}"
        log_err "mark $mode $PKG_NAME: ${hint:-failed}"
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_marks() {
    local a expr out
    local marks_items=(
        "Mark package as manually installed"
        "Mark package as automatically installed"
        "Show manually installed packages"
        "Show automatically installed packages"
        "Find what provides a virtual package"
        "Back")
    if have_fzf; then
        a=$(pick_menu "$ICON_CHECKBOX  Mark manual / auto" "${marks_items[@]}")
    else
        printf '1) Mark package as manually installed\n2) Mark package as automatically installed\n3) Show manually installed packages\n4) Show automatically installed packages\n5) Find what provides a virtual package\n6) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Mark package as manually installed" ;;
            2) a="Mark package as automatically installed" ;;
            3) a="Show manually installed packages" ;;
            4) a="Show automatically installed packages" ;;
            5) a="Find what provides a virtual package" ;;
            6) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        "Mark package as manually"*)      do_mark manual ;;
        "Mark package as automatically"*) do_mark auto ;;
        "Show manually"*)
            log "mark showmanual"
            say "$ICON_CHECKBOX Manually installed packages (first 50):"
            if out=$(apt-mark showmanual 2>/dev/null); then
                [ -n "$out" ] && printf '%s\n' "$out" | awk 'NR<=50' || say "(none)"
            else
                err "Could not read the manual list (apt-mark failed)."
            fi
            ;;
        "Show automatically"*)
            log "mark showauto"
            say "$ICON_CHECKBOX Automatically installed packages (first 50):"
            if out=$(apt-mark showauto 2>/dev/null); then
                [ -n "$out" ] && printf '%s\n' "$out" | awk 'NR<=50' || say "(none)"
            else
                err "Could not read the auto list (apt-mark failed)."
            fi
            ;;
        "Find what provides"*)
            printf 'Virtual package to look up (e.g. awk, mail-transport-agent): ' >&2
            read -r expr
            expr=$(printf '%s\n' "$expr" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -n "$expr" ] || { warn "Nothing to look up."; return; }
            case "$expr" in -* ) err "Expression must not start with '-'."; return ;; esac
            log "satisfies: $expr"
            # apt-cache pkgnames has no provides-query on Termux; search names+descriptions
            say "$ICON_DEPENDS Packages matching/providing \"$expr\":"
            if out=$(apt-cache search -- "$expr" 2>/dev/null | awk 'NF' | head -n 30) && [ -n "$out" ]; then
                printf '%s\n' "$out"
            else
                err "No packages provide \"$expr\"."
            fi
            ;;
        *) return ;;
    esac
}

do_watch() {
    local a p
    local watch_items=(
        "Add package to watchlist"
        "Remove package from watchlist"
        "Show watchlist"
        "Check watchlist for updates"
        "Back")
    if have_fzf; then
        a=$(pick_menu "$ICON_EYE  Package watchlist" "${watch_items[@]}")
    else
        printf '1) Add package to watchlist\n2) Remove package from watchlist\n3) Show watchlist\n4) Check watchlist for updates\n5) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Add package to watchlist" ;;
            2) a="Remove package from watchlist" ;;
            3) a="Show watchlist" ;;
            4) a="Check watchlist for updates" ;;
            5) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        Add*)
            ask_name "Package to watch"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            if [ -f "$WATCH_FILE" ] && grep -Fxq -- "$PKG_NAME" "$WATCH_FILE"; then
                say "$PKG_NAME is already on the watchlist."
                return
            fi
            refuse_symlink "$WATCH_FILE" || return
            if printf '%s\n' "$PKG_NAME" >> "$WATCH_FILE"; then
                log "watch add $PKG_NAME"
                ok "$PKG_NAME added to the watchlist."
            else
                err "Could not update $WATCH_FILE."
            fi
            ;;
        Remove*)
            if [ ! -s "$WATCH_FILE" ]; then
                warn "Watchlist is empty."
                return
            fi
            if have_fzf; then
                mapfile -t _wl < "$WATCH_FILE"
                p=$(printf '%s\n' "${_wl[@]}" | pick_one "$ICON_TRASH  Remove from watchlist")
            else
                printf 'Watchlist:\n' >&2
                nl -w2 -s') ' "$WATCH_FILE" >&2
                printf '❯ Pick number (0 = cancel): ' >&2
                read -r p
                case "$p" in
                    [1-9]|[1-9][0-9]) p=$(sed -n "${p}p" "$WATCH_FILE") ;;
                    *) return ;;
                esac
            fi
            [ -n "$p" ] || return
            valid_pkg_name "$p" || { err "Invalid package name: '$p'"; return; }
            if tmp=$(scratch_new); then
                grep -Fxv -- "$p" "$WATCH_FILE" > "$tmp" || [ $? -le 1 ] || { rm -f "$tmp"; err "Could not read watchlist — leaving it unchanged."; return; }
                if mv -f "$tmp" "$WATCH_FILE"; then
                    log "watch remove $p"
                    ok "$p removed from the watchlist."
                else
                    err "Failed to update the watchlist."
                    rm -f "$tmp"
                fi
            else
                err "Could not create a temp file for the watchlist."
            fi
            ;;
        Show*)
            if [ -s "$WATCH_FILE" ]; then
                say "$ICON_EYE  Watchlist ($WATCH_FILE):"
                cat "$WATCH_FILE"
            else
                say "Watchlist is empty."
            fi
            ;;
        Check*)
            do_watch_check
            ;;
        *) return ;;
    esac
}

do_watch_check() {
    [ -s "$WATCH_FILE" ] || { say "Watchlist is empty — add a package first."; return; }
    log "watch check"
    say "$ICON_EYE  Checking watchlist against the repositories..."
    local p inst cand updates=0 gone=0
    while IFS= read -r p || [ -n "$p" ]; do
        [ -n "$p" ] || continue
        valid_pkg_name "$p" || continue
        inst=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null | head -n1)
        cand=$(apt-cache policy "$p" 2>/dev/null | awk '/^  Candidate:/ {print $2; exit}')
        if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
            printf '? %s — no longer available in the repositories\n' "$p"
            gone=$((gone+1))
        elif [ -z "$inst" ]; then
            printf '+ %s — not installed (candidate %s)\n' "$p" "$cand"
            updates=$((updates+1))
        elif [ "$inst" != "$cand" ]; then
            printf '^ %s — %s -> %s available\n' "$p" "$inst" "$cand"
            updates=$((updates+1))
        else
            printf '= %s — up to date (%s)\n' "$p" "$inst"
        fi
    done < "$WATCH_FILE"
    if [ "$updates" -gt 0 ]; then
        say "$ICON_EYE  $updates watched package(s) have updates available."
        if command -v termux-notification >/dev/null 2>&1; then
            termux-notification --title "Package watchlist" \
                --content "$updates watched package(s) have updates available" \
                >/dev/null 2>&1 || true
        fi
    elif [ "$gone" -gt 0 ]; then
        warn "$gone watched package(s) are no longer in any repository."
    else
        ok "All watched packages are up to date."
    fi
}

# --- mirror candidates — official mirrors from termux-tools mirrors/ (2026-11)
# region|name|url, one per line; fetched from github.com/termux/termux-tools
_mirror_candidates() {
    cat <<'MIRS'
primary|packages.termux.dev (official)|https://packages.termux.dev/apt/termux-main
primary|packages-cf.termux.dev (cloudflare)|https://packages-cf.termux.dev/apt/termux-main
asia|DomaiNesia|https://linux.domainesia.com/applications/termux/termux-main
asia|freedif|https://mirror.freedif.org/termux/termux-main
asia|jeonnam.school|https://mirror.jeonnam.school/termux/termux-main
asia|meowsmp.net|https://mirror.meowsmp.net/termux/termux-main
asia|nag.albony.in|https://mirror.nag.albony.in/termux/termux-main
asia|nevacloud.com|https://mirror.nevacloud.com/applications/termux/termux-main
asia|rinarin.dev|https://mirror.rinarin.dev/termux/termux-main
asia|twds.com.tw|https://mirror.twds.com.tw/termux/termux-main
asia|cbrx.io|https://mirrors.cbrx.io/apt/termux/termux-main
asia|in.sahilister.net|https://mirrors.in.sahilister.net/termux/termux-main
asia|krnk.org|https://mirrors.krnk.org/apt/termux/termux-main
asia|nguyenhoang.cloud|https://mirrors.nguyenhoang.cloud/termux/termux-main
asia|ravidwivedi.in|https://mirrors.ravidwivedi.in/termux/termux-main
asia|saswata.cc|https://mirrors.saswata.cc/termux/termux-main
asia|niranjan.co|https://termux.niranjan.co/termux-main
asia|tmx.xvx.my.id|https://tmx.xvx.my.id/apt/termux-main
chinese_mainland|iscas.ac.cn|https://mirror.iscas.ac.cn/termux/apt/termux-main
chinese_mainland|nyist.edu.cn|https://mirror.nyist.edu.cn/termux/apt/termux-main
chinese_mainland|sjtu.edu.cn|https://mirror.sjtu.edu.cn/termux/termux-main
chinese_mainland|aliyun.com|https://mirrors.aliyun.com/termux/termux-main
chinese_mainland|bfsu.edu.cn|https://mirrors.bfsu.edu.cn/termux/apt/termux-main
chinese_mainland|cernet.edu.cn|https://mirrors.cernet.edu.cn/termux/apt/termux-main
chinese_mainland|cqupt.edu.cn|https://mirrors.cqupt.edu.cn/termux/termux-main
chinese_mainland|hust.edu.cn|https://mirrors.hust.edu.cn/termux/apt/termux-main
chinese_mainland|nju.edu.cn|https://mirrors.nju.edu.cn/termux/apt/termux-main
chinese_mainland|pku.edu.cn|https://mirrors.pku.edu.cn/termux/termux-main
chinese_mainland|sau.edu.cn|https://mirrors.sau.edu.cn/termux/apt/termux-main
chinese_mainland|sdu.edu.cn|https://mirrors.sdu.edu.cn/termux/termux-main
chinese_mainland|sustech.edu.cn|https://mirrors.sustech.edu.cn/termux/apt/termux-main
chinese_mainland|tuna.tsinghua.edu.cn|https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main
chinese_mainland|ustc.edu.cn|https://mirrors.ustc.edu.cn/termux/termux-main
chinese_mainland|zju.edu.cn|https://mirrors.zju.edu.cn/termux/apt/termux-main
europe|agdsn.de|https://ftp.agdsn.de/termux/termux-main
europe|fau.de|https://ftp.fau.de/termux/termux-main
europe|icm.edu.pl|https://ftp.icm.edu.pl/pub/Linux/dist/termux/termux-main
europe|grimler.se|https://grimler.se/termux/termux-main
europe|is.mirror.flokinet.net|https://is.mirror.flokinet.net/termux/termux-main
europe|md.mirrors.hacktegic.com|https://md.mirrors.hacktegic.com/termux/termux-main
europe|mirror.accum.se|https://mirror.accum.se/mirror/termux.dev/termux-main
europe|mirror.autkin.net|https://mirror.autkin.net/termux/termux-main
europe|mirror.bouwhuis.network|https://mirror.bouwhuis.network/termux/termux-main
europe|mirror.cutie.dating|https://mirror.cutie.dating/termux/termux-main
europe|mirror.leitecastro.com|https://mirror.leitecastro.com/termux/termux-main
europe|mirror.sunred.org|https://mirror.sunred.org/termux/termux-main
europe|mirrors.medzik.dev|https://mirrors.medzik.dev/termux/termux-main
europe|nl.mirror.flokinet.net|https://nl.mirror.flokinet.net/termux/termux-main
europe|ro.mirror.flokinet.net|https://ro.mirror.flokinet.net/termux/termux-main
europe|termux.3san.dev|https://termux.3san.dev/termux/termux-main
europe|termux.cdn.lumito.net|https://termux.cdn.lumito.net/termux-main
europe|termux.librehat.com|https://termux.librehat.com/apt/termux-main
north_america|gnlug.org|https://gnlug.org/pub/termux/termux-main
north_america|mirror.csclub.uwaterloo.ca|https://mirror.csclub.uwaterloo.ca/termux/termux-main
north_america|mirror.fcix.net|https://mirror.fcix.net/termux/termux-main
north_america|mirror.mwt.me|https://mirror.mwt.me/termux/main
north_america|mirror.quantum5.ca|https://mirror.quantum5.ca/termux/termux-main
north_america|mirror.vern.cc|https://mirror.vern.cc/termux/termux-main
north_america|mirrors.utermux.dev|https://mirrors.utermux.dev/termux/termux-main
north_america|plug-mirror.rcac.purdue.edu|https://plug-mirror.rcac.purdue.edu/termux/termux-main
north_america|termux.danyael.xyz|https://termux.danyael.xyz/termux/termux-main
oceania|middlendian.com|https://mirrors.middlendian.com/termux/termux-main
russia|mephi.ru|http://mirror.mephi.ru/termux/termux-main
russia|repository.su|https://repository.su/termux/termux-main
south_america|ufscar.br|https://mirror.ufscar.br/termux/termux-main
MIRS
}

do_mirror() {
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required for the mirror speed test."
        say "Install it with: $MGR install curl"
        return 1
    fi
    # mirror rows are tab-separated (mirror names contain spaces)
    local IFS=$'\t'
    say "$ICON_PLAY Mirror speed test — timing mirrors (a few seconds each)..."
    local cur_url="" cur_src="" u t results="" line
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        u=$(grep -E '^deb[[:space:]]' "$PREFIX/etc/apt/sources.list" 2>/dev/null | grep 'termux-main' | awk '{print $2}' | head -n1)
        if [ -n "$u" ]; then
            cur_url="$u"
            cur_src="$PREFIX/etc/apt/sources.list"
        fi
    fi
    if [ -z "$cur_url" ]; then
        local f
        for f in "$PREFIX"/etc/apt/sources.list.d/*.list; do
            [ -f "$f" ] || continue
            u=$(grep -E '^deb[[:space:]]' "$f" 2>/dev/null | grep 'termux-main' | awk '{print $2}' | head -n1)
            if [ -n "$u" ]; then
                cur_url="$u"
                cur_src="$f"
                break
            fi
        done
    fi
    [ -n "$cur_url" ] || cur_url="https://packages.termux.dev/apt/termux-main"
    say "Current main mirror: $cur_url"
    # the FULL official candidate list, probed in parallel
    local probe_file
    probe_file=$(mktemp "$HOME/.pkg-manager-mirror-probe.XXXXXX" 2>/dev/null) || { err "mktemp failed"; return; }
    # probe ALL candidates (including current — harmless) in parallel
    local _i=0 total
    total=$(_mirror_candidates | wc -l)
    while IFS='|' read -r region name url; do
        _i=$((_i+1))
        (
            t=$(curl -fsS -m 6 --connect-timeout 3 -o /dev/null -w '%{time_total}' "$url/dists/stable/Release" 2>/dev/null)
            [ -n "$t" ] && printf '%s\t%s\t%s\n' "$t" "$name" "$url" >> "$probe_file.lock-$((_i % 16))"
        ) &
        # bound concurrency to 16
        while [ "$(jobs -r | wc -l)" -ge 16 ]; do wait -n 2>/dev/null || break; done
    done < <(_mirror_candidates)
    wait
    cat "$probe_file".lock-* > "$probe_file" 2>/dev/null || true
    rm -f "$probe_file".lock-*
    local results="" unreachable=0 responded=0
    if [ -s "$probe_file" ]; then
        results=$(sort -n -s "$probe_file")
        responded=$(printf '%s\n' "$results" | grep -c .)
    fi
    rm -f "$probe_file"
    unreachable=$(( total - responded ))
    if [ -z "$results" ]; then
        err "No mirror responded — check your connection."
        log_err "mirror test: no mirror reachable"
        return 1
    fi
    say ""
    printf '  %-8s  %-34s %s\n' "time" "mirror" "url"
    printf '%s\n' "$results" | sort -n -s | awk -F'\t' '{printf "  %-8s  %-34s %s\n", $1"s", $2, $3}'
    [ "$unreachable" -gt 0 ] && say "( $unreachable mirror(s) unreachable )"
    read -r best_t best_name best_url <<< "$(printf '%s\n' "$results" | sort -n -s | head -n1)"
    log "mirror test (best: $best_url at $best_t)"
    if [ "$best_url" = "$cur_url" ]; then
        ok "Your current mirror is already the fastest — nothing to do."
        return 0
    fi
    say ""
    say "Fastest reachable mirror: $best_name ($best_url) at ${best_t}s"
    if ! confirm_danger "$ICON_PLAY Switch the main repo to $best_url?"; then
        say "Canceled — mirror unchanged."
        return 0
    fi
    local target="${cur_src:-$PREFIX/etc/apt/sources.list}" backup tmp
    backup="$target.pkg-manager.bak"
    if ! safe_cp "$target" "$backup" 2>/dev/null; then
        if [ ! -f "$target" ]; then
            mkdir -p "$PREFIX/etc/apt" 2>/dev/null || true
            : > "$target" || { err "Could not create $target"; return 1; }
        else
            err "Could not back up $target — aborting, mirror unchanged."
            return 1
        fi
    fi
    # never silently truncate: the file must stay readable, and the rewrite must
    # keep every line that isn't the main repo line
    [ -r "$target" ] || { err "$target is not readable — aborting, mirror unchanged."; return 1; }
    if ! tmp=$(scratch_new); then
        err "Could not create a temp file for sources.list."
        return 1
    fi
    local keep grc
    keep=$(grep -v -E '^deb[[:space:]].*termux-main' "$target" 2>/dev/null)
    grc=$?   # rc 0 = lines filtered out; rc 1 = no other lines (fine); rc >=2 = read failure
    if [ "$grc" -ge 2 ]; then
        err "Could not read $target — aborting, mirror unchanged."
        rm -f "$tmp"
        return 1
    fi
    {
        [ -n "$keep" ] && printf '%s\n' "$keep"
        printf '# main repo switched by Easy Termux Package Manager (backup: %s)\n' "$backup"
        printf 'deb %s stable main\n' "$best_url"
    } > "$tmp" || { rm -f "$tmp"; err "Could not stage $tmp — mirror unchanged."; return 1; }
    if ! grep -q '^deb ' "$tmp"; then
        err "Refusing to write an empty/invalid $target — aborting."
        rm -f "$tmp"
        return 1
    fi
    if ! mv -f "$tmp" "$target"; then
        err "Failed to write $target — restore it from $backup"
        rm -f "$tmp"
        log_err "mirror switch: write failed"
        return 1
    fi
    say "$ICON_PLAY Running apt update with the new mirror..."
    local out hint
    if out=$(apt update 2>&1); then
        log "mirror switch to $best_url"
        ok "Mirror switched to $best_url — package lists refreshed."
    else
        hint=$(apt_hint "$out")
        warn "${hint:-apt update failed with the new mirror.}"
        printf '%s\n' "$out" | tail -n 4
        say "The old mirror is saved at $backup"
        log_err "mirror switch to $best_url: apt update failed"
    fi
}

do_audit() {
    say "$ICON_SHIELD  System audit — checking your Termux install..."
    log "audit"
    local score=100
    local -a issues=()
    local up_n orph_n held_n res_n cache_k disk_k up out
    # 1. available upgrades (unknown ≠ zero when apt fails)
    if ! out=$(list_upgradable 2>/dev/null); then
        err "Could not check for upgrades — cannot score this section."
        up_n=0
    else
        up_n=$(printf '%s\n' "$out" | grep -c . || true)
    fi
    if [ "$up_n" -gt 0 ]; then
        if [ "$up_n" -ge 20 ]; then
            score=$((score-15))
            issues+=("$up_n packages can be upgraded — run the Upgrade center")
        else
            score=$((score-5))
            issues+=("$up_n package(s) can be upgraded")
        fi
    fi
    # 2. orphans
    if ! out=$(apt autoremove --simulate -y 2>&1); then
        orph_n=0
    else
        orph_n=$(printf '%s\n' "$out" | awk '
            /will be REMOVED:/ {on=1; next}
            on && /upgraded|newly installed|not upgraded|after this operation/ {on=0}
            on { for (i=1;i<=NF;i++)
                    if ($i ~ /^[A-Za-z][A-Za-z0-9+.:~-]*$/ && $i !~ /^[0-9][0-9.:-]+$/) print $i }' | grep -c . || true)
    fi
    if [ "$orph_n" -gt 0 ]; then
        score=$((score-orph_n))
        issues+=("$orph_n orphaned package(s) can be autoremoved (option 29 or 9)")
    fi
    # 3. held packages (informational)
    if ! out=$(apt-mark showhold 2>/dev/null); then
        held_n=0
    else
        held_n=$(printf '%s\n' "$out" | grep -c . || true)
    fi
    if [ "$held_n" -gt 0 ]; then
        score=$((score-held_n*2))
        issues+=("$held_n package(s) are pinned from upgrades (informational)")
    fi
    # 4. residual config files (rc state = purged but not auto-removed)
    if ! out=$(dpkg -l 2>/dev/null); then
        res_n=0
    else
        res_n=$(printf '%s\n' "$out" | awk '$1=="rc" && NF>1' | grep -c . || true)
    fi
    if [ "$res_n" -gt 0 ]; then
        score=$((score-5))
        issues+=("$res_n package(s) still have leftover config files (purge them)")
    fi
    # 5. cache weight
    cache_k=$(du -sk "$PREFIX/var/cache/apt/archives" 2>/dev/null | awk '{print $1}')
    if [ -n "$cache_k" ] && [ "$cache_k" -gt 102400 ]; then
        score=$((score-5))
        issues+=("package cache is over 100 MiB — clean it with the Cache manager")
    fi
    # 6. free disk on $PREFIX
    disk_k=$(df -Pk "$PREFIX" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$disk_k" ] && [ "$disk_k" -lt 512000 ]; then
        score=$((score-10))
        issues+=("less than 500 MiB free on the Termux prefix")
    fi
    [ "$score" -lt 0 ] && score=0
    say ""
    say "════════ Audit report ════════"
    local grade
    if [ "$score" -ge 90 ]; then grade="excellent"
    elif [ "$score" -ge 70 ]; then grade="good"
    elif [ "$score" -ge 40 ]; then grade="needs attention"
    else grade="critical"
    fi
    say "$ICON_CHART Health score: $score/100 ($grade)"
    say "$ICON_UPGRADABLE Upgradable packages: $up_n"
    say "$ICON_TREE  Orphaned packages:   $orph_n"
    say "$ICON_HOLD Pinned packages:      $held_n"
    say "$ICON_TRASH Leftover configs:   $res_n"
    say "$ICON_CACHE Package cache:       $([ -n "$cache_k" ] && du -sh "$PREFIX/var/cache/apt/archives" 2>/dev/null | awk '{print $1}' || echo '?')"
    say "$ICON_DISK Free on prefix:       $([ -n "$disk_k" ] && df -Ph "$PREFIX" 2>/dev/null | awk 'NR==2{print $4}' || echo '?')"
    if [ "${#issues[@]}" -gt 0 ]; then
        say ""
        say "$ICON_ERROR Findings:"
        printf '  • %s\n' "${issues[@]}"
        say ""
        say "$ICON_MAINT Tip: option 33 (Maintenance wizard) fixes most of these in one flow."
    else
        say ""
        ok "No issues found — your install looks healthy!"
    fi
    say "═════════════════════════════"
}

do_selfupdate() {
    say "$ICON_UP Checking for a new version of pkg-manager..."
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to check for updates."
        say "Install it with: $MGR install curl"
        return 1
    fi
    local self="$0" resolved new_tmp local_ver remote_ver
    case "$self" in
        */*) ;;
        *) resolved=$(command -v -- "$self" 2>/dev/null)
           [ -n "$resolved" ] && self="$resolved"
           ;;
    esac
    # refuse to guess the install path when we only have $0 == relative name
    case "$self" in
        /*) ;;
        *) resolved=$(command -v -- "$self" 2>/dev/null)
           if [ -z "$resolved" ]; then
               err "Cannot resolve install path from \$0 — nothing was changed."
               return 1
           fi
           self="$resolved"
           ;;
    esac
    if ! new_tmp=$(scratch_new); then
        err "Could not create a temp file for the download."
        return 1
    fi
    if ! curl -fsSL "$UPDATE_URL" -o "$new_tmp" 2>/dev/null; then
        err "Could not download the latest version — check your connection."
        log_err "self-update: download failed"
        rm -f "$new_tmp"
        return 1
    fi
    if ! bash -n "$new_tmp" 2>/dev/null; then
        err "Downloaded file failed the bash syntax check — nothing was changed."
        log_err "self-update: downloaded file failed bash -n"
        rm -f "$new_tmp"
        return 1
    fi
    if ! grep -q 'pkg-manager' "$new_tmp" 2>/dev/null; then
        err "Downloaded file does not look like pkg-manager — nothing was changed."
        log_err "self-update: downloaded file content mismatch"
        rm -f "$new_tmp"
        return 1
    fi
    # Integrity gate: when the release publishes a companion SHA-256 file,
    # verify the download before replacing the installed binary. A missing
    # checksum endpoint (older releases) skips verification but keeps every
    # check above.
    if ! checksum_tmp=$(scratch_new); then
        err "Could not create a temp file for checksum verification."
        rm -f "$new_tmp"
        return 1
    fi
    if curl -fsSL "$UPDATE_URL.sha256" -o "$checksum_tmp" 2>/dev/null; then
        local want got
        want=$(grep -m1 -oE '\b[0-9a-fA-F]{64}\b' "$checksum_tmp" 2>/dev/null | tr 'A-F' 'a-f')
        got=$(sha256sum "$new_tmp" 2>/dev/null | cut -d' ' -f1)
        if [ -z "$want" ]; then
            say "Published checksum was unreadable — skipping SHA-256 verification."
            log_err "self-update: checksum file unreadable"
        elif [ -z "$got" ]; then
            say "sha256sum unavailable — skipping SHA-256 verification."
        elif [ "$want" != "$got" ]; then
            err "SHA-256 mismatch — refusing to install (expected $want, got $got)."
            log_err "self-update: sha256 mismatch"
            rm -f "$new_tmp" "$checksum_tmp"
            return 1
        fi
    else
        say "No checksum published for this release — skipping SHA-256 verification."
    fi
    rm -f "$checksum_tmp"
    if cmp -s "$new_tmp" "$self"; then
        ok "pkg-manager is already up to date."
        rm -f "$new_tmp"
        return 0
    fi
    local_ver=$(grep -m1 -E '^VERSION=' "$self" 2>/dev/null | sed -E 's/^VERSION="([^"]*)".*/\1/')
    remote_ver=$(grep -m1 -E '^VERSION=' "$new_tmp" 2>/dev/null | sed -E 's/^VERSION="([^"]*)".*/\1/')
    say "New version available: ${remote_ver:-unknown version} (you have ${local_ver:-unknown})."
    say "Update target: $self"
    if ! confirm_danger "$ICON_UP  Replace $self with the new version?"; then
        say "Update canceled."
        rm -f "$new_tmp"
        return 0
    fi
    # Self-update must not leave a broken payload behind, and must fix the
    # shebang exactly like install.sh does (#!/bin/bash is wrong on Termux).
    local bash_path
    bash_path=$(command -v bash 2>/dev/null) || bash_path=""
    # bash_path goes into a replacement string; restrict to a sane charset
    case "$bash_path" in ''|*[!A-Za-z0-9/._-]*) err "Unexpected bash path — aborting."; rm -f "$new_tmp"; return 1 ;; esac
    if [ -n "$bash_path" ]; then
        # avoid sed replacement-delimiter injection by rewriting the first line directly
        if ! { printf '#!%s\n' "$bash_path"; tail -n +2 "$new_tmp"; } > "${new_tmp}.fixed"; then
            err "Could not rewrite the shebang — nothing was changed."
            rm -f "$new_tmp" "${new_tmp}.fixed"
            return 1
        fi
        if ! mv -f "${new_tmp}.fixed" "$new_tmp"; then
            err "Could not install the shebang-fixed download — nothing was changed."
            rm -f "$new_tmp" "${new_tmp}.fixed"
            return 1
        fi
        # re-run the syntax check on the rewritten file
        if ! bash -n "$new_tmp" 2>/dev/null; then
            err "Downloaded file failed the bash syntax check after shebang rewrite — nothing was changed."
            log_err "self-update: downloaded file failed bash -n (after shebang fix)"
            rm -f "$new_tmp"
            return 1
        fi
    fi
    # back up the running script before replacing it
    if ! safe_cp "$self" "$self.pkg-manager.bak" 2>/dev/null; then
        err "Could not back up $self — aborting, nothing was changed."
        log_err "self-update: backup of $self failed"
        rm -f "$new_tmp"
        return 1
    fi
    rm -f "$self.new" 2>/dev/null
    if cp -- "$new_tmp" "$self.new" && chmod +x "$self.new" 2>/dev/null && mv -f -- "$self.new" "$self"; then
        log "self-update to ${remote_ver:-latest} (backup: $self.pkg-manager.bak)"
        ok "Updated to ${remote_ver:-the latest version}! Restart pkg-manager to use it."
        ok "The previous version is at ${self}.pkg-manager.bak"
        rm -f "$new_tmp"
        return 0
    fi
    err "Failed to replace $self — nothing was changed."
    rm -f "$new_tmp" "$self.new"
    log_err "self-update: replace failed"
    return 1
}

do_palette() {
    local all picked
    local -a prows=()
    local i d det n=0 us=$'\x1f'
    for i in "${MENU_ITEMS[@]}"; do
        n=$((n + 1))
        d="${MENU_DESC[$i]:-}"
        [ -n "$d" ] || d="Open this action."
        det="${MENU_DETAIL[$i]:-}"
        [ -n "$det" ] || det="menu action"
        prows+=("$i$us$d$us$n$us$det")
    done
    prows+=("$OPTION_SUB_EXIT${us}$OPTION_SUB_EXIT${us}0${us}back one level")
    prows+=("$OPTION_APP_EXIT${us}$OPTION_APP_EXIT${us}0${us}leave the app")
    if have_fzf; then
        local e_bold e_dim e_off
        e_bold=$'\033[1m'; e_dim=$'\033[2m'; e_off=$'\033[0m'
        FZF_PREVIEW="printf '\n  ${e_bold}%s${e_off}\n  ───────────────────────────────\n\n  %s\n\n  ${e_dim}%s${e_off}\n  ${e_dim}row %s${e_off}\n' {1} {2} {4} {3}"
        FZF_NTH="--delimiter=\x1f --nth=1,2 --with-nth=1"
        FZF_GHOST="type to filter the commands"
        picked=$(printf '%s\n' "${prows[@]}" | fzf_select "Command palette — type to filter" "❯ " 0 \
            --header="? preview · / search · ESC cancel" --marker="▶" --gutter=" " --no-separator) || picked=""
        FZF_PREVIEW=""; FZF_NTH=""; FZF_GHOST=""
        [ -n "$picked" ] && picked="${picked%%$'\x1f'*}"
    else
        printf '❯ Palette — type substring to filter (empty for all): ' >&2
        read -r picked
        local all
        all=$(printf '%s\n' "${MENU_ITEMS[@]}")
        if [ -n "$picked" ]; then all=$(printf '%s\n' "$all" | grep -iF -- "$picked" || printf '%s\n' "$all"); fi
        if ! tmp=$(scratch_new); then return; fi
        printf '%s\n' "$all" > "$tmp"
        nl -w2 -s') ' "$tmp" >&2
        printf 'Pick number: ' >&2
        read -r picked
        case "$picked" in [1-9]|[1-9][0-9]) picked=$(sed -n "${picked}p" "$tmp") ;; *) rm -f "$tmp"; return ;; esac
        rm -f "$tmp"
    fi
    [ -n "$picked" ] || { say "Canceled."; return; }
    say "$ICON_WAND Running: $picked"
    case "$picked" in
        "$OPTION_INSTALL") do_install ;;
        "$OPTION_UNINSTALL") do_uninstall ;;
        "$OPTION_LIST") do_list ;;
        "$OPTION_REINSTALL") do_reinstall ;;
        "$OPTION_UPDATE") do_upgrade_center ;;
        "$OPTION_CLEAN") do_clean ;;
        "$OPTION_INFO") do_info ;;
        "$OPTION_AUTOREMOVE") do_autoremove ;;
        "$OPTION_DEPENDS") do_depends ;;
        "$OPTION_RDEPENDS") do_rdepends ;;
        "$OPTION_SIZE") do_size ;;
        "$OPTION_FILES") do_files ;;
        "$OPTION_OWNER") do_owner ;;
        "$OPTION_HOLD") do_hold ;;
        "$OPTION_PURGE") do_purge ;;
        "$OPTION_FIXBROKEN") do_fixbroken ;;
        "$OPTION_UPGRADABLE") do_upgradable ;;
        "$OPTION_BACKUP") do_backup ;;
        "$OPTION_RESTORE") do_restore ;;
        "$OPTION_EXPORT") do_export ;;
        "$OPTION_IMPORT") do_import ;;
        "$OPTION_DOCTOR") do_doctor ;;
        "$OPTION_SETTINGS") do_settings ;;
        "$OPTION_HISTORY") do_history ;;
        "$OPTION_SIMULATE") do_simulate ;;
        "$OPTION_STATS") do_stats ;;
        "$OPTION_CACHE") do_cache ;;
        "$OPTION_DEPTREE") do_deptools ;;
        "$OPTION_BULK") do_bulk ;;
        "$OPTION_FAVS") do_favs ;;
        "$OPTION_INSPECT") do_inspect ;;
        "$OPTION_MAINT") do_maintenance ;;
        "$OPTION_GROUPS") do_groups ;;
        "$OPTION_LOCALDEB") do_localdeb ;;
        "$OPTION_DOWNGRADE") do_downgrade ;;
        "$OPTION_DLONLY") do_dlonly ;;
        "$OPTION_HOLDVER") do_holdver ;;
        "$OPTION_FILESEARCH") do_filesearch ;;
        "$OPTION_CHANGELOG") do_changelog ;;
        "$OPTION_WHY") do_why ;;
        "$OPTION_NOTES") do_notes ;;
        "$OPTION_SNAPSHOT") do_snapshot ;;
        "$OPTION_PALETTE") do_palette ;;
        "$OPTION_WATCH") do_watch ;;
        "$OPTION_MIRROR") do_mirror ;;
        "$OPTION_AUDIT") do_audit ;;
        "$OPTION_MARKS") do_marks ;;
        "$OPTION_RECYCLE") do_recycle ;;
        "$OPTION_SELFUPDATE") do_selfupdate ;;
        "$OPTION_REPOS") do_repos ;;
        "$OPTION_HEALTH") do_health ;;
        "$OPTION_DEPTREE_GRAPH") do_depgraph ;;
        "$OPTION_THEME") do_theme ;;
        "$OPTION_ESSENTIALS") do_essentials ;;
        "$OPTION_SYSINFO") do_sysinfo ;;
        "$OPTION_WHATSNEW") do_whatsnew ;;
        "$OPTION_UNDO") do_undo ;;
        "$OPTION_SNAPSHOT_DIFF") do_snapshot ;;
        *) err "Unknown palette selection." ;;
    esac
}
pin_install() {
    local pkg="$1" out hint
    [ -n "$pkg" ] || { err "Invalid pinned package name."; return; }
    valid_pkg_name "$pkg" || { err "Invalid pinned package name '$pkg'."; return; }
    if confirm_danger "$ICON_STAR Install pinned package $pkg?"; then
        say "$ICON_STAR Installing $pkg..."
        if out=$("$MGR" install -y "$pkg" 2>&1); then
            log "pinned install $pkg"
            hint=$(apt_hint "$out")
            if [ -n "$hint" ]; then
                ok "$hint"
            else
                ok "$pkg installed!"
            fi
        else
            hint=$(apt_hint "$out")
            err "${hint:-Failed to install $pkg.}"
            log_err "pinned install $pkg: ${hint:-install failed}"
            printf '%s\n' "$out" | tail -n 4
        fi
    fi
}

# Theme hub — pick a theme, preview them all, or push the palette into the
# Termux terminal itself via ~/.termux/colors.properties
do_theme() {
    local choice
    if have_fzf; then
        choice=$(pick_menu "$ICON_WAND  Theme hub (current: $THEME)" "Pick a theme" "Preview all themes" "Apply '$THEME' to the Termux terminal" "Restore backed-up Termux colors" "$ICON_BACK  Back")
    else
        printf '1) Pick a theme\n2) Preview all themes\n3) Apply current theme (%s) to the Termux terminal\n4) Restore backed-up Termux colors\n5) Back\n> ' "$THEME" >&2
        read -r choice
        case "$choice" in
            1) choice="Pick a theme" ;;
            2) choice="Preview all themes" ;;
            3) choice="Apply '$THEME' to the Termux terminal" ;;
            4) choice="Restore backed-up Termux colors" ;;
            *) return ;;
        esac
    fi
    [ -n "$choice" ] || return
    case "$choice" in
        "Pick a theme")       set_theme_pick ;;
        "Preview all themes") theme_preview ;;
        "Apply"*"terminal"*)  apply_termux_theme "$THEME" ;;
        "Restore"*)           restore_termux_theme ;;
        *) return ;;
    esac
}

# Essential toolkit — curated bundles of the most-installed Termux packages,
# installed in one batched apt call.
do_essentials() {
    local pick pkgs="" n
    local bundles=(
        "Core — git curl wget nano termux-tools"
        "Dev — python nodejs jq"
        "Net & security — openssh rsync nmap"
        "Power utils — htop ripgrep fd tree bat"
        "Everything above"
    )
    if have_fzf; then
        pick=$(pick_menu "$ICON_BOLT  Essential toolkit — pick a bundle" "${bundles[@]}" "$ICON_BACK  Back")
    else
        local i=1
        list_numbered 0 "${bundles[@]}"
        printf '❯ 6) Back\n' >&2
        read -r pick
        case "$pick" in
            1|2|3|4|5) pick="${bundles[$((pick-1))]}" ;;
            *) return ;;
        esac
    fi
    [ -n "$pick" ] || return
    case "$pick" in
        Core*)         pkgs="git curl wget nano termux-tools" ;;
        Dev*)          pkgs="python nodejs jq" ;;
        "Net & security"*) pkgs="openssh rsync nmap" ;;
        "Power utils"*)    pkgs="htop ripgrep fd tree bat" ;;
        Everything*)  pkgs="git curl wget nano termux-tools python nodejs jq openssh rsync nmap htop ripgrep fd tree bat" ;;
        *) return ;;
    esac
    local -a list=()
    mapfile -t list <<< "$(printf '%s\n' $pkgs | filter_pkgs)"
    n=${#list[@]}
    [ "$n" -gt 0 ] || { warn "Nothing valid to install."; return; }
    say "$ICON_BOLT  Bundle: $pick"
    printf '  %s\n' "${list[@]}"
    if confirm_danger "$ICON_BOLT  Install $n essential packages?"; then
        log "essentials $pick"
        run_multi_op install "${list[@]}"
    else
        say "Canceled."
    fi
}

# System & network dashboard — read-only info, no package changes.
do_sysinfo() {
    section "System & network info"
    local line
    line=$(uname -srmo 2>/dev/null || uname -a)
    printf '  %-14s %s\n' "Kernel:" "$line"
    printf '  %-14s %s\n' "Hostname:" "$(hostname 2>/dev/null || echo unknown)"
    printf '  %-14s %s\n' "Prefix:" "$PREFIX"
    line=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //')
    printf '  %-14s %s (%s cores)\n' "CPU:" "${line:-unknown}" "$(nproc 2>/dev/null || echo '?')"
    line=$(grep -m1 MemTotal /proc/meminfo 2>/dev/null)
    printf '  %-14s %s\n' "RAM:" "${line:-unknown}"
    printf '  %-14s %s\n' "Storage:" "$(df -h "$HOME" 2>/dev/null | tail -n1 | awk '{print $3" used / "$2" total ("$5" of "$1")"}')"
    line=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    if [ -n "$line" ]; then
        printf '  %-14s %s%% (%s)\n' "Battery:" "$line" "$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo '?')"
    elif command -v termux-battery-status >/dev/null 2>&1; then
        line=$(termux-battery-status 2>/dev/null | sed -n 's/.*"percentage":[[:space:]]*\([0-9]*\).*/\1%/p')
        printf '  %-14s %s\n' "Battery:" "${line:-n/a}"
    else
        printf '  %-14s %s\n' "Battery:" "n/a"
    fi
    line=$(grep -m1 nameserver "$PREFIX/etc/resolv.conf" 2>/dev/null | awk '{print $2}')
    printf '  %-14s %s\n' "DNS:" "${line:-none configured}"
    local code
    code=$(curl -o /dev/null -s -w '%{http_code}' --max-time 4 "$UPDATE_URL" 2>/dev/null)
    if [ -n "$code" ] && [ "$code" != "000" ]; then
        ok "Connectivity: HTTPS $code from the update server"
    else
        warn "Connectivity: could not reach the update server"
    fi
    printf '  %-14s %s\n' "Uptime:" "$(cut -d' ' -f1 /proc/uptime 2>/dev/null | awk '{printf "%.1f h", $1/3600}')"
}

# What's new in this major version
do_whatsnew() {
    section "What's new in pkg-manager v$VERSION"
    say "  9 real terminal themes with official truecolor palettes:"
    dim "  dracula · catppuccin · tokyo-night · nord · gruvbox · one-dark ·"
    dim "  solarized · everforest · rosepine (plus the 8 legacy 256-color ones)"
    say "  Theme hub: preview every theme, and export the palette to"
    dim "  ~/.termux/colors.properties so the whole terminal matches the app"
    say "  Truecolor in plain text mode too — menus, ok/warn/err all themed"
    say "  Status strip under the banner (manager · theme · installed count)"
    say "  $ICON_BOLT Essential toolkit — one-tap curated package bundles"
    say "  $ICON_GLOBE System & network dashboard (CPU, RAM, storage, battery, DNS)"
    say "  Command palette now covers every menu entry"
    say "  NEW in v5.1:"
    dim "  --check-updates lists upgradable packages without opening the app"
    dim "  --quiet prints just the count (machine-readable, for cron)"
    dim "  --doctor runs the full system audit and exits"
    say "  NEW in v5.2:"
    dim "  apt / pkg backends — every operation goes through the real apt"
    dim "  package pickers show a live info preview (dpkg status + apt-cache)"
    dim "  the install list offers only not-installed packages; uninstall gets"
    dim "    its own finder with removal-flavoured previews"
    dim "  the banner travels INSIDE every picker (it is the header), so a"
    dim "    terminal resize can no longer wipe it off the screen"
    dim "  pickers still size below 100% so fzf never switches to the"
    dim "    alternate screen that hides them"
    dim "  if fzf itself fails, the app says so and finishes in text mode"
    say "  NEW in v5.3:"
    dim "  the screen clears before the app starts"
    dim "  every submenu picker ends with an Exit row, so the app can be left"
    dim "    from any depth — picking packages and then Exit still installs them"
    dim "  every fzf picker shows a ghost hint in its input line (type to"
    dim "    filter …), with the live count where one is meaningful"
    dim "  the menu LIST shows the bare action label only — the description,"
    dim "    what the action runs and the row number moved to the preview pane"
    dim "  the preview panel now explains what each action actually does"
    dim "    (apt install / apt purge / dpkg -L …), never a repeat of the"
    dim "    status strip"
    dim "  install/uninstall rows are capped to the list width, so a long"
    dim "    description is truncated instead of scrolling sideways into a"
    dim "    middle slice of itself — the full text stays in the preview"
    say "  NEW in v5.3.1:"
    dim "  every submenu now has TWO rows: ⬅️ Back to main menu (back a"
    dim "    level, like ESC) and 🚪 Exit pkg-manager (leave the app)"
    dim "  the upgrade center picker shows installed → candidate versions"
    dim "    inline instead of printing a list that disappears (Back row)"
    dim "  Ctrl-Q quits the app from any fzf picker, one key"
    dim "  long lists/reports now show their entry counts and rules;"
    dim "    package sizes print human-readable instead of raw bytes/KiB"
    dim "  row overflow no longer scrolls sideways (fzf gets --no-hscroll,"
    dim "    and --tiebreak ranks matches on the name first)"
    dim "  Themes → Settings → Color theme, or the theme hub in the main menu."
}

# ============================================================================
# MAX IMPROVEMENTS — integrated from exa web search results
# Sources: Termux Wiki (pkg wrapper, mirror load-balancing), Mark44928/Termux-TUI-Package-Store
# (fzf fuzzy picker, live previews, 85 slash commands, batch multi-select), APTUI (parallel
# downloads, mirror optimization, undo, progress), jpikl/pm (POSIX unified CLI, fzf preview)
# ============================================================================

FZF_CACHE_VER=2
FZF_CACHE="$HOME/.pkg-manager-fzf-cache.v$FZF_CACHE_VER"

refresh_fzf_cache() {
    local now last
    now=$(date +%s 2>/dev/null || echo 0)
    last=0
    if [ -f "$FZF_CACHE" ]; then
        last=$(stat -c %Y "$FZF_CACHE" 2>/dev/null || echo 0)
    fi
    # drop the pre-format-flip v1 cache so it is never mistaken for current
    [ -e "$HOME/.pkg-manager-fzf-cache" ] && rm -f "$HOME/.pkg-manager-fzf-cache" 2>/dev/null
    if [ "$now" -eq 0 ] || [ $((now - last)) -gt 1800 ] || [ ! -s "$FZF_CACHE" ]; then
        # INSTALL list: only packages that are NOT installed yet — already
        # installed names had to be filtered out of hundreds of rows every time.
        # Rows are "name|description" with the FULL description: the display
        # column is built (and length-capped) when the list is READ, not here,
        # so a terminal resize no longer invalidates the cache.
        {
            # stage with mktemp rather than fixed $HOME paths: a fixed name can
            # be pre-planted as a symlink and redirect the rewrite
            local inst tmp
            inst=$(mktemp "$HOME/.pkg-manager-fzf-inst.XXXXXX" 2>/dev/null) || inst=""
            tmp=$(mktemp "$HOME/.pkg-manager-fzf-cache.XXXXXX" 2>/dev/null) || tmp=""
            if [ -z "$inst" ] || [ -z "$tmp" ]; then
                err "Could not build the package cache (mktemp failed)."
                rm -f "$inst" "$tmp"; return
            fi
            dpkg-query -W -f='${Package}\n' 2>/dev/null | sort > "$inst" 2>/dev/null || : > "$inst"
            if apt-cache search ".*" 2>/dev/null | sed -E 's/^([^ ]+) - (.*)$/\1|\2/' \
                | awk -F'|' 'NR == FNR { installed[$1] = 1; next }
                    $1 != "" && !($1 in installed) && !seen[$1]++' "$inst" - \
                > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
                # sanity check: refuse to replace a good cache with an empty one
                if mv "$tmp" "$FZF_CACHE"; then
                    :
                else
                    rm -f "$tmp"
                    warn "Could not replace the package cache — keeping the old one."
                fi
            else
                rm -f "$tmp"
                warn "apt-cache search failed — keeping the old package cache."
            fi
            rm -f "$inst" 2>/dev/null || true
        }
    fi
}

# fzf_theme — build an fzf --color=... string from the active palette. Plain
# rows keep the terminal's own foreground; the accents (selected row, match
# highlight, prompt, pointer, marker, spinner) carry the theme hues so the
# picker reads multi-colored, not one flat wash.
fzf_theme() {
    printf -- '--color=fg+:%s,hl:%s,info:%s,prompt:%s,pointer:%s,marker:%s,spinner:%s,header:%s,border:%s' \
        "$GREEN" "$YELLOW" "$DIM" "$PINK" "$PINK" "$CYAN" "$GREEN" "$DIM" "$CYAN"
}

# Widest display column a picker may use: rows longer than this make fzf
# scroll the list horizontally, and a scrolled row shows a useless MIDDLE
# slice of its text ("·nes for reading and writing data files in FITS (Fle…")
# instead of the name it starts with. The preview pane takes ~45% on the side
# on wide/landscape screens, and sits below (full width) otherwise.
fzf_disp_max() {
    local cols lines n
    cols=$(term_size cols)
    lines=$(term_size lines)
    [ "$cols" -lt 20 ] && cols=80
    [ "$lines" -lt 10 ] && lines=24
    if [ "$cols" -gt 110 ] || [ "$cols" -gt $((lines * 3)) ]; then
        n=$(( cols * 55 / 100 ))
    else
        n=$cols
    fi
    n=$(( n - 8 ))          # borders, padding, gutter, pointer marker
    [ "$n" -lt 24 ] && n=24
    echo "$n"
}

# Screen-adaptive fzf geometry. A wide terminal gets a side preview pane, a
# narrow/tall one gets a bottom pane, and everything uses the full height so
# the picker gets as much room as the screen allows (pattern borrowed from
# ~/../bin/pkgs).
# term_size <cols|lines> — real terminal size when attached to a tty, else the
# shell's COLUMNS/LINES (zsh updates them on resize; tests set them), else 80/24.
# NB: a non-tty `tput cols` still succeeds with the terminfo default (80), so it
# cannot be trusted as a fallback — test for the tty instead.
term_size() {
    local sz=0
    if [ -t 1 ]; then
        if [ "$1" = "cols" ]; then sz=$(tput cols 2>/dev/null || echo 0)
        else sz=$(tput lines 2>/dev/null || echo 0); fi
    fi
    case "$sz" in ''|*[!0-9]*|0)
        if [ "$1" = "cols" ]; then sz="${COLUMNS:-0}"; else sz="${LINES:-0}"; fi
        ;; esac
    case "$sz" in ''|*[!0-9]*|0) sz=$( [ "$1" = "cols" ] && echo 80 || echo 24 ) ;; esac
    echo "$sz"
}

fzf_layout() {
    local cols lines
    cols=$(term_size cols)
    lines=$(term_size lines)
    [ "$cols" -lt 20 ] && cols=80
    [ "$lines" -lt 10 ] && lines=24
    if [ "$cols" -gt 110 ] || [ "$cols" -gt $((lines * 3)) ]; then
        printf 'right:45%%:wrap:border-left'
    else
        printf 'down:45%%:wrap:border-top'
    fi
}

# Finder height as a percentage of the terminal, ALWAYS below 100%: at 100%
# fzf enters fullscreen and switches to the alternate screen, which hides
# everything around the picker. The banner rides inside the window (it is
# the header), so the window may use nearly the whole screen — fzf shrinks
# the list to fit the header rows.
fzf_height() {
    local lines pct
    lines=$(term_size lines)
    pct=$(( (lines - 1) * 100 / lines ))
    [ "$pct" -gt 95 ] && pct=95
    [ "$pct" -lt 50 ] && pct=50
    echo "${pct}%"
}

# --margin=<top rows>,<side cols>. Top stays 0; side margins grow on roomy
# terminals for breathing room.
fzf_margin() {
    local cols
    cols=$(term_size cols)
    [ "$cols" -lt 20 ] && cols=80
    local side=2
    if [ "$cols" -ge 120 ]; then side=6; elif [ "$cols" -ge 90 ]; then side=4; fi
    echo "0,$side"
}


# Optional preview wiring for fzf_select callers (globals, since bash cannot
# return arrays): FZF_PREVIEW holds the preview shell command, FZF_NTH holds
# extra field args such as --nth/--with-nth/--delimiter, FZF_GHOST holds the
# hint text fzf shows in the input line while it is empty.
FZF_PREVIEW=""
FZF_NTH=""
FZF_GHOST=""

# fzf_select <header> <prompt> <multi:0|1> [extra fzf args...] — generic themed
# fzf picker. Choices arrive on stdin (one per line); selection goes to stdout.
# Returns 1 on abort. When FZF_PREVIEW is set, the preview pane is laid out
# from the terminal geometry and '?' toggles it.
fzf_select() {
    local header="$1" prompt="$2" multi="$3"; shift 3
    local colors
    colors=$(fzf_theme)
    # A caller may pass its own --header=...; merge it with the banner block
    # instead of letting it replace the whole header.
    local extra_header="" a
    local -a extra=()
    for a in "$@"; do
        case "$a" in
            --header=*) extra_header="${a#--header=}" ;;
            *) extra+=("$a") ;;
        esac
    done
    [ -n "$extra_header" ] && header="$extra_header"
    # The banner travels INSIDE the window, as header lines. Text printed
    # above an fzf window is static: on resize fzf re-anchors its window and
    # the static text above it is wiped for good (fzf cannot repaint it).
    header="$(banner_header)"$'\n'"$header"
    local args=(--layout=reverse --cycle --info=inline-right --header-first --height="$(fzf_height)" --border=rounded
        --header="$header" --prompt="$prompt" "$colors"
        --no-hscroll --ellipsis="…"
        '--tiebreak=begin,length,index'
        --margin="$(fzf_margin)" --padding="1,1")
    [ "$multi" = "1" ] && args+=(-m)
    args+=(--bind='ctrl-a:select-all' --bind='ctrl-d:deselect-all')
    if [ -n "$FZF_PREVIEW" ]; then
        args+=(--preview="$FZF_PREVIEW"
               --preview-window="$(fzf_layout)"
               --bind='?:toggle-preview')
        # shellcheck disable=SC2206  # FZF_NTH intentionally holds several flags
        [ -n "$FZF_NTH" ] && args+=($FZF_NTH)
    fi
    # Ghost hint in the input line (fzf >= 0.61 only).
    [ -n "$FZF_GHOST" ] && fzf_supports_ghost && args+=(--ghost="$FZF_GHOST")
    # Whole-row highlight + slim scrollbar when this fzf understands the
    # flags. The caps string is probed ONCE at startup (exported
    # APP_INIT_CAPS) so no picker pays forks for it. The probe neutralizes
    # the queue/log: the test-suite fake fzf would otherwise pop a queued
    # answer and pollute the call log.
    case "${APP_INIT_CAPS:-}" in
        *'--highlight-line'*) args+=(--highlight-line) ;;
    esac
    case "${APP_INIT_CAPS:-}" in
        *'--scrollbar'*) args+=(--scrollbar='▏') ;;
    esac
    # Ctrl-Y copies the highlighted name to the clipboard (Termux:API only —
    # without termux-clipboard-set the key is simply not bound). {1} is the
    # bare package/action name, never the display column.
    if command -v termux-clipboard-set >/dev/null 2>&1; then
        args+=(--bind="ctrl-y:execute-silent(printf '%s' {1} | termux-clipboard-set 2>/dev/null)+bell")
    fi
    # Ctrl-Q (or the "Exit pkg-manager" row): leave the app from any picker.
    # The command runs in fzf's shell, so the path is expanded here.
    local _qflag
    printf -v _qflag '%q' "${APP_EXIT_FLAG:?}"
    args+=(--bind="ctrl-q:execute-silent(touch $_qflag)+abort")
    [ "${#extra[@]}" -gt 0 ] && args+=("${extra[@]}")
    # --no-hscroll + --ellipsis: a row wider than the list pane used to be
    # H-scrolled so fzf kept the matched substring plus hscroll-off=10
    # columns visible — the user got a useless middle slice wrapped in the
    # default ellipsis string '··' (e.g. '··passphrase2pgp · Generate
    # EdDSA…··'), with the row's leading marker scrolled off the left edge.
    # --no-hscroll anchors every row at its start and cuts the tail at the
    # right edge instead; --ellipsis="…" makes a cut read as normal
    # truncation. Row pre-clipping with fzf_disp_max() stays as the second
    # belt (the full row text is also always in the preview pane).
    local rc errfile out
    errfile=$(mktemp "${TMPDIR:-$HOME}/pkgmgr-fzf-err.XXXXXX" 2>/dev/null) || errfile=/dev/null
    out=$(fzf "${args[@]}" 2>"$errfile")
    rc=$?
    local errline
    errline=$(head -n 1 "$errfile" 2>/dev/null)
    [ "$errfile" != /dev/null ] && rm -f "$errfile"
    if [ "$rc" -eq 130 ]; then
        # ESC / Ctrl-C in fzf exits 130 — a normal cancel, NOT a broken fzf.
        [ "$errfile" != /dev/null ] && rm -f "$errfile"
        return 1
    fi
    if [ "$rc" -ge 2 ]; then
        # rc 0 = picked, 1 = ESC-cancelled-with-empty. Anything else fails.
        # stderr, not stdout — callers capture fzf_select's stdout
        printf '%s\n' "$(paint "$YELLOW" "⚠ fzf failed (exit $rc)${errline:+ — $errline}")" >&2
        printf '%s\n' "$(paint "$DIM" "Switching to text mode for this session (NO_FZF=1 to force it).")" >&2
        : > "${FZF_BROKEN_FLAG:?}" 2>/dev/null || true
        return 1
    fi
    # The submenu Exit row is not a pick: strip it from the answer so no caller
    # can ever install a package called "Exit pkg-manager", and record the
    # request in the flag file — this runs inside the caller's command
    # substitution, where a variable would die with the subshell. Anything
    # ELSE the user selected stays in the answer, so "pick two, then Exit"
    # still installs the two.
    if [ -n "$OPTION_SUB_EXIT" ] && case "$out" in *"$OPTION_SUB_EXIT"*) true ;; *) false ;; esac; then
        out=$(printf '%s\n' "$out" | grep -vF "$OPTION_SUB_EXIT" || true)
        # "Back to main menu" picked alone == ESC: no answer, so the caller
        # returns one level. Anything else picked stays in the answer.
        [ -n "$out" ] || rc=1
    fi
    # The explicit app-exit row (or the ctrl-q bind below) asks to LEAVE THE
    # APP: the request rides in the flag file out of this command
    # substitution, and the main loop answers it with the farewell.
    if [ -n "$OPTION_APP_EXIT" ] && case "$out" in *"$OPTION_APP_EXIT"*) true ;; *) false ;; esac; then
        request_app_exit
        out=$(printf '%s\n' "$out" | grep -vF "$OPTION_APP_EXIT" || true)
        [ -n "$out" ] || rc=1
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
    return "$rc"
}

# list_numbered <extra_rows> <item>... — print an aligned numbered list to
# stderr. <extra_rows> counts the rows that follow the list (e.g. the Exit
# row) so the number column is uniform for every row of that list. The width
# follows the total (9 rows -> "1)", 12 rows -> " 1)") and is left in
# LIST_NUM_W for a caller that prints the trailing row itself.
# num_row <n> <item> — one numbered row: the "N)" painted in the theme accent
# (CYAN), the item text in the terminal's own foreground. Uses the row width
# list_numbered() computed so the number column stays right-aligned.
num_row() {
    printf '%s %s\n' "$(paint "$CYAN" "$(printf "%${LIST_NUM_W}d)" "$1")")" "$2"
}

list_numbered() {
    local extra_rows=$1; shift
    local n=$(($# + extra_rows))
    LIST_NUM_W=${#n}
    local i=1 o
    for o in "$@"; do num_row "$i" "$o" >&2; i=$((i+1)); done
}

# pick_menu <header> <item>... — single-select submenu picker.
# fzf → numbered text list (blank = cancel).
# The text branch prints the same 1) item … > list the app used before, so
# scripted/text-mode behavior is unchanged. Both branches append the Exit row.
pick_menu() {
    local header="$1"; shift
    if have_fzf; then
        printf '%s\n' "$@" "$OPTION_SUB_EXIT" "$OPTION_APP_EXIT" | fzf_select "$header" "❯ " 0
        return $?
    fi
    local pick exit_n app_n
    exit_n=$(( $# + 1 ))
    app_n=$(( $# + 2 ))
    list_numbered 2 "$@"
    num_row "$exit_n" "$OPTION_SUB_EXIT" >&2
    num_row "$app_n" "$OPTION_APP_EXIT" >&2
    printf '❯ ' >&2
    read -r pick
    case "$pick" in
        [1-9]|[1-9][0-9])
            if [ "$pick" -eq "$app_n" ]; then request_app_exit; return 1; fi
            if [ "$pick" -eq "$exit_n" ]; then return 1; fi
            if [ "$pick" -ge 1 ] && [ "$pick" -lt "$exit_n" ]; then
                printf '%s\n' "$@" | sed -n "${pick}p"; return 0
            fi
            return 1 ;;
        *) return 1 ;;
    esac
}

# pick_multi <header> <item>... — multi-select submenu picker (packages,
# files, snapshots). fzf -m first → space-separated
# text prompt (an optional trailing prompt string via PICK_MULTI_PROMPT).
# The Exit row is stripped from the answer before it is returned, so picking
# packages and then Exit still installs them — and then leaves the app.
pick_multi() {
    local header="$1"; shift
    if have_fzf; then
        printf '%s\n' "$@" "$OPTION_SUB_EXIT" "$OPTION_APP_EXIT" | fzf_select "$header" "❯ " 1
        return $?
    fi
    local prompt="${PICK_MULTI_PROMPT:-Pick (space-separated numbers, or n): }"
    local tok exit_n app_n
    exit_n=$(( $# + 1 ))
    app_n=$(( $# + 2 ))
    list_numbered 2 "$@"
    num_row "$exit_n" "$OPTION_SUB_EXIT" >&2
    num_row "$app_n" "$OPTION_APP_EXIT" >&2
    printf '%s' "$prompt" >&2
    read -r _picks
    case "$_picks" in ""|n|N|no) return 1 ;; esac
    local n out=""
    for tok in $_picks; do
        if [ "$tok" -eq "$exit_n" ] 2>/dev/null; then continue; fi
        if [ "$tok" -eq "$app_n" ] 2>/dev/null; then request_app_exit; continue; fi
        case "$tok" in
            [1-9]|[1-9][0-9]) n=$(printf '%s\n' "$@" | sed -n "${tok}p"); out="$out$n"$'\n' ;;
        esac
    done
    [ -n "$out" ] || return 1
    # %s, not %b — package names must never be re-interpreted as escapes
    printf '%s' "$out"
}

# pick_one <header> — single-select from a stdin list (package names, version
# lists). fzf first → numbered text prompt. Both branches append the Exit row.
pick_one() {
    local header="$1" prompt="${2:-❯ }" list sel
    list=$(cat | awk 'NF')
    if have_fzf; then
        printf '%s\n' "$list" "$OPTION_SUB_EXIT" "$OPTION_APP_EXIT" | fzf_select "$header" "$prompt" 0
        return $?
    fi
    local exit_n app_n pick n i
    exit_n=$(( $(printf '%s\n' "$list" | grep -c .) + 1 ))
    app_n=$(( exit_n + 1 ))
    # Width-aware rows (aligned when a list runs to two digits); matches the
    # exit row that pick_menu/pick_multi print.
    n=1
    mapfile -t _items <<< "$list"
    list_numbered 2 "${_items[@]}"
    num_row "$exit_n" "$OPTION_SUB_EXIT" >&2
    num_row "$app_n" "$OPTION_APP_EXIT" >&2
    printf '%s' "$prompt" >&2
    read -r pick
    case "$pick" in
        [1-9]|[1-9][0-9])
            if [ "$pick" -eq "$app_n" ]; then request_app_exit; return 1; fi
            if [ "$pick" -eq "$exit_n" ]; then return 1; fi
            printf '%s\n' "$list" | sed -n "${pick}p" ;;
        *) return 1 ;;
    esac
}

# pkg_preview_cmd [install|remove] — fzf --preview command for a package row.
# {1} is fzf's field placeholder for the first column of a "name|display" row
# (substituted before the command runs), so no shell parsing of the row is
# needed. Sizes are humanized and bat colors the record when available.
pkg_preview_cmd() {
    local mode="${1:-install}" pager="cat" action="candidate"
    command -v bat >/dev/null 2>&1 && pager="bat"
    [ "$mode" = "remove" ] && action="WILL BE REMOVED"
    printf '%s' "name={1}; [ -z \"\$name\" ] && { printf '(no package under cursor)\n'; exit 0; }; "
    printf '%s' "printf '=== %s ===\n' \"\$name\"; "
    printf '%s' "dpkg-query -W -f='\${Status} \${Version}\n' \"\$name\" 2>/dev/null | head -n1; "
    if [ "$mode" = "remove" ]; then
        printf '%s' "printf 'status: $action\n'; du -sh \"\$PREFIX/var/lib/dpkg/info/\$name\" 2>/dev/null | head -n1; "
    else
        printf '%s' "apt-cache policy \"\$name\" 2>/dev/null | sed -n 's/^  Candidate: /candidate: /p' | head -n1; "
    fi
    printf '%s' "apt-cache show -- \"\$name\" 2>/dev/null | "
    printf '%s' "awk 'BEGIN{split(\"B KB MB GB TB\",u,\" \")} /^Size:/||/^Installed-Size:/{s=\$2;i=1;while(s>=1024&&i<5){s/=1024;i++}\$2=sprintf(\"%.2f %s\",s,u[i])} {print}' | "
    if [ "$pager" = "bat" ]; then
        printf '%s' "bat --color=always --style=plain --language=yaml --paging=never 2>/dev/null || cat"
    else
        printf '%s' "cat"
    fi
}

fzf_pick_pkgs() {
    local prompt="${1:-Select packages}" mode="${2:-install}" input selected
    if ! have_fzf; then
        echo "fzf not installed. Install with: $MGR install fzf" >&2
        return 1
    fi
    local pickprompt pickheader pickfooter rcap
    rcap=$(fzf_disp_max)
    if [ "$mode" = "remove" ]; then
        # Uninstall gets its own finder: installed-only rows, its own prompt,
        # header and preview emphasis ("will be removed"). The display column
        # is built here and capped at the list-pane width: a longer row makes
        # fzf scroll the list horizontally and the user sees only a middle
        # slice of it (the full text stays in the preview pane).
        input=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort | \
            awk -F'|' -v cap="$rcap" '
                function clip(s) { return (length(s) > cap) ? substr(s, 1, cap) "…" : s }
                { print $1 "|" clip("✓ " $1 " · installed") }')
        pickprompt="remove ❯ "
        pickheader="✗ remove · ✓ select · ? preview · / search · Tab multi"
        pickfooter="installed packages only │ ESC aborts"
    else
        refresh_fzf_cache
        # Cache rows are "name|description" — clip into the display column now
        # so the rows always fit the pane, whatever the terminal is right now.
        input=$(awk -F'|' -v cap="$rcap" '
            function clip(s) { return (length(s) > cap) ? substr(s, 1, cap) "…" : s }
            { print $1 "|" clip("【 】 " $1 " · " $2) }' "$FZF_CACHE" 2>/dev/null)
        pickprompt="install ❯ "
        pickheader="＋ install · ? preview · / search · Tab multi"
        pickfooter="not-installed packages only │ ESC aborts"
    fi
    if [ -z "$input" ]; then
        echo "Package list empty. Try apt update first." >&2
        return 1
    fi
    local inst avail
    inst=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -c . || true)
    avail=$(printf '%s\n' "$input" | grep -c . || true)
    FZF_PREVIEW=$(pkg_preview_cmd "$mode")
    FZF_NTH="--delimiter=| --nth=1,2 --with-nth=2"
    # The ghost carries a real number, and it is rebuilt every time the picker
    # opens, so it can never go stale.
    FZF_GHOST="type to filter ${avail:-?} packages"
    # The Exit row rides along as a normal row (label in both fields, so the
    # pretty column and the preview show the same text). fzf_select strips it
    # from the answer and records the exit request, so picking packages and
    # then Exit still installs them.
    selected=$(printf '%s\n' "$input" "$OPTION_SUB_EXIT|$OPTION_SUB_EXIT" "$OPTION_APP_EXIT|$OPTION_APP_EXIT" | fzf_select \
        "$prompt — Tab/Space multi-select, ESC to abort" "$pickprompt" 1 \
        --header="$pickheader" \
        --footer="${inst:-?} installed · ${avail:-?} in list │ ? preview · Y copy · ESC back · ^Q quit" \
        --marker="✓ " --pointer="▶" --gutter=" " --no-separator) || selected=""
    FZF_PREVIEW=""; FZF_NTH=""; FZF_GHOST=""
    [ -z "$selected" ] && return 1
    # Field 1 of "name|display" rows is the bare name; a plain name (text-mode
    # style input, or a test feeding one line) passes through unchanged.
    printf '%s\n' "$selected" | cut -d'|' -f1 | sed '/^$/d' | filter_pkgs
}

# human_size <kb> — "1.2 MB" / "834 KB" for apt's Installed-Size in KB.
human_size() {
    local kb="$1"
    case "$kb" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$kb" -ge 1024 ]; then
        awk -v k="$kb" 'BEGIN{printf "%.1f MB", k/1024}'
    else
        printf '%s KB' "$kb"
    fi
}

batch_preview() {
    local op="$1"; shift
    local pkgs=("$@")
    local total=${#pkgs[@]}
    [ "$total" -eq 0 ] && return 0
    section "Batch preview — $op $total package(s)"
    local p ver size_kb inst_total=0 have_inst=0 unknown=0 width=0
    local -a rows=()
    # gather first so the version column aligns regardless of name lengths
    for p in "${pkgs[@]}"; do
        ver=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2; exit}')
        size_kb=$(apt-cache show "$p" 2>/dev/null | awk -F': ' '/^Installed-Size:/{print $2; exit}')
        [ -z "$ver" ] && { ver="not in repositories"; unknown=$((unknown+1)); }
        [ -n "$size_kb" ] && case "$size_kb" in *[!0-9]*) size_kb="" ;; esac
        [ -n "$size_kb" ] && inst_total=$((inst_total + size_kb))
        local tag=""
        if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
            tag="  $ICON_ERROR already installed"
            have_inst=$((have_inst+1))
        fi
        rows+=("$p|$ver$tag")
        [ ${#p} -gt "$width" ] && width=${#p}
    done
    local row
    for row in "${rows[@]}"; do
        say "$(printf '  %-*s  %s' "$width" "${row%%|*}" "${row#*|}")"
    done
    local summary="  $ICON_SIZE $total package(s)"
    [ "$inst_total" -gt 0 ] && summary="$summary · $(human_size "$inst_total") installed size"
    [ "$have_inst" -gt 0 ] && summary="$summary · $have_inst already present"
    [ "$unknown" -gt 0 ] && summary="$summary · $unknown not found"
    dim "$summary"
    [ "$unknown" -gt 0 ] && warn "  Unresolvable packages are skipped, not installed."
    hr
}

audit_log() {
    local action="$1"; shift
    local msg="${*:-}"
    local logfile="$HOME/.pkg-manager-audit.log"
    printf '%s [%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(whoami 2>/dev/null || echo "$USER")" "$action" "$msg" >> "$logfile" 2>/dev/null || true
}

do_repos() {
    local source_file="$PREFIX/etc/apt/sources.list"
    local backup_file="$HOME/pkg-repo-backup-$(date +%Y%m%d-%H%M%S).txt"
    if [ ! -f "$source_file" ]; then
        err "Sources file not found: $source_file"
        return 1
    fi
    say "$ICON_FOLDER Optional repositories — manage sources and mirrors"
    local choice=""
    local repo_items=("Show sources" "Test mirror speed" "Add repo line" "Remove line by number" "Backup sources" "Apt update" "Back")
    if have_fzf; then
        choice=$(pick_menu "Repo actions..." "${repo_items[@]}")
    else
        printf '\n1) Show sources\n2) Test mirror speed\n3) Add line\n4) Remove line\n5) Backup\n6) Apt update\n7) Back\nChoice: '
        read -r choice
    fi
    case "$choice" in
        "Show sources"|"1")
            cat -n "$source_file" ;;
        "Test mirror speed"|"2")
            do_mirror ;;
        "Add repo line"|"3")
            ask_name "Repo line (e.g. deb https://packages.termux.dev/apt/termux-main stable main)" "any"
            if [ -n "$PKG_NAME" ]; then
                # validate shape: must start with `deb` (or deb-src) and carry a
                # URI + suite — anything else breaks every apt update
                if ! printf '%s\n' "$PKG_NAME" | grep -qE '^deb(-src)?[[:space:]]+https?://[^[:space:]]+[[:space:]]+[[:alnum:]-]+[[:space:]]+[[:alnum:],-]+'; then
                    err "That doesn't look like a valid repo line (must match: deb <url> <suite> <components...>)."
                    return
                fi
                safe_cp "$source_file" "$source_file.pkg-manager.bak" || { err "Could not back up $source_file — aborting."; return; }
                # stage the new line, verify it's intact, then promote
                if ! tmp=$(scratch_new); then err "Could not create scratch for the add."; return; fi
                if ! { cat "$source_file"; printf '%s\n' "$PKG_NAME"; } > "$tmp" || ! [ -s "$tmp" ]; then
                    err "Could not build new sources.list — aborted."
                    rm -f "$tmp"; return
                fi
                if ! mv -f "$tmp" "$source_file"; then
                    err "Could not install the new sources.list."
                    rm -f "$tmp"; return
                fi
                say "Added: $PKG_NAME (backup: $source_file.pkg-manager.bak)"
                audit_log "repo_add" "$PKG_NAME"
                say "Running apt update..."
                apt update -qq 2>&1 | tail -n 3 || true
            fi ;;
        "Remove line by number"|"4")
            echo "Current lines:"
            grep -n "" "$source_file" | head -n 20
            ask_name "Line number to delete" "number"
            if [[ "$PKG_NAME" =~ ^[0-9]+$ ]]; then
                if ! sed -n "${PKG_NAME}p" "$source_file" | grep -q .; then
                    err "No line $PKG_NAME in $source_file."
                    return
                fi
                safe_cp "$source_file" "$source_file.pkg-manager.bak" || { err "Could not back up $source_file — aborting."; return; }
                if sed -i "${PKG_NAME}d" "$source_file"; then
                    say "Deleted line $PKG_NAME (backup: $source_file.pkg-manager.bak)"
                    audit_log "repo_remove" "line $PKG_NAME"
                else
                    err "sed failed — restoring backup."
                    safe_cp "$source_file.pkg-manager.bak" "$source_file"
                fi
            else
                err "Invalid number."
            fi ;;
        "Backup sources"|"5")
            if safe_cp "$source_file" "$backup_file"; then
                say "Backed up to $backup_file"
                audit_log "repo_backup" "$backup_file"
            else
                err "Could not back up $source_file."
            fi ;;
        "Apt update"|"6")
            apt update ;;
        "Back"|"7"|"") return ;;
    esac
    say "Press Enter to return to menu..."
    read -r _ < /dev/tty 2>/dev/null || true
}

# ============================================================================
# MAX 99 — extreme features from exa research: aptui (undo/redo, tabs, mirror fetch,
# transaction history), pkgtui (metrics/dashboard, dependency tree breadcrumbs, disk cleanup),
# pactool (auto-mirror, stats), glazepkg (snapshots/diffs, 36 managers), metapak (themes,
# animations, i18n, embedded console), trx (tiered fuzzy, cache, themes)
# ============================================================================

# Transaction Undo / Redo Engine (aptui-style 'z' / transaction history)
do_undo() {
    local logfile="$HOME/.pkg-manager-audit.log"
    if [ ! -f "$logfile" ]; then err "No audit log found."; return; fi
    say "$ICON_HISTORY Transaction History — last batches (batch_start lines):"
    grep -n "batch_start" "$logfile" 2>/dev/null | tail -n 10 | while read -r num line; do
        printf '  %s %s\n' "$num" "$line"
    done
    ask_name "Line number of batch to undo (from grep output)" "number"
    if [[ "$PKG_NAME" =~ ^[0-9]+$ ]]; then
        local entry; entry=$(sed -n "${PKG_NAME}p" "$logfile" 2>/dev/null)
        if echo "$entry" | grep -q "batch_start"; then
            local op; op=$(echo "$entry" | grep -oE 'batch_start [a-z]+' | awk '{print $2}')
            local pkgs; pkgs=$(echo "$entry" | sed 's/.*batch_start [a-z]* //')
            [ -z "$op" ] && op="install"
            local revert_op="remove"; [ "$op" = "remove" ] && revert_op="install"
            # audit-log tokens are not pre-validated: filter them before apt
            local clean_pkgs
            clean_pkgs=$(printf '%s\n' "$pkgs" | tr ' ' '\n' | filter_pkgs)
            if [ -n "$clean_pkgs" ]; then
                say "Reverting with: $revert_op $(printf '%s\n' "$clean_pkgs" | tr '\n' ' ')"
                if confirm_danger "Undo $op → $revert_op for $(printf '%s\n' "$clean_pkgs" | tr '\n' ' ')?"; then
                    audit_log "undo_start" "$revert_op $(printf '%s\n' "$clean_pkgs" | tr '\n' ' ')"
                    local -a _upkgs=()
                    mapfile -t _upkgs <<< "$clean_pkgs"
                    run_multi_op "$revert_op" "${_upkgs[@]}"
                    audit_log "undo_done" "$revert_op rc=$?"
                fi
            else
                err "Could not parse packages from audit line."
            fi
        else
            err "That line is not a batch_start entry."
        fi
    else
        err "Invalid line number."
    fi
}

# Colored dependency tree with breadcrumb (pkgtui / pactool style)
do_depgraph() {
    ask_name "Package for dependency tree" "pkg"
    [ -n "$PKG_NAME" ] || return
    local RED CYAN GREEN YELLOW RESET
    RED=$(tput setaf 1 2>/dev/null || printf '\033[31m')
    CYAN=$(tput setaf 6 2>/dev/null || printf '\033[36m')
    GREEN=$(tput setaf 2 2>/dev/null || printf '\033[32m')
    YELLOW=$(tput setaf 3 2>/dev/null || printf '\033[33m')
    RESET=$(tput sgr0 2>/dev/null || printf '\033[0m')
    say "$CYAN═══ DEPENDENCY TREE: $PKG_NAME ═══$RESET"
    echo "${GREEN}[FORWARD DEPENDENCIES]${RESET}"
    apt-cache depends "$PKG_NAME" 2>/dev/null | grep -E "^  [<>]?" | while read -r line; do
        local symbol=""
        case "$line" in
            *"Depends"*) symbol="${RED}├─${RESET}" ;;
            *"Recommends"*) symbol="${YELLOW}├─${RESET}" ;;
            *"Suggests"*) symbol="${CYAN}├─${RESET}" ;;
            *) symbol="${GREEN}└─${RESET}" ;;
        esac
        printf '  %s %s\n' "$symbol" "$line"
    done | head -n 30
    echo "${GREEN}[REVERSE DEPENDENCIES]${RESET}"
    apt-cache rdepends "$PKG_NAME" 2>/dev/null | grep -v "^ " | grep -v "^$" | head -n 10 | while read -r line; do
        printf '  %s %s\n' "${RED}└─${RESET}" "$line"
    done
    echo "${GREEN}[WHY INSTALLED — manual vs dependency]${RESET}"
    apt-mark showmanual 2>/dev/null | grep -qx "$PKG_NAME" && echo "  ${GREEN}Manually installed${RESET}" || echo "  ${CYAN}Pulled in as dependency${RESET}"
}

# Health / Metrics Dashboard (pkgtui M / pactool stats style)
do_health() {
    say "═══ SYSTEM HEALTH DASHBOARD ═══"
    local total installed upgradable auto_orphan
    if ! out=$(dpkg-query -W 2>/dev/null); then
        raw_known=0; installed=0
    else
        raw_known=1; installed=$(printf '%s\n' "$out" | wc -l)
    fi
    if ! out=$(apt list --upgradable 2>/dev/null); then
        upd_known=0; upgradable=0
    else
        upd_known=1; upgradable=$(printf '%s\n' "$out" | grep -cE '^[^/[:space:]]+/' || true)
    fi
    if ! out=$(apt-mark showauto 2>/dev/null); then
        orph_known=0; auto_orphan=0
    else
        orph_known=1; auto_orphan=$(printf '%s\n' "$out" | wc -l)
    fi
    if [ "$raw_known" = 1 ]; then printf '  Installed:  %s\n' "$installed"; else printf '  Installed:  ? (dpkg failed)\n'; fi
    if [ "$upd_known" = 1 ]; then printf '  Upgradable: %s\n' "$upgradable"; else printf '  Upgradable: ? (apt failed)\n'; fi
    if [ "$orph_known" = 1 ]; then printf '  Auto/Orphan:%s\n' "$auto_orphan"; else printf '  Auto/Orphan: ? (apt-mark failed)\n'; fi
    local last_audit; last_audit=$(tail -n1 "$HOME/.pkg-manager-audit.log" 2>/dev/null | awk '{print $1" "$2}')
    printf '  Last audit: %s\n' "${last_audit:-none}"
    printf '\n  Top disk users (Installed-Size):\n'
    dpkg-query -W -f='${Installed-Size} ${Package}\n' 2>/dev/null | sort -nr | head -n 6 | while read -r sz pkg; do
        printf '    %10s KB  %s\n' "$sz" "$pkg"
    done
    local cache_size; cache_size=$(du -sh "$PREFIX/var/cache/apt/archives" 2>/dev/null | cut -f1)
    printf '  Apt cache:  %s\n' "${cache_size:-unknown}"
}


use_fzf_for_op() {
    local op="$1"
    if ! have_fzf; then
        return 1
    fi
    local selected
    selected=$(fzf_pick_pkgs "Select packages for $op — Tab/Space multi-select, ESC cancels" "$op") || {
        # Silence "Canceled." when the user chose Exit — that wasn't a cancel.
        app_exit_wanted || dim "  Canceled."
        return 1
    }
    local -a pkgs=()
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && pkgs+=("$line")
    done <<< "$selected"
    [ ${#pkgs[@]} -eq 0 ] && return 1
    batch_preview "$op" "${pkgs[@]}"
    local confirm="y"
    printf 'Confirm %s %s package(s)? (y/n/d=dry-run): ' "$op" "${#pkgs[@]}" >&2
    read -r confirm
    if [ "$confirm" = "d" ]; then
        say "Dry-run — no apt command executed."
        audit_log "dryrun" "$op ${pkgs[*]}"
        return 0
    elif [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        audit_log "batch_start" "$op ${pkgs[*]}"
        run_multi_op "$op" "${pkgs[@]}"
        local rc=$?
        audit_log "batch_end" "$op ${pkgs[*]} rc=$rc"
        return $rc
    else
        say "Canceled."
        return 1
    fi
}
# ============================================================================
# MAX 99 — extreme features from exa research: aptui (undo/redo, tabs, mirror fetch,
# transaction history), pkgtui (metrics/dashboard, dependency tree breadcrumbs, disk cleanup),
# pactool (auto-mirror, stats), glazepkg (snapshots/diffs, 36 managers), metapak (themes,
# animations, i18n, embedded console), trx (tiered fuzzy, cache, themes)
# ============================================================================

# Transaction Undo / Redo Engine (aptui-style 'z' / transaction history)

# ============================================================================
# CLI MODE — non-interactive flags. Before this point options only configure
# the environment; from here any leftover arg is a misuse error.
#   --version · --help · --list-themes · --theme <name> · --export-theme <name>
# (install.sh --theme <name> uses --export-theme via the installed copy.)
# ============================================================================
case "$CLI_MODE" in
    version)
        printf 'pkg-manager v%s — Easy Termux Package Manager\n' "$VERSION"
        exit 0
        ;;
    help)
        cat <<USAGE
pkg-manager v$VERSION — Easy Termux Package Manager

Usage:
  pkg-manager                     launch the interactive app
  pkg-manager --help              this text
  pkg-manager --version           print version
  pkg-manager --list-themes       preview every theme's palette
  pkg-manager --theme <name>      set the app theme (no menu needed)
  pkg-manager --export-theme <t>  write that theme's terminal palette to
                                  ~/.termux/colors.properties (truecolor
                                  themes only; run termux-reload-settings
                                  afterwards to apply it)
  pkg-manager --check-updates    list packages with available upgrades
                                  (scriptable: prints the count and list)
  pkg-manager --quiet            print only the upgradable count (machine
                                  readable, for cron / status lines)
  pkg-manager --doctor           run the full system audit and exit

Interactive extras (inside the app):
  Settings → Command palette      filter all commands with fzf
  Install / Uninstall             fzf multi-select picker with live
                                  package previews (ESC to type a name)
  Settings → Icons                nerd-font glyphs or emoji

Docs: https://github.com/Mark44928/Easy-Termux-Package-Manager
USAGE
        exit 0
        ;;
    list-themes)
        theme_preview
        exit 0
        ;;
    set-theme)
        [ -n "${2:-}" ] || { printf 'usage: pkg-manager --theme <name> (%s)\n' "${THEME_NAMES[*]}" >&2; exit 2; }
        THEME=$2
        case "$THEME" in
            green|blue|purple|red|nord|amber|teal|mono|dracula|catppuccin|tokyo|gruvbox|onedark|solarized|everforest|rosepine) ;;
            *) printf 'unknown theme: %s (run: pkg-manager --list-themes)\n' "$THEME" >&2; exit 2 ;;
        esac
        set_theme
        save_config
        ok "Theme set to $THEME"
        exit 0
        ;;
    export-theme)
        [ -n "${2:-}" ] || { printf 'usage: pkg-manager --export-theme <name> (%s)\n' "${THEME_NAMES[*]}" >&2; exit 2; }
        apply_termux_theme "$2" || exit 1
        exit 0
        ;;
    check-updates|check-updates-quiet)
        # v5.1: scriptable upgrade check (cron / status scripts).
        # --check-updates prints a human list; --quiet prints just the count.
        # An apt failure must NOT read as "0 upgrades available".
        if ! local_up=$(list_upgradable 2>/dev/null); then
            printf 'Could not check for upgrades (apt failed).\n' >&2
            exit 1
        fi
        local_n=$(printf '%s\n' "$local_up" | grep -c . || true)
        if [ "$CLI_MODE" = "check-updates-quiet" ]; then
            printf '%s\n' "$local_n"
            exit 0
        fi
        if [ -z "$local_up" ]; then
            printf 'All packages are up to date.\n'
            exit 0
        fi
        printf '%s package(s) can be upgraded:\n' "$local_n"
        printf '%s\n' "$local_up"
        printf '\nUpgrade with: pkg-manager → Upgrade center (or: pkg upgrade)\n'
        exit 0
        ;;
    doctor)
        # v5.1: the full system audit without the menu.
        do_audit
        exit 0
        ;;
    "unknown:"*)
        printf 'unknown option: %s\n' "${CLI_MODE#unknown:}" >&2
        printf "try 'pkg-manager --help'\n" >&2
        exit 2
        ;;
    *)
        :   # CLI_MODE empty → interactive app; nothing to do
        ;;
esac

FIRST_LOOP=1
# Probe fzf capabilities once per session and EXPORT the result: fzf_select
# always runs inside a command substitution, where a fresh local variable
# would die with the subshell — so every picker would pay two `fzf --help`
# forks. The caps check honors the test-harness queue/log like the ghost
# probe does. APP_INIT_CAPS: ... unless NO_FZF/FZF missing, then never set.
if have_fzf && [ -z "$APP_INIT_CAPS" ]; then
    APP_INIT_CAPS=$(FZF_QUEUE='' FZF_CALL_LOG=/dev/null fzf --help 2>/dev/null || :)
    export APP_INIT_CAPS
fi
# Clear the screen before the interactive app starts. tty only: piped runs
# (scripts, tests) must keep their output clean.
[ -t 1 ] && printf '\033[2J\033[H'
while true; do
    if [ "$FIRST_LOOP" = "1" ] && [ "$STARTUP_CHECK" = "1" ]; then
        do_maintenance
    fi
    FIRST_LOOP=0
    banner_refresh
    # fzf mode: the banner rides inside the picker window (its header), so a
    # terminal resize cannot wipe it. Printing it here as well would show it
    # twice. Text mode has no window to carry it and prints it as before.
    have_fzf || banner
    choice=$(main_menu)
    case "$choice" in
        "$OPTION_INSTALL")    do_install ;;
        "$OPTION_UNINSTALL")  do_uninstall ;;
        "$OPTION_LIST")       do_list ;;
        "$OPTION_REINSTALL")  do_reinstall ;;
        "$OPTION_UPDATE")     do_upgrade_center ;;
        "$OPTION_CLEAN")      do_clean ;;
        "$OPTION_INFO")       do_info ;;
        "$OPTION_AUTOREMOVE") do_autoremove ;;
        "$OPTION_DEPENDS")    do_depends ;;
        "$OPTION_RDEPENDS")   do_rdepends ;;
        "$OPTION_SIZE")       do_size ;;
        "$OPTION_FILES")      do_files ;;
        "$OPTION_OWNER")      do_owner ;;
        "$OPTION_HOLD")       do_hold ;;
        "$OPTION_PURGE")      do_purge ;;
        "$OPTION_FIXBROKEN")  do_fixbroken ;;
        "$OPTION_UPGRADABLE") do_upgradable ;;
        "$OPTION_BACKUP")     do_backup ;;
        "$OPTION_RESTORE")    do_restore ;;
        "$OPTION_EXPORT")     do_export ;;
        "$OPTION_IMPORT")     do_import ;;
        "$OPTION_DOCTOR")     do_doctor ;;
        "$OPTION_SETTINGS")   do_settings ;;
        "$OPTION_HISTORY")    do_history ;;
        "$OPTION_SIMULATE")   do_simulate ;;
        "$OPTION_STATS")      do_stats ;;
        "$OPTION_CACHE")      do_cache ;;
        "$OPTION_DEPTREE")    do_deptools ;;
        "$OPTION_BULK")       do_bulk ;;
        "$OPTION_FAVS")       do_favs ;;
        "$OPTION_INSPECT")    do_inspect ;;
        "$OPTION_MAINT")      do_maintenance ;;
        "$OPTION_GROUPS")     do_groups ;;
        "$OPTION_LOCALDEB")   do_localdeb ;;
        "$OPTION_DOWNGRADE")  do_downgrade ;;
        "$OPTION_DLONLY")     do_dlonly ;;
        "$OPTION_HOLDVER")    do_holdver ;;
        "$OPTION_FILESEARCH") do_filesearch ;;
        "$OPTION_CHANGELOG")  do_changelog ;;
        "$OPTION_WHY")        do_why ;;
        "$OPTION_NOTES")       do_notes ;;
        "$OPTION_SNAPSHOT")    do_snapshot ;;
        "$OPTION_PALETTE")     do_palette ;;
        "$OPTION_WATCH")       do_watch ;;
        "$OPTION_MIRROR")      do_mirror ;;
        "$OPTION_AUDIT")       do_audit ;;
        "$OPTION_MARKS")       do_marks ;;
        "$OPTION_RECYCLE")     do_recycle ;;
        "$OPTION_REPOS")       do_repos ;;
        "$OPTION_UNDO")        do_undo ;;
        "$OPTION_DEPTREE_GRAPH") do_depgraph ;;
        "$OPTION_HEALTH")      do_health ;;
        "$OPTION_SNAPSHOT_DIFF") do_snapshot ;;
        "$OPTION_THEME")       do_theme ;;
        "$OPTION_SELFUPDATE")  do_selfupdate ;;
        "$OPTION_ESSENTIALS")  do_essentials ;;
        "$OPTION_SYSINFO")     do_sysinfo ;;
        "$OPTION_WHATSNEW")    do_whatsnew ;;
        *"Pinned:"*)           pin_install "${choice##*Pinned: }" ;;
        "$OPTION_EXIT")       say "Catch ya later! $ICON_WAVE"; break ;;
        "__INVALID__")        err "Invalid option, try again." ;;
        "")                   say "Catch ya later! $ICON_WAVE"; break ;;
        *)                    err "Invalid option, try again." ;;
    esac
    # A submenu asked to leave the app (its "Exit pkg-manager" row or Ctrl-Q):
    # the do_* levels have unwound, so quit with the farewell here.
    if app_exit_wanted; then
        say "Catch ya later! $ICON_WAVE"
        break
    fi
    pause || break
done
