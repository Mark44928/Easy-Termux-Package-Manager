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

fzf_pick_pkgs() {
    local prompt="${1:-Select packages}" mode="${2:-install}"
    if ! command -v fzf >/dev/null 2>&1; then
        echo "fzf not installed. Install with: $MGR install fzf" >&2
        return 1
    fi
    refresh_fzf_cache
    if [ ! -s "$FZF_CACHE" ]; then
        echo "Package cache empty. Try apt update first." >&2
        return 1
    fi
    local selected
    selected=$(cat "$FZF_CACHE" 2>/dev/null | fzf -m \
        --header="$prompt" \
        --prompt="Packages (Tab/Space multi, Enter confirm) > " \
        --preview='line={}; pkg=$(printf "%s" "$line" | sed "s/^\[[^]]*\] //"); printf "=== %s ===\n" "$pkg"; apt-cache show "$pkg" 2>/dev/null | head -n 12' \
        --preview-window='right:50%:wrap' \
        --layout=reverse \
        --cycle \
        --bind='ctrl-a:select-all' \
        --bind='ctrl-d:deselect-all' \
        --bind='ctrl-r:abort' \
        2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    [ -z "$selected" ] && return 1
    printf '%s\n' "$selected" | sed -E 's/^\[[✓✓ ]+\] //' | sed '/^$/d' | sort -u
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
    if [ "$GUM" = "1" ]; then
        choice=$(gum choose --header "Repo actions..." \
            "Show sources" \
            "Test mirror speed" \
            "Add repo line" \
            "Remove line by number" \
            "Backup sources" \
            "Apt update" \
            "Back")
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
    local op="$1"
    if ! command -v fzf >/dev/null 2>&1; then
        return 1
    fi
    local selected
    selected=$(fzf_pick_pkgs "Select packages for $op" "$op") || return 1
    local -a pkgs=()
    while IFS= read -r line; do
        [ -n "$line" ] && pkgs+=("$line")
    done <<< "$selected"
    [ ${#pkgs[@]} -eq 0 ] && return 1
    batch_preview "$op" "${pkgs[@]}"
    local confirm="y"
    if [ "$GUM" = "1" ]; then
        if gum confirm --default=no "Confirm $op for ${#pkgs[@]} package(s)? (y/n/d=dry-run)"; then
            confirm="y"; else confirm="n"; fi
    else
        printf 'Confirm %s %s package(s)? (y/n/d=dry-run): ' "$op" "${#pkgs[@]}"
        read -r confirm
    fi
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
