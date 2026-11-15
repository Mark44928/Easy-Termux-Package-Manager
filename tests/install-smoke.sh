#!/data/data/com.termux/files/usr/bin/env bash
# Installer CI: fake HOME/PREFIX -> install -> rerun -> uninstall.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/etpm-install-smoke.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/state" "$TMP/prefix"
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state"
bash "$ROOT/install.sh" --prefix "$TMP/prefix" --yes >/dev/null
"$TMP/prefix/bin/pkg-manager" --version >/dev/null
test -f "$XDG_STATE_HOME/pkg-manager/installed.tsv"
bash "$ROOT/install.sh" --prefix "$TMP/prefix" --yes >/dev/null
bash "$ROOT/install.sh" --uninstall --yes >/dev/null
test ! -e "$TMP/prefix/bin/pkg-manager"
test ! -e "$XDG_STATE_HOME/pkg-manager/installed.tsv"
echo "installer smoke OK"
