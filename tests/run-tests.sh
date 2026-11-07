#!/bin/bash
cd "$(dirname "$0")" || exit 1
MANAGER="$PWD/../manager.sh"
export PATH="$PWD/fakebin:$PATH"
# Disable the optional fzf picker so tests stay hermetic on hosts that have
# fzf installed (otherwise do_install/do_uninstall ask an extra prompt).
export NO_FZF=1
export ICONS=emoji

TOTAL=0 PASS=0 FAIL=0
FAILED=()

run() {
    local name="$1" feed="$2" marker="$3" mgr="${4:-apt}" filechk="${5:-}"
    TOTAL=$((TOTAL+1))
    local home="$PWD/tmp/$name"
    rm -rf "$home"
    mkdir -p "$home/var/cache/apt/archives"
    touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
    if [ -d "$PWD/seeds/$name" ]; then
        cp -r "$PWD/seeds/$name/." "$home/"
    fi
    export HOME="$home" PREFIX="$home" MGR="$mgr"
    local log="$home/run.log"
    timeout 30 bash "$MANAGER" < "$feed" > "$log" 2>&1; rc=$?
    local ok=1
    # A timeout kill (124) or a crash (non-zero) is always a failure.
    if [ "$rc" -eq 124 ]; then
        FAIL=$((FAIL+1)); FAILED+=("$name:timeout"); return
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        FAIL=$((FAIL+1)); FAILED+=("$name:exit=$rc"); return
    fi
    [ -n "$marker" ] && ! grep -Fq "$marker" "$log" && ok=0
    grep -q "command not found" "$log" && ok=0
    grep -qE "^manager\.sh: line [0-9]+:|bash: " "$log" && ok=0
    if [ "$ok" != "1" ]; then
        FAIL=$((FAIL+1))
        FAILED+=("$name")
        return
    fi
    if [ -n "$filechk" ]; then
        local glob="${filechk%%|*}" rest="${filechk#*|}"
        local pos="${rest%%|*}" neg="${rest#*|}"
        if [ -n "$glob" ] && ! compgen -G "$home/$glob" >/dev/null 2>&1; then
            FAIL=$((FAIL+1))
            FAILED+=("$name:file")
            return
        fi
        if [ -n "$pos" ] && ! grep -qE "$pos" "$log"; then
            FAIL=$((FAIL+1))
            FAILED+=("$name:pos")
            return
        fi
        if [ -n "$neg" ] && grep -qE "$neg" "$log"; then
            FAIL=$((FAIL+1))
            FAILED+=("$name:neg")
            return
        fi
    fi
    PASS=$((PASS+1))
}

T()  { run "$1" "$2" "$3" apt "$4"; }
P()  { run "$1" "$2" "$3" pkg "$4"; }
# F() — text-mode run with the fake fzf answering from a queue. Remaining args
# become fzf answers, ONE QUEUE LINE each, popped in order; an empty queue
# aborts (like ESC) so the typed/numeric fallbacks kick in.
F() {
    local name="$1" feed="$2" marker="$3"; shift 3
    run_fzf_q "$name" "$feed" "$marker" "$@"
}

run_fzf_q() {
    local name="$1" feed="$2" marker="$3"; shift 3
    TOTAL=$((TOTAL+1))
    local home="$PWD/tmp/$name"
    rm -rf "$home"
    mkdir -p "$home/var/cache/apt/archives"
    touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
    if [ -d "$PWD/seeds/$name" ]; then
        cp -r "$PWD/seeds/$name/." "$home/"
    fi
    : > "$home/fzfqueue"
    local a
    for a in "$@"; do printf '%s\n' "$a" >> "$home/fzfqueue"; done
    export HOME="$home" PREFIX="$home" MGR=apt
    local log="$home/run.log"
    env -u NO_FZF FZF_QUEUE="$home/fzfqueue" FZF_CALL_LOG="$home/fzf-calls" \
        timeout 30 bash "$MANAGER" < "$feed" > "$log" 2>&1; local rc=$?
    local ok=1
    if [ "$rc" -eq 124 ] || { [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; }; then
        FAIL=$((FAIL+1)); FAILED+=("$name:exit=$rc"); return
    fi
    [ -n "$marker" ] && ! grep -Fq "$marker" "$log" && ok=0
    grep -q "command not found" "$log" && ok=0
    grep -qE "^manager\.sh: line [0-9]+:|bash: " "$log" && ok=0
    if [ "$ok" != "1" ]; then
        FAIL=$((FAIL+1)); FAILED+=("$name")
        return
    fi
    PASS=$((PASS+1))
}

# FG() — like F() but in GUM mode: proves that fzf (when preferred) wins the
FG() {
    run_fzf_g "$1" "$2" "$3" "$@"
}

run_fzf_g() {
    local name="$1" feed="$2" marker="$3"; shift 3
    TOTAL=$((TOTAL+1))
    local home="$PWD/tmp/$name"
    rm -rf "$home"
    mkdir -p "$home/var/cache/apt/archives"
    touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
    : > "$home/fzfqueue"
    : > "$home/queue"
    local a
    for a in "$@"; do
        # to the fake-fzf queue (menus/pickers).
        case "$a" in
            G:*) printf '%s' "${a#G:}" | base64 -w0 >> "$home/queue"; printf '\n' >> "$home/queue" ;;
            *)   printf '%s\n' "$a" >> "$home/fzfqueue" ;;
        esac
    done
    export HOME="$home" PREFIX="$home" MGR=apt
    export GUM_QUEUE="$home/queue" GUM_CALL_LOG="$home/calls" GUM_VALIDATE_LOG="$home/validate"
    : > "$GUM_CALL_LOG"; : > "$GUM_VALIDATE_LOG"
    local log="$home/run.log"
    env -u NO_FZF FZF_QUEUE="$home/fzfqueue" FZF_CALL_LOG="$home/fzf-calls" \
        timeout 30 bash "$MANAGER" < "$feed" > "$log" 2>&1; local rc=$?
    local ok=1
    if [ "$rc" -eq 124 ] || { [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; }; then
        FAIL=$((FAIL+1)); FAILED+=("$name:exit=$rc"); return
    fi
    [ -n "$marker" ] && ! grep -Fq "$marker" "$log" && ok=0
    grep -q "command not found" "$log" && ok=0
    grep -qE "^manager\.sh: line [0-9]+:|bash: " "$log" && ok=0
    if [ "$ok" != "1" ]; then
        FAIL=$((FAIL+1)); FAILED+=("$name")
        return
    fi
    PASS=$((PASS+1))
}

# --- regression (text/apt) ---
T install_ok       <(printf '1\npython3\n')            "python3 installed!"
T uninstall_ok     <(printf '2\npython3\ny\n')         "python3 removed!"
T search_ok        <(printf '3\npython\n')             "python3/stable 3.12 arm64"
T search_installed <(printf '3\npython\n')             "✓ [installed]"
T search_none      <(printf '3\nnotfound\n')           "No results"
T list_ok          <(printf '4\n')                     "python3"
T reinstall_ok     <(printf '5\npython3\ny\n')         "python3 reinstalled!"
T upgrade_all      <(printf '6\na\ny\ny\n')            "Cache cleaned!"
T upgrade_some     <(printf '6\npython3\ny\ny\n')      "Cache cleaned!"
FAKE_UPGRADABLE=empty
export FAKE_UPGRADABLE
T upgrade_none     <(printf '6\n')                     "All packages are up to date!"
unset FAKE_UPGRADABLE
T clean_ok         <(printf '7\ny\n')                  "Cache cleaned!"
T info_ok          <(printf '8\npython3\n')            "Version: 3.12"
T autoremove_ok    <(printf '9\ny\n')                  "System cleaned!"
T depends_ok       <(printf '10\npython3\n')           "Depends: libc"
T rdepends_ok      <(printf '11\npython3\n')           "python-pip"
T size_ok          <(printf '12\npython3\n')           "Download size"
T files_ok         <(printf '13\npython3\n')           "bin/python3"
T owner_ok         <(printf '14\n/usr/bin/python\n')   "python3:"
T hold_ok          <(printf '15\n1\npython3\n')        "now held"
T upgradable_ok    <(printf '18\n')                    "python3/stable 3.12 arm64"
T backup_ok        <(printf '19\n')                    "Backed up" "pkg-backup-*.txt|"
T export_txt       <(printf '21\n1\n\n')               "Exported 2 packages" "pkg-export.txt|"
T settings_show    <(printf '59\n6\n')                 "No config yet"
T settings_icons   <(printf '59\n4\n')                 "Settings saved"
T history_ok       <(printf '1\npython3\n\n24\n1\n')   "install python3"

# --- invalid package errors ---
T install_bad      <(printf '1\ninvalidpkg\n')         "Package not found"
T info_bad         <(printf '8\ninvalidpkg\n')         "Package not found"
T install_nospace  <(printf '1\nnospace\n')            "Not enough disk space"
T install_held     <(printf '1\nheldpkg\n')            "held back"
T install_conflict <(printf '1\nconfpkg\n')            "File conflict"
T rdepends_bad     <(printf '11\ninvalidpkg\n')        "No reverse dependencies found"
T size_bad         <(printf '12\ninvalidpkg\n')        "Package not in cache"

# --- v2.0 expansion #2 (text/apt) ---
T stats_disk       <(printf '26\n2\n')                 "Disk usage by directory"
T stats_files      <(printf '26\n3\n')                 "Largest files"
T inspect_ok       <(printf '31\npython3\n')           "Inspecting python3"
T maint_ok         <(printf '32\nn\nn\nn\nn\nn\n')     "can be upgraded"
FAKE_UPGRADABLE=empty
export FAKE_UPGRADABLE
T maint_clean      <(printf '32\nn\n')                 "System looks healthy!"
T maint_update     <(printf '32\ny\nn\nn\nn\nn\n')     "Hit:1 https"
unset FAKE_UPGRADABLE
T groups_show      <(printf '33\n1\n')                 "git tools"
T groups_install   <(printf '33\n2\n1\ny\n')           "Installing group"
T group_create     <(printf '33\n4\nmytools\ncurl wget\n') "created" ".pkg-manager-groups|"
T bulk_pick_rm     <(printf '29\n3\n1 2\ny\n')         "✓ python3"
T bulk_pick_up     <(printf '29\n4\n1\ny\n')           "✓ python3"
T fav_pin          <(printf '30\n5\n')                 "Favorites pinned"
T pin_installed    <(printf '60\ny\n')                 "Installing python3"
T log_errors       <(printf '1\ninvalidpkg\n\n24\n2\n') "FAIL: install invalidpkg" ".pkg-manager.log|FAIL: install invalidpkg|"
T undo_remove      <(printf '2\npython3\ny\n\n24\n5\ny\n') "Undo complete!"
T search_install   <(printf '3\npython\npython-tool\ny\n') "✓ python-tool"
T quiet_mode       <(printf '2\npython3\n')             "python3 removed!"
T lock_mode        <(printf '2\npython3\n')             "Canceled."
T group_delete     <(printf '33\n5\n1\ny\n\n33\n5\n')    "No custom groups to delete" ".pkg-manager-groups|"
T undo_pick        <(printf '29\n3\n1 2\ny\n\n24\n5\ny\n') "Undo complete!" "||Setting up picked"
T history_installs <(printf '1\npython3\n\n24\n3\n')    "Install / remove actions:" "||Action history"
T fav_remove_last  <(printf '30\n2\n1\n\n30\n3\n')      "No favorites yet — add some first!"

# --- v2.0 new features (text/apt) ---
T simulate_install <(printf '25\n1\npython3\n')        "Simulated install: python3"
T simulate_remove  <(printf '25\n2\npython3\n')        "Simulated remove: python3"
T simulate_upgrade <(printf '25\n3\n')                 "Simulated upgrade"
T stats_ok         <(printf '26\n1\n')                "Total installed size: 3.0 MiB"
T cache_clean      <(printf '27\n1\ny\n')              "Cache cleaned!"
T cache_autoclean  <(printf '27\n2\ny\n')              "Outdated packages cleaned!"
T cache_show       <(printf '27\n3\n')                 "python3_3.12_arm64.deb"
T deptree_ok       <(printf '28\n1\npython3\n')        "termux-exec"
T orphans_none     <(printf '28\n2\n')                 "No orphaned packages found!"
FAKE_ORPHANS=1
export FAKE_ORPHANS
T orphans_found    <(printf '28\n2\ny\n')              "Orphans removed!"
unset FAKE_ORPHANS
T bulk_install     <(printf '29\n1\npython3 git\ny\n') "Installing 2 packages"
T bulk_remove      <(printf '29\n2\npython3 git\ny\n') "Removing 2 packages"
T fav_add          <(printf '30\n1\npython3\n')        "added to favorites" ".pkg-manager-favs|"
T fav_show         <(printf '30\n3\n')                 "1 favorite"
T fav_dup          <(printf '30\n1\npython3\n')        "already a favorite"
T fav_remove       <(printf '30\n2\n1\n')              "removed from favorites"
T fav_install_all  <(printf '30\n4\ny\n')              "Favorites installed!"

# --- partial / multi-package failures ---
T bulk_partial     <(printf '29\n1\npython3 invalidpkg\ny\n') "1 of 2 succeeded, 1 failed" "||✓ invalidpkg"
T bulk_allfail     <(printf '29\n1\ninvalidpkg\ny\n')     "invalidpkg — Package not found"
T search_partial   <(printf '3\npython\npython-tool invalidpkg\ny\n') "1 of 2 succeeded, 1 failed"
T upgrade_partial  <(printf '6\npython3 invalidpkg\ny\ny\n') "1 of 2 succeeded, 1 failed"
T fav_one_fail     <(printf '30\n6\n1\ny\n')              "Package not found"

# --- audit fixes: option injection (M4), upgradable failure (M2), error log (M3) ---
T inject_flag      <(printf '1\n-f\n')                     "Invalid package name"
T inject_double    <(printf '1\n--force\n')                 "Invalid package name"
FAKE_UPGRAD_FAIL=1
export FAKE_UPGRAD_FAIL
T upgr_failure     <(printf '32\n')                         "Could not read the upgradable list"
unset FAKE_UPGRAD_FAIL
T bulk_err_logged  <(printf '29\n1\ninvalidpkg\ny\n\n24\n2\n') "FAIL: install invalidpkg" ".pkg-manager.log|FAIL: install invalidpkg|"
T undo_last_remove_dead <(printf '2\npython3\ny\n')          "python3 removed!" "||remove multiple"
T search_dash      <(printf '3\n-foo\n')                     "Invalid search term"
T owner_dash       <(printf '14\n-etc/passwd\n')             "Invalid file path"

# --- coverage gaps: purge / restore / export-json / owner / doctor / favs unpin / history clear ---
T purge_ok         <(printf '16\npython3\ny\n')              "python3 purged!"
T restore_ok       <(printf '20\n%s/tmp/restore_ok/restore.txt\ny\n' "$PWD") "Restore complete!"
T owner_ok         <(printf '14\n/usr/bin/python\n')         "python3"
T doctor_ok        <(printf '23\ny\n')                       "All helper tools present!"
T export_json      <(printf '21\n2\n\n')                     "Exported 2 packages" "pkg-export.json|"
T fav_unpin        <(printf '30\n5\n\n30\n5\n')              "Favorites removed from the main menu"
T history_clear    <(printf '1\npython3\n\n24\n6\ny\n') "History cleared" ".pkg-manager.log|"
T import_ok        <(printf '22\n%s/tmp/import_ok/pkg-list.txt\ny\n' "$PWD") "Import complete!"
T group_remove     <(printf '33\n3\n1\ny\n')                 "Removing group"
T fixbroken_ok     <(printf '17\ny\n')                       "Dependency problems fixed!"
T unhold_ok        <(printf '15\n2\npython3\n')              "no longer held"
T hold_show        <(printf '15\n3\n')                       "Held packages:"
T stats_cache      <(printf '26\n4\n')                       "Cache breakdown"
T settings_theme   <(printf '59\n2\n2\n')                    "Settings saved"

# --- pkg mode ---
P pkg_list         <(printf '4\n')                     "python3"
P pkg_upgrade      <(printf '6\na\ny\ny\n')            "Cache cleaned!"
P pkg_backup       <(printf '19\n')                    "Backed up" "pkg-backup-*.txt|"

# --- v3.0 new features (text/apt) ---
T localdeb_ok      <(printf '34\n%s/tmp/localdeb_ok/var/cache/apt/archives/python3_3.12_arm64.deb\ny\n' "$PWD") "Installed"
T downgrade_ok     <(printf '35\npython3\n1\ny\n') "downgraded"
T dlonly_ok        <(printf '36\npython3\ny\n') "Downloaded"
T holdver_show     <(printf '37\n3\n') "Held packages"
T filesearch_ok    <(printf '38\nbin/python\n') "python3:"
T changelog_ok     <(printf '39\npython3\n') "Changelog"
T why_ok           <(printf '40\npython3\n') "Why is"
T notes_add        <(printf '41\n1\npython3\nmy note for 3.0\n\n41\n3\n') "Note added"
T snapshot_create  <(printf '42\n1\n\n42\n2\n') "Snapshot created"
T palette_choose   <(printf '43\n\n1\npython3\n') "Installing python3"

# --- v4.0 new themes (text/apt) ---
T theme_nord       <(printf '59\n2\n5\n\n59\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=nord|"
T theme_teal       <(printf '59\n2\n7\n\n59\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=teal|"
T theme_invalid    <(printf '59\n2\n1\n\n59\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=green|"

# --- v4.0 package watchlist (text/apt) ---
T watch_add        <(printf '44\n1\npython3\n')            "added to the watchlist" ".pkg-manager-watch|"
T watch_dup        <(printf '44\n1\npython3\n')            "already on the watchlist"
T watch_show       <(printf '44\n3\n')                     "Watchlist is empty."
T watch_list       <(printf '44\n3\n')                     "Watchlist (/"
T watch_check      <(printf '44\n4\n')                     "up to date (3.12)"
T watch_missing    <(printf '44\n4\n')                     "no longer available in the repositories"
T watch_rm         <(printf '44\n2\n1\n')                  "removed from the watchlist"

# --- v4.0 mirror speed test (text/apt) ---
T mirror_fastest   <(printf '45\n')                        "already the fastest"
T mirror_switch    <(printf '45\ny\n\n')                   "Mirror switched" "etc/apt/sources.list|packages.termux.dev|"
FAKE_CURL_FAIL=1
export FAKE_CURL_FAIL
T mirror_fail      <(printf '45\n')                        "No mirror responded"
unset FAKE_CURL_FAIL

# --- v4.0 system audit (text/apt) ---
T audit_ok         <(printf '46\n')                        "Health score"
T audit_report     <(printf '46\n')                        "Audit report"

# --- v4.0 mark manual / auto (text/apt) ---
T mark_manual      <(printf '47\n1\npython3\n')            "marked as manual"
T mark_auto        <(printf '47\n2\ngit\n')                "marked as auto"
T mark_show_manual <(printf '47\n3\n')                     "Manually installed packages"
T mark_show_auto   <(printf '47\n4\n')                     "Automatically installed packages"
T mark_satisfies   <(printf '47\n5\npython3\n')            "Packages providing"

# --- v4.0 recycle bin (text/apt) ---
T recycle_empty    <(printf '48\n')                        "recycle bin is empty"
T recycle_archive  <(printf '2\npython3\ny\n')              "archived to the recycle bin" "pkg-trash/*.deb|"
T recycle_restore  <(printf '48\n1\npython3_3.12_arm64.deb\ny\n') "Restored python3_3.12_arm64.deb"
T recycle_all      <(printf '48\n2\ny\n')                  "Recycle bin fully restored!"
T recycle_show     <(printf '48\n3\n')                     "Recycle bin contents"
T recycle_trash    <(printf '48\n4\ny\n')                  "Recycle bin emptied."

# --- v4.0 history charts (text/apt) ---
T history_charts   <(printf '1\npython3\n\n24\n4\n')       "Charts & statistics"
T charts_bars      <(printf '1\npython3\n\n24\n4\n')       "Actions per day (last 14 days"

# --- v4.0 self-update (text/apt, decline + failure paths) ---
T selfupdate_cancel <(printf '55\nn\n')                    "Update canceled"
FAKE_CURL_FAIL=1
export FAKE_CURL_FAIL
T selfupdate_fail  <(printf '55\n')                        "Could not download the latest version"
unset FAKE_CURL_FAIL

# --- v4.0 ---

# --- v5.0 real terminal themes ---
T theme_dracula    <(printf '59\n2\n9\n\n59\n6\n')         "Settings saved" ".pkg-manager.conf|THEME=dracula|"
T theme_rosepine   <(printf '59\n2\n16\n\n59\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=rosepine|"
T termux_theme_legacy <(printf '59\n12\n3\n')                  "no full ANSI table" "||"
export THEME=dracula
T termux_theme_apply <(printf '59\n12\n3\n')                   "colors.properties" ".termux/colors.properties|(theme: dracula)|"
unset THEME
T theme_preview    <(printf '59\n12\n2\n')                     "Theme preview" "|dracula|"

# --- v5.0 new main-menu features ---
T essentials_core  <(printf '56\n1\ny\n')                  "✓ git"
T essentials_all   <(printf '56\n5\ny\n')                  "✓ bat"
T sysinfo_ok       <(printf '57\n')                        "System & network info"
T whatsnew_ok      <(printf '58\n')                        "What's new"

# --- v5.0 fzf integration: fake fzf answers from FZF_QUEUE (one line per arg,
# first arg = main-menu pick since text fzf menus answer before the numbered
# prompt); empty queue = ESC/abort → typed/numeric fallback.
F fzf_install_pick    <(printf 'y\n\n0\n')                 "✓ git"    "📦 Install a package" "git"
F fzf_install_multi   <(printf 'y\n\n0\n')                 "✓ git"    "📦 Install a package" "MULTI:git figlet"
F fzf_install_fallback <(printf '1\npython3\n\n0\n')       "python3 installed!" ""
F fzf_uninstall_pick  <(printf 'y\n\n0\n')                 "✓ python3" "🗑️ Uninstall a package" "python3"
F fzf_menu_pick       <(printf 'python3\n\n0\n')           "python3 installed!" "📦 Install a package"
F fzf_palette_pick    <(printf 'python3\n\n0\n')           "Installing python3..." "🪄 Command palette" "📦 Install a package"
# --- fzf owns the submenus too (FZF_FIRST=1 default) ---
FG fzf_settings_submenu <(printf '\n\n0\n')         "Theme set to dracula" "⚙️ Settings" "🎨  Color theme: green" "dracula (truecolor)"
FG fzf_theme_hub_fzf    <(printf '\n\n0\n')         "Theme set to dracula" "⚙️ Settings" "🪄 Themes & terminal colors" "Pick a theme" "dracula (truecolor)"
F fzf_search_pick     <(printf 'python\ny\n\n0\n')         "✓ python-tool" "🔎 Search packages" "python-tool"

# --- self-update replace path: runs against a COPY of the script, never the repo file ---
TOTAL=$((TOTAL+1))
home2="$PWD/tmp/selfupdate_replace"
rm -rf "$home2"
mkdir -p "$home2"
cp "$MANAGER" "$home2/pkg-manager"
export HOME="$home2" PREFIX="$home2" MGR=apt
printf '55\ny\n' | timeout 30 bash "$home2/pkg-manager" > "$home2/run.log" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    FAIL=$((FAIL+1)); FAILED+=("selfupdate_replace:exit=$rc")
elif grep -q "fake pkg-manager 9.9" "$home2/pkg-manager" && grep -q "Updated to" "$home2/run.log"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); FAILED+=("selfupdate_replace")
fi

echo
echo "== RESULTS =="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "FAILED:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
