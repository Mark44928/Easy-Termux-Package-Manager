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
        [ -n "$f" ] && rm -f -- "$f" 2>/dev/null
    done
    _SCRATCH=()
}
trap cleanup_tmp EXIT

# Load .pkg-manager.conf as plain KEY=VALUE data, never `source`d: the file
# may be planted / hand-edited, and sourcing it would run arbitrary code.
load_config() {
    local line k v
    local c_mgr c_theme c_confirm c_log c_gum c_icons c_quiet c_lock c_startup c_favs
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
    return 0
}
load_config

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

# env overrides win over the config file
[ -n "$MGR_ENV" ] && MGR=$MGR_ENV
[ -n "$THEME_ENV" ] && THEME=$THEME_ENV
[ -n "$CONFIRM_ENV" ] && CONFIRM=$CONFIRM_ENV
[ -n "$LOG_ENABLED_ENV" ] && LOG_ENABLED=$LOG_ENABLED_ENV
[ -n "$GUM_ENABLED_ENV" ] && GUM_ENABLED=$GUM_ENABLED_ENV
[ -n "$ICONS_ENV" ] && ICONS=$ICONS_ENV

# validate both the config file and any env override with the same guards
case "$MGR" in apt|pkg) ;; *) MGR="apt" ;; esac
case "$THEME" in green|blue|purple|red) ;; *) THEME="green" ;; esac
case "$CONFIRM" in 0|1) ;; *) CONFIRM=1 ;; esac
case "$LOG_ENABLED" in 0|1) ;; *) LOG_ENABLED=1 ;; esac
case "$GUM_ENABLED" in 0|1) ;; *) GUM_ENABLED=1 ;; esac
case "$ICONS" in nerd|emoji) ;; *) ICONS="nerd" ;; esac
case "$QUIET" in 0|1) ;; *) QUIET=0 ;; esac
case "$LOCK" in 0|1) ;; *) LOCK=0 ;; esac
case "$STARTUP_CHECK" in 0|1) ;; *) STARTUP_CHECK=0 ;; esac
case "$FAVS_PINNED" in 0|1) ;; *) FAVS_PINNED=0 ;; esac
unset MGR_ENV THEME_ENV CONFIRM_ENV LOG_ENABLED_ENV GUM_ENABLED_ENV ICONS_ENV

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
            if "$MGR" install -y gum >/dev/null 2>&1; then
                GUM=1
                echo "gum installed!"
            else
                echo "Failed to install gum. Continuing in basic text mode."
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

BANNER_B64="H4sIAAAAAAAC/21PMQoCMRDs84ppbW7FWq6zFKysFkIQuUKwUBCELXyEf7H3Kb7kZjdRTjG72dnMTMIGuS5MAWib1TFHTdYaC64ClKACGIOpDIEkfJi4FTALnfJbUWx5mnjjcQe6XPfSvOixBL7frW71GZrJghJ0ZMPrU1r9W/SatVKmzolkcS7hdb/9JFblfMWm7A5l2GNdjoQTng9cFt38nz+NtVcYPE0BAAA="

banner() {
    local art
    if ! art=$(printf '%s' "$BANNER_B64" | base64 -d 2>/dev/null | gzip -d 2>/dev/null); then
        art="TERMUX Pkg Manager v2.0"
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
        ""|-*|*" "*|*'|'*|*';'*|*'&'*) return 1 ;;
    esac
    printf '%s\n' "$1" | grep -qE '^[A-Za-z0-9][A-Za-z0-9+:._~+-]*$'
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
    if [ "$GUM" = "1" ]; then
        m=$(gum choose --header "$ICON_SLIDERS  Select package manager" "apt (default, recommended)" "pkg (Termux wrapper)")
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
    local t
    if [ "$GUM" = "1" ]; then
        t=$(gum choose --header "$ICON_THEME  Select theme" "green (cyan/pink)" "blue (blue/orange)" "purple (purple/pink)" "red (red/yellow)")
    else
        printf '1) green\n2) blue\n3) purple\n4) red\n> ' >&2
        read -r t
        case "$t" in
            1) t="green (cyan/pink)" ;;
            2) t="blue (blue/orange)" ;;
            3) t="purple (purple/pink)" ;;
            4) t="red (red/yellow)" ;;
            *) return ;;
        esac
    fi
    [ -n "$t" ] || return
    case "$t" in
        green*)  THEME="green" ;;
        blue*)   THEME="blue" ;;
        purple*) THEME="purple" ;;
        red*)    THEME="red" ;;
        *) return ;;
    esac
    set_theme
    save_config
}

pause() {
    printf '\n%s' "Press Enter to continue... "
    if ! read -r _; then
        return 1
    fi
    clear
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
    ask_name "Package name to uninstall"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm_danger "$ICON_UNINSTALL  Really uninstall $PKG_NAME?"; then
        say "Canceled."
        return
    fi
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
    out=$(apt search "$PKG_NAME" 2>/dev/null | grep -vE '^(Sorting|Full Text Search)')
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
    if [ "$GUM" = "1" ]; then
        sel=$(printf '%s\n' "$cands" | gum choose --no-limit --header "$ICON_CHECKBOX Select packages to install")
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
        if [ "$GUM" = "1" ]; then
            printf '%s\n' "$out" | gum pager 2>/dev/null || printf '%s\n' "$out"
        else
            printf '%s\n' "$out"
        fi
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
    if [ "$GUM" = "1" ]; then
        local -a _upg=()
        mapfile -t _upg <<< "$pkgs"
        choice=$(gum choose --no-limit --header "Select what to upgrade (SPACE toggles, ENTER goes)" "All packages" "${_upg[@]}")
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
        log "upgrade all"
        say "$ICON_UP  Upgrading all packages..."
        if run_spin "Upgrading..." "$MGR" upgrade -y; then
            ok "Upgrade complete!"
        else
            err "Upgrade failed."
            log_err "upgrade all: upgrade failed"
        fi
    else
        sel=$(printf '%s\n' "$choice" | filter_pkgs)
        [ -n "$sel" ] || { say "Nothing selected."; return; }
        log "upgrade: $(printf '%s' "$sel" | tr '\n' ' ')"
        say "$ICON_UP  Upgrading selected packages..."
        local -a _pkgs=()
        mapfile -t _pkgs <<< "$sel"
        run_multi_op install "${_pkgs[@]}"
    fi
    if confirm_danger "$ICON_AUTOREMOVE Remove now-unused dependencies?"; then
        if apt autoremove -y >/dev/null 2>&1; then
            ok "Autoremoved unused dependencies."
        else
            err "Autoremove failed."
            log_err "autoremove: failed"
        fi
    fi
    if confirm_danger "$ICON_CLEAN Clean the download cache?"; then
        if "$MGR" clean >/dev/null 2>&1; then
            ok "Cache cleaned!"
        else
            err "Failed to clean cache."
            log_err "clean cache: failed"
        fi
    fi
}

do_clean() {
    if ! confirm_danger "$ICON_CLEAN Clear the download cache?"; then
        say "Canceled."
        return
    fi
    log "clean cache"
    if run_spin "Cleaning cache..." "$MGR" clean; then
        ok "Cache cleaned!"
    else
        err "Failed to clean cache"
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
    log "autoremove"
    local out hint
    if out=$(apt autoremove -y 2>&1); then
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
    local out
    out=$(apt-cache show "$PKG_NAME" 2>/dev/null \
        | grep -E '^(Package|Version|Size|Installed-Size):' \
        | sed 's/^Size:/Download size (bytes):/; s/^Installed-Size:/Installed size (KiB):/')
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        err "Package not in cache — run $ICON_UPDATE Upgrade center first?"
    fi
}

do_files() {
    ask_name "Installed package name"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "files $PKG_NAME"
    say "$ICON_FILES Files installed by $PKG_NAME:"
    local out
    out=$(dpkg -L "$PKG_NAME" 2>/dev/null | tail -n +2)
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        err "Package may not be installed"
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
    dpkg -S "$file" 2>/dev/null || err "No installed package owns that file"
}

do_hold() {
    local a
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_HOLD  Pin / hold" "Hold a package" "Unhold a package" "Show held packages")
    else
        printf '1) Hold a package\n2) Unhold a package\n3) Show held packages\n> ' >&2
        read -r a
        case "$a" in
            1) a="Hold a package" ;;
            2) a="Unhold a package" ;;
            3) a="Show held packages" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        Hold*)
            ask_name "Package to hold"
            [ -n "$PKG_NAME" ] || return
            log "hold $PKG_NAME"
            if apt-mark hold "$PKG_NAME" 2>/dev/null; then ok "$PKG_NAME is now held"; else err "Failed to hold $PKG_NAME"; fi
            ;;
        Unhold*)
            ask_name "Package to unhold"
            [ -n "$PKG_NAME" ] || return
            log "unhold $PKG_NAME"
            if apt-mark unhold "$PKG_NAME" 2>/dev/null; then ok "$PKG_NAME is no longer held"; else err "Failed to unhold $PKG_NAME"; fi
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
    log "fix-broken"
    say "$ICON_FIXBROKEN Fixing broken packages..."
    local out hint
    if out=$(apt --fix-broken install -y 2>&1); then
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
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_EYE  Simulate a change" "Simulate install" "Simulate remove" "Simulate upgrade all")
    else
        printf '1) Simulate install\n2) Simulate remove\n3) Simulate upgrade all\n> ' >&2
        read -r a
        case "$a" in
            1) a="Simulate install" ;;
            2) a="Simulate remove" ;;
            3) a="Simulate upgrade all" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        *install*)
            ask_name "Package name to preview"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            log "simulate install $PKG_NAME"
            say "$ICON_EYE  Dry-run — what installing $PKG_NAME would change:"
            "$MGR" install -s "$PKG_NAME" 2>&1 || err "Could not simulate install"
            ;;
        *remove*)
            ask_name "Package name to preview"
            [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
            log "simulate remove $PKG_NAME"
            say "$ICON_EYE  Dry-run — what removing $PKG_NAME would change:"
            "$MGR" remove -s "$PKG_NAME" 2>&1 || err "Could not simulate remove"
            ;;
        *upgrade*)
            log "simulate upgrade"
            say "$ICON_EYE  Dry-run — full system upgrade preview:"
            "$MGR" upgrade -s 2>&1 || err "Could not simulate upgrade"
            ;;
    esac
}

do_stats() {
    local a
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_CHART  Package stats & disk" "Overview" "Disk usage by directory" "Largest files" "Cache breakdown" "Back")
    else
        printf '1) Overview\n2) Disk usage by directory\n3) Largest files\n4) Cache breakdown\n5) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Overview" ;;
            2) a="Disk usage by directory" ;;
            3) a="Largest files" ;;
            4) a="Cache breakdown" ;;
            5) a="Back" ;;
            *) return ;;
        esac
    fi
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
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_CACHE  Cache manager" "Clean all cached files (apt clean)" "Remove only outdated .deb (autoclean)" "Show cached files" "Back")
    else
        printf '1) Clean all cached files (apt clean)\n2) Remove only outdated .deb (autoclean)\n3) Show cached files\n4) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Clean all cached files (apt clean)" ;;
            2) a="Remove only outdated .deb (autoclean)" ;;
            3) a="Show cached files" ;;
            4) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        *"Clean all"*)
            if confirm_danger "$ICON_CACHE  Delete every cached .deb?"; then
                log "apt clean"
                if run_spin "Cleaning cache..." "$MGR" clean; then
                    ok "Cache cleaned!"
                else
                    err "Failed to clean cache."
                fi
            fi
            ;;
        *"outdated"*)
            if confirm_danger "$ICON_CACHE  Remove outdated .deb files only?"; then
                log "apt autoclean"
                if run_spin "Autocleaning..." apt autoclean; then
                    ok "Outdated packages cleaned!"
                else
                    err "Autoclean failed."
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
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_TREE  Dependency tools" "Dependency tree" "Orphan finder" "Back")
    else
        printf '1) Dependency tree\n2) Orphan finder\n3) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Dependency tree" ;;
            2) a="Orphan finder" ;;
            3) a="Back" ;;
            *) return ;;
        esac
    fi
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
                        if apt autoremove -y >/dev/null 2>&1; then
                            ok "Orphans removed!"
                        else
                            err "Autoremove failed."
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
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_BULK  Bulk operations" "Install multiple packages" "Remove multiple packages" "Remove (pick from installed list)" "Upgrade (pick from upgradable list)" "Back")
    else
        printf '1) Install multiple packages\n2) Remove multiple packages\n3) Remove (pick from installed list)\n4) Upgrade (pick from upgradable list)\n5) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Install multiple packages" ;;
            2) a="Remove multiple packages" ;;
            3) a="Remove (pick from installed list)" ;;
            4) a="Upgrade (pick from upgradable list)" ;;
            5) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        Install*)
            if [ "$GUM" = "1" ]; then
                names=$(gum input --prompt "➜ " --placeholder "Space-separated package names")
            else
                printf 'Packages (space-separated): ' >&2
                read -r names
            fi
            names=$(printf '%s\n' "$names" | tr ' ' '\n' | filter_pkgs)
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            [ "$n" -gt 0 ] || { warn "No valid package names."; return; }
            if confirm_danger "$ICON_INSTALL Install $n packages ($(printf '%s' "$names" | tr '\n' ' '))?"; then
                log "bulk install: $(printf '%s' "$names" | tr '\n' ' ')"
                say "$ICON_INSTALL Installing $n packages..."
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                run_multi_op install "${_pkgs[@]}"
            fi
            ;;
        Remove*multiple*)
            if [ "$GUM" = "1" ]; then
                names=$(gum input --prompt "➜ " --placeholder "Space-separated package names")
            else
                printf 'Packages (space-separated): ' >&2
                read -r names
            fi
            names=$(printf '%s\n' "$names" | tr ' ' '\n' | filter_pkgs)
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            [ "$n" -gt 0 ] || { warn "No valid package names."; return; }
            if confirm_danger "$ICON_UNINSTALL Remove $n packages ($(printf '%s' "$names" | tr '\n' ' '))?"; then
                log "bulk remove: $(printf '%s' "$names" | tr '\n' ' ')"
                say "$ICON_UNINSTALL Removing $n packages..."
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                run_multi_op remove "${_pkgs[@]}"
            fi
            ;;
        *"installed list"*)
            names=$(pick_names "$ICON_UNINSTALL Pick packages to remove (SPACE toggles)")
            [ -n "$names" ] || { say "Nothing selected."; return; }
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            if confirm_danger "$ICON_UNINSTALL Remove $n package(s) from the installed list?"; then
                log "bulk remove picked: $(printf '%s' "$names" | tr '\n' ' ')"
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                run_multi_op remove "${_pkgs[@]}"
            fi
            ;;
        *"upgradable list"*)
            names=$(pick_upgradable)
            [ -n "$names" ] || { say "Nothing selected."; return; }
            n=$(printf '%s\n' "$names" | awk 'NF' | wc -l)
            if confirm_danger "$ICON_UP  Upgrade $n package(s)?"; then
                log "bulk upgrade picked: $(printf '%s' "$names" | tr '\n' ' ')"
                local -a _pkgs=()
                mapfile -t _pkgs <<< "$names"
                run_multi_op install "${_pkgs[@]}"
            fi
            ;;
        *) return ;;
    esac
}

pick_names() {
    local header="$1" tmp n i sel
    if [ "$GUM" = "1" ]; then
        list_installed_names | gum choose --no-limit --header "$header" || return 1
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
    if [ "$GUM" = "1" ]; then
        printf '%s\n' "$list" | gum choose --no-limit --header "$header" || return 1
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
    fi
}

do_favs() {
    local a name n
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_STAR  Favorites" "Add favorite" "Remove favorite" "Show favorites" "Install all favorites" "Pin favorites to main menu: $(onoff "$FAVS_PINNED")" "Install one favorite" "Back")
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
                printf '%s\n' "$PKG_NAME" > "$FAVS_FILE"
                log "favorite add $PKG_NAME"
                ok "$PKG_NAME added to favorites ($FAVS_FILE)"
                return
            fi
            if grep -Fxq "$PKG_NAME" "$FAVS_FILE"; then
                warn "$PKG_NAME is already a favorite."
            else
                printf '%s\n' "$PKG_NAME" >> "$FAVS_FILE"
                log "favorite add $PKG_NAME"
                ok "$PKG_NAME added to favorites"
            fi
            [ "$FAVS_PINNED" = "1" ] && build_menu
            ;;
        Remove*)
            [ -s "$FAVS_FILE" ] || { warn "No favorites yet."; return; }
            if [ "$GUM" = "1" ]; then
                local -a _favs=()
                mapfile -t _favs < "$FAVS_FILE"
                name=$(gum choose --header "$ICON_STAR  Pick favorite to remove" "${_favs[@]}")
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
            if [ "$GUM" = "1" ]; then
                local -a _favs=()
                mapfile -t _favs < <(awk 'NF' "$FAVS_FILE")
                name=$(gum choose --header "$ICON_STAR  Pick favorite to install" "${_favs[@]}")
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
    local file
    file="$HOME/pkg-backup-$(date +%Y%m%d-%H%M%S)-$$.txt"
    say "$ICON_BACKUP Backing up installed packages..."
    if list_installed_names > "$file" 2>/dev/null && [ -s "$file" ]; then
        log "backup → $file"
        ok "Backed up $(wc -l < "$file") packages → $file"
    else
        rm -f "$file"
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
    if [ "$GUM" = "1" ]; then
        fmt=$(gum choose --header "$ICON_EXPORT  Export format" "Plain text (.txt)" "JSON (.json)")
    else
        printf '1) Plain text (.txt)\n2) JSON (.json)\n> ' >&2
        read -r fmt
        case "$fmt" in
            1) fmt="Plain text (.txt)" ;;
            2) fmt="JSON (.json)" ;;
            *) return ;;
        esac
    fi
    [ -n "$fmt" ] || return
    case "$fmt" in
        *JSON*) ext="json" ;;
        *)      ext="txt" ;;
    esac
    if [ "$GUM" = "1" ]; then
        file=$(gum input --prompt "➜ " --placeholder "Save path" --value "$HOME/pkg-export.$ext")
    else
        printf 'Save path [%s]: ' "$HOME/pkg-export.$ext"
        read -r file
    fi
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
    local missing=() dep
    say "$ICON_DOCTOR Checking helper tools..."
    for dep in gum git curl figlet; do
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
            if "$MGR" install -y "${missing[@]}" 2>/dev/null; then
                ok "Installed: ${missing[*]}"
                refresh_gum
            else
                err "Install failed"
            fi
        fi
    else
        say "All helper tools present!"
    fi
}

do_settings() {
    local choice
    if [ "$GUM" = "1" ]; then
        choice=$(gum choose --header "$ICON_SETTINGS  Settings" \
            "$ICON_SLIDERS  Package manager: $MGR" \
            "$ICON_THEME  Color theme: $THEME" \
            "$ICON_WAND  Gum UI: $(onoff "$GUM_ENABLED")" \
            "$ICON_PAINT  Icons: $ICONS" \
            "$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")" \
            "$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")" \
            "$ICON_FOLDER  Show config file" \
            "$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")" \
            "$ICON_LOCK  Safety lock: $(onoff "$LOCK")" \
            "$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")" \
            "$ICON_BACK  Back")
    else
        printf '1) Package manager: %s\n2) Color theme: %s\n3) Gum UI: %s\n4) Icons: %s\n5) Safety confirms: %s\n6) History log: %s\n7) Show config file\n8) Quiet mode (skip confirms): %s\n9) Safety lock: %s\n10) Maintenance on launch: %s\n11) Back\n> ' \
            "$MGR" "$THEME" "$(onoff "$GUM_ENABLED")" "$ICONS" "$(onoff "$CONFIRM")" "$(onoff "$LOG_ENABLED")" "$(onoff "$QUIET")" "$(onoff "$LOCK")" "$(onoff "$STARTUP_CHECK")" >&2
        read -r choice
        case "$choice" in
            1) choice="$ICON_SLIDERS  Package manager: $MGR" ;;
            2) choice="$ICON_THEME  Color theme: $THEME" ;;
            3) choice="$ICON_WAND  Gum UI: $(onoff "$GUM_ENABLED")" ;;
            4) choice="$ICON_PAINT  Icons: $ICONS" ;;
            5) choice="$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")" ;;
            6) choice="$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")" ;;
            7) choice="$ICON_FOLDER  Show config file" ;;
            8) choice="$ICON_MOON  Quiet mode (skip confirms): $(onoff "$QUIET")" ;;
            9) choice="$ICON_LOCK  Safety lock: $(onoff "$LOCK")" ;;
            10) choice="$ICON_MAINT  Maintenance on launch: $(onoff "$STARTUP_CHECK")" ;;
            11) choice="$ICON_BACK  Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$choice" ] || return
    case "$choice" in
        *"Package manager"*) set_mgr ;;
        *"Color theme"*)     set_theme_pick ;;
        *"Gum UI"*)          GUM_ENABLED=$((1-GUM_ENABLED)); refresh_gum; save_config ;;
        *"Icons"*)           if [ "$ICONS" = "nerd" ]; then ICONS="emoji"; else ICONS="nerd"; fi; init_icons; build_menu; save_config ;;
        *"Safety confirms"*) CONFIRM=$((1-CONFIRM)); save_config ;;
        *"History log"*)     LOG_ENABLED=$((1-LOG_ENABLED)); save_config ;;
        *"Show config"*)     cat "$HOME/.pkg-manager.conf" 2>/dev/null || say "No config yet." ;;
        *"Quiet mode"*)      QUIET=$((1-QUIET)); save_config ;;
        *"Safety lock"*)     LOCK=$((1-LOCK)); save_config ;;
        *"Maintenance on launch"*) STARTUP_CHECK=$((1-STARTUP_CHECK)); save_config ;;
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

do_history() {
    local a tmp
    if [ ! -f "$LOG_FILE" ]; then
        say "No history yet — run some actions first!"
        return
    fi
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_HISTORY  History & log viewer" "Show all history" "Show errors & failures" "Show installs / removals" "Undo last removal" "Clear history" "Back")
    else
        printf '1) Show all history\n2) Show errors & failures\n3) Show installs / removals\n4) Undo last removal\n5) Clear history\n6) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Show all history" ;;
            2) a="Show errors & failures" ;;
            3) a="Show installs / removals" ;;
            4) a="Undo last removal" ;;
            5) a="Clear history" ;;
            6) a="Back" ;;
            *) return ;;
        esac
    fi
    [ -n "$a" ] || return
    case "$a" in
        *"all history"*)
            say "$ICON_HISTORY Action history ($LOG_FILE)"
            if [ "$GUM" = "1" ]; then
                gum pager < "$LOG_FILE" || cat "$LOG_FILE"
            else
                cat "$LOG_FILE"
            fi
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
    if [ "$GUM" = "1" ]; then
        gum pager < "$tmp" || cat "$tmp"
    else
        cat "$tmp"
    fi
    rm -f "$tmp"
}

do_maintenance() {
    log "maintenance wizard"
    say "$ICON_MAINT  Maintenance wizard — checking your system..."
    local up orphans n broken cache held issues=0
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
        if output=$(apt --fix-broken install -y 2>&1); then
            printf '%s\n' "$output" | tail -n 5
        else
            printf '%s\n' "$output" | tail -n 5
            err "apt fix-broken failed."
            log_err "fix-broken: failed"
            issues=$((issues+1))
        fi
    fi
    if confirm_danger "$ICON_AUTOREMOVE  Remove orphaned packages now?"; then
        if output=$(apt autoremove -y 2>&1); then
            printf '%s\n' "$output" | tail -n 5
        else
            printf '%s\n' "$output" | tail -n 5
            err "apt autoremove failed."
            log_err "autoremove: failed"
            issues=$((issues+1))
        fi
    fi
    if confirm_danger "$ICON_UP  Upgrade all packages now?"; then
        if output=$("$MGR" upgrade -y 2>&1); then
            printf '%s\n' "$output" | tail -n 5
        else
            printf '%s\n' "$output" | tail -n 5
            err "upgrade failed."
            log_err "upgrade all: failed"
            issues=$((issues+1))
        fi
    fi
    if confirm "$ICON_CLEAN  Clean the download cache?"; then
        "$MGR" clean 2>/dev/null && ok "Cache cleaned."
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
    if [ "$GUM" = "1" ]; then
        a=$(gum choose --header "$ICON_GROUPS  Package groups" "Show all groups" "Install a group" "Remove a group's packages" "Create custom group" "Delete custom group" "Back")
    else
        printf '1) Show all groups\n2) Install a group\n3) Remove a group\x27s packages\n4) Create custom group\n5) Delete custom group\n6) Back\n> ' >&2
        read -r a
        case "$a" in
            1) a="Show all groups" ;;
            2) a="Install a group" ;;
            3) a="Remove a group's packages" ;;
            4) a="Create custom group" ;;
            5) a="Delete custom group" ;;
            6) a="Back" ;;
            *) return ;;
        esac
    fi
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
            if [ -f "$GROUPS_FILE" ] && grep -q "^${gname}::" "$GROUPS_FILE"; then
                warn "A group named \"$gname\" already exists."
                return
            fi
            printf '%s::%s\n' "$gname" "$(printf '%s' "$gpkgs" | tr '\n' ' ')" >> "$GROUPS_FILE"
            load_groups
            log "group create $gname"
            ok "Group \"$gname\" created."
            ;;
        Delete*)
            if [ ! -s "$GROUPS_FILE" ]; then
                warn "No custom groups to delete."
                return
            fi
            if [ "$GUM" = "1" ]; then
                mapfile -t custom_names < <(sed 's/::.*//' "$GROUPS_FILE" | grep -E '^[A-Za-z0-9 _-]+$')
                gname=$(gum choose --header "$ICON_TRASH  Pick custom group to delete" "${custom_names[@]}")
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
                    grep -v "^${gname}::" "$GROUPS_FILE" > "$tmp" || true
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
    if [ "$GUM" = "1" ]; then
        mapfile -t gnames < <(group_names)
        gum choose --header "$header" "${gnames[@]}"
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
        *"Pinned:"*)          pin_install "${choice##*Pinned: }" ;;
        "$OPTION_EXIT")       say "Catch ya later! $ICON_WAVE"; break ;;
        "__INVALID__")        err "Invalid option, try again." ;;
        "")                   break ;;
        *)                    err "Invalid option, try again." ;;
    esac
    pause || break
done
