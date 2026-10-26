#!/bin/bash

# Every pipeline must report the failure of its first command, or "apt foo |
# tail" would let real errors look like success.
set -o pipefail

# Optional env overrides (e.g. GUM_ENABLED=0 pkg-manager) — conf file still wins otherwise.
[ -v MGR ] && MGR_ENV=$MGR || MGR_ENV=""
[ -v THEME ] && THEME_ENV=$THEME || THEME_ENV=""
[ -v CONFIRM ] && CONFIRM_ENV=$CONFIRM || CONFIRM_ENV=""
[ -v LOG_ENABLED ] && LOG_ENABLED_ENV=$LOG_ENABLED || LOG_ENABLED_ENV=""
[ -v GUM_ENABLED ] && GUM_ENABLED_ENV=$GUM_ENABLED || GUM_ENABLED_ENV=""
[ -v ICONS ] && ICONS_ENV=$ICONS || ICONS_ENV=""
[ -v RECYCLE ] && RECYCLE_ENV=$RECYCLE || RECYCLE_ENV=""

MGR="apt"
THEME="green"
CONFIRM=1
LOG_ENABLED=1
GUM_ENABLED=1
ICONS="nerd"
QUIET=0
LOCK=0
STARTUP_CHECK=0
FAVS_PINNED=0
RECYCLE=0

# Scratch files: use mktemp (unique, unguessable names) so a predictable
# fixed path can't be pre-planted as a symlink to truncate a victim via the
# " >" redirect (TOCTOU / symlink attack). Track them so the EXIT trap cleans
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
    local c_mgr c_theme c_confirm c_log c_gum c_icons c_quiet c_lock c_startup c_favs c_recycle
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
            GUM_ENABLED)    c_gum=$v ;;
            ICONS)          c_icons=$v ;;
            QUIET)          c_quiet=$v ;;
            LOCK)           c_lock=$v ;;
            STARTUP_CHECK)  c_startup=$v ;;
            FAVS_PINNED)    c_favs=$v ;;
            RECYCLE)        c_recycle=$v ;;
        esac
    done < "$HOME/.pkg-manager.conf"
    [ -n "$c_mgr" ] && MGR=$c_mgr
    [ -n "$c_theme" ] && THEME=$c_theme
    [ -n "$c_confirm" ] && CONFIRM=$c_confirm
    [ -n "$c_log" ] && LOG_ENABLED=$c_log
    [ -n "$c_gum" ] && GUM_ENABLED=$c_gum
    [ -n "$c_icons" ] && ICONS=$c_icons
    [ -n "$c_quiet" ] && QUIET=$c_quiet
    [ -n "$c_lock" ] && LOCK=$c_lock
    [ -n "$c_startup" ] && STARTUP_CHECK=$c_startup
    [ -n "$c_favs" ] && FAVS_PINNED=$c_favs
    [ -n "$c_recycle" ] && RECYCLE=$c_recycle
    return 0
}
load_config

# Prefer the modern Termux prefix variable, but keep compatibility with the
# legacy PREFIX value used by older scripts. This follows the official
# Termux layout and avoids assuming generic Linux /usr paths.
TERMUX__PREFIX="${TERMUX__PREFIX:-${PREFIX:-/data/data/com.termux/files/usr}}"
PREFIX="$TERMUX__PREFIX"
export TERMUX__PREFIX PREFIX

# env overrides win over the config file
[ -n "$MGR_ENV" ] && MGR=$MGR_ENV
[ -n "$THEME_ENV" ] && THEME=$THEME_ENV
[ -n "$CONFIRM_ENV" ] && CONFIRM=$CONFIRM_ENV
[ -n "$LOG_ENABLED_ENV" ] && LOG_ENABLED=$LOG_ENABLED_ENV
[ -n "$GUM_ENABLED_ENV" ] && GUM_ENABLED=$GUM_ENABLED_ENV
[ -n "$ICONS_ENV" ] && ICONS=$ICONS_ENV
[ -n "$RECYCLE_ENV" ] && RECYCLE=$RECYCLE_ENV

# validate both the config file and any env override with the same guards
case "$MGR" in apt|pkg) ;; *) MGR="apt" ;; esac
case "$THEME" in green|blue|purple|red|nord|amber|teal|mono) ;; *) THEME="green" ;; esac
case "$CONFIRM" in 0|1) ;; *) CONFIRM=1 ;; esac
case "$LOG_ENABLED" in 0|1) ;; *) LOG_ENABLED=1 ;; esac
case "$GUM_ENABLED" in 0|1) ;; *) GUM_ENABLED=1 ;; esac
case "$ICONS" in nerd|emoji) ;; *) ICONS="nerd" ;; esac
case "$QUIET" in 0|1) ;; *) QUIET=0 ;; esac
case "$LOCK" in 0|1) ;; *) LOCK=0 ;; esac
case "$STARTUP_CHECK" in 0|1) ;; *) STARTUP_CHECK=0 ;; esac
case "$FAVS_PINNED" in 0|1) ;; *) FAVS_PINNED=0 ;; esac
case "$RECYCLE" in 0|1) ;; *) RECYCLE=0 ;; esac
unset MGR_ENV THEME_ENV CONFIRM_ENV LOG_ENABLED_ENV GUM_ENABLED_ENV ICONS_ENV RECYCLE_ENV

GREEN=46
CYAN=45
PINK=212
RED=196
YELLOW=220

set_theme() {
    case "$THEME" in
        blue)   CYAN=33;  PINK=208; GREEN=76;  YELLOW=214; RED=196 ;;
        purple) CYAN=99;  PINK=212; GREEN=48;  YELLOW=220; RED=196 ;;
        red)    CYAN=203; PINK=229; GREEN=46;  YELLOW=220; RED=196 ;;
        nord)   CYAN=110; PINK=139; GREEN=108; YELLOW=222; RED=167 ;;
        amber)  CYAN=179; PINK=216; GREEN=114; YELLOW=214; RED=203 ;;
        teal)   CYAN=80;  PINK=121; GREEN=79;  YELLOW=191; RED=203 ;;
        mono)   CYAN=252; PINK=250; GREEN=255; YELLOW=253; RED=247 ;;
        *)      CYAN=45;  PINK=212; GREEN=46;  YELLOW=220; RED=196 ;;
    esac
}
set_theme

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
    fi
}
init_icons

LOG_FILE="$HOME/.pkg-manager.log"
FAVS_FILE="$HOME/.pkg-manager-favs"
GROUPS_FILE="$HOME/.pkg-manager-groups"
WATCH_FILE="$HOME/.pkg-manager-watch"
TRASH_DIR="$HOME/pkg-trash"
UPDATE_URL="https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master/manager.sh"

refresh_gum() {
    if [ "$GUM_ENABLED" = "1" ] && command -v gum >/dev/null 2>&1 \
        && gum style "probe" >/dev/null 2>&1; then
        GUM=1
    else
        GUM=0
    fi
}

GUM=0
if [ "$GUM_ENABLED" = "1" ]; then
    if command -v gum >/dev/null 2>&1 && gum style "probe" >/dev/null 2>&1; then
        GUM=1
    elif ! command -v gum >/dev/null 2>&1; then
        echo "gum is not installed — needed for the full fancy UI."
        echo "    $MGR install gum"
        printf "Install gum now? [y/N] "
        read -r _yn
        if [[ "${_yn,,}" == "y" ]]; then
            out=""
            if out=$("$MGR" install -y gum 2>&1); then
                GUM=1
                echo "gum installed!"
            else
                echo "Failed to install gum. Continuing in basic text mode."
                printf '%s\n' "$out" | tail -n 4
            fi
        else
            echo "Continuing in basic text mode."
        fi
    else
        echo "gum is present but not working — falling back to basic text mode."
    fi
fi

say()  { if [ "$GUM" = "1" ]; then gum style --foreground "$CYAN"  "$1";   else printf '%s\n' "$1";   fi; }
ok()   { if [ "$GUM" = "1" ]; then gum style --foreground "$GREEN" "✓ $1"; else printf '✓ %s\n' "$1"; fi; }
err()  { if [ "$GUM" = "1" ]; then gum style --foreground "$RED"   "✗ $1"; else printf '✗ %s\n' "$1"; fi; }
warn() { if [ "$GUM" = "1" ]; then gum style --foreground "$YELLOW" "⚠ $1"; else printf '⚠ %s\n' "$1"; fi; }

BANNER_B64="H4sIAAAAAAACA21PMQoCMRDs84ppbW4tLOU6S8HKaiEEkSsECwVB2MJH+Bd7n+JLbnYT5RSzm53NzCRskOvCFIC2WR1z1GStseAqQAkqgDGYyhBIwoeJWwGz0Cm/FcWWp4k3Hnegy3UvzYseS+D73epWn6GZLChBRza8PqXVv0WvWStl6pxIFuc[...]

banner() {
    local art
    if ! art=$(printf '%s' "$BANNER_B64" | base64 -d 2>/dev/null | gzip -d 2>/dev/null); then
        art="TERMUX Pkg Manager v4.0"
    fi
    if [ "$GUM" = "1" ]; then
        gum style --foreground "$CYAN" --border rounded --border-foreground "$PINK" --padding "1 1" --align center "$art"
    else
        printf '%s\n' "$art"
    fi
}

# valid_pkg_name — 1 if "$1" is a safe package token for apt/dpkg: starts with
# an alphanumeric (blocks leading "-" option injection) and contains only
# package-safe characters. Rejects empty / whitespace / globs / shell metas.
valid_pkg_name() {
    case "$1" in
        ""|-*|*" "*|'|'*|*';'*|*'&'*) return 1 ;;
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
    OPTION_SELFUPDATE="$ICON_UP Update pkg-manager"
    OPTION_EXIT="$ICON_EXIT Exit"

    MENU_ITEMS=(
        "$OPTION_INSTALL" "$OPTION_UNINSTALL" "$OPTION_SEARCH" "$OPTION_LIST" "$OPTION_REINSTALL"
        "$OPTION_UPDATE" "$OPTION_CLEAN" "$OPTION_INFO" "$OPTION_AUTOREMOVE"
        "$OPTION_DEPENDS" "$OPTION_RDEPENDS" "$OPTION_SIZE" "$OPTION_FILES" "$OPTION_OWNER"
        "$OPTION_HOLD" "$OPTION_PURGE" "$OPTION_FIXBROKEN" "$OPTION_UPGRADABLE"
        "$OPTION_BACKUP" "$OPTION_RESTORE" "$OPTION_EXPORT" "$OPTION_IMPORT"
        "$OPTION_DOCTOR" "$OPTION_SETTINGS" "$OPTION_HISTORY"
        "$OPTION_SIMULATE" "$OPTION_STATS" "$OPTION_CACHE"
        "$OPTION_DEPTREE" "$OPTION_BULK" "$OPTION_FAVS"
        "$OPTION_INSPECT" "$OPTION_MAINT" "$OPTION_GROUPS"
        "$OPTION_LOCALDEB" "$OPTION_DOWNGRADE" "$OPTION_DLONLY" "$OPTION_HOLDVER" "$OPTION_FILESEARCH"
        "$OPTION_CHANGELOG" "$OPTION_WHY" "$OPTION_NOTES" "$OPTION_SNAPSHOT" "$OPTION_PALETTE"
        "$OPTION_WATCH" "$OPTION_MIRROR" "$OPTION_AUDIT" "$OPTION_MARKS" "$OPTION_RECYCLE" "$OPTION_SELFUPDATE"
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
    if [ "$GUM" = "1" ]; then
        opts+=( "$OPTION_EXIT" )
        gum choose --header "Pick an option..." --cursor "➜ " --cursor.foreground "$PINK" --selected.foreground "$CYAN" \
            "${opts[@]}"
    else
        printf '\n' >&2
        i=1
        for o in "${opts[@]}"; do
            printf '[%d]  %s\n' "$i" "$o" >&2
            i=$((i+1))
        done
        printf '[0]  %s\n' "$OPTION_EXIT" >&2
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
    fi
}

# ask_name <prompt> <pkghint> — read a value into PKG_NAME. With pkghint="pkg"
# (default for package prompts) the value is validated with valid_pkg_name;
# pass "path" to skip validation for e.g. file paths, or "any" for free text.
ask_name() {
    local prompt="$1" mode="${2:-pkg}"
    PKG_NAME=""
    if [ "$GUM" = "1" ]; then
        PKG_NAME=$(gum input --prompt "➜ " --placeholder "$prompt" --width 40)
    else
        printf '%s' "$prompt: "
        read -r PKG_NAME
    fi
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
    if [ "$GUM" = "1" ]; then
        gum spin --spinner dot --spinner.foreground "$CYAN" --title "$title" -- "$@"
    else
        printf '%s\n' "[*] $title"
        "$@"
    fi
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
        if [ "$GUM" = "1" ]; then
            gum confirm "$1" && return 0 || return 1
        else
            printf '%s [y/N]: ' "$1"
            read -r _a
            [ "${_a,,}" = "y" ]
        fi
    else
        return 0
    fi
}

confirm_danger() {
    if [ "$LOCK" = "1" ]; then
        if [ "$GUM" = "1" ]; then
            gum confirm "$1" && return 0 || return 1
        else
            printf '%s [y/N]: ' "$1"
            read -r _a
            [ "${_a,,}" = "y" ]
        fi
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
    if [ "$GUM" = "1" ]; then
        f=$(gum file --header "➜ $title" --file 2>/dev/null)
    fi
    if [ -z "$f" ]; then
        printf '%s (full path): ' "$title" >&2
        read -r f
    fi
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
        printf 'GUM_ENABLED=%s\n' "$GUM_ENABLED"
        printf 'ICONS=%s\n' "$ICONS"
        printf 'QUIET=%s\n' "$QUIET"
        printf 'LOCK=%s\n' "$LOCK"
        printf 'STARTUP_CHECK=%s\n' "$STARTUP_CHECK"
        printf 'FAVS_PINNED=%s\n' "$FAVS_PINNED"
        printf 'RECYCLE=%s\n' "$RECYCLE"
    } > "$tmp"
    if mv -f "$tmp" "$HOME/.pkg-manager.conf"; then
        printf '✓ Settings saved → %s\n' "$HOME/.pkg-manager.conf"
        return 0
    fi
    err "Failed to save settings to $HOME/.pkg-manager.conf"
    return 1
}

# rest of file unchanged beyond the prefix fix above
