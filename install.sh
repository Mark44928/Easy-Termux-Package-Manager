#!/bin/bash
set -e

# ── Terminal styling (auto-disabled when piped or NO_COLOR) ──────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    R=$'\e[0m';  BD=$'\e[1m';  DM=$'\e[2m'
    RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'
    CYN=$'\e[36m'
else
    R=; BD=; DM=; RED=; GRN=; YEL=; CYN=
fi

hdr()     { printf '%b\n' "${BD}${CYN}══ ${*} ══${R}"; }
ok()      { printf '%b\n' "  ${GRN}✔${R} ${*}"; }
info()    { printf '%b\n' "  ${DM}➜${R} ${*}"; }
warn()    { printf '%b\n' "  ${YEL}⚠${R} ${*}"; }
divider() { printf '%b\n' "${DM}$(printf '─%.0s' {1..50})${R}"; }

REPO="https://raw.githubusercontent.com/Mark44928/Easy-Termux-Package-Manager/master"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="$PREFIX/bin/pkg-manager"
DIR="$(cd "$(dirname "$0")" && pwd)"
FONT_DIR="$DIR/fonts"
FONT_REMOTE_DIR="$REPO/fonts"
TERMUX_FONT="$HOME/.termux/font.ttf"
BIN_TMP=$(mktemp "$PREFIX/bin/.pkg-manager.XXXXXX" 2>/dev/null) || BIN_TMP=$(mktemp "$HOME/.pkg-manager-install.XXXXXX") || { warn "Cannot create a temp file"; exit 1; }
FONT_TMP=$(mktemp "$HOME/.termux/.font.ttf.XXXXXX" 2>/dev/null) || FONT_TMP=$(mktemp "$HOME/.pkg-manager-font.XXXXXX")

trap 'rm -f "$BIN_TMP" "$FONT_TMP"' EXIT INT TERM

# ── Header ────────────────────────────────────────────────────────────────
printf '%b\n' "${CYN}╭────────────────────────────────────────────────╮${R}"
printf '%b\n' "${CYN}│${R}     ${BD}✨ Easy Termux Package Manager · v3.0${R}      ${CYN}│${R}"
printf '%b\n' "${CYN}│${R}     the one-command Termux package manager     ${CYN}│${R}"
printf '%b\n' "${CYN}╰────────────────────────────────────────────────╯${R}"
divider
info "Installing globally to: ${BD}${BIN}${R}"

# ── Fetch the manager ────────────────────────────────────────────────────
if [ -f "$DIR/manager.sh" ]; then
    ok "Using local ${BD}manager.sh${R} from this repository..."
    cp "$DIR/manager.sh" "$BIN_TMP" || { warn "Failed to copy $DIR/manager.sh to $BIN_TMP"; exit 1; }
else
    if ! command -v curl >/dev/null 2>&1; then
        warn "${RED}curl not found — aborting.${R} Install it with: ${BD}pkg install curl${R}"
        exit 1
    fi
    if ! command -v gum >/dev/null 2>&1; then
        hdr "Installing gum (for the fancy UI)"
        if command -v pkg >/dev/null 2>&1; then
            pkg install -y gum >/dev/null 2>&1 || warn "gum install failed — continuing without it"
        else
            warn "gum not available — continuing without it"
        fi
    fi
    hdr "Downloading manager.sh"
    curl -fsSL "$REPO/manager.sh" -o "$BIN_TMP" || { warn "Failed to download $REPO/manager.sh to $BIN_TMP"; exit 1; }
fi

mkdir -p "$(dirname "$BIN")" || { warn "Failed to create $(dirname "$BIN")"; exit 1; }
mv -f "$BIN_TMP" "$BIN" || { warn "Failed to move $BIN_TMP to $BIN"; exit 1; }
chmod +x "$BIN" || { warn "Failed to chmod $BIN"; exit 1; }
bash_path=$(command -v bash)
if [ -n "$bash_path" ]; then
    sed -i "1s|^#!.*|#!$bash_path|" "$BIN" || warn "Failed to fix shebang in $BIN"
else
    warn "bash not found — cannot fix shebang in $BIN"
fi

divider
ok "Installed → ${BD}${BIN}${R}"
case ":$PATH:" in
    *:"${BIN%/pkg-manager}":*) ;;
    *)
        warn "${BIN%/pkg-manager} is not on your PATH — add it with:"
        info "${BD}export PATH=\"${BIN%/pkg-manager}:\$PATH\"${R} (then re-open the terminal)"
        ;;
esac
info "Run it anytime with: ${BD}pkg-manager${R}"
divider

# ── Nerd Font install ────────────────────────────────────────────────────
install_font() {
    local font="$1"
    hdr "Installing font: $font"
    mkdir -p "$HOME/.termux" || { warn "Failed to create $HOME/.termux"; return 1; }
    if [ -f "$FONT_DIR/$font" ]; then
        cp "$FONT_DIR/$font" "$FONT_TMP" || { warn "Failed to copy $FONT_DIR/$font to $FONT_TMP"; return 1; }
    else
        curl -fsSL "$FONT_REMOTE_DIR/$font" -o "$FONT_TMP" || { warn "Failed to download $FONT_REMOTE_DIR/$font to $FONT_TMP"; return 1; }
    fi
    mv -f "$FONT_TMP" "$TERMUX_FONT" || { warn "Failed to move $FONT_TMP to $TERMUX_FONT"; return 1; }
    ok "$font installed → $TERMUX_FONT"
    if command -v termux-reload-settings >/dev/null 2>&1; then
        termux-reload-settings >/dev/null 2>&1 || true
        ok "Settings reloaded — the font should be live."
    fi
    info "If it didn't apply, fully close Termux (swiping from Recents won't"
    info "do it — background sessions keep it alive). Type ${BD}exit${R} or run:"
    info "${BD}am force-stop com.termux${R}, then reopen the app."
}

if [ -n "${FONT:-}" ]; then
    case "${FONT,,}" in
        1|cask*) install_font "CaskaydiaCoveNerdFont-Regular.ttf" ;;
        2|fira*)            install_font "FiraCodeNerdFont-Regular.ttf" ;;
        s|skip|none)        warn "Skipping the font install." ;;
        *)                  warn "Invalid FONT value '$FONT' — skipping the font install." ;;
    esac
elif [ -d "$HOME/.termux" ]; then
    hdr "Nerd Font (for the icon glyphs)"
    printf '%b\n' "${BD}Install a Nerd Font for the icons?${R}"
    printf '%b\n' "  ${CYN}[1]${R} ${BD}CaskaydiaCove${R} (recommended) — clean, balanced, gorgeous"
    printf '%b\n' "  ${CYN}[2]${R} ${BD}FiraCode${R} (alternative)      — the classic coding font"
    printf '%b\n' "  ${DM}[s]${R} Skip (icons fall back to emoji inside the app)"
    printf '%b\n' "  ${DM}Tip: an invalid choice simply skips the install — no harm done. 💡${R}"
    printf '%b'   "Choice ${CYN}[1]${R} or ${DM}[s]${R}: "
    if [ -t 0 ]; then
        read -r _ans
    else
        read -r _ans < /dev/tty 2>/dev/null || _ans="s"
    fi
    case "${_ans,,}" in
        ""|1) install_font "CaskaydiaCoveNerdFont-Regular.ttf";;
        2)    install_font "FiraCodeNerdFont-Regular.ttf";;
        s)    warn "Skipping the font install.";;
        *)    warn "Invalid choice — skipping the font install.";;
    esac
else
    warn "$HOME/.termux not found — skipping the font install."
    warn "To see the Nerd Font icon glyphs, install a Nerd Font manually"
    warn "(or re-run this installer after creating ~/.termux)."
fi

# ── Done ──────────────────────────────────────────────────────────────────
divider
printf '%b\n' "${GRN}╭────────────────────────────────────────────────╮${R}"
printf '%b\n' "${GRN}│${R}                  ${BD}✅ All set!${R}                   ${GRN}│${R}"
printf '%b\n' "${GRN}│${R}        ${BD}type  pkg-manager  to launch it${R}         ${GRN}│${R}"
printf '%b\n' "${GRN}╰────────────────────────────────────────────────╯${R}"

if [ -t 0 ]; then
    printf '%b\n' "${DM}Launching...${R}"
    "$BIN"
fi
