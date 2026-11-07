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

VERSION="5.0"
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
cleanup_tmp() {
    local f
    for f in "${_SCRATCH[@]:-}"; do
        [ -n "$f" ] && rm -rf -- "$f" 2>/dev/null
    done
    _SCRATCH=()
}
trap cleanup_tmp EXIT

# Load .pkg-manager.conf as plain KEY=VALUE data, never `source`d: the file
# may be planted / hand-edited, and sourcing it would run arbitrary code.
load_config() {
    local line k v
    local c_mgr c_theme c_confirm c_log c_icons c_quiet c_lock c_startup c_favs c_recycle c_fzf
    [ -f "$HOME/.pkg-manager.conf" ] || return 0
    while IFS= read -r line; do
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
        blue)       CYAN=33;        PINK=208;       GREEN=76;   YELLOW=214;    RED=196;      DIM=245 ;;
        purple)     CYAN=99;        PINK=212;       GREEN=48;   YELLOW=220;    RED=196;      DIM=245 ;;
        red)        CYAN=203;       PINK=229;       GREEN=46;   YELLOW=220;    RED=196;      DIM=245 ;;
        nord)       CYAN="#88C0D0"; PINK="#B48EAD"; GREEN="#A3BE8C"; YELLOW="#EBCB8B"; RED="#BF616A"; DIM="#4C566A" ;;
        amber)      CYAN=179;       PINK=216;       GREEN=114;  YELLOW=214;    RED=203;      DIM=245 ;;
        teal)       CYAN=80;        PINK=121;       GREEN=79;   YELLOW=191;    RED=203;      DIM=245 ;;
        mono)       CYAN=252;       PINK=250;       GREEN=255;  YELLOW=253;    RED=247;      DIM=240 ;;
        dracula)    CYAN="#8BE9FD"; PINK="#FF79C6"; GREEN="#50FA7B"; YELLOW="#F1FA8C"; RED="#FF5555"; DIM="#6272A4" ;;
        catppuccin) CYAN="#94E2D5"; PINK="#CBA6F7"; GREEN="#A6E3A1"; YELLOW="#F9E2AF"; RED="#F38BA8"; DIM="#6C7086" ;;
        tokyo)      CYAN="#7DCFFF"; PINK="#BB9AF7"; GREEN="#9ECE6A"; YELLOW="#E0AF68"; RED="#F7768E"; DIM="#565F89" ;;
        gruvbox)    CYAN="#8EC07C"; PINK="#D3869B"; GREEN="#B8BB26"; YELLOW="#FABD2F"; RED="#FB4934"; DIM="#928374" ;;
        onedark)    CYAN="#56B6C2"; PINK="#C678DD"; GREEN="#98C379"; YELLOW="#E5C07B"; RED="#E06C75"; DIM="#5C6370" ;;
        solarized)  CYAN="#2AA198"; PINK="#D33682"; GREEN="#859900"; YELLOW="#B58900"; RED="#DC322F"; DIM="#586E75" ;;
        everforest) CYAN="#83C092"; PINK="#D699B6"; GREEN="#A7C080"; YELLOW="#DBBC7F"; RED="#E67E80"; DIM="#859289" ;;
        rosepine)   CYAN="#9CCFD8"; PINK="#C4A7E7"; GREEN="#31748F"; YELLOW="#F6C177"; RED="#EB6F92"; DIM="#6E6A86" ;;
        *)          CYAN=45;        PINK=212;       GREEN=46;   YELLOW=220;    RED=196;      DIM=240 ;;
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
        tokyo)      printf '%s\n' 1A1B26 C0CAF5 15161E F7768E 9ECE6A E0AF68 7AA2F7 BB9AF7 7DCFFF A9B1D6 414868 F7768E 9ECE6A E0AF68 7AA2F7 BB9AF7 7DCFFF C0CAF5 ;;
        nord)       printf '%s\n' 2E3440 D8DEE9 3B4252 BF616A A3BE8C EBCB8B 5E81AC B48EAD 88C0D0 E5E9F0 4C566A BF616A A3BE8C EBCB8B 81A1C1 B48EAD 8FBCBB ECEFF4 ;;
        gruvbox)    printf '%s\n' 282828 EBDBB2 282828 CC241D 98971A D79921 458588 B16286 689D6A A89984 928374 FB4934 B8BB26 FABD2F 83A598 D3869B 8EC07C EBDBB2 ;;
        onedark)    printf '%s\n' 282C34 ABB2BF 1E2127 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 ABB2BF 5C6370 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 FFFFFF ;;
        solarized)  printf '%s\n' 002B36 839496 073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 002B36 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3 ;;
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
have_fzf() {
    [ "$FZF_ENABLED" = "1" ] || return 1
    [ "${NO_FZF:-0}" = "1" ] && return 1
    command -v fzf >/dev/null 2>&1
}

# CLI mode — non-interactive flags (--help --version --theme --export-theme
# --list-themes) are detected here and handled after all functions are defined (before FIRST_LOOP).
case "${1:-}" in
    -h|--help|help)           CLI_MODE="help" ;;
    -V|--version|version)     CLI_MODE="version" ;;
    --list-themes)            CLI_MODE="list-themes" ;;
    --theme)                  CLI_MODE="set-theme" ;;
    --export-theme)           CLI_MODE="export-theme" ;;
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

BANNER_B64="H4sIAAAAAAACA21PMQoCMRDs84ppbW5t7OQ6S8HKaiEEkSsECwVB2MJH+Bd7n+JLbnYT5RSzm53NzCRskOvCFIC2WR1z1GStseAqQAkqgDGYyhBIwoeJWwGz0Cm/FcWWp4k3Hnegy3UvzYseS+D73epWn6GZLChBRza8PqXVv0WvWStl6pxIFucSXvfbT2JVzldsyu5Qhj3W5Ug44fnAZdHN//lHpoxgYkwBAAA="

banner() {
    local art n favs
    if ! art=$(printf '%s' "$BANNER_B64" | base64 -d 2>/dev/null | gzip -d 2>/dev/null); then
        art="TERMUX Pkg Manager v$VERSION"
    fi
    printf '%s\n' "$(paint "$CYAN" "$art")"
    # status strip: manager · theme · installed count · version
    n=$(dpkg-query -W 2>/dev/null | wc -l | tr -d ' ')
    favs=0
    [ -s "$FAVS_FILE" ] && favs=$(grep -c . "$FAVS_FILE" 2>/dev/null || echo 0)
    dim "  pkg-manager v$VERSION · manager: $MGR · theme: $THEME · installed: ${n:-?} · favorites: $favs"
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
    while IFS= read -r p; do
        valid_pkg_name "$p" && printf '%s\n' "$p"
    done
}

build_menu() {
    OPTION_INSTALL="$ICON_INSTALL Install a package"
    OPTION_UNINSTALL="$ICON_UNINSTALL Uninstall a package"
    OPTION_SEARCH="$ICON_SEARCH Search packages"
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
    OPTION_DEPTREE="$ICON_DEPENDS Dependency tree"
    OPTION_HEALTH="$ICON_SHIELD Health dashboard"
    OPTION_SNAPSHOT="$ICON_BACKUP Snapshot / Diff"
    OPTION_AUTO_MIRROR="$ICON_PLAY Auto-mirror"
    OPTION_THEME="$ICON_WAND Themes & terminal colors"
    OPTION_SELFUPDATE="$ICON_UP Update pkg-manager"
    OPTION_ESSENTIALS="$ICON_BOLT Essential toolkit"
    OPTION_SYSINFO="$ICON_GLOBE System & network info"
    OPTION_WHATSNEW="$ICON_ROCKET What's new in v$VERSION"
    OPTION_EXIT="$ICON_EXIT Exit"

    MENU_ITEMS=(
        "$OPTION_INSTALL" "$OPTION_UNINSTALL" "$OPTION_SEARCH" "$OPTION_LIST" "$OPTION_REINSTALL"
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
        "$OPTION_UNDO" "$OPTION_DEPTREE" "$OPTION_HEALTH" "$OPTION_SNAPSHOT" "$OPTION_AUTO_MIRROR" "$OPTION_SELFUPDATE"
        "$OPTION_ESSENTIALS" "$OPTION_SYSINFO" "$OPTION_WHATSNEW" "$OPTION_SETTINGS"
    )

    FAVPIN=()
    if [ "$FAVS_PINNED" = "1" ] && [ -s "$FAVS_FILE" ]; then
        local p_pin seen=" "
        while IFS= read -r p_pin; do
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
    # fzf-first: fuzzy menu whenever fzf is available and preferred (default),
    # ESC falls through to the numbered list below.
    if have_fzf; then
        local sel
        sel=$(printf '%s\n' "${opts[@]}" "$OPTION_EXIT" | fzf_select "pkg-manager v$VERSION — filter & pick (ESC for the numbered list)" "> " 0) || sel=""
        if [ -n "$sel" ]; then
            printf '%s\n' "$sel"
            return
        fi
    fi
    # Text mode with fzf available but lower priority: still prefer fzf over
    # typing numbers.
    if have_fzf; then
        sel=$(printf '%s\n' "${opts[@]}" "$OPTION_EXIT" | fzf_select "pkg-manager v$VERSION — filter & pick (ESC for the numbered list)" "> " 0) || sel=""
        if [ -n "$sel" ]; then
            printf '%s\n' "$sel"
            return
        fi
    fi
    printf '\n' >&2
        printf '%s\n' "$(paint "$PINK" "  ═══ MAIN MENU ═══")" >&2
        i=1
        for o in "${opts[@]}"; do
            printf '%s  %s\n' "$(paint "$CYAN" "[$i]")" "$o" >&2
            i=$((i+1))
        done
        printf '%s  %s\n' "$(paint "$CYAN" "[0]")" "$OPTION_EXIT" >&2
        printf '%s\n' "$(paint "$DIM" "  ───────────────")" >&2
        printf 'Choose an option: ' >&2
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
ask_name() {
    local prompt="$1" mode="${2:-pkg}"
    PKG_NAME=""
    printf '%s: ' "$prompt" >&2
    read -r PKG_NAME
    # normalize: trim surrounding whitespace and CR
    PKG_NAME=$(printf '%s\n' "$PKG_NAME" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ "$mode" = "pkg" ] && [ -n "$PKG_NAME" ] && ! valid_pkg_name "$PKG_NAME"; then
        warn "Invalid package name: '$PKG_NAME'"
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
    printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# log_err — record a real failure so the history "Errors & failures" filter is
# meaningful (log() only records successful actions and never reaches these paths).
log_err() {
    [ "$LOG_ENABLED" = "1" ] || return 0
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
        pkg list-installed 2>/dev/null | tail -n +2 | awk '{print $1}' | cut -d/ -f1
    else
        apt list --installed 2>/dev/null | tail -n +2 | cut -d/ -f1
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
    } > "$tmp"
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
        printf '1) apt\n2) pkg\n> ' >&2
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
    local labels=(
        "green (cyan/pink)" "blue (blue/orange)" "purple (purple/pink)" "red (red/yellow)"
        "nord (icy/rose · truecolor)" "amber (orange/rose)" "teal (cyan/mint)" "mono (grayscale)"
        "dracula (truecolor)" "catppuccin (truecolor)" "tokyo-night (truecolor)" "gruvbox (truecolor)"
        "one-dark (truecolor)" "solarized (truecolor)" "everforest (truecolor)" "rose-pine (truecolor)"
    )
    if have_fzf; then
        t=$(pick_menu "$ICON_THEME  Select theme (current: $THEME)" "${labels[@]}")
    else
        i=1
        for l in "${labels[@]}"; do
            printf '%d) %s\n' "$i" "$l" >&2
            i=$((i+1))
        done
        printf '> ' >&2
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
        say "Pick a truecolor theme first: nord, dracula, catppuccin, tokyo, gruvbox, onedark, solarized, everforest, rose-pine."
        return 1
    }
    mkdir -p "$dir" || { err "Cannot create $dir"; return 1; }
    if [ -f "$dir/colors.properties" ] && [ ! -f "$dir/colors.properties.pkg-manager.bak" ]; then
        cp -f "$dir/colors.properties" "$dir/colors.properties.pkg-manager.bak" \
            && dim "  existing colors backed up → $dir/colors.properties.pkg-manager.bak"
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
    } > "$tmp"
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
    if [ -f "$dir/colors.properties.pkg-manager.bak" ]; then
        mv -f "$dir/colors.properties.pkg-manager.bak" "$dir/colors.properties" \
            && ok "Restored previous $dir/colors.properties" \
            || err "Restore failed"
    else
        warn "No backup found ($dir/colors.properties.pkg-manager.bak)."
    fi
}

pause() {
    printf '\n%s' "Press Enter to continue... "
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
        return 0
    fi
    for pkg in "${uniq[@]}"; do
        if out=$("$MGR" "$op" -y "$pkg" 2>&1); then
            ok=$((ok+1))
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
    printf '%s\n' "$out" | tail -n +2
    return 0
}

do_install() {
    FZF_ABORTED=0
    if have_fzf; then
        use_fzf_for_op install
        local rc=$?
        if [ "$FZF_ABORTED" = "1" ]; then
            dim "  fzf picker canceled — type a package name instead."
        else
            return $rc
        fi
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
    FZF_ABORTED=0
    if have_fzf; then
        use_fzf_for_op remove
        local rc=$?
        if [ "$FZF_ABORTED" = "1" ]; then
            dim "  fzf picker canceled — type a package name instead."
        else
            return $rc
        fi
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

do_search() {
    ask_name "Package name or keyword to search" any
    [ -n "$PKG_NAME" ] || { warn "No search term given."; return; }
    case "$PKG_NAME" in -*)
        err "Invalid search term — must not start with '-'."
        return ;;
    esac
    log "search $PKG_NAME"
    local out installed
    installed=$(list_installed_names)
    out=$(apt search -- "$PKG_NAME" 2>/dev/null | grep -vE '^(Sorting|Full Text Search)')
    if [ -z "$out" ]; then
        err "No results — check the name or run $ICON_UPDATE Upgrade center first?"
        return
    fi
    say "$ICON_SEARCH Search results for \"$PKG_NAME\" (✓ = already installed):"
    printf '%s\n' "$out" | awk -v inst="$installed" '
        BEGIN { n=split(inst, a, "\n"); for (i=1; i<=n; i++) has[a[i]]=1 }
        /^[^ ]/ {
            pkg=$0; sub(/\/.*/, "", pkg)
            printf "%s%s\n", $0, (pkg in has ? "  ✓ [installed]" : "")
            next
        }
        { print }
    '
    local cands sel
    cands=$(printf '%s\n' "$out" | awk -v inst="$installed" '
        BEGIN { n=split(inst, a, "\n"); for (i=1; i<=n; i++) has[a[i]]=1 }
        /^[^ ]/ { pkg=$0; sub(/\/.*/, "", pkg); if (!(pkg in has)) print pkg }
    ')
    [ -n "$cands" ] || return
    say "$ICON_INSTALL Found installable packages:"
    printf '%s\n' "$cands"
    if have_fzf; then
        sel=$(printf '%s\n' "$cands" | fzf_select "Install from results — Tab/Space multi-select, ESC for none" "install> " 1) || sel=""
        [ -n "$sel" ] || { say "Nothing selected."; return; }
    else
        printf '\nInstall from these results? (space-separated names, or n): ' >&2
        read -r sel
        case "$sel" in
            ""|n|N|no) return ;;
        esac
    fi
    [ -n "$sel" ] || { say "Nothing selected."; return; }
    sel=$(printf '%s\n' "$sel" | tr ' ' '\n' | filter_pkgs)
    [ -n "$sel" ] || { warn "No valid package names."; return; }
    if confirm_danger "$ICON_INSTALL Install $(printf '%s\n' "$sel" | awk 'NF' | wc -l) package(s) from the results?"; then
        log "search install: $(printf '%s' "$sel" | tr '\n' ' ')"
        local -a _pkgs=()
        mapfile -t _pkgs <<< "$sel"
        run_multi_op install "${_pkgs[@]}"
    fi
}

do_list() {
    log "list installed packages"
    say "$ICON_LIST Installed packages:"
    local out
    if [ "$MGR" = "pkg" ]; then
        out=$(pkg list-installed 2>/dev/null | tail -n +2 | cut -d/ -f1)
    else
        out=$(apt list --installed 2>/dev/null | tail -n +2 | cut -d/ -f1)
    fi
    if [ -n "$out" ]; then
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
    say "$ICON_UPGRADABLE $n package(s) have updates:"
    printf '%s\n' "$list"
    if have_fzf; then
        local -a _upg=()
        mapfile -t _upg <<< "$pkgs"
        choice=$(printf '%s\n' "All packages" "${_upg[@]}" | pick_multi "Select what to upgrade (SPACE toggles, ENTER goes)")
    else
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
        [ -n "$sel" ] || { say "Nothing selected."; return; }
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
        | grep -E '^(Package|Version|Size|Installed-Size):' \
        | sed 's/^Size:/Download size (bytes):/; s/^Installed-Size:/Installed size (KiB):/')
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
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
    out=$(dpkg -L "$PKG_NAME" 2>&1 | tail -n +2)
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
    say "$ICON_UPGRADABLE Packages with available updates:"
    local out
    if ! out=$(list_upgradable); then
        err "Could not read the upgradable list — run $ICON_UPDATE Upgrade center first?"
        return
    fi
    if [ -n "$out" ]; then
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
            if du -h -d1 "$PREFIX" 2>/dev/null | sort -rh | head -20; then
                :
            else
                warn "Could not scan $PREFIX."
            fi
            ;;
        *Largest*)
            log "largest files"
            say "$ICON_DISK  Largest files under $PREFIX:"
            find "$PREFIX" -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 \
                | awk '{ printf "  %6.1f MiB  %s\n", $1/1048576, substr($0, index($0,"\t")+1) }'
            ;;
        Cache*)
            log "cache breakdown"
            local dir="$PREFIX/var/cache/apt/archives"
            say "$ICON_DISK  Cache breakdown:"
            if [ -d "$dir" ]; then
                du -ah "$dir" 2>/dev/null | sort -rh | head -20 || ls -lh "$dir"
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
            printf 'Packages (space-separated): ' >&2
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
            printf 'Packages (space-separated): ' >&2
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
        printf 'Numbers (space-separated): ' >&2
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
        printf 'Numbers (space-separated): ' >&2
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
                if tmp=$(scratch_new); then cat "$FAVS_FILE" > "$tmp" 2>/dev/null || true; printf '%s\n' "$PKG_NAME" >> "$tmp" && mv -f "$tmp" "$FAVS_FILE" && log "favorite add $PKG_NAME" && ok "$PKG_NAME added to favorites"; else err "Could not create temp file for favorites."; fi
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
                printf 'Pick number (0 = cancel): ' >&2
                read -r a
                case "$a" in
                    [1-9]|[1-9][0-9]) name=$(sed -n "${a}p" "$FAVS_FILE") ;;
                    *) return ;;
                esac
            fi
            [ -n "$name" ] || return
            if grep -Fxq "$name" "$FAVS_FILE"; then
                if tmp=$(scratch_new); then
                    grep -Fxv "$name" "$FAVS_FILE" > "$tmp" || true
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
                printf 'Pick number (0 = cancel): ' >&2
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
    list=$(list_installed_names)
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
            warn "python3 not found — exporting as plain text instead"
            ext="txt"
            file="${file%.json}.txt"
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
        "$ICON_THEME  Color theme: $THEME"
        "$ICON_PAINT  Icons: $ICONS"
        "$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")"
        "$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")"
        "$ICON_FOLDER  Show config file"
        "$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")"
        "$ICON_LOCK  Safety lock: $(onoff "$LOCK")"
        "$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")"
        "$ICON_TRASH  Recycle bin (archive on remove): $(onoff "$RECYCLE")"
        "$ICON_SEARCH  fzf picker: $(fzf_label)"
        "$OPTION_THEME"
        "$ICON_BACK  Back")
    if have_fzf; then
        choice=$(pick_menu "$ICON_SETTINGS  Settings" "${settings_items[@]}")
    else
        printf '1) Package manager: %s\n2) Color theme: %s\n3) Icons: %s\n4) Safety confirms: %s\n5) History log: %s\n6) Show config file\n7) Quiet mode (skip confirms): %s\n8) Safety lock: %s\n9) Maintenance on launch: %s\n10) Recycle bin (archive on remove): %s\n11) fzf picker: %s\n12) %s\n13) Back\n> ' \
            "$MGR" "$THEME" "$ICONS" "$(onoff "$CONFIRM")" "$(onoff "$LOG_ENABLED")" "$(onoff "$QUIET")" "$(onoff "$LOCK")" "$(onoff "$STARTUP_CHECK")" "$(onoff "$RECYCLE")" "$(fzf_label)" "$OPTION_THEME" >&2
        read -r choice
        case "$choice" in
             1) choice="$ICON_SLIDERS  Package manager: $MGR" ;;
             2) choice="$ICON_THEME  Color theme: $THEME" ;;
             3) choice="$ICON_PAINT  Icons: $ICONS" ;;
             4) choice="$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")" ;;
             5) choice="$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")" ;;
             6) choice="$ICON_FOLDER  Show config file" ;;
             7) choice="$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")" ;;
             8) choice="$ICON_LOCK  Safety lock: $(onoff "$LOCK")" ;;
             9) choice="$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")" ;;
             10) choice="$ICON_TRASH  Recycle bin (archive on remove): $(onoff "$RECYCLE")" ;;
             11) choice="$ICON_SEARCH  fzf picker: $(fzf_label)" ;;
             12) choice="$OPTION_THEME" ;;
             13) choice="$ICON_BACK  Back" ;;
             *) return ;;
        esac
    fi
    [ -n "$choice" ] || return
    case "$choice" in
        *"Package manager"*) set_mgr ;;
        *"Color theme"*)     set_theme_pick ;;
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
        *"Themes & terminal colors"*) do_theme ;;
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
            say "$ICON_HISTORY Action history ($LOG_FILE)"
            cat "$LOG_FILE"
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
        if dpkg -L "$PKG_NAME" 2>/dev/null | tail -n +2; then
            :
        else
            echo "(not installed — no file list)"
        fi
        printf '\n═══ Hold status ═══\n'
        if apt-mark showhold 2>/dev/null | grep -Fxq "$PKG_NAME"; then
            echo "$PKG_NAME is held."
        else
            echo "$PKG_NAME is not held."
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
        while IFS= read -r line; do
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
            if [ -f "$GROUPS_FILE" ] && grep -F -q -- "${gname}::" "$GROUPS_FILE"; then
                warn "A group named \"$gname\" already exists."
                return
            fi
            if tmp=$(scratch_new); then
                [ -f "$GROUPS_FILE" ] && cat "$GROUPS_FILE" > "$tmp" 2>/dev/null || true
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
                printf 'Pick number (0 = cancel): ' >&2
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
                    grep -F -v -- "${gname}::" "$GROUPS_FILE" > "$tmp" || true
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
        local i=1 n
        while IFS= read -r n; do
            printf '%d) %s\n' "$i" "$n" >&2
            i=$((i+1))
        done < <(group_names)
        printf 'Pick number (0 = cancel): ' >&2
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
    if [ -z "$vers" ]; then vers=$(apt-cache policy "$PKG_NAME" 2>/dev/null | grep -E '^\s+[0-9]' | awk '{print $1}' | head -20); fi
    if [ -z "$vers" ]; then err "No versions found — check name or run Upgrade center."; return; fi
    printf '%s\n' "$vers"
    local picked
    if have_fzf; then
        picked=$(printf '%s\n' "$vers" | pick_one "Pick version to downgrade to")
    else
        if ! tmp=$(scratch_new); then warn "Could not create temp file."; return; fi
        printf '%s\n' "$vers" > "$tmp"
        nl -w2 -s') ' "$tmp" >&2
        printf 'Pick number (0 = cancel): ' >&2
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
                printf '%s\n' "$vers" >&2; printf 'Version: ' >&2; read -r picked
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
    printf 'File pattern to search (e.g. bin/python): ' >&2
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
    if out=$(apt changelog "$PKG_NAME" 2>&1 | head -80) && [ -n "$out" ]; then
        printf '%s\n' "$out"
    elif out=$(apt-get changelog "$PKG_NAME" 2>&1 | head -80) && [ -n "$out" ]; then
        printf '%s\n' "$out"
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
            printf 'Note for %s: ' "$PKG_NAME" >&2; read -r note
            note=$(printf '%s\n' "$note" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/::/--/g')
            [ -n "$note" ] || { warn "No note given."; return; }
            if [ -f "$NOTES_FILE" ] && awk -F:: -v pkg="$PKG_NAME" '$1==pkg{found=1; exit} END{exit !found}' "$NOTES_FILE"; then
                if tmp=$(scratch_new); then awk -F:: -v pkg="$PKG_NAME" '$1!=pkg' "$NOTES_FILE" > "$tmp" || true; printf '%s::%s\n' "$PKG_NAME" "$note" >> "$tmp"; mv -f "$tmp" "$NOTES_FILE"; ok "Note updated for $PKG_NAME"; log "note add $PKG_NAME"; else err "Could not create temp file for notes."; fi
            else
                if tmp=$(scratch_new); then
                    [ -f "$NOTES_FILE" ] && cat "$NOTES_FILE" > "$tmp" 2>/dev/null || true
                    printf '%s::%s\n' "$PKG_NAME" "$note" >> "$tmp"; mv -f "$tmp" "$NOTES_FILE"; ok "Note added for $PKG_NAME"; log "note add $PKG_NAME"
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
                if tmp=$(scratch_new); then awk -F:: -v pkg="$PKG_NAME" '$1!=pkg' "$NOTES_FILE" > "$tmp" || true; mv -f "$tmp" "$NOTES_FILE"; ok "Note removed for $PKG_NAME"; log "note remove $PKG_NAME"; fi
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
            printf 'Search: ' >&2; read -r q
            [ -n "$q" ] || return
            grep -i -- "$q" "$NOTES_FILE" || say "No matches."
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
            list_installed_names > "$tmp" 2>/dev/null
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
                picked=$(printf '%s\n' "${snap_files[@]}" | pick_multi "Pick 2 snapshots to diff" | tr '\n' ' ')
            else
                printf 'Snapshots:\n' >&2
                local i=1
                for _s in "${snap_files[@]}"; do printf '%d) %s\n' "$i" "$_s" >&2; i=$((i+1)); done
                printf 'Pick 2 (space-separated numbers): ' >&2
                read -r picked
                picked=$(printf '%s\n' "$picked" | tr ' ' '\n' | while read -r n; do [ -n "$n" ] && printf '%s\n' "${snap_files[$((n-1))]}"; done | tr '\n' ' ')
                # shellcheck disable=SC2086
                set -- $picked
                [ $# -ge 2 ] || { say "Need 2 snapshots."; return; }
                diff -u <(tar -tzf "$1" 2>/dev/null | sort) <(tar -tzf "$2" 2>/dev/null | sort) | head -60 || true
            fi
            ;;
        Restore*)
            local file
            file=$(pick_file "Select snapshot")
            case "$file" in -* ) err "Invalid path."; return ;; esac
            [ -n "$file" ] && [ -f "$file" ] || { warn "No file."; return; }
            if ! confirm_danger "$ICON_RESTORE Restore from $file? This may overwrite favs/groups/notes."; then say "Canceled."; return; fi
            log "snapshot restore $file"
            say "$ICON_RESTORE Restoring $file..."
            if tar -tzf "$file" 2>/dev/null | grep -qE '(^/|^\.\./|\.\./)'; then
                err "Archive contains unsafe paths — aborting restore"
                return
            fi
            if tar -xzf "$file" -C "$HOME" 2>/dev/null; then ok "Snapshot restored to $HOME"; else err "Restore failed (try tar -tzf $file to inspect)"; fi
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
            mapfile -t debs < <(printf '%s\n' "$TRASH_DIR"/*.deb | xargs -n1 basename 2>/dev/null)
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
            apt-mark showmanual 2>/dev/null | head -n 50 || say "(none)"
            ;;
        "Show automatically"*)
            log "mark showauto"
            say "$ICON_CHECKBOX Automatically installed packages (first 50):"
            apt-mark showauto 2>/dev/null | head -n 50 || say "(none)"
            ;;
        "Find what provides"*)
            printf 'Package name or versioned expression (e.g. python3 (>= 3.11)): ' >&2
            read -r expr
            expr=$(printf '%s\n' "$expr" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -n "$expr" ] || { warn "Nothing to look up."; return; }
            case "$expr" in -* ) err "Expression must not start with '-'."; return ;; esac
            log "satisfies: $expr"
            say "$ICON_DEPENDS Packages providing \"$expr\":"
            if out=$(apt satisfies "$expr" 2>&1); then
                printf '%s\n' "$out" | head -n 30
            else
                err "No packages provide \"$expr\" (or apt could not resolve it)."
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
                printf 'Pick number (0 = cancel): ' >&2
                read -r p
                case "$p" in
                    [1-9]|[1-9][0-9]) p=$(sed -n "${p}p" "$WATCH_FILE") ;;
                    *) return ;;
                esac
            fi
            [ -n "$p" ] || return
            valid_pkg_name "$p" || { err "Invalid package name: '$p'"; return; }
            if tmp=$(scratch_new); then
                grep -Fxv -- "$p" "$WATCH_FILE" > "$tmp" || true
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
    while IFS= read -r p; do
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
    local -a names=() urls=()
    names+=("current"); urls+=("$cur_url")
    local -a cand_names=(
        "official (packages.termux.dev)" "cloudflare (packages-cf.termux.dev)"
        "mwt (mirror.mwt.me)" "tuna (tsinghua)" "bfsu" "nju" "iscas"
        "gnlug" "librehat" "middlendian" "krnk" "autkin"
    )
    local -a cand_urls=(
        "https://packages.termux.dev/apt/termux-main" "https://packages-cf.termux.dev/apt/termux-main"
        "https://mirror.mwt.me/termux/main" "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
        "https://mirrors.bfsu.edu.cn/termux/apt/termux-main" "https://mirrors.nju.edu.cn/termux/apt/termux-main"
        "https://mirror.iscas.ac.cn/termux/apt/termux-main" "https://gnlug.org/pub/termux/termux-main"
        "https://termux.librehat.com/apt/termux-main" "https://mirrors.middlendian.com/termux/termux-main"
        "https://mirrors.krnk.org/apt/termux/termux-main" "https://mirror.autkin.net/termux/termux-main"
    )
    local i
    for i in "${!cand_urls[@]}"; do
        [ "${cand_urls[$i]}" = "$cur_url" ] && continue
        names+=("${cand_names[$i]}")
        urls+=("${cand_urls[$i]}")
    done
    results=""
    local unreachable=0
    for i in "${!urls[@]}"; do
        t=$(curl -fsS -m 8 -o /dev/null -w '%{time_total}' "${urls[$i]}/dists/stable/Release" 2>/dev/null)
        if [ -n "$t" ]; then
            [ -n "$results" ] && results+=$'\n'
            results+="${t}"$'\t'"${names[$i]}"$'\t'"${urls[$i]}"
        else
            unreachable=$((unreachable+1))
            printf '! unreachable: %s (%s)\n' "${names[$i]}" "${urls[$i]}"
        fi
    done
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
    if ! cp -- "$target" "$backup" 2>/dev/null; then
        if [ ! -f "$target" ]; then
            mkdir -p "$PREFIX/etc/apt" 2>/dev/null || true
            : > "$target" || { err "Could not create $target"; return 1; }
        else
            err "Could not back up $target — aborting, mirror unchanged."
            return 1
        fi
    fi
    if ! tmp=$(scratch_new); then
        err "Could not create a temp file for sources.list."
        return 1
    fi
    {
        grep -v -E '^deb[[:space:]].*termux-main' "$target" 2>/dev/null
        printf '# main repo switched by Easy Termux Package Manager (backup: %s)\n' "$backup"
        printf 'deb %s stable main\n' "$best_url"
    } > "$tmp"
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
    # 1. available upgrades
    up_n=$(list_upgradable 2>/dev/null | grep -c .)
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
    out=$(apt autoremove --simulate -y 2>&1)
    orph_n=$(printf '%s\n' "$out" | awk '
        /will be REMOVED:/ {on=1; next}
        on && /upgraded|newly installed|not upgraded|after this operation/ {on=0}
        on { for (i=1;i<=NF;i++)
                if ($i ~ /^[A-Za-z][A-Za-z0-9+.:~-]*$/ && $i !~ /^[0-9][0-9.:-]+$/) print $i }' | grep -c .)
    if [ "$orph_n" -gt 0 ]; then
        score=$((score-orph_n))
        issues+=("$orph_n orphaned package(s) can be autoremoved (option 29 or 9)")
    fi
    # 3. held packages (informational)
    held_n=$(apt-mark showhold 2>/dev/null | grep -c .)
    if [ "$held_n" -gt 0 ]; then
        score=$((score-held_n*2))
        issues+=("$held_n package(s) are pinned from upgrades (informational)")
    fi
    # 4. residual config files (rc state = purged but not auto-removed)
    res_n=$(dpkg -l 2>/dev/null | awk '$1=="rc" && NF>1' | grep -c .)
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
    [ -n "$self" ] || self="$0"
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
    if cp -- "$new_tmp" "$self.new" && mv -f -- "$self.new" "$self"; then
        chmod +x "$self" 2>/dev/null || true
        log "self-update to ${remote_ver:-latest}"
        ok "Updated to ${remote_ver:-the latest version}! Restart pkg-manager to use it."
        rm -f "$new_tmp"
        return 0
    fi
    err "Failed to replace $self — nothing was changed."
    rm -f "$new_tmp" "$self.new"
    log_err "self-update: replace failed"
    return 1
}

do_palette() {
    local all
    all=$(printf '%s\n' "${MENU_ITEMS[@]}")
    local picked
    if have_fzf; then
        picked=$(printf '%s\n' "$all" | fzf_select "Command palette — type to filter" "palette> " 0) || picked=""
    else
        printf 'Palette — type substring to filter (empty for all): ' >&2
        read -r picked
        if [ -n "$picked" ]; then all=$(printf '%s\n' "$all" | grep -i -- "$picked" || printf '%s\n' "$all"); fi
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
        "$OPTION_SEARCH") do_search ;;
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
        "$OPTION_DEPTREE") do_depgraph ;;
        "$OPTION_AUTO_MIRROR") do_auto_mirror ;;
        "$OPTION_THEME") do_theme ;;
        "$OPTION_ESSENTIALS") do_essentials ;;
        "$OPTION_SYSINFO") do_sysinfo ;;
        "$OPTION_WHATSNEW") do_whatsnew ;;
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
        for b in "${bundles[@]}"; do printf '%d) %s\n' "$i" "$b" >&2; i=$((i+1)); done
        printf '6) Back\n> ' >&2
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
    dim "  solarized · everforest · rose-pine (plus the 8 legacy 256-color ones)"
    say "  Theme hub: preview every theme, and export the palette to"
    dim "  ~/.termux/colors.properties so the whole terminal matches the app"
    say "  Truecolor in plain text mode too — menus, ok/warn/err all themed"
    say "  Status strip under the banner (manager · theme · installed count)"
    say "  $ICON_BOLT Essential toolkit — one-tap curated package bundles"
    say "  $ICON_GLOBE System & network dashboard (CPU, RAM, storage, battery, DNS)"
    say "  Command palette now covers every menu entry"
    dim "  Themes → Settings → Color theme, or the theme hub in the main menu."
}

# ============================================================================
# MAX IMPROVEMENTS — integrated from exa web search results
# Sources: Termux Wiki (pkg wrapper, mirror load-balancing), Mark44928/Termux-TUI-Package-Store
# (fzf fuzzy picker, live previews, 85 slash commands, batch multi-select), APTUI (parallel
# downloads, mirror optimization, undo, progress), jpikl/pm (POSIX unified CLI, fzf preview)
# ============================================================================

FZF_CACHE="$HOME/.pkg-manager-fzf-cache"

refresh_fzf_cache() {
    local now last
    now=$(date +%s 2>/dev/null || echo 0)
    last=0
    if [ -f "$FZF_CACHE" ]; then
        last=$(stat -c %Y "$FZF_CACHE" 2>/dev/null || echo 0)
    fi
    if [ $((now - last)) -gt 1800 ] || [ ! -s "$FZF_CACHE" ]; then
        {
            dpkg-query -W -f '${Package}\n' 2>/dev/null | awk '{print "[✓] " $0}'
            apt list 2>/dev/null | awk -F/ 'NF>=2 && $1 !~ /^Listing/ {print "[ ] " $1}' | sort -u | head -n 1000
        } | awk '!seen[$0]++' > "${FZF_CACHE}.tmp" 2>/dev/null || true
        mv "${FZF_CACHE}.tmp" "$FZF_CACHE" 2>/dev/null || true
    fi
}

# fzf_theme — build an fzf --color=... string from the active palette so the
# picker matches the app (works for both 256-index and truecolor hex palettes).
fzf_theme() {
    printf -- '--color=fg:%s,hl:%s,fg+:%s,info:%s,prompt:%s,pointer:%s,marker:%s,spinner:%s,header:%s,border:%s' \
        "$CYAN" "$GREEN" "$YELLOW" "$CYAN" "$PINK" "$PINK" "$GREEN" "$CYAN" "$DIM" "$CYAN"
}

# fzf_select <header> <prompt> <multi:0|1> — generic themed fzf picker. Choices
# arrive on stdin (one per line); selection goes to stdout. Returns 1 on abort.
fzf_select() {
    local header="$1" prompt="$2" multi="$3" colors
    colors=$(fzf_theme)
    local args=(--layout=reverse --cycle --info=inline --height=40% --border=rounded
        --header="$header" --prompt="$prompt" "$colors")
    [ "$multi" = "1" ] && args+=(-m)
    args+=(--bind='ctrl-a:select-all' --bind='ctrl-d:deselect-all')
    fzf "${args[@]}" 2>/dev/null
}

# pick_menu <header> <item>... — single-select submenu picker.
# fzf → numbered text list (blank = cancel).
# The text branch prints the same 1) item … > list the app used before, so
# scripted/text-mode behavior is unchanged.
pick_menu() {
    local header="$1"; shift
    if have_fzf; then
        printf '%s\n' "$@" | fzf_select "$header" "> " 0
        return $?
    fi
    local i=1 o pick
    for o in "$@"; do printf '%d) %s\n' "$i" "$o" >&2; i=$((i+1)); done
    printf '> ' >&2
    read -r pick
    case "$pick" in
        [1-9]|[1-9][0-9])
            if [ "$pick" -ge 1 ] && [ "$pick" -le $# ]; then printf '%s\n' "$@" | sed -n "${pick}p"; return 0; fi
            return 1 ;;
        *) return 1 ;;
    esac
}

# pick_multi <header> <item>... — multi-select submenu picker (packages,
# files, snapshots). fzf -m first → space-separated
# text prompt (an optional trailing prompt string via PICK_MULTI_PROMPT).
pick_multi() {
    local header="$1"; shift
    if have_fzf; then
        printf '%s\n' "$@" | fzf_select "$header" "> " 1
        return $?
    fi
    local prompt="${PICK_MULTI_PROMPT:-Pick (space-separated numbers, or n): }"
    printf '%s' "$prompt" >&2
    read -r _picks
    case "$_picks" in ""|n|N|no) return 1 ;; esac
    local n out="" tok
    for tok in $_picks; do
        case "$tok" in
            [1-9]|[1-9][0-9]) n=$(printf '%s\n' "$@" | sed -n "${tok}p"); out="$out$n\n" ;;
        esac
    done
    [ -n "$out" ] || return 1
    printf '%b' "$out"
}

# pick_one <header> — single-select from a stdin list (package names, version
# lists). fzf first → numbered text prompt.
pick_one() {
    local header="$1" prompt="${2:-> }" list pick
    list=$(cat)
    if have_fzf; then
        printf '%s\n' "$list" | fzf_select "$header" "$prompt" 0
        return $?
    fi
    printf '%s\n' "$list" | nl -w2 -s') ' >&2
    printf '%s' "$prompt" >&2
    read -r pick
    case "$pick" in
        [1-9]|[1-9][0-9]) printf '%s\n' "$list" | sed -n "${pick}p" ;;
        *) return 1 ;;
    esac
}

fzf_pick_pkgs() {
    local prompt="${1:-Select packages}" mode="${2:-install}" input selected
    if ! have_fzf; then
        echo "fzf not installed. Install with: $MGR install fzf" >&2
        return 1
    fi
    if [ "$mode" = "remove" ]; then
        input=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | awk '{print "[✓] " $0}' | sort)
    else
        refresh_fzf_cache
        input=$(cat "$FZF_CACHE" 2>/dev/null)
    fi
    if [ -z "$input" ]; then
        echo "Package list empty. Try apt update first." >&2
        return 1
    fi
    selected=$(printf '%s\n' "$input" | fzf -m \
        --layout=reverse --cycle --info=inline --height=40% --border=rounded \
        --header="$prompt" \
        --prompt="packages> " \
        --preview='line={}; pkg=$(printf "%s" "$line" | sed "s/^\[[^]]*\] //"); printf "=== %s ===\n" "$pkg"; apt-cache show "$pkg" 2>/dev/null | head -n 12' \
        --preview-window='right:45%:wrap' \
        --bind='ctrl-a:select-all' \
        --bind='ctrl-d:deselect-all' \
        "$(fzf_theme)" \
        2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    [ -z "$selected" ] && return 1
    printf '%s\n' "$selected" | sed -E 's/^\[[^]]*\] //' | sed '/^$/d' | sort -u
}

batch_preview() {
    local op="$1"; shift
    local pkgs=("$@")
    local total=${#pkgs[@]}
    [ "$total" -eq 0 ] && return 0
    echo "=== BATCH PREVIEW ($op) ==="
    printf 'Packages: %s\n' "${pkgs[*]}"
    echo "Total: $total"
    if [ "$op" = "install" ]; then
        for p in "${pkgs[@]}"; do
            local ver; ver=$(apt-cache policy "$p" 2>/dev/null | grep 'Candidate:' | awk '{print $2}')
            printf '  %s (candidate: %s)\n' "$p" "${ver:-unknown}"
        done
    fi
    echo "============================="
}

audit_log() {
    local action="$1"; shift
    local msg="${*:-}"
    local logfile="$HOME/.pkg-manager-audit.log"
    printf '%s [%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(whoami 2>/dev/null || echo $USER)" "$action" "$msg" >> "$logfile" 2>/dev/null || true
}

do_repos() {
    local source_file="$PREFIX/etc/apt/sources.list"
    local backup_file="$HOME/pkg-repo-backup-$(date +%Y%m%d).txt"
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
            ask_name "Repo line (e.g. deb https://mirror.freedif.org/termux/termux-main stable main)" "any"
            if [ -n "$PKG_NAME" ]; then
                echo "$PKG_NAME" >> "$source_file"
                say "Added: $PKG_NAME"
                audit_log "repo_add" "$PKG_NAME"
                say "Running apt update..."
                apt update -qq 2>/dev/null || true
            fi ;;
        "Remove line by number"|"4")
            echo "Current lines:"
            grep -n "" "$source_file" | head -n 20
            ask_name "Line number to delete" "number"
            if [[ "$PKG_NAME" =~ ^[0-9]+$ ]]; then
                sed -i "${PKG_NAME}d" "$source_file"
                say "Deleted line $PKG_NAME"
                audit_log "repo_remove" "line $PKG_NAME"
            else
                err "Invalid number."
            fi ;;
        "Backup sources"|"5")
            cp "$source_file" "$backup_file"
            say "Backed up to $backup_file"
            audit_log "repo_backup" "$backup_file" ;;
        "Apt update"|"6")
            apt update ;;
        "Back"|"7"|"") return ;;
    esac
    say "Press Enter to return to menu..."
    read -r _ < /dev/tty 2>/dev/null || true
}

use_fzf_for_op() {
    # Sets FZF_ABORTED=1 when the fzf picker itself was aborted (ESC), so
    # callers can fall back to the typed-name prompt. Distinguish confirm-cancel.
    FZF_ABORTED=0
    local op="$1"
    if ! have_fzf; then
        FZF_ABORTED=1
        return 1
    fi
    local selected
    selected=$(fzf_pick_pkgs "Select packages for $op — Tab/Space multi-select, ESC to abort" "$op") || { FZF_ABORTED=1; return 1; }
    local -a pkgs=()
    while IFS= read -r line; do
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
            if [ -n "$pkgs" ]; then
                say "Reverting with: $revert_op $pkgs"
                if confirm_danger "Undo $op → $revert_op for $pkgs?"; then
                    audit_log "undo_start" "$revert_op $pkgs"
                    run_multi_op "$revert_op" $pkgs
                    audit_log "undo_done" "$revert_op $pkgs rc=$?"
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
    say "$CYAN═══ SYSTEM HEALTH DASHBOARD ═══$RESET"
    local total installed upgradable auto_orphan
    total=$(dpkg-query -W 2>/dev/null | wc -l)
    installed=$total
    upgradable=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
    auto_orphan=$(apt-mark showauto 2>/dev/null | wc -l)
    printf '  Installed:  %s\n' "$installed"
    printf '  Upgradable: %s\n' "$upgradable"
    printf '  Auto/Orphan:%s\n' "$auto_orphan"
    local last_audit; last_audit=$(tail -n1 "$HOME/.pkg-manager-audit.log" 2>/dev/null | awk '{print $1" "$2}')
    printf '  Last audit: %s\n' "${last_audit:-none}"
    echo "  ${YELLOW}Top disk users (Installed-Size):${RESET}"
    dpkg-query -W -f='${Installed-Size} ${Package}\n' 2>/dev/null | sort -nr | head -n 6 | while read -r sz pkg; do
        printf '    %10s KB  %s\n' "$sz" "$pkg"
    done
    local cache_size; cache_size=$(du -sh "$PREFIX/var/cache/apt/archives" 2>/dev/null | cut -f1)
    printf '  Apt cache:  %s\n' "${cache_size:-unknown}"
}

# Auto-mirror optimization (pactool / aptui mirror-fetch style)
do_auto_mirror() {
    local arch_part; arch_part=$(uname -m)
    local source_file="$PREFIX/etc/apt/sources.list"
    [ -f "$source_file" ] || { err "No sources file."; return; }
    say "Testing mirrors (curl latency)..."
    local best_url="" best_time=999999
    local urls=(
        "https://mirror.freedif.org/termux/termux-main"
        "https://packages.termux.dev/apt/termux-main"
        "https://termux-archive.repo/enstry.net/packages/termux"
    )
    for url in "${urls[@]}"; do
        local t; t=$(curl -o /dev/null -s -w "%{time_total}" --max-time 3 --connect-timeout 2 "$url/${arch_part}/dpkg.status" 2>/dev/null || echo 999)
        local t_int; t_int=$(printf '%d' "${t%.*}" 2>/dev/null || echo 999)
        if [ "$t_int" -lt "$best_time" ]; then best_time="$t_int"; best_url="$url"; fi
    done
    if [ -n "$best_url" ]; then
        say "Fastest: $best_url (${best_time}s)"
        if confirm_danger "Apply $best_url to sources.list?"; then
            # Replace domain part while keeping path structure
            local old_domain; old_domain=$(grep -oE '^deb https://[^/]+/termux/termux-main' "$source_file" 2>/dev/null | awk '{print $3}' | sed 's|/termux/termux-main||' | head -n1)
            if [ -n "$old_domain" ]; then
                sed -i "s|$old_domain|${best_url}|g" "$source_file"
            else
                echo "deb $best_url stable main" > "$source_file"
            fi
            audit_log "mirror_auto" "$best_url"
            say "Updated. Running apt update..."
            apt update -qq 2>/dev/null || true
        fi
    else
        err "Mirror test failed."
    fi
}

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
while true; do
    if [ "$FIRST_LOOP" = "1" ] && [ "$STARTUP_CHECK" = "1" ]; then
        do_maintenance
    fi
    FIRST_LOOP=0
    banner
    choice=$(main_menu)
    case "$choice" in
        "$OPTION_INSTALL")    do_install ;;
        "$OPTION_UNINSTALL")  do_uninstall ;;
        "$OPTION_SEARCH")     do_search ;;
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
        "$OPTION_DEPTREE")     do_depgraph ;;
        "$OPTION_HEALTH")      do_health ;;
        "$OPTION_SNAPSHOT")    do_snapshot ;;
        "$OPTION_AUTO_MIRROR") do_auto_mirror ;;
        "$OPTION_THEME")       do_theme ;;
        "$OPTION_SELFUPDATE")  do_selfupdate ;;
        "$OPTION_ESSENTIALS")  do_essentials ;;
        "$OPTION_SYSINFO")     do_sysinfo ;;
        "$OPTION_WHATSNEW")    do_whatsnew ;;
        *"Pinned:"*)           pin_install "${choice##*Pinned: }" ;;
        "$OPTION_EXIT")       say "Catch ya later! $ICON_WAVE"; break ;;
        "__INVALID__")        err "Invalid option, try again." ;;
        "")                   break ;;
        *)                    err "Invalid option, try again." ;;
    esac
    pause || break
done
