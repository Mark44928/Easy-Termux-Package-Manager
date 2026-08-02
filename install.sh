#!/bin/bash
set -e

REPO="https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master"
PREFIX="${PREFIX:-/usr/local}"
BIN="$PREFIX/bin/pkg-manager"
DIR="$(cd "$(dirname "$0")" && pwd)"
FONT_DIR="$DIR/fonts"
FONT_REMOTE_DIR="$REPO/fonts"
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
    local font="$1" tmp
    echo "==> Installing $font ..."
    mkdir -p "$HOME/.termux"
    tmp="$HOME/.termux/.font.ttf.tmp"
    if [ -f "$FONT_DIR/$font" ]; then
        cp "$FONT_DIR/$font" "$tmp"
    else
        curl -fsSL "$FONT_REMOTE_DIR/$font" -o "$tmp"
    fi
    mv -f "$tmp" "$TERMUX_FONT"
    echo "✓ $font installed → $TERMUX_FONT"
    if command -v termux-reload-settings >/dev/null 2>&1; then
        termux-reload-settings >/dev/null 2>&1 || true
        echo "  Settings reloaded — the font should be live."
    fi
    echo "  If it didn't apply, fully close Termux (swiping from Recents won't do it —"
    echo "  background sessions keep it alive). Type \"exit\" or run:  am force-stop com.termux"
    echo "  then reopen the app."
}

if [ -d "$HOME/.termux" ]; then
    echo "Install a Nerd Font for the icons?"
    echo "Friendly Warning: Font installation skips if invalid choice or a typo"
    echo "  [1] CaskaydiaCove (recommended)"
    echo "  [2] FiraCode (alternative)"
    echo "  [s] Skip"
    printf "Choice [1] or [s]: "
    read -r _ans
    case "${_ans,,}" in
        ""|1) install_font "CaskaydiaCoveNerdFont-Regular.ttf";;
        2)    install_font "FiraCodeNerdFont-Regular.ttf";;
        s)    echo "Skipping the font install.";;
        *)    echo "Invalid choice — skipping the font install.";;
    esac
fi

if [ -t 0 ]; then
    echo "==> Launching..."
    "$BIN"
fi
