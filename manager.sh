#!/bin/bash

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

[ -f "$HOME/.pkg-manager.conf" ] && source "$HOME/.pkg-manager.conf"

case "$MGR" in apt|pkg) ;; *) MGR="apt" ;; esac
case "$THEME" in green|blue|purple|red) ;; *) THEME="green" ;; esac
case "$CONFIRM" in 0|1) ;; *) CONFIRM=1 ;; esac
case "$LOG_ENABLED" in 0|1) ;; *) LOG_ENABLED=1 ;; esac
case "$GUM_ENABLED" in 0|1) ;; *) GUM_ENABLED=1 ;; esac
case "$ICONS" in nerd|emoji) ;; *) ICONS="nerd" ;; esac

[ -n "$MGR_ENV" ] && MGR=$MGR_ENV
[ -n "$THEME_ENV" ] && THEME=$THEME_ENV
[ -n "$CONFIRM_ENV" ] && CONFIRM=$CONFIRM_ENV
[ -n "$LOG_ENABLED_ENV" ] && LOG_ENABLED=$LOG_ENABLED_ENV
[ -n "$GUM_ENABLED_ENV" ] && GUM_ENABLED=$GUM_ENABLED_ENV
[ -n "$ICONS_ENV" ] && ICONS=$ICONS_ENV
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
    else
        ICON_INSTALL=$'\uEB29'; ICON_UNINSTALL=$'\uEA81'
        ICON_SEARCH=$'\uEA6D';  ICON_LIST=$'\uEB84'
        ICON_REINSTALL=$'\uF0AD'; ICON_UPDATE=$'\uEB37'
        ICON_CLEAN=$'\uEDE4';   ICON_INFO=$'\uEA74'
        ICON_AUTOREMOVE=$'\uF1F8'; ICON_DEPENDS=$'\uF0C1'
        ICON_RDEPENDS=$'\uE725'; ICON_SIZE=$'\uF24E'
        ICON_FILES=$'\uF07B';   ICON_OWNER=$'\uF02B'
        ICON_HOLD=$'\uF08D';    ICON_PURGE=$'\uF1E2'
        ICON_FIXBROKEN=$'\uED74'; ICON_UPGRADABLE=$'\uF080'
        ICON_BACKUP=$'\uF0C7';  ICON_RESTORE=$'\uF2EA'
        ICON_EXPORT=$'\uF0EE';  ICON_IMPORT=$'\uF0ED'
        ICON_DOCTOR=$'\uF0F1';  ICON_SETTINGS=$'\uF013'
        ICON_HISTORY=$'\uF1DA'; ICON_EXIT=$'\uEDF5'
        ICON_THEME=$'\uEFCC';   ICON_SLIDERS=$'\uF1DE'
        ICON_SHIELD=$'\uEB53';  ICON_MEMO=$'\uED7B'
        ICON_FOLDER=$'\uF07C';  ICON_WAND=$'\uEBCF'
        ICON_WAVE=$'\uF259';    ICON_UP=$'\uF062'
        ICON_BACK=$'\uF060';    ICON_PAINT=$'\uF1FC'
    fi
}
init_icons

LOG_FILE="$HOME/.pkg-manager.log"

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
        echo "    pkg install gum"
        printf "Install gum now? [y/N] "
        read -r _yn
        if [[ "${_yn,,}" == "y" ]]; then
            if pkg install -y gum >/dev/null 2>&1; then
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

BANNER_B64="H4sICGbcbmoCA2FydF92MTQudHh0AG1PMQoCMRDs84ppbW4RLOU6S8HKaiEEkSsECwVB2MJH+Bd7n+JLbnYT5RSzm53NzCRskOvCFIC2WR1z1GStseAqQAkqgDGYyhBIwoeJWwGz0Cm/FcWWp4k3Hnegy3UvzYseS+D73epWn6GZLChBRza8PqXVv0WvWStl6pxIFufofd1vP4lVOV+xKbtDGfZYlyPhhOcDl3m3+ONPIyyVBGtNAQAA"

banner() {
    local art
    if ! art=$(printf '%s' "$BANNER_B64" | base64 -d 2>/dev/null | gzip -d 2>/dev/null); then
        art="TERMUX Pkg Manager v1.4"
    fi
    if [ "$GUM" = "1" ]; then
        gum style --foreground "$CYAN" --border double --border-foreground "$PINK" --padding "1 1" --align center "$art"
    else
        printf '%s\n' "$art"
    fi
}

build_menu() {
    OPTION_INSTALL="$ICON_INSTALL Install a package"
    OPTION_UNINSTALL="$ICON_UNINSTALL Uninstall a package"
    OPTION_SEARCH="$ICON_SEARCH Search packages"
    OPTION_LIST="$ICON_LIST List installed packages"
    OPTION_REINSTALL="$ICON_REINSTALL Reinstall / repair a package"
    OPTION_UPDATE="$ICON_UPDATE Update all packages"
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
    OPTION_HISTORY="$ICON_HISTORY View history log"
    OPTION_EXIT="$ICON_EXIT Exit"
}
build_menu

main_menu() {
    if [ "$GUM" = "1" ]; then
        gum choose --header "Pick an option..." --cursor "➜ " --cursor.foreground "$PINK" --selected.foreground "$CYAN" \
            "$OPTION_INSTALL" "$OPTION_UNINSTALL" "$OPTION_SEARCH" "$OPTION_LIST" "$OPTION_REINSTALL" \
            "$OPTION_UPDATE" "$OPTION_CLEAN" "$OPTION_INFO" "$OPTION_AUTOREMOVE" \
            "$OPTION_DEPENDS" "$OPTION_RDEPENDS" "$OPTION_SIZE" "$OPTION_FILES" "$OPTION_OWNER" \
            "$OPTION_HOLD" "$OPTION_PURGE" "$OPTION_FIXBROKEN" "$OPTION_UPGRADABLE" \
            "$OPTION_BACKUP" "$OPTION_RESTORE" "$OPTION_EXPORT" "$OPTION_IMPORT" \
            "$OPTION_DOCTOR" "$OPTION_SETTINGS" "$OPTION_HISTORY" "$OPTION_EXIT"
    else
        printf '\n' >&2
        printf '[1]  %s\n' "$OPTION_INSTALL" >&2
        printf '[2]  %s\n' "$OPTION_UNINSTALL" >&2
        printf '[3]  %s\n' "$OPTION_SEARCH" >&2
        printf '[4]  %s\n' "$OPTION_LIST" >&2
        printf '[5]  %s\n' "$OPTION_REINSTALL" >&2
        printf '[6]  %s\n' "$OPTION_UPDATE" >&2
        printf '[7]  %s\n' "$OPTION_CLEAN" >&2
        printf '[8]  %s\n' "$OPTION_INFO" >&2
        printf '[9]  %s\n' "$OPTION_AUTOREMOVE" >&2
        printf '[10] %s\n' "$OPTION_DEPENDS" >&2
        printf '[11] %s\n' "$OPTION_RDEPENDS" >&2
        printf '[12] %s\n' "$OPTION_SIZE" >&2
        printf '[13] %s\n' "$OPTION_FILES" >&2
        printf '[14] %s\n' "$OPTION_OWNER" >&2
        printf '[15] %s\n' "$OPTION_HOLD" >&2
        printf '[16] %s\n' "$OPTION_PURGE" >&2
        printf '[17] %s\n' "$OPTION_FIXBROKEN" >&2
        printf '[18] %s\n' "$OPTION_UPGRADABLE" >&2
        printf '[19] %s\n' "$OPTION_BACKUP" >&2
        printf '[20] %s\n' "$OPTION_RESTORE" >&2
        printf '[21] %s\n' "$OPTION_EXPORT" >&2
        printf '[22] %s\n' "$OPTION_IMPORT" >&2
        printf '[23] %s\n' "$OPTION_DOCTOR" >&2
        printf '[24] %s\n' "$OPTION_SETTINGS" >&2
        printf '[25] %s\n' "$OPTION_HISTORY" >&2
        printf '[0]  %s\n' "$OPTION_EXIT" >&2
        printf 'Choose an option: ' >&2
        if ! read -r n; then
            echo "$OPTION_EXIT"
            return
        fi
        case "$n" in
            1)  echo "$OPTION_INSTALL" ;;
            2)  echo "$OPTION_UNINSTALL" ;;
            3)  echo "$OPTION_SEARCH" ;;
            4)  echo "$OPTION_LIST" ;;
            5)  echo "$OPTION_REINSTALL" ;;
            6)  echo "$OPTION_UPDATE" ;;
            7)  echo "$OPTION_CLEAN" ;;
            8)  echo "$OPTION_INFO" ;;
            9)  echo "$OPTION_AUTOREMOVE" ;;
            10) echo "$OPTION_DEPENDS" ;;
            11) echo "$OPTION_RDEPENDS" ;;
            12) echo "$OPTION_SIZE" ;;
            13) echo "$OPTION_FILES" ;;
            14) echo "$OPTION_OWNER" ;;
            15) echo "$OPTION_HOLD" ;;
            16) echo "$OPTION_PURGE" ;;
            17) echo "$OPTION_FIXBROKEN" ;;
            18) echo "$OPTION_UPGRADABLE" ;;
            19) echo "$OPTION_BACKUP" ;;
            20) echo "$OPTION_RESTORE" ;;
            21) echo "$OPTION_EXPORT" ;;
            22) echo "$OPTION_IMPORT" ;;
            23) echo "$OPTION_DOCTOR" ;;
            24) echo "$OPTION_SETTINGS" ;;
            25) echo "$OPTION_HISTORY" ;;
            0)  echo "$OPTION_EXIT" ;;
            *)  echo "__INVALID__" ;;
        esac
    fi
}

ask_name() {
    local prompt="$1"
    PKG_NAME=""
    if [ "$GUM" = "1" ]; then
        PKG_NAME=$(gum input --prompt "➜ " --placeholder "$prompt" --width 40)
    else
        printf '%s' "$prompt: "
        read -r PKG_NAME
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

onoff() { [ "$1" = "1" ] && printf 'on' || printf 'off'; }

confirm() {
    [ "$CONFIRM" = "1" ] || return 0
    if [ "$GUM" = "1" ]; then
        gum confirm "$1" && return 0 || return 1
    else
        printf '%s [y/N]: ' "$1"
        read -r _a
        [ "${_a,,}" = "y" ]
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
    local tmp="$HOME/.pkg-manager.conf.tmp"
    {
        printf 'MGR=%s\n' "$MGR"
        printf 'THEME=%s\n' "$THEME"
        printf 'CONFIRM=%s\n' "$CONFIRM"
        printf 'LOG_ENABLED=%s\n' "$LOG_ENABLED"
        printf 'GUM_ENABLED=%s\n' "$GUM_ENABLED"
        printf 'ICONS=%s\n' "$ICONS"
    } > "$tmp"
    mv -f "$tmp" "$HOME/.pkg-manager.conf"
    printf '✓ Settings saved → %s\n' "$HOME/.pkg-manager.conf"
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
        *"not installed, so not removed"*)      echo "Package is not installed — nothing to remove or purge." ;;
        *"is not installed"*)                   echo "Package is not installed." ;;
        *"Could not get lock"*|*"dpkg is locked"*) echo "Another package operation is running — wait a moment and retry." ;;
        *"Failed to fetch"*)                   echo "Network or repository error while downloading." ;;
        *"held broken packages"*)               echo "Held or broken packages blocked the fix — try Pin/hold or fix manually." ;;
        *"depends on"*|*"has unmet dependencies"*) echo "Unmet dependencies — run Fix broken packages." ;;
        *)                                      echo "" ;;
    esac
}

do_install() {
    ask_name "Package name to install"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    log "install $PKG_NAME"
    say "$ICON_INSTALL Installing $PKG_NAME..."
    local out hint
    if out=$("$MGR" install -y "$PKG_NAME" 2>&1); then
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
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_uninstall() {
    ask_name "Package name to uninstall"
    [ -n "$PKG_NAME" ] || { warn "No package name given."; return; }
    if ! confirm "$ICON_UNINSTALL  Really uninstall $PKG_NAME?"; then
        say "Canceled."
        return
    fi
    log "remove $PKG_NAME"
    say "$ICON_UNINSTALL  Removing $PKG_NAME..."
    local out hint
    if out=$("$MGR" remove -y "$PKG_NAME" 2>&1); then
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
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_search() {
    ask_name "Package name or keyword to search"
    [ -n "$PKG_NAME" ] || { warn "No search term given."; return; }
    log "search $PKG_NAME"
    say "$ICON_SEARCH Search results for \"$PKG_NAME\":"
    apt search "$PKG_NAME" 2>/dev/null || err "Search failed — run $ICON_UPDATE Update all first?"
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
    log "reinstall $PKG_NAME"
    say "$ICON_REINSTALL Reinstalling $PKG_NAME..."
    local out hint
    if out=$("$MGR" install --reinstall -y "$PKG_NAME" 2>&1); then
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
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_update() {
    log "update all packages"
    say "$ICON_UPDATE Updating package lists..."
    if ! run_spin "Checking for updates..." "$MGR" update; then
        err "Update failed — not upgrading."
        return
    fi
    say "$ICON_UP  Upgrading packages..."
    local out hint
    if out=$("$MGR" upgrade -y 2>&1); then
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            ok "$hint"
        else
            ok "All packages are up to date!"
        fi
    else
        hint=$(apt_hint "$out")
        if [ -n "$hint" ]; then
            err "$hint"
        else
            err "Upgrade failed."
        fi
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_clean() {
    if ! confirm "$ICON_CLEAN Clear the download cache?"; then
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
        err "Package not found — check the name or run $ICON_UPDATE Update all first?"
    fi
}

do_autoremove() {
    if ! confirm "$ICON_AUTOREMOVE Remove orphaned dependencies?"; then
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
        err "Package not in cache — run $ICON_UPDATE Update all first?"
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
    ask_name "File path (e.g. $PREFIX/bin/python)"
    file="$PKG_NAME"
    [ -n "$file" ] || { warn "No file given."; return; }
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
    if ! confirm "$ICON_PURGE Purge $PKG_NAME (remove + config)?"; then
        say "Canceled."
        return
    fi
    log "purge $PKG_NAME"
    say "$ICON_PURGE Purging $PKG_NAME..."
    local out hint
    if out=$(apt purge -y "$PKG_NAME" 2>&1); then
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
        printf '%s\n' "$out" | tail -n 4
    fi
}

do_fixbroken() {
    if ! confirm "$ICON_FIXBROKEN Run apt --fix-broken install?"; then
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
    if ! out=$(apt list --upgradable 2>/dev/null | tail -n +2); then
        err "Could not read the upgradable list — run $ICON_UPDATE Update all first?"
        return
    fi
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        ok "All packages are up to date!"
    fi
}

do_backup() {
    local file
    file="$HOME/pkg-backup-$(date +%Y%m%d-%H%M%S).txt"
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
    local file="$1" action="$2" list fail lines
    list=$(awk '$0 ~ /^[A-Za-z0-9+.:~-]+$/ {print}' "$file")
    [ -n "$list" ] || { err "No valid package names in $file"; return 1; }
    if ! fail=$(printf '%s\n' "$list" | xargs "$MGR" install -y 2>&1); then
        lines=$(printf '%s\n' "$fail" | tail -n 5)
        err "$action failed — see output below."
        [ -n "$lines" ] && printf '%s\n' "$lines"
        return 1
    fi
}

do_restore() {
    local file
    file=$(pick_file "Select a backup file")
    [ -n "$file" ] && [ -f "$file" ] || { warn "No file selected."; return; }
    if ! confirm "$ICON_RESTORE  Restore $(wc -l < "$file") packages from $(basename "$file")?"; then
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
    list=$(list_installed_names)
    count=$(printf '%s\n' "$list" | awk 'NF' | wc -l)
    if [ "$ext" = "json" ]; then
        if command -v python3 >/dev/null 2>&1; then
            printf '%s\n' "$list" | python3 -c 'import sys,json; p=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps({"packages":p}, indent=2))' > "$file"
        else
            warn "python3 not found — exporting as plain text instead"
            ext="txt"
            file="${file%.json}.txt"
            printf '%s\n' "$list" > "$file"
        fi
    else
        printf '%s\n' "$list" > "$file"
    fi
    log "export → $file"
    ok "Exported $count packages → $file"
}

do_import() {
    local file
    file=$(pick_file "Select a package list file")
    [ -n "$file" ] && [ -f "$file" ] || { warn "No file selected."; return; }
    if ! confirm "$ICON_IMPORT Install $(wc -l < "$file") packages from $(basename "$file")?"; then
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
        if confirm "Install:${missing[*]} ?"; then
            log "install helpers:${missing[*]}"
            if apt install -y "${missing[@]}" 2>/dev/null; then
                ok "Installed:${missing[*]}"
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
            "$ICON_BACK  Back")
    else
        printf '1) Package manager: %s\n2) Color theme: %s\n3) Gum UI: %s\n4) Icons: %s\n5) Safety confirms: %s\n6) History log: %s\n7) Show config file\n8) Back\n> ' \
            "$MGR" "$THEME" "$(onoff "$GUM_ENABLED")" "$ICONS" "$(onoff "$CONFIRM")" "$(onoff "$LOG_ENABLED")" >&2
        read -r choice
        case "$choice" in
            1) choice="$ICON_SLIDERS  Package manager: $MGR" ;;
            2) choice="$ICON_THEME  Color theme: $THEME" ;;
            3) choice="$ICON_WAND  Gum UI: $(onoff "$GUM_ENABLED")" ;;
            4) choice="$ICON_PAINT  Icons: $ICONS" ;;
            5) choice="$ICON_SHIELD  Safety confirms: $(onoff "$CONFIRM")" ;;
            6) choice="$ICON_MEMO  History log: $(onoff "$LOG_ENABLED")" ;;
            7) choice="$ICON_FOLDER  Show config file" ;;
            8) choice="$ICON_BACK  Back" ;;
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
        *) return ;;
    esac
}

do_history() {
    if [ ! -f "$LOG_FILE" ]; then
        say "No history yet — run some actions first!"
        return
    fi
    say "$ICON_HISTORY Action history ($LOG_FILE)"
    if [ "$GUM" = "1" ]; then
        gum pager < "$LOG_FILE" || cat "$LOG_FILE"
    else
        cat "$LOG_FILE"
    fi
}

while true; do
    banner
    choice=$(main_menu)
    case "$choice" in
        "$OPTION_INSTALL")    do_install ;;
        "$OPTION_UNINSTALL")  do_uninstall ;;
        "$OPTION_SEARCH")     do_search ;;
        "$OPTION_LIST")       do_list ;;
        "$OPTION_REINSTALL")  do_reinstall ;;
        "$OPTION_UPDATE")     do_update ;;
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
        "$OPTION_EXIT")       say "Catch ya later! $ICON_WAVE"; break ;;
        "__INVALID__")        err "Invalid option, try again." ;;
        "")                   break ;;
        *)                    err "Invalid option, try again." ;;
    esac
    pause || break
done
