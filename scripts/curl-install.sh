#!/bin/bash
set -euo pipefail

# Bootstrap entrypoint served from https://arch.zeroxclem.org/install
#
# Pinned to a tagged release so an install is reproducible: whatever lands on
# main later cannot change an install that is already documented and tested.
# To cut a new release, tag it and bump ARCHTITUS_REF below.
#
# Override for testing an unreleased branch:
#   ARCHTITUS_REF=main bash <(curl -L arch.zeroxclem.org/install)

ARCHTITUS_REF="${ARCHTITUS_REF:-v2026.08.15}"
ARCHTITUS_REPO="${ARCHTITUS_REPO:-https://github.com/ZeroXClem/ArchTitus}"
DEST="$HOME/ArchTitus"

# Refuse to run from inside a checkout — ./archtitus.sh is the entrypoint there
if [[ "$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')" =~ ^scripts$ ]]; then
    echo "You are running this inside the ArchTitus folder."
    echo "Use ./archtitus.sh instead."
    exit 1
fi

echo "Installing git."
pacman -Sy --noconfirm --needed git glibc

# A stale checkout silently runs old code, so replace it rather than reuse it
if [[ -e "$DEST" ]]; then
    echo "Existing checkout at $DEST — replacing it."
    rm -rf "$DEST"
fi

echo "Cloning ArchTitus at $ARCHTITUS_REF"
# Clone to an absolute path: the previous version cloned into $PWD but then
# cd'd to $HOME, which only worked when invoked from $HOME.
git clone "$ARCHTITUS_REPO" "$DEST"

# Accepts a tag, branch, or commit hash
if ! git -C "$DEST" checkout --quiet "$ARCHTITUS_REF"; then
    echo "Could not check out '$ARCHTITUS_REF' — does that tag exist?" >&2
    exit 1
fi

echo "Running ArchTitus ($(git -C "$DEST" rev-parse --short HEAD))"
cd "$DEST"
exec ./archtitus.sh
