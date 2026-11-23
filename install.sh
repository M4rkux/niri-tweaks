#!/usr/bin/env bash
# Build niri with the niri-tweaks patch and install it to /usr/local/bin/niri.
#
# /usr/local/bin comes before /usr/bin in PATH (including systemd's), so the patched binary is
# used by niri-session / niri.service while your package manager keeps owning /usr/bin/niri.
#
# Usage:
#   ./install.sh               build for the niri version your system has installed
#   ./install.sh v26.04        build a specific niri tag
#   ./install.sh --uninstall   remove /usr/local/bin/niri (back to your distro's niri)
#
# Re-run it after every niri update: until you do, the old patched build keeps running.
set -euo pipefail

TESTED_TAG="v26.04"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/patches/niri-tweaks.patch"
SRC="${NIRI_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/niri-tweaks/niri}"
DEST="/usr/local/bin/niri"
REPO_URL="https://github.com/niri-wm/niri.git"

die() { echo "error: $*" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
    sudo rm -v -f "$DEST"
    echo "Removed. Log out and back in to use your distro's niri again."
    exit 0
fi

command -v git >/dev/null || die "git is required"
command -v cargo >/dev/null || die "cargo is required (install rustup or your distro's rust package)"

# Figure out which niri version to build. Prefer the distro binary over $DEST, since $DEST is
# our own (possibly outdated) build.
detect_tag() {
    local ver=""
    if command -v pacman >/dev/null && pacman -Q niri >/dev/null 2>&1; then
        ver="$(pacman -Q niri | awk '{print $2}')"   # e.g. 26.04-1
        ver="${ver%%-*}"
    elif [[ -x /usr/bin/niri ]]; then
        ver="$(/usr/bin/niri --version | awk '{print $2}')"   # "niri 26.04 (...)"
    fi
    [[ -n "$ver" ]] && echo "v$ver"
}

TAG="${1:-$(detect_tag || true)}"
[[ -n "$TAG" ]] || die "couldn't detect your niri version; pass a tag, e.g. ./install.sh $TESTED_TAG"

echo "==> niri tag: $TAG (patch tested on $TESTED_TAG)"
if [[ "$TAG" != "$TESTED_TAG" ]]; then
    echo "    note: $TAG is untested. If the patch doesn't apply, open an issue or use $TESTED_TAG."
fi

if [[ ! -d "$SRC/.git" ]]; then
    echo "==> Cloning niri into $SRC"
    mkdir -p "$(dirname "$SRC")"
    git clone --quiet "$REPO_URL" "$SRC"
fi

cd "$SRC"
git fetch --quiet --tags origin
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG doesn't exist in $REPO_URL"

# Start from a clean checkout of the tag (keeps target/ for faster rebuilds).
git reset --quiet --hard
git clean -fdq -e target
git checkout --quiet --detach "$TAG"

echo "==> Applying patch"
if ! git apply --3way "$PATCH"; then
    die "the patch doesn't apply cleanly to $TAG. Resolve the conflicts in $SRC, or build $TESTED_TAG."
fi

echo "==> Building (cargo build --release); the first build takes a few minutes"
cargo build --release --locked

BIN="$SRC/target/release/niri"

if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl" ]]; then
    echo "==> Checking your config with the new build"
    "$BIN" validate || die "your config doesn't validate with the new build; not installing"
fi

echo "==> Installing to $DEST (needs sudo)"
sudo install -m755 "$BIN" "$DEST"

echo
echo "Installed: $("$DEST" --version)"
echo "Log out and back in to start using it, then enable the options in your config (see README)."
