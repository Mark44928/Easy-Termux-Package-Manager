#!/bin/bash
set -e

REPO="https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master"
PREFIX="${PREFIX:-/usr/local}"
BIN="$PREFIX/bin/pkg-manager"
DIR="$(cd "$(dirname "$0")" && pwd)"
FONT_LOCAL="$DIR/fonts/FiraCodeNerdFont-Regular.ttf"
FONT_REMOTE="$REPO/fonts/FiraCodeNerdFont-Regular.ttf"
TERMUX_FONT="$HOME/.termux/font.ttf"

echo "==> Easy Termux Package Manager installer"
echo "    Installing globally to: $BIN"

if [ -f "$DIR/manager.sh" ]; then
    echo "==> Using local manager.sh from this repository..."
    cp "$DIR/manager.sh" "$BIN"
else
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found — aborting. Install it with: pkg install curl"
        exit 1
    fi
    if ! command -v gum >/dev/null 2>&1; then
        echo "==> Installing gum (for the fancy UI)..."
        if command -v pkg >/dev/null 2>&1; then
            pkg install -y gum >/dev/null 2>&1 || echo "    gum install failed — continuing without it"
        else
            echo "    gum not available — continuing without it"
        fi
    fi
    echo "==> Downloading manager.sh..."
    curl -fsSL "$REPO/manager.sh" -o "$BIN"
fi

chmod +x "$BIN"
sed -i "1s|^#!.*|#!$(command -v bash)|" "$BIN"

echo "✓ Installed → $BIN"
echo "  Run it anytime with:  pkg-manager"

install_font() {
    local tmp
    echo "==> Installing FiraCode Nerd Font (Regular)..."
    mkdir -p "$HOME/.termux"
    tmp="$HOME/.termux/.font.ttf.tmp"
    if [ -f "$FONT_LOCAL" ]; then
        cp "$FONT_LOCAL" "$tmp"
    else
        curl -fsSL "$FONT_REMOTE" -o "$tmp"
    fi
    mv -f "$tmp" "$TERMUX_FONT"
    echo "✓ Font installed → $TERMUX_FONT"
    if command -v termux-reload-settings >/dev/null 2>&1; then
        termux-reload-settings >/dev/null 2>&1 || true
        echo "  Settings reloaded — the font should be live."
    fi
    echo "  If it didn't apply, fully close Termux (swiping from Recents won't do it —"
    echo "  background sessions keep it alive). Type \"exit\" or run:  am force-stop com.termux"
    echo "  then reopen the app."
}

if [ -d "$HOME/.termux" ]; then
    printf "Install the FiraCode Nerd Font for the icons? [y/N] "
    read -r _ans
    if [[ "${_ans,,}" == "y" ]]; then
        install_font
    fi
else
    echo "Note: running outside Termux — skipping the font install."
fi

if [ -t 0 ]; then
    echo "==> Launching..."
    "$BIN"
fi
