#!/bin/bash
cd "$(dirname "$0")"
MANAGER="$PWD/../manager.sh"
export PATH="$PWD/fakebin:$PATH"
export GUM_HELPS="$PWD/helps"
export ICONS=emoji

TOTAL=0 PASS=0 FAIL=0
FAILED=()

run() {
    local name="$1" mode="$2" feed="$3" marker="$4" gumen="$5" mgr="${6:-apt}" filechk="${7:-}"
    TOTAL=$((TOTAL+1))
    local home="$PWD/tmp/$name"
    rm -rf "$home"
    mkdir -p "$home/var/cache/apt/archives"
    touch "$home/var/cache/apt/archives/python3_3.12_arm64.deb"
    if [ -d "$PWD/seeds/$name" ]; then
        cp -r "$PWD/seeds/$name/." "$home/"
    fi
    export HOME="$home" PREFIX="$home" GUM_ENABLED="$gumen"
    local log="$home/run.log"
    if [ "$mode" = "gum" ]; then
        : > "$home/queue"
        if [ -n "$feed" ]; then
            while IFS= read -r l; do
                [ -z "$l" ] && continue
                printf '%s' "$l" | base64 -w0 >> "$home/queue"
                printf '\n' >> "$home/queue"
            done < "$feed"
        fi
        export GUM_QUEUE="$home/queue" GUM_CALL_LOG="$home/calls" GUM_VALIDATE_LOG="$home/validate"
        : > "$GUM_CALL_LOG"
        : > "$GUM_VALIDATE_LOG"
        timeout 30 bash "$MANAGER" < <(printf '\n') > "$log" 2>&1
    else
        timeout 30 bash "$MANAGER" < "$feed" > "$log" 2>&1
    fi
    local ok=1
    [ -n "$marker" ] && ! grep -Fq "$marker" "$log" && ok=0
    grep -q "command not found" "$log" && ok=0
    grep -qE "^manager\.sh: line [0-9]+:|bash: " "$log" && ok=0
    if [ "$ok" != "1" ]; then
        FAIL=$((FAIL+1))
        FAILED+=("$name")
        return
    fi
    if [ "$mode" = "gum" ] && grep -q "UNKNOWN FLAG" "$GUM_VALIDATE_LOG"; then
        FAIL=$((FAIL+1))
        FAILED+=("$name:gumflag")
        return
    fi
    if [ -n "$filechk" ]; then
        local glob="${filechk%%|*}" rest="${filechk#*|}"
        local pos="${rest%%|*}" neg="${rest#*|}"
        if [ -n "$glob" ] && ! ls "$home"/$glob >/dev/null 2>&1; then
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

T()  { run "$1" text "$2" "$3" 0 apt "$4"; }
P()  { run "$1" text "$2" "$3" 0 pkg "$4"; }
G()  { run "$1" gum  "$2" "$3" 1 apt "$4"; }
GP() { run "$1" gum  "$2" "$3" 1 pkg "$4"; }

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
T settings_show    <(printf '24\n7\n')                 "No config yet"
T settings_icons   <(printf '24\n4\n')                 "Settings saved"
T history_ok       <(printf '1\npython3\n\n25\n1\n')   "install python3"

# --- invalid package errors ---
T install_bad      <(printf '1\ninvalidpkg\n')         "Package not found"
T info_bad         <(printf '8\ninvalidpkg\n')         "Package not found"
T install_nospace  <(printf '1\nnospace\n')            "Not enough disk space"
T install_held     <(printf '1\nheldpkg\n')            "held back"
T install_conflict <(printf '1\nconfpkg\n')            "File conflict"
T rdepends_bad     <(printf '11\ninvalidpkg\n')        "No reverse dependencies found"
T size_bad         <(printf '12\ninvalidpkg\n')        "Package not in cache"

# --- v2.0 expansion #2 (text/apt) ---
T stats_disk       <(printf '27\n2\n')                 "Disk usage by directory"
T stats_files      <(printf '27\n3\n')                 "Largest files"
T inspect_ok       <(printf '32\npython3\n')           "Inspecting python3"
T maint_ok         <(printf '33\nn\nn\nn\nn\n')        "can be upgraded"
FAKE_UPGRADABLE=empty
export FAKE_UPGRADABLE
T maint_clean      <(printf '33\n')                    "System looks healthy!"
unset FAKE_UPGRADABLE
T groups_show      <(printf '34\n1\n')                 "git tools"
T groups_install   <(printf '34\n2\n1\ny\n')           "Installing group"
T group_create     <(printf '34\n4\nmytools\ncurl wget\n') "created" ".pkg-manager-groups|"
T bulk_pick_rm     <(printf '30\n3\n1 2\ny\n')         "✓ python3"
T bulk_pick_up     <(printf '30\n4\n1\ny\n')           "✓ python3"
T fav_pin          <(printf '31\n5\n')                 "Favorites pinned"
T pin_installed    <(printf '35\ny\n')                 "Installing python3"
T log_errors       <(printf '1\ninvalidpkg\n\n25\n2\n') "No errors in the log"
T undo_remove      <(printf '2\npython3\ny\n\n25\n4\ny\n') "Undo complete!"
T search_install   <(printf '3\npython\npython-tool\ny\n') "✓ python-tool"
T quiet_mode       <(printf '2\npython3\n')             "python3 removed!"
T lock_mode        <(printf '2\npython3\n')             "Canceled."
T group_delete     <(printf '34\n5\n1\ny\n\n34\n5\n')    "No custom groups to delete" ".pkg-manager-groups|"
T undo_pick        <(printf '30\n3\n1 2\ny\n\n25\n4\ny\n') "Undo complete!" "||Setting up picked"
T history_installs <(printf '1\npython3\n\n25\n3\n')    "Install / remove actions:" "||Action history"
T fav_remove_last  <(printf '31\n2\n1\n\n31\n3\n')      "No favorites yet — add some first!"

# --- v2.0 new features (text/apt) ---
T simulate_install <(printf '26\n1\npython3\n')        "Simulated install: python3"
T simulate_remove  <(printf '26\n2\npython3\n')        "Simulated remove: python3"
T simulate_upgrade <(printf '26\n3\n')                 "Simulated upgrade"
T stats_ok         <(printf '27\n1\n')                "Total installed size: 3.0 MiB"
T cache_clean      <(printf '28\n1\ny\n')              "Cache cleaned!"
T cache_autoclean  <(printf '28\n2\ny\n')              "Outdated packages cleaned!"
T cache_show       <(printf '28\n3\n')                 "python3_3.12_arm64.deb"
T deptree_ok       <(printf '29\n1\npython3\n')        "termux-exec"
T orphans_none     <(printf '29\n2\n')                 "No orphaned packages found!"
FAKE_ORPHANS=1
export FAKE_ORPHANS
T orphans_found    <(printf '29\n2\ny\n')              "Orphans removed!"
unset FAKE_ORPHANS
T bulk_install     <(printf '30\n1\npython3 git\ny\n') "Installing 2 packages"
T bulk_remove      <(printf '30\n2\npython3 git\ny\n') "Removing 2 packages"
T fav_add          <(printf '31\n1\npython3\n')        "added to favorites" ".pkg-manager-favs|"
T fav_show         <(printf '31\n3\n')                 "1 favorite"
T fav_dup          <(printf '31\n1\npython3\n')        "already a favorite"
T fav_remove       <(printf '31\n2\n1\n')              "removed from favorites"
T fav_install_all  <(printf '31\n4\ny\n')              "Favorites installed!"

# --- partial / multi-package failures ---
T bulk_partial     <(printf '30\n1\npython3 invalidpkg\ny\n') "1 of 2 succeeded, 1 failed" "||✓ invalidpkg"
T bulk_allfail     <(printf '30\n1\ninvalidpkg\ny\n')     "invalidpkg — Package not found"
T search_partial   <(printf '3\npython\npython-tool invalidpkg\ny\n') "1 of 2 succeeded, 1 failed"
T upgrade_partial  <(printf '6\npython3 invalidpkg\ny\ny\n') "1 of 2 succeeded, 1 failed"
T fav_one_fail     <(printf '31\n6\n1\ny\n')              "Package not found"

# --- pkg mode ---
P pkg_list         <(printf '4\n')                     "python3"
P pkg_upgrade      <(printf '6\na\ny\ny\n')            "Cache cleaned!"
P pkg_backup       <(printf '19\n')                    "Backed up" "pkg-backup-*.txt|"

# --- gum mode ---
G gum_install      <(printf '📦 Install a package\npython3\n') "python3 installed!"
G gum_search       <(printf '🔎 Search packages\npython\n')    "python3/stable 3.12 arm64"
G gum_upgrade      <(printf '🔄 Upgrade center\nAll packages\ny\ny\n') "Cache cleaned!"
G gum_simulate     <(printf '👁️ Simulate a change\nSimulate install\npython3\n') "Simulated install: python3"
G gum_stats        <(printf '📊 Package stats & disk\nOverview\n') "Total installed size: 3.0 MiB"
G gum_cache        <(printf '🗃️ Cache manager\nClean all cached files (apt clean)\ny\n') "Cache cleaned!"
G gum_deptree      <(printf '🌳 Dependency tools\nDependency tree\npython3\n') "termux-exec"
G gum_orphans      <(printf '🌳 Dependency tools\nOrphan finder\n') "No orphaned packages found!"
G gum_bulk         <(printf '📚 Bulk operations\nInstall multiple packages\npython3 git\ny\n') "Installing 2 packages"
G gum_fav          <(printf '⭐ Favorites\nAdd favorite\npython3\n') "added to favorites" ".pkg-manager-favs|"
G gum_upgrade_some <(printf '🔄 Upgrade center\npython3\ny\ny\n') "Cache cleaned!"
G gum_fav_install  <(printf '⭐ Favorites\nInstall all favorites\ny\n') "Favorites installed!"
G gum_inspect      <(printf '🔍 Package inspector\npython3\n') "Inspecting python3"
G gum_maint        <(printf '🩺 Maintenance wizard\nn\nn\nn\nn\n') "can be upgraded"
G gum_groups_show  <(printf '🗂️ Package groups\nShow all groups\n') "git tools"
G gum_group_install <(printf '🗂️ Package groups\nInstall a group\ngit tools\ny\n') "Installing group"
G gum_stats_disk   <(printf '📊 Package stats & disk\nDisk usage by directory\n') "Disk usage by directory"
G gum_bulk_pick    <(printf '📚 Bulk operations\nRemove (pick from installed list)\npython3\ny\n') "✓ python3"
GP gum_pkg_list    <(printf '📜 List installed packages\n') "python3"
GP gum_pkg_upgrade <(printf '🔄 Upgrade center\nAll packages\ny\ny\n') "Cache cleaned!"

echo
echo "== RESULTS =="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "FAILED:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
