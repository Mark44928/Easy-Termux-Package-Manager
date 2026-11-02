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
    echo "$GREEN[FORWARD DEPENDENCIES]$RESET"
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
    echo "$GREEN[REVERSE DEPENDENCIES]$RESET"
    apt-cache rdepends "$PKG_NAME" 2>/dev/null | grep -v "^ " | grep -v "^$" | head -n 10 | while read -r line; do
        printf '  %s %s\n' "${RED}└─${RESET}" "$line"
    done
    echo "$GREEN[WHY INSTALLED — manual vs dependency]$RESET"
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
        local t; t=$(curl -o /dev/null -s -w "%{time_total}" --max-time 3 --connect-timeout 2 "$url/$ARCH/dpkg.status" 2>/dev/null || echo 999)
        local t_int; t_int=$(printf '%d' "${t%.*}" 2>/dev/null || echo 999)
        if [ "$t_int" -lt "$best_time" ]; then best_time="$t_int"; best_url="$url"; fi
    done
    if [ -n "$best_url" ]; then
        say "Fastest: $best_url (${best_time}s)"
        local arch_part; arch_part=$(uname -m)
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

# Snapshot / Diff engine (glazepkg / pactool style)
do_snapshot() {
    local out="$HOME/pkg-snapshot-$(date +%Y%m%d_%H%M%S).txt"
    dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort > "$out"
    say "Snapshot saved: $out ($(wc -l < "$out") packages)"
    audit_log "snapshot" "$out"
}

do_diff() {
    local snaps=($(ls -t "$HOME/pkg-snapshot-"*.txt 2>/dev/null | head -n 2))
    if [ ${#snaps[@]} -lt 2 ]; then
        err "Need 2+ snapshots in $HOME. Use menu → Snapshot first."
        return
    fi
    say "Diffing: ${snaps[1]} → ${snaps[0]} (newest vs previous)"
    local added removed
    added=$(comm -23 <(sort "$snaps[0]") <(sort "$snaps[1]") | wc -l)
    removed=$(comm -13 <(sort "$snaps[0]") <(sort "$snaps[1]") | wc -l)
    echo "  Added: $added  |  Removed: $removed"
    echo "  First 10 added lines:"
    comm -23 <(sort "$snaps[0]") <(sort "$snaps[1]") | head -n 10 | sed 's/^/    + /'
    echo "  First 10 removed lines:"
    comm -13 <(sort "$snaps[0]") <(sort "$snaps[1]") | head -n 10 | sed 's/^/    - /'
}

# Theme / color switcher (aptui / metapak style — T for theme toggle)
do_theme() {
    local themes=("default" "nyan" "pink" "dark")
    say "Current theme: $THEME (default: default)"
    if [ "$GUM" = "1" ]; then
        local choice; choice=$(gum choose --header "Theme" "default" "pink" "nyan" "dark" "Back")
    else
        printf '1) default 2) pink 3) nyan 4) dark 5) Back > '; read -r choice
        case "$choice" in 1) choice="default";; 2) choice="pink";; 3) choice="nyan";; 4) choice="dark";; 5) choice="Back";; esac
    fi
    if [ "$choice" = "Back" ] || [ -z "$choice" ]; then return; fi
    case "$choice" in
        pink) ICON_INSTALL="💖"; ICON_SHIELD="🛡️"; PINK="#FF69B4";;
        nyan) ICON_INSTALL="🌈"; ICON_SHIELD="🌟"; PINK="#39FF14";;
        dark) ICON_INSTALL="⚫"; ICON_SHIELD="🌑"; PINK="#555555";;
        *) ICON_INSTALL="$ICON_INSTALL";;
    esac
    save_config "THEME=$choice" || true
    say "Theme set to $choice (restart menu to fully refresh colors)"
}
