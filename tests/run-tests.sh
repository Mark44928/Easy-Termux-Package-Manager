#!/bin/bash
cd "$(dirname "$0")" || exit 1
MANAGER="$PWD/../manager.sh"
REAL_PREFIX="${TERMUX__PREFIX:-$PREFIX}"
export MANAGER
export PATH="$PWD/fakebin:$PATH"
# Disable the optional fzf picker so tests stay hermetic on hosts that have
# fzf installed (otherwise do_install/do_uninstall ask an extra prompt).
export NO_FZF=1
export ICONS=emoji
export TERM="${TERM:-dumb}"

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

# --- regression (text/apt) ---
T install_ok       <(printf '1\npython3\n')            "python3 installed!"
T no_apt_nag       <(printf '1\npython3\n')            "python3 installed!" "|python3 installed!|stable CLI"
T uninstall_ok     <(printf '2\npython3\ny\n')         "python3 removed!"
T list_ok          <(printf '3\n')                     "python3"
T reinstall_ok     <(printf '4\npython3\ny\n')         "python3 reinstalled!"
T upgrade_all      <(printf '5\na\ny\ny\n')            "Cache cleaned!"
T upgrade_some     <(printf '5\npython3\ny\ny\n')      "Cache cleaned!"
FAKE_UPGRADABLE=empty
export FAKE_UPGRADABLE
T upgrade_none     <(printf '5\n')                     "All packages are up to date!"
unset FAKE_UPGRADABLE
T clean_ok         <(printf '6\ny\n')                  "Cache cleaned!"
T info_ok          <(printf '7\npython3\n')            "Version: 3.12"
T autoremove_ok    <(printf '8\ny\n')                  "System cleaned!"
T depends_ok       <(printf '9\npython3\n')           "Depends: libc"
T rdepends_ok      <(printf '10\npython3\n')           "python-pip"
T size_ok          <(printf '11\npython3\n')           "Download size"
T files_ok         <(printf '12\npython3\n')           "bin/python3"
T owner_ok         <(printf '13\n/usr/bin/python\n')   "python3:"
T hold_ok          <(printf '14\n1\npython3\n')        "now held"
T upgradable_ok    <(printf '17\n')                    "python3/stable 3.12 arm64"
T backup_ok        <(printf '18\n')                    "Backed up" "pkg-backup-*.txt|"
T export_txt       <(printf '20\n1\n\n')               "Exported 2 packages" "pkg-export.txt|"
T settings_show    <(printf '57\n6\n')                 "No config yet"
T settings_icons   <(printf '57\n3\n')                 "Settings saved"
T history_ok       <(printf '1\npython3\n\n23\n1\n')   "install python3"

# --- invalid package errors ---
T install_bad      <(printf '1\ninvalidpkg\n')         "Package not found"
T info_bad         <(printf '7\ninvalidpkg\n')         "Package not found"
T install_nospace  <(printf '1\nnospace\n')            "Not enough disk space"
T install_held     <(printf '1\nheldpkg\n')            "held back"
T install_conflict <(printf '1\nconfpkg\n')            "File conflict"
T rdepends_bad     <(printf '10\ninvalidpkg\n')        "No reverse dependencies found"
T size_bad         <(printf '11\ninvalidpkg\n')        "Package not in cache"

# --- v2.0 expansion #2 (text/apt) ---
T stats_disk       <(printf '25\n2\n')                 "Disk usage by directory"
T stats_files      <(printf '25\n3\n')                 "Largest files"
T inspect_ok       <(printf '30\npython3\n')           "Inspecting python3"
T maint_ok         <(printf '31\nn\nn\nn\nn\nn\n')     "can be upgraded"
FAKE_UPGRADABLE=empty
export FAKE_UPGRADABLE
T maint_clean      <(printf '31\nn\n')                 "System looks healthy!"
T maint_update     <(printf '31\ny\nn\nn\nn\nn\n')     "Hit:1 https"
unset FAKE_UPGRADABLE
T groups_show      <(printf '32\n1\n')                 "git tools"
T groups_install   <(printf '32\n2\n1\ny\n')           "Installing group"
T group_create     <(printf '32\n4\nmytools\ncurl wget\n') "created" ".pkg-manager-groups|"
T bulk_pick_rm     <(printf '28\n3\n1 2\ny\n')         "✓ python3"
T bulk_pick_up     <(printf '28\n4\n1\ny\n')           "✓ python3"
T fav_pin          <(printf '29\n5\n')                 "Favorites pinned"
T pin_installed    <(printf '58\ny\n')                 "Installing python3"
T log_errors       <(printf '1\ninvalidpkg\n\n23\n2\n') "FAIL: install invalidpkg" ".pkg-manager.log|FAIL: install invalidpkg|"
T undo_remove      <(printf '2\npython3\ny\n\n23\n5\ny\n') "Undo complete!"
T quiet_mode       <(printf '2\npython3\n')             "python3 removed!"
T lock_mode        <(printf '2\npython3\n')             "Canceled."
T group_delete     <(printf '32\n5\n1\ny\n\n32\n5\n')    "No custom groups to delete" ".pkg-manager-groups|"
T undo_pick        <(printf '28\n3\n1 2\ny\n\n23\n5\ny\n') "Undo complete!" "||Setting up picked"
T history_installs <(printf '1\npython3\n\n23\n3\n')    "Install / remove actions:" "||Action history"
T fav_remove_last  <(printf '29\n2\n1\n\n29\n3\n')      "No favorites yet — add some first!"

# --- v2.0 new features (text/apt) ---
T simulate_install <(printf '24\n1\npython3\n')        "Simulated install: python3"
T simulate_remove  <(printf '24\n2\npython3\n')        "Simulated remove: python3"
T simulate_upgrade <(printf '24\n3\n')                 "Simulated upgrade"
T stats_ok         <(printf '25\n1\n')                "Total installed size: 3.0 MiB"
T cache_clean      <(printf '26\n1\ny\n')              "Cache cleaned!"
T cache_autoclean  <(printf '26\n2\ny\n')              "Outdated packages cleaned!"
T cache_show       <(printf '26\n3\n')                 "python3_3.12_arm64.deb"
T deptree_ok       <(printf '27\n1\npython3\n')        "termux-exec"
T orphans_none     <(printf '27\n2\n')                 "No orphaned packages found!"
FAKE_ORPHANS=1
export FAKE_ORPHANS
T orphans_found    <(printf '27\n2\ny\n')              "Orphans removed!"
unset FAKE_ORPHANS
T bulk_install     <(printf '28\n1\npython3 git\ny\n') "Installing 2 packages"
T bulk_remove      <(printf '28\n2\npython3 git\ny\n') "Removing 2 packages"
T fav_add          <(printf '29\n1\npython3\n')        "added to favorites" ".pkg-manager-favs|"
T fav_show         <(printf '29\n3\n')                 "1 favorite"
T fav_dup          <(printf '29\n1\npython3\n')        "already a favorite"
T fav_remove       <(printf '29\n2\n1\n')              "removed from favorites"
T fav_install_all  <(printf '29\n4\ny\n')              "Favorites installed!"

# --- partial / multi-package failures ---
T bulk_partial     <(printf '28\n1\npython3 invalidpkg\ny\n') "1 of 2 succeeded, 1 failed" "||✓ invalidpkg"
T bulk_allfail     <(printf '28\n1\ninvalidpkg\ny\n')     "invalidpkg — Package not found"
T upgrade_partial  <(printf '5\npython3 invalidpkg\ny\ny\n') "1 of 2 succeeded, 1 failed"
T fav_one_fail     <(printf '29\n6\n1\ny\n')              "Package not found"

# --- audit fixes: option injection (M4), upgradable failure (M2), error log (M3) ---
T inject_flag      <(printf '1\n-f\n')                     "Invalid package name"
T inject_double    <(printf '1\n--force\n')                 "Invalid package name"
FAKE_UPGRAD_FAIL=1
export FAKE_UPGRAD_FAIL
T upgr_failure     <(printf '31\n')                         "Could not read the upgradable list"
unset FAKE_UPGRAD_FAIL
T bulk_err_logged  <(printf '28\n1\ninvalidpkg\ny\n\n23\n2\n') "FAIL: install invalidpkg" ".pkg-manager.log|FAIL: install invalidpkg|"
T undo_last_remove_dead <(printf '2\npython3\ny\n')          "python3 removed!" "||remove multiple"
T owner_dash       <(printf '13\n-etc/passwd\n')             "Invalid file path"

# --- coverage gaps: purge / restore / export-json / owner / doctor / favs unpin / history clear ---
T purge_ok         <(printf '15\npython3\ny\n')              "python3 purged!"
T restore_ok       <(printf '19\n%s/tmp/restore_ok/restore.txt\ny\n' "$PWD") "Restore complete!"
T owner_ok         <(printf '13\n/usr/bin/python\n')         "python3"
T doctor_ok        <(printf '22\ny\n')                       "All helper tools present!"
T export_json      <(printf '20\n2\n\n')                     "Exported 2 packages" "pkg-export.json|"
T fav_unpin        <(printf '29\n5\n\n29\n5\n')              "Favorites removed from the main menu"
T history_clear    <(printf '1\npython3\n\n23\n6\ny\n') "History cleared" ".pkg-manager.log|"
T import_ok        <(printf '21\n%s/tmp/import_ok/pkg-list.txt\ny\n' "$PWD") "Import complete!"
T group_remove     <(printf '32\n3\n1\ny\n')                 "Removing group"
T fixbroken_ok     <(printf '16\ny\n')                       "Dependency problems fixed!"
T unhold_ok        <(printf '14\n2\npython3\n')              "no longer held"
T hold_show        <(printf '14\n3\n')                       "Held packages:"
T stats_cache      <(printf '25\n4\n')                       "Cache breakdown"
T settings_theme   <(printf '57\n3\n3\n')                    "Settings saved"

# --- pkg mode ---
P pkg_list         <(printf '3\n')                     "python3"
P pkg_upgrade      <(printf '5\na\ny\ny\n')            "Cache cleaned!"
P pkg_backup       <(printf '18\n')                    "Backed up" "pkg-backup-*.txt|"

# --- v3.0 new features (text/apt) ---
T localdeb_ok      <(printf '33\n%s/tmp/localdeb_ok/var/cache/apt/archives/python3_3.12_arm64.deb\ny\n' "$PWD") "Installed"
T downgrade_ok     <(printf '34\npython3\n1\ny\n') "downgraded"

# --- downgrade policy fallback (madison empty): must pick a version from the
# version table, never the priority column ("500"/"100") ---
FAKE_MADISON_EMPTY=1
export FAKE_MADISON_EMPTY
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/downgrade_policy"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
out=$(printf '34\npython3\n1\ny\n' | timeout 30 bash "$MANAGER" 2>&1); rc=$?
if [ "$rc" -eq 124 ] || { [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; }; then
    FAIL=$((FAIL+1)); FAILED+=("downgrade_policy:exit=$rc")
elif printf '%s\n' "$out" | grep -Fq "downgraded to 3.12"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); FAILED+=("downgrade_policy:$out")
fi
unset FAKE_MADISON_EMPTY
T dlonly_ok        <(printf '35\npython3\ny\n') "Downloaded"
T holdver_show     <(printf '36\n3\n') "Held packages"
T filesearch_ok    <(printf '37\nbin/python\n') "python3:"
T changelog_ok     <(printf '38\npython3\n') "Changelog"
T why_ok           <(printf '39\npython3\n') "Why is"
T notes_add        <(printf '40\n1\npython3\nmy note for 3.0\n\n40\n3\n') "Note added"
T snapshot_create  <(printf '41\n1\n\n41\n2\n') "Snapshot created"
T palette_choose   <(printf '42\n\n1\npython3\n') "Installing python3"

# --- v4.0 new themes (text/apt) ---
T theme_nord       <(printf '57\n2\n1\n5\n\n57\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=nord|"
T theme_teal       <(printf '57\n2\n1\n7\n\n57\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=teal|"
T theme_invalid    <(printf '57\n2\n1\n1\n\n57\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=green|"

# --- v4.0 package watchlist (text/apt) ---
T watch_add        <(printf '43\n1\npython3\n')            "added to the watchlist" ".pkg-manager-watch|"
T watch_dup        <(printf '43\n1\npython3\n')            "already on the watchlist"
T watch_show       <(printf '43\n3\n')                     "Watchlist is empty."
T watch_list       <(printf '43\n3\n')                     "Watchlist (/"
T watch_check      <(printf '43\n4\n')                     "up to date (3.12)"
T watch_missing    <(printf '43\n4\n')                     "no longer available in the repositories"
T watch_rm         <(printf '43\n2\n1\n')                  "removed from the watchlist"

# --- v4.0 mirror speed test (text/apt) ---
T mirror_fastest   <(printf '44\n')                        "already the fastest"
T mirror_switch    <(printf '44\ny\n\n')                   "Mirror switched" "etc/apt/sources.list|packages.termux.dev|"
FAKE_CURL_FAIL=1
export FAKE_CURL_FAIL
T mirror_fail      <(printf '44\n')                        "No mirror responded"
unset FAKE_CURL_FAIL

# --- v4.0 system audit (text/apt) ---
T audit_ok         <(printf '45\n')                        "Health score"
T audit_report     <(printf '45\n')                        "Audit report"

# --- v4.0 mark manual / auto (text/apt) ---
T mark_manual      <(printf '46\n1\npython3\n')            "marked as manual"
T mark_auto        <(printf '46\n2\ngit\n')                "marked as auto"
T mark_show_manual <(printf '46\n3\n')                     "Manually installed packages"
T mark_show_auto   <(printf '46\n4\n')                     "Automatically installed packages"
T mark_satisfies   <(printf '46\n5\npython3\n')            "matching/providing"

# --- v4.0 recycle bin (text/apt) ---
T recycle_empty    <(printf '47\n')                        "recycle bin is empty"
T recycle_archive  <(printf '2\npython3\ny\n')              "archived to the recycle bin" "pkg-trash/*.deb|"
T recycle_restore  <(printf '47\n1\npython3_3.12_arm64.deb\ny\n') "Restored python3_3.12_arm64.deb"
T recycle_all      <(printf '47\n2\ny\n')                  "Recycle bin fully restored!"
T recycle_show     <(printf '47\n3\n')                     "Recycle bin contents"
T recycle_trash    <(printf '47\n4\ny\n')                  "Recycle bin emptied."

# --- v4.0 history charts (text/apt) ---
T history_charts   <(printf '1\npython3\n\n23\n4\n')       "Charts & statistics"
T charts_bars      <(printf '1\npython3\n\n23\n4\n')       "Actions per day (last 14 days"

# --- v4.0 self-update (text/apt, decline + failure paths) ---
T selfupdate_cancel <(printf '53\nn\n')                    "Update canceled"
FAKE_CURL_FAIL=1
export FAKE_CURL_FAIL
T selfupdate_fail  <(printf '53\n')                        "Could not download the latest version"
unset FAKE_CURL_FAIL
FAKE_BAD_SHA=1
export FAKE_BAD_SHA
T selfupdate_badsha <(printf '53\ny\n')                    "SHA-256 mismatch — refusing to install"
unset FAKE_BAD_SHA

# --- v4.0 ---

# --- v5.0 real terminal themes ---
T theme_dracula    <(printf '57\n2\n1\n9\n\n57\n6\n')         "Settings saved" ".pkg-manager.conf|THEME=dracula|"
T theme_rosepine   <(printf '57\n2\n1\n16\n\n57\n6\n')        "Settings saved" ".pkg-manager.conf|THEME=rosepine|"
T termux_theme_legacy <(printf '57\n2\n3\n')                  "no full ANSI table" "||"
export THEME=dracula
T termux_theme_apply <(printf '57\n2\n3\n')                   "colors.properties" ".termux/colors.properties|(theme: dracula)|"
unset THEME
T theme_preview    <(printf '57\n2\n2\n')                     "Theme preview" "|dracula|"

# --- v5.0 new main-menu features ---
T essentials_core  <(printf '54\n1\ny\n')                  "✓ git"
T essentials_all   <(printf '54\n5\ny\n')                  "✓ bat"
T sysinfo_ok       <(printf '55\n')                        "System & network info"
T whatsnew_ok      <(printf '56\n')                        "What's new"

# --- v5.0 fzf integration: fake fzf answers from FZF_QUEUE (one line per arg,
# first arg = main-menu pick since text fzf menus answer before the numbered
# prompt); empty queue = ESC/abort → typed/numeric fallback.
F fzf_install_pick    <(printf 'y\n\n0\n')                 "✓ git"    "📦 Install a package" "git"
F fzf_install_multi   <(printf 'y\n\n0\n')                 "✓ git"    "📦 Install a package" "MULTI:git figlet"
# ESC in the package picker cancels back to the main menu (no typed-name prompt)
F fzf_install_cancel <(printf '\n0\n')                 "Canceled" "📦 Install a package"
F fzf_uninstall_pick  <(printf 'y\n\n0\n')                 "✓ python3" "🗑️ Uninstall a package" "python3"
F fzf_menu_pick       <(printf 'y\n\n0\n')                "✓ python3" "📦 Install a package" "python3"
F fzf_palette_pick    <(printf 'y\n\n0\n')                "✓ python3" "🪄 Command palette" "📦 Install a package" "python3"
# --- fzf owns the submenus too (FZF_FIRST=1 default) ---
# settings has ONE theme row now (it opens the hub): settings → hub → pick
F fzf_settings_submenu <(printf '\n\n0\n')         "Theme set to dracula" "⚙️ Settings" "🎨  Themes & terminal colors: green" "Pick a theme" "dracula (truecolor)"
F fzf_theme_hub_fzf    <(printf '\n\n0\n')         "Theme preview" "⚙️ Settings" "🎨  Themes & terminal colors: green" "Preview all themes"

# --- structural guard: a shadowed OPTION_* var once rendered two identical
# menu rows and left do_depgraph() unreachable — never again. ---
TOTAL=$((TOTAL+1))
home="$PWD/tmp/menu_unique"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
# The row style may change ("[1]  label" or " 1) label"), so the extraction
# accepts both — what matters is that the main menu prints every option and
# the Exit row exactly once, with no duplicates.
labels=$(sed 's/\x1b\[[0-9;]*m//g' "$home/run.log" | sed -n 's/^\[[0-9]\{1,\}\]  //p; s/^ *[0-9]\{1,\}) //p')
mcount=$(printf '%s\n' "$labels" | grep -c .)
mdups=$(printf '%s\n' "$labels" | sort | uniq -d)
# 57 numbered options + the [0] Exit row = 58 unique rows.
if [ "$mcount" -eq 58 ] && [ -z "$mdups" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); FAILED+=("menu_unique:count=$mcount,dups=${mdups//$'\n'/,}")
fi

# --- v5.0 restored dispatch: 50 = colored dependency graph, 52 = snapshot/diff hub ---
T depgraph_ok     <(printf '50\npython3\n')            "DEPENDENCY TREE: python3"
T snapshot_diff   <(printf '52\n')                     "Create snapshot"

# --- v5.3.1: snapshot restore path guard ---
TOTAL=$((TOTAL+1))
home="$PWD/tmp/snapshot_unsafe"
rm -rf "$home"; mkdir -p "$home/seed"
printf 'x' > "$home/seed/evil.txt"
(
    cd "$home/seed" || exit 1
    tar --absolute-names -czf "$home/evil.tar.gz" "$home/seed/evil.txt"
)
EVIL="$home/evil.tar.gz"
export HOME="$home" PREFIX="$home" MGR=apt
out=$(printf '52\n4\n%s\ny\n' "$EVIL" | timeout 30 bash "$MANAGER" 2>&1)
if printf '%s\n' "$out" | grep -q "unsafe paths"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); FAILED+=("snapshot_unsafe")
fi
unset HOME PREFIX MGR

# --- CLI mode (parsed before the interactive loop; was completely untested) ---
# shellcheck disable=SC2086  # $args is deliberately word-split
cli() {
    local name="$1" args="$2" marker="$3"
    TOTAL=$((TOTAL+1))
    local home="$PWD/tmp/$name"
    rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
    touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
    export HOME="$home" PREFIX="$home" MGR=apt
    timeout 30 bash "$MANAGER" $args < /dev/null > "$home/run.log" 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL+1)); FAILED+=("$name:exit=$rc"); return
    fi
    if grep -Fq "$marker" "$home/run.log"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); FAILED+=("$name")
    fi
}
cli cli_help        "--help"                "Usage:"
cli cli_version     "--version"             "pkg-manager v5.3.1"
cli cli_list_themes "--list-themes"         "Theme preview"
cli cli_theme       "--theme dracula"       "Theme set to dracula"
cli cli_export      "--export-theme rosepine" "colors.properties (theme: rosepine)"

# --- v5.1: fzf rewrite regressions ---
# The menu must call fzf exactly ONCE (a duplicated block made ESC reopen it).
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/fzf_once"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF FZF_QUEUE="/dev/null" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
n_calls=$(grep -c '^fzf' "$home/calls" 2>/dev/null || echo 0)
if [ "$n_calls" -eq 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("fzf_once:expected 1 fzf call, got $n_calls")
fi

# --- v5.2: the banner must ride INSIDE the fzf window ---
# Text printed above an fzf window is static: on a terminal resize fzf
# re-anchors its window and the static banner above it is wiped for good
# (fzf cannot repaint it). The banner is therefore the picker's header, so
# fzf redraws it on every resize.
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/fzf_banner_header"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF FZF_QUEUE="/dev/null" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
calls_flat=$(tr '\n' ' ' < "$home/calls" 2>/dev/null)
bok=1
case "$calls_flat" in *"--header="*"____"*"pkg-manager v"*) ;; *) bok=0 ;; esac
# and it must NOT also be printed above the picker (that would show it twice)
grep -q '____' "$home/run.log" 2>/dev/null && bok=0
if [ "$bok" -eq 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("fzf_banner_header")
fi

# Short terminal: the 5-line art is dropped so the picker keeps list rows,
# but the status strip stays in the header (it is what survives a resize).
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/fzf_banner_short"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF FZF_QUEUE="/dev/null" FZF_CALL_LOG="$home/calls" LINES=10 COLUMNS=80 \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
calls_flat=$(tr '\n' ' ' < "$home/calls" 2>/dev/null)
bok=1
case "$calls_flat" in *"--header="*"pkg-manager v"*) ;; *) bok=0 ;; esac
case "$calls_flat" in *"--header="*"____"*) bok=0 ;; esac
if [ "$bok" -eq 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("fzf_banner_short")
fi

# ---- v5.2 menu picking: invisible delimiter, detail coverage, ghost, clear ----
# The fzf list shows the bare action label only, so the extra preview columns
# must sit behind an INVISIBLE separator: fzf's --with-nth leaves a delimiter
# marker for hidden fields, and a visible one prints it at the end of every
# row (that is exactly what shipped in 5.2 and looked broken).
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/menu_delim"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF FZF_QUEUE="/dev/null" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
args=$(tr '\n' ' ' < "$home/calls" 2>/dev/null)
dok=1
case "$args" in
    *"--with-nth=1"*) ;;
    *) dok=0 ; echo "no with-nth=1 (list must show the label only)" ;;
esac
case "$args" in
    *"--nth=1,2"*) ;;
    *) dok=0 ; echo "no nth=1,2 (search must cover label + description)" ;;
esac
# the separator fzf is told about must be invisible: 0x1f, NOT '|'
case "$args" in
    *'--delimiter=\x1f'*) ;;
    *) dok=0 ; echo "delimiter is not the invisible US char" ;;
esac
case "$args" in
    *'--delimiter=|'*) dok=0 ; echo "delimiter is the visible pipe" ;;
esac
# the preview must carry a FOURTH column (the action detail) — a two-column
# preview would leave the detail line missing.
case "$args" in
    *"--preview="*"{4}"*) ;;
    *) dok=0 ; echo "preview does not use the detail field {4}" ;;
esac
if [ "$dok" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("menu_delim"); fi

# Every menu row must have a detail line — a missing one leaves a blank line
# in the preview panel, which is the exact regression this guards.
TOTAL=$((TOTAL + 1))
detail_head="$PWD/tmp/detail_head.sh"
mkdir -p "$PWD/tmp"
awk '/^FIRST_LOOP=1$/{exit} {print}' "$MANAGER" > "$detail_head" 2>/dev/null
detail_out=$(HOME="$PWD/tmp/detail_cov" PREFIX="$PWD/tmp/detail_cov" bash -c '
    f="$1"; shift          # our own argument must not reach the CLI-mode case
    source "$f"
    missing=0
    for i in "${MENU_ITEMS[@]}" "$OPTION_EXIT"; do
        d="${MENU_DETAIL[$i]:-}"
        [ -n "$d" ] || { echo "no detail: $i"; missing=1; }
    done
    exit $missing
' bash "$detail_head" 2>&1)
rm -f "$detail_head"
if [ -z "$detail_out" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("menu_detail_cov:$detail_out"); fi

# The ghost hint is passed only when the installed fzf understands --ghost
# (>= 0.61); an unknown flag makes fzf exit 2 and the app drops to text mode.
TOTAL=$((TOTAL + 1))
ghost_out=$(bash -c 'source <(sed -n "/^have_fzf()/,/^}/p;/^FZF_GHOST_OK=/p;/^fzf_supports_ghost()/,/^}/p" "'"$MANAGER"'")
    fzf() { echo "$1"; }        # pretend an old fzf
    FZF_GHOST_OK=""
    fzf_supports_ghost && echo "old fzf accepted"
    case "0.58" in 0.*) ;; esac
    FZF_GHOST_OK=""
    v=$(fzf --version)
    fzf() { echo "0.74 (devel)"; }
    FZF_GHOST_OK=""
    fzf_supports_ghost || echo "0.74 rejected"
    fzf() { echo ""; }
    FZF_GHOST_OK=""
    fzf_supports_ghost && echo "empty accepted"
    fzf() { echo "1.2.3"; }
    FZF_GHOST_OK=""
    fzf_supports_ghost || echo "1.2.3 rejected"' 2>&1)
# supporting 0.74+ and 1.x, rejecting <0.61 and unreadable versions
if [ -z "$ghost_out" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("fzf_supports_ghost:$ghost_out")
fi

# ---- v5.2 install list: rows must FIT the list pane ----
# A row longer than the pane makes fzf scroll the list horizontally, and the
# user then sees a useless middle slice of the description ("·nes for reading
# and writing data files in FITS (Fle…") instead of the package name. The
# display column is capped with fzf_disp_max, so cap it and measure the rows.
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/row_cap"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
cap_out=$(HOME="$home" PREFIX="$home" MGR=apt COLUMNS=100 LINES=24 bash -c '
    source <(sed -n "/^term_size()/,/^}/p;/^fzf_disp_max()/,/^}/p" "'"$MANAGER"'" 2>/dev/null)
    fzf_disp_max' 2>/dev/null)
long_rows=$(printf '%s\n' \
    "cfitsio|a library of C and Fortran subroutines for reading and writing data files in FITS (Flexible Image Transport System) data format" \
    "git|fast, scalable, distributed revision control system" | \
    awk -v cap="$cap_out" '{ d="【 】 " $1 " · " $2; if (length(d) > cap) d=substr(d,1,cap) "…"; print length(d) "\t" d }' | awk -v cap="$cap_out" '$1 > cap {print}')
# every rendered display column must fit inside the cap
if [ -z "$long_rows" ] && [ -n "$cap_out" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("row_cap:cap=$cap_out,overflow=${long_rows//$'\n'/,}")
fi

# The checkbox must be the fancy bracket pair, and the cap must track the
# screen: a wider screen keeps a wider list (the preview pane takes ~45% on
# wide/landscape screens, and sits below on narrow ones, so the cap follows
# the LAYOUT — 60 cols and 140 cols are both side panes).
TOTAL=$((TOTAL + 1))
cap_wide=$(HOME="$PWD/tmp/row_cap" MGR=apt COLUMNS=200 LINES=60 bash -c '
    source <(sed -n "/^term_size()/,/^}/p;/^fzf_disp_max()/,/^}/p" "'"$MANAGER"'" 2>/dev/null)
    fzf_disp_max' 2>/dev/null)
cap_narrow=$(HOME="$PWD/tmp/row_cap" MGR=apt COLUMNS=140 LINES=60 bash -c '
    source <(sed -n "/^term_size()/,/^}/p;/^fzf_disp_max()/,/^}/p" "'"$MANAGER"'" 2>/dev/null)
    fzf_disp_max' 2>/dev/null)
cap_floor=$(HOME="$PWD/tmp/row_cap" MGR=apt COLUMNS=30 LINES=24 bash -c '
    source <(sed -n "/^term_size()/,/^}/p;/^fzf_disp_max()/,/^}/p" "'"$MANAGER"'" 2>/dev/null)
    fzf_disp_max' 2>/dev/null)
cok=1
[ "$cap_wide" -gt "$cap_narrow" ] 2>/dev/null || cok=0   # wider screen, wider list
[ "$cap_floor" -ge 24 ] 2>/dev/null || cok=0             # floor holds
grep -q '【 】' "$MANAGER" || cok=0                       # the fancy bracket pair
! grep -qF '[ ] ' "$MANAGER" || cok=0                    # old plain checkbox gone
if [ "$cok" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("row_cap_adaptive:cap=$cap_wide/$cap_narrow/$cap_floor"); fi

# ---- v5.3: overflowing rows are cut at the right edge, never H-scrolled ----
# fzf's default --ellipsis is the string '··' and a row wider than the list
# pane gets horizontally scrolled so the matched substring plus hscroll-off
# stays visible: the user saw a useless middle slice wrapped in '··'s with
# the row's leading marker scrolled off ('··passphrase2pgp · Generate
# EdDSA...··'). --no-hscroll anchors every row at its start and cuts the
# tail instead (the same pattern the pkgs tool uses), and --ellipsis='…'
# makes a cut read as normal truncation. Both flags come from fzf_select,
# the one chokepoint every picker passes through.
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/no_hscroll"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
: > "$home/fzfqueue"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF FZF_QUEUE="$home/fzfqueue" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
calls_flat=$(tr '\n' ' ' < "$home/calls" 2>/dev/null)
nok=1
case "$calls_flat" in *"--no-hscroll"*) ;; *) nok=0 ;; esac
case "$calls_flat" in *"--ellipsis=…"*) ;; *) nok=0 ;; esac
# Probed whole-row polish (the fake fzf now answers --help like the real one)
case "$calls_flat" in *"--highlight-line"*) ;; *) nok=0 ;; esac
case "$calls_flat" in *"--scrollbar=▏"*) ;; *) nok=0 ;; esac
# One-key app exit from any picker, plus better ranking
case "$calls_flat" in *"ctrl-q:execute-silent"*) ;; *) nok=0 ;; esac
case "$calls_flat" in *"--tiebreak=begin,length,index"*) ;; *) nok=0 ;; esac
if [ "$nok" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("fzf_no_hscroll"); fi

# ---- Submenu Exit row ----
# Every submenu picker appends a "Back to main menu" row: one tap leaves the
# menu, exactly like ESC. The row is stripped from the answer INSIDE
# fzf_select (the one chokepoint every picker passes through), so no caller
# can ever install a package called "Back to main menu". Picked alone it is a
# plain cancel (rc 1) — it must NOT quit the app: only the main menu's own
# Exit row does that.
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/sub_exit_plain"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
: > "$home/fzfqueue"
printf '%s\n' "📦 Install a package" "⬅️ Back to main menu" >> "$home/fzfqueue"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF ICONS=emoji FZF_QUEUE="$home/fzfqueue" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
eok=1
grep -Fq "Canceled." "$home/run.log" || eok=0               # picker went back a level
[ "$(grep -c '^fzf' "$home/calls")" -eq 2 ] || eok=0        # menu → picker → menu again
[ -f "$home/.pkg-manager-exit" ] && eok=0                    # Back is not an app exit
if [ "$eok" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("sub_exit_plain"); fi

# ...but the explicit "Exit pkg-manager" row (or Ctrl-Q) DOES leave the app,
# from any depth: it sets the flag the main loop answers with the farewell.
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/sub_exit_app"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
: > "$home/fzfqueue"
printf '%s\n' "📦 Install a package" "🚪 Exit pkg-manager" >> "$home/fzfqueue"
export HOME="$home" PREFIX="$home" MGR=apt
env -u NO_FZF ICONS=emoji FZF_QUEUE="$home/fzfqueue" FZF_CALL_LOG="$home/calls" \
    timeout 30 bash "$MANAGER" < /dev/null > "$home/run.log" 2>&1
xok=1
grep -Fq "Catch ya later" "$home/run.log" || xok=0           # farewell = app left
grep -Fq "Canceled." "$home/run.log" && xok=0                # not a cancel message
grep -Fq "python3 installed" "$home/run.log" && xok=0        # nothing was installed
if [ "$xok" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("sub_exit_app"); fi

# Picking a package AND then "Back" must keep the package in the answer: the
# row is stripped in fzf_select and the rest of the selection survives.
TOTAL=$((TOTAL + 1))
shome="$PWD/tmp/sub_exit_strip"
rm -rf "$shome"; mkdir -p "$shome/bin" "$shome/var/cache/apt/archives"
cat > "$shome/bin/fzf" <<'STUB'
#!/usr/bin/env bash
printf 'git|【 】 git · distributed vcs\n\xe2\xac\x85\xef\xb8\x8f Back to main menu|\xe2\xac\x85\xef\xb8\x8f Back to main menu\n'
exit 0
STUB
chmod +x "$shome/bin/fzf"
shead="$PWD/tmp/sub_exit_head.sh"
awk '/^FIRST_LOOP=1$/{exit} {print}' "$MANAGER" > "$shead" 2>/dev/null
strip_out=$(HOME="$shome" PREFIX="$shome" MGR=apt ICONS=emoji COLUMNS=100 LINES=24 \
    PATH="$shome/bin:$PATH" bash -c '
    f="$1"; shift
    source "$f"
    sel=$(printf "%s\n" "git|【 】 git · distributed vcs" \
        "\xe2\xac\x85\xef\xb8\x8f Back to main menu|\xe2\xac\x85\xef\xb8\x8f Back to main menu" | fzf_select "h" "p " 1)
    printf "RETURN<%s>ANSWER<%s>" "$?" "$sel"
' bash "$shead" 2>/dev/null)
rm -f "$shead"
case "$strip_out" in
    *"RETURN<0>ANSWER<git|【 】 git · distributed vcs>"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); FAILED+=("sub_exit_strip:$strip_out") ;;
esac

# Geometry + preview contract (pure functions, no TTY needed).
TOTAL=$((TOTAL + 1))
geo_out=$(bash -c 'source <(sed -n "/^term_size()/,/^}/p;/^fzf_height()/,/^}/p;/^fzf_layout()/,/^}/p;/^fzf_margin()/,/^}/p;/^pkg_preview_cmd()/,/^}/p" "'"$MANAGER"'")
    # wide/landscape → side pane; narrow → bottom pane
    l1=$(COLUMNS=120 LINES=40 fzf_layout); case "$l1" in right:45%:wrap:border-left) ;; *) echo "layout-wide:$l1";; esac
    l2=$(COLUMNS=60 LINES=30 fzf_layout);  case "$l2" in down:45%:wrap:border-top) ;; *) echo "layout-narrow:$l2";; esac
    # height must stay below 100%: at 100% fzf goes fullscreen (alternate
    # screen) and hides the picker. The banner is the window header, so
    # the window may use the whole screen minus one row.
    h1=$(COLUMNS=80 LINES=24 fzf_height);  case "$h1" in 95%) ;; *) echo "height-24:$h1";; esac
    h2=$(COLUMNS=80 LINES=40 fzf_height);  case "$h2" in 95%) ;; *) echo "height-40:$h2";; esac
    h3=$(COLUMNS=80 LINES=200 fzf_height); case "$h3" in 95%) ;; *) echo "height-cap:$h3";; esac
    h4=$(COLUMNS=80 LINES=8 fzf_height);   case "$h4" in 87%) ;; *) echo "height-short:$h4";; esac
    m1=$(COLUMNS=80 LINES=24 fzf_margin);  case "$m1" in 0,2) ;; *) echo "margin-narrow:$m1";; esac
    m2=$(COLUMNS=130 LINES=45 fzf_margin); case "$m2" in 0,6) ;; *) echo "margin-wide:$m2";; esac
    m3=$(COLUMNS=60 LINES=16 fzf_margin);  case "$m3" in 0,2) ;; *) echo "margin-short:$m3";; esac
    # reverse layout keeps natural top-down order
    grep -q -- '--layout=reverse' "$MANAGER" || echo "layout-not-reverse"
    # preview must use the field placeholder and the empty-name guard
    p=$(pkg_preview_cmd); case "$p" in *"{1}"*) ;; *) echo "preview-no-field";; esac
    case "$p" in *"no package under cursor"*) ;; *) echo "preview-no-guard";; esac' 2>/dev/null)
if [ -z "$geo_out" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED+=("fzf_geometry:$geo_out"); fi
cli cli_check_upd    "--check-updates"        "package(s) can be upgraded"
cli cli_quiet        "--quiet"                "1"
cli cli_doctor       "--doctor"               "Health score"

# --- v5.2: nala as a manager, with apt fallback when it is missing ---
cli cli_mgr_nala_cfg  "--version"     "pkg-manager v5.3.1"
TOTAL=$((TOTAL + 1))
home="$PWD/tmp/nala_fallback"
rm -rf "$home"; mkdir -p "$home/var/cache/apt/archives"
touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
# Build a PATH that has every Termux tool EXCEPT nala, so the fallback path is
# genuinely exercised (nala is installed on most dev devices).
mkdir -p "$home/bin"
for f in "$REAL_PREFIX"/bin/*; do
    [ "$(basename "$f")" = "nala" ] || ln -sf "$f" "$home/bin/$(basename "$f")" 2>/dev/null || true
done
out=$(HOME="$home" PREFIX="$home" MGR=nala NO_FZF=1 ICONS=emoji TERM=dumb PATH="$home/bin" \
      timeout 20 bash "$MANAGER" --version < /dev/null 2>&1)
# config validation must accept MGR=nala: the app runs (prints version) rather
# than dying, and the fallback keeps every apt call working.
if printf '%s\n' "$out" | grep -q "pkg-manager v5.3.1"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED+=("nala_fallback:$out")
fi

# --- self-update replace path: runs against a COPY of the script, never the repo file ---
TOTAL=$((TOTAL+1))
home2="$PWD/tmp/selfupdate_replace"
rm -rf "$home2"
mkdir -p "$home2"
cp "$MANAGER" "$home2/pkg-manager"
export HOME="$home2" PREFIX="$home2" MGR=apt
printf '53\ny\n' | timeout 30 bash "$home2/pkg-manager" > "$home2/run.log" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    FAIL=$((FAIL+1)); FAILED+=("selfupdate_replace:exit=$rc")
elif grep -q "fake pkg-manager 9.9" "$home2/pkg-manager" && grep -q "Updated to" "$home2/run.log"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); FAILED+=("selfupdate_replace")
fi

# ---- Real-theme export contract ----
# Every truecolor theme must write a full 18-row colors.properties
# (background, foreground, color0..color15) of valid #RRGGBB values, and a
# legacy 256-color theme must refuse with a clear message instead of writing
# a broken palette.
TOTAL=$((TOTAL + 1))
exhome="$PWD/tmp/export_theme"
rm -rf "$exhome"; mkdir -p "$exhome"
export HOME="$exhome" PREFIX="$exhome" MGR=apt
export_ok=1
for t in dracula catppuccin tokyo nord gruvbox onedark solarized everforest rosepine; do
    rm -rf "$exhome/.termux"
    if ! timeout 20 bash "$MANAGER" --export-theme "$t" > "$exhome/run.log" 2>&1; then
        export_ok=0; FAILED+=("export_theme:$t:rc"); break
    fi
    if [ "$(grep -cE '^[a-z0-9]+=#?[0-9A-F]{6}$' "$exhome/.termux/colors.properties" 2>/dev/null)" -ne 18 ]; then
        export_ok=0; FAILED+=("export_theme:$t:rows"); break
    fi
done
if [ "$export_ok" -eq 1 ]; then
    rm -rf "$exhome/.termux"
    if timeout 20 bash "$MANAGER" --export-theme green > "$exhome/legacy.log" 2>&1; then
        export_ok=0; FAILED+=("export_theme:legacy_green_rc")
    elif ! grep -qF "no full ANSI table" "$exhome/legacy.log"; then
        export_ok=0; FAILED+=("export_theme:legacy_green_msg")
    fi
fi
if [ "$export_ok" -eq 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

echo
echo "== RESULTS =="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "FAILED:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
