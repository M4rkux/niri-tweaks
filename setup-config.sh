#!/usr/bin/env bash
# Adds the niri-tweaks shortcuts and layout options to your niri config.
#
# - Reads the binds already in your config (every .kdl under the config dir).
# - Shortcuts you don't have yet: shown as a list, added after one confirmation.
# - Shortcuts whose key you already use for something else: asks, one by one.
# - Shortcuts you already have exactly: skipped.
# - Optionally enables toggle-center-column / reset-height-when-alone (needs the patched niri).
#
# Everything goes into ~/.config/niri/niri-tweaks.kdl, included at the end of config.kdl so it
# takes precedence. Your own files are never edited, except for that one include line.
# Re-running is safe: it regenerates niri-tweaks.kdl from scratch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TWEAK_BINDS="$HERE/binds.kdl"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$CONFIG_DIR/config.kdl"
OUT_NAME="niri-tweaks.kdl"
OUT="$CONFIG_DIR/$OUT_NAME"
INCLUDE_LINE="include \"$OUT_NAME\""
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { echo "error: $*" >&2; exit 1; }

ask() { # ask "question" default(y|n) -> returns 0 for yes
    local q="$1" def="$2" ans hint="[y/N]"
    [[ "$def" == y ]] && hint="[Y/n]"
    read -r -p "$q $hint " ans 2>/dev/null </dev/tty || ans=""
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy] ]]
}

command -v niri >/dev/null || die "niri not found in PATH"
[[ -f "$MAIN" ]] || die "$MAIN not found"

# Prints one line per bind: normalized-key <TAB> key <TAB> action <TAB> full line.
# Only looks at single-line binds inside `binds { }` blocks; skips // comments and /- binds.
parse_binds() {
    awk '
    function norm(key,   n, parts, i, j, mods, m, last, tmp) {
        key = tolower(key)
        n = split(key, parts, "+")
        last = parts[n]
        m = 0
        for (i = 1; i < n; i++) {
            p = parts[i]
            if (p == "control") p = "ctrl"
            if (p == "win") p = "super"
            mods[++m] = p
        }
        # sort modifiers so Mod+Shift+Ctrl == Mod+Ctrl+Shift
        for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++)
            if (mods[j] < mods[i]) { tmp = mods[i]; mods[i] = mods[j]; mods[j] = tmp }
        out = ""
        for (i = 1; i <= m; i++) out = out mods[i] "+"
        return out last
    }
    {
        line = $0
        sub(/\/\/.*/, "", line)               # strip // comments
        if (!inbinds) {
            if (line ~ /^[ \t]*binds[ \t]*\{/) { inbinds = 1; depth = 0 }
            else next
        }
        # brace depth inside the binds block
        opens = gsub(/\{/, "{", line); closes = gsub(/\}/, "}", line)
        if (line ~ /^[ \t]*binds[ \t]*\{/) { depth += opens - closes; next }
        if (depth == 1 && opens == 1 && closes == 1 && line !~ /^[ \t]*\/-/) {
            if (match(line, /^[ \t]*[^ \t{]+/)) {
                key = substr(line, RSTART, RLENGTH); gsub(/[ \t]/, "", key)
                action = line; sub(/^[^{]*\{[ \t]*/, "", action); sub(/[ \t]*\}[ \t]*$/, "", action)
                gsub(/[ \t]+/, " ", action)
                full = $0; sub(/^[ \t]+/, "", full); sub(/[ \t]*\/\/.*$/, "", full)
                print norm(key) "\t" key "\t" action "\t" full
            }
        }
        depth += opens - closes
        if (depth <= 0) inbinds = 0
    }' "$@"
}

# Existing binds, from every config file except our own output and backups. Later definitions win,
# like in niri, so keep the last one per key.
mapfile -t CONFIG_FILES < <(find "$CONFIG_DIR" -name '*.kdl' ! -name "$OUT_NAME" ! -name '*.bak*' | sort)
declare -A HAVE_ACTION HAVE_KEY
if ((${#CONFIG_FILES[@]})); then
    while IFS=$'\t' read -r nk key action _full; do
        HAVE_ACTION["$nk"]="$action"; HAVE_KEY["$nk"]="$key"
    done < <(parse_binds "${CONFIG_FILES[@]}")
fi

NEW=(); CONFLICTS=(); SAME=0
declare -A TWEAK_LINE TWEAK_ACTION TWEAK_KEY
while IFS=$'\t' read -r nk key action full; do
    TWEAK_LINE["$nk"]="$full"; TWEAK_ACTION["$nk"]="$action"; TWEAK_KEY["$nk"]="$key"
    if [[ -z "${HAVE_ACTION[$nk]+x}" ]]; then
        NEW+=("$nk")
    elif [[ "${HAVE_ACTION[$nk]}" == "$action" ]]; then
        SAME=$((SAME + 1))
    else
        CONFLICTS+=("$nk")
    fi
done < <(parse_binds "$TWEAK_BINDS")

CHOSEN=()

echo "Shortcuts: ${#NEW[@]} new, ${#CONFLICTS[@]} conflicting with yours, $SAME already set."
echo

if ((${#NEW[@]})); then
    echo "New shortcuts (these keys are free in your config):"
    for nk in "${NEW[@]}"; do printf '  %-26s %s\n' "${TWEAK_KEY[$nk]}" "${TWEAK_ACTION[$nk]}"; done
    if ask "Add these ${#NEW[@]} shortcuts?" y; then CHOSEN+=("${NEW[@]}"); fi
    echo
fi

if ((${#CONFLICTS[@]})); then
    echo "These keys are already bound to something else in your config."
    echo "Answer y to use the niri-tweaks action, n to keep yours, a = yes to all, s = keep all."
    mode=""
    for nk in "${CONFLICTS[@]}"; do
        if [[ "$mode" == all ]]; then CHOSEN+=("$nk"); continue; fi
        if [[ "$mode" == none ]]; then continue; fi
        printf '\n  %s\n    yours:      %s\n    niri-tweaks: %s\n' \
            "${HAVE_KEY[$nk]}" "${HAVE_ACTION[$nk]}" "${TWEAK_ACTION[$nk]}"
        read -r -p "  Replace? [y/N/a/s] " ans 2>/dev/null </dev/tty || ans=""
        case "$ans" in
            [Yy]*) CHOSEN+=("$nk") ;;
            [Aa]*) CHOSEN+=("$nk"); mode=all ;;
            [Ss]*) mode=none ;;
            *) ;;
        esac
    done
    echo
fi

# Layout options from the patch. Check that the niri in PATH understands them first.
LAYOUT_FLAGS=()
probe="$(mktemp --suffix=.kdl)"
trap 'rm -f "$probe"' EXIT
printf 'layout {\n    toggle-center-column\n    reset-height-when-alone\n}\n' >"$probe"
if niri validate -c "$probe" >/dev/null 2>&1; then
    if ask "Enable toggle-center-column (pressing center-column again goes back)?" y; then
        LAYOUT_FLAGS+=("toggle-center-column")
    fi
    if ask "Enable reset-height-when-alone (last window in a column fills it again)?" y; then
        LAYOUT_FLAGS+=("reset-height-when-alone")
    fi
else
    echo "The niri in PATH doesn't have the niri-tweaks patch, so the layout options are skipped."
    echo "Run ./install.sh, log out and back in, then run this script again to enable them."
fi
echo

if ((${#CHOSEN[@]} == 0 && ${#LAYOUT_FLAGS[@]} == 0)); then
    echo "Nothing to write."
    exit 0
fi

# Back up and write.
[[ -f "$OUT" ]] && cp "$OUT" "$OUT.bak-$STAMP"
{
    echo "// Generated by niri-tweaks/setup-config.sh on $STAMP. Re-run the script to change it."
    if ((${#LAYOUT_FLAGS[@]})); then
        echo
        echo "layout {"
        for f in "${LAYOUT_FLAGS[@]}"; do echo "    $f"; done
        echo "}"
    fi
    if ((${#CHOSEN[@]})); then
        echo
        echo "binds {"
        for nk in "${CHOSEN[@]}"; do echo "    ${TWEAK_LINE[$nk]}"; done
        echo "}"
    fi
} >"$OUT"

added_include=0
if ! grep -qxF "$INCLUDE_LINE" "$MAIN"; then
    cp "$MAIN" "$MAIN.bak-$STAMP"
    printf '\n// niri-tweaks (keep last so it takes precedence)\n%s\n' "$INCLUDE_LINE" >>"$MAIN"
    added_include=1
fi

if niri validate >/dev/null 2>&1; then
    echo "Wrote $OUT (${#CHOSEN[@]} shortcuts, ${#LAYOUT_FLAGS[@]} layout options)."
    ((added_include)) && echo "Added '$INCLUDE_LINE' to the end of $MAIN (backup: $MAIN.bak-$STAMP)."
    echo "niri reloads the config automatically."
else
    echo "niri validate failed; rolling back:" >&2
    niri validate >&2 || true
    if [[ -f "$OUT.bak-$STAMP" ]]; then mv "$OUT.bak-$STAMP" "$OUT"; else rm -f "$OUT"; fi
    ((added_include)) && mv "$MAIN.bak-$STAMP" "$MAIN"
    exit 1
fi
