#!/data/data/com.termux/files/usr/bin/env bash
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

# ── Flags ─────────────────────────────────────────────────────────────────
#   --theme <name>   after install, export that theme's terminal palette to
#                    ~/.termux/colors.properties (pkg-manager --export-theme)
#   --yes            non-interactive: skip font + launch prompts
#   --help           show this
THEME_ARG=""
YES=0
while [ $# -ge 1 ]; do
    case "$1" in
        -t|--theme)
            [ -n "${2:-}" ] || { printf 'install.sh: --theme needs a name (see: pkg-manager --list-themes)\n' >&2; exit 2; }
            THEME_ARG="$2"; shift 2 ;;
        --theme=*) THEME_ARG="${1#*=}"; shift ;;
        -y|--yes) YES=1; shift ;;
        -h|--help)
            printf 'install.sh — Easy Termux Package Manager installer\n\n'
            printf 'Usage: bash install.sh [--theme <name>] [--yes]\n\n'
            printf '  --theme <name>  also set the terminal colors to that theme\n'
            printf '                  (truecolor themes: dracula, nord, catppuccin,\n'
            printf '                  tokyo, gruvbox, onedark, solarized, everforest,\n'
            printf '                  rosepine ... see: pkg-manager --list-themes)\n'
            printf '  --yes           skip all interactive prompts\n'
            printf '  FONT=1|2|s      env: font choice (1 caskaydia, 2 firacode, s skip)\n'
            exit 0 ;;
        *) printf 'install.sh: unknown option %s (try --help)\n' "$1" >&2; exit 2 ;;
    esac
done

BIN_TMP=$(mktemp "$PREFIX/bin/.pkg-manager.XXXXXX" 2>/dev/null) || BIN_TMP=$(mktemp "$HOME/.pkg-manager-install.XXXXXX") || { warn "Cannot create a temp file"; exit 1; }
FONT_TMP=$(mktemp "$HOME/.termux/.font.ttf.XXXXXX" 2>/dev/null) || FONT_TMP=$(mktemp "$HOME/.pkg-manager-font.XXXXXX")

trap 'rm -f "$BIN_TMP" "$FONT_TMP"; exit 130' INT TERM
trap 'rm -f "$BIN_TMP" "$FONT_TMP"' EXIT

# ── Helper tools: fzf is the interactive UI ─────────────────────────────
declare -a MISSING=()
command -v fzf >/dev/null 2>&1 || MISSING+=("fzf")
if [ ${#MISSING[@]} -gt 0 ]; then
    hdr "Installing helper tools:${MISSING[*]}"
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y "${MISSING[@]}" >/dev/null 2>&1 || warn "install of ${MISSING[*]} failed — the app still works in text mode"
    elif command -v apt >/dev/null 2>&1; then
        apt install -y "${MISSING[@]}" >/dev/null 2>&1 || warn "install of ${MISSING[*]} failed — the app still works in text mode"
    else
        warn "Cannot install ${MISSING[*]} automatically (no pkg/apt on PATH)"
    fi
fi

# ── Version (read from manager.sh so the installer can never drift) ───────
detect_version() {
    local f="$1" v=""
    [ -f "$f" ] || { echo ""; return; }
    v=$(grep -m1 -oP '^VERSION="\K[^"]+' "$f" 2>/dev/null || true)
    echo "$v"
}
VERSION="$(detect_version "$DIR/manager.sh")"

# ── Header ────────────────────────────────────────────────────────────────
printf '%b\n' "${CYN}╭────────────────────────────────────────────────╮${R}"
printf '%b\n' "${CYN}│${R}   ${BD}✨ Easy Termux Package Manager · v${VERSION:-?}${R}      ${CYN}│${R}"
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
    hdr "Downloading manager.sh"
    curl -fsSL "$REPO/manager.sh" -o "$BIN_TMP" || { warn "Failed to download $REPO/manager.sh to $BIN_TMP"; exit 1; }
fi

mkdir -p "$(dirname "$BIN")" || { warn "Failed to create $(dirname "$BIN")"; exit 1; }
# Syntax-check and smoke-test the candidate BEFORE it replaces any
# already-working install — never leave a broken payload at $BIN.
chmod +x "$BIN_TMP" || { warn "Failed to make $BIN_TMP executable"; exit 1; }
bash_path=$(command -v bash) || bash_path=""
if [ -n "$bash_path" ]; then
    sed -i "1s|^#!.*|#!$bash_path|" "$BIN_TMP" || { warn "Failed to fix shebang in $BIN_TMP"; exit 1; }
else
    warn "bash not found — cannot fix shebang in $BIN_TMP"
fi
if ! bash -n "$BIN_TMP" 2>/dev/null; then
    warn "${RED}The downloaded script has a syntax error — aborting.${R}"
    warn "It may be a corrupted download; re-run this installer."
    exit 1
fi
if ! "$BIN_TMP" --version >/dev/null 2>&1; then
    warn "${RED}The downloaded script failed its smoke test (--version) — aborting.${R}"
    warn "Re-run this installer; if it keeps failing, report it with your Termux version."
    exit 1
fi
mv -f "$BIN_TMP" "$BIN" || { warn "Failed to move $BIN_TMP to $BIN"; exit 1; }
chmod +x "$BIN" || { warn "Failed to chmod $BIN"; exit 1; }
ok "Smoke test passed ($("$BIN" --version 2>/dev/null | head -n1))"

divider
ok "Installed → ${BD}${BIN}${R}"
case ":$PATH:" in
    *:"${BIN%/pkg-manager}":*) ;;
    *)
        warn "${BIN%/pkg-manager} is not on your PATH — add it with:"
        info "${BD}export PATH=\"${BIN%/pkg-manager}:\$PATH\"${R} (then re-open the terminal)"
        ;;
esac
info "Run it anytime with: ${BD}pkg-manager${R}   ·   quick help: ${BD}pkg-manager --help${R}"
divider
info "${BD}v${VERSION:-?} highlights:${R} 9 truecolor themes (dracula, catppuccin, tokyo-night, nord,"
info "  gruvbox, one-dark, solarized, everforest, rose-pine …) + 7 legacy ones · theme hub with live"
info "  preview + Termux colors.properties export · ${BD}fzf pickers${R} for install/uninstall"
info "  with live package-info preview panes and the command palette ·"
info "  apt / pkg backends · undo engine · dep tree · system audit / doctor ·"
info "  snapshot/diff · essential toolkit · --check-updates --quiet --doctor"
info "Nerd Font below for the icon glyphs"

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
        1|cask*)       install_font "CaskaydiaCoveNerdFont-Regular.ttf" || warn "Font install failed — continuing (the app works without it)." ;;
        2|fira*)       install_font "FiraCodeNerdFont-Regular.ttf" || warn "Font install failed — continuing (the app works without it)." ;;
        s|skip|none)   warn "Skipping the font install." ;;
        *)             warn "Invalid FONT value '$FONT' — skipping the font install." ;;
    esac
elif [ $YES -eq 1 ]; then
    warn "--yes given — skipping the font install."
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
        ""|1) install_font "CaskaydiaCoveNerdFont-Regular.ttf" || warn "Font install failed — continuing (the app works without it)." ;;
        2)    install_font "FiraCodeNerdFont-Regular.ttf" || warn "Font install failed — continuing (the app works without it)." ;;
        s)    warn "Skipping the font install." ;;
        *)    warn "Invalid choice — skipping the font install." ;;
    esac
else
    warn "$HOME/.termux not found — skipping the font install."
    warn "To see the Nerd Font icon glyphs, install a Nerd Font manually"
    warn "(or re-run this installer after creating ~/.termux)."
fi

# ── Terminal theme export (--theme <name>) ────────────────────────────────
if [ -n "$THEME_ARG" ]; then
    hdr "Exporting theme: $THEME_ARG"
    mkdir -p "$HOME/.termux" || warn "Cannot create $HOME/.termux"
    if "$BIN" --export-theme "$THEME_ARG"; then
        if command -v termux-reload-settings >/dev/null 2>&1; then
            termux-reload-settings >/dev/null 2>&1 || true
            ok "Settings reloaded — the palette should be live."
        fi
        info "Inside Termux, revert anytime with Settings → Themes → Restore"
        info "(or delete $HOME/.termux/colors.properties)."
    else
        warn "Theme export failed — the app itself is installed and fine."
        info "Truecolor themes only: try ${BD}pkg-manager --list-themes${R}"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────
divider
printf '%b\n' "${GRN}╭────────────────────────────────────────────────╮${R}"
printf '%b\n' "${GRN}│${R}                  ${BD}✅ All set!${R}                   ${GRN}│${R}"
printf '%b\n' "${GRN}│${R}        ${BD}type  pkg-manager  to launch it${R}         ${GRN}│${R}"
printf '%b\n' "${GRN}╰────────────────────────────────────────────────╯${R}"

if [ $YES -eq 1 ]; then
    warn "--yes given — not launching the app."
elif [ -t 0 ]; then
    printf '%b\n' "${DM}Launching...${R}"
    "$BIN"
fi
