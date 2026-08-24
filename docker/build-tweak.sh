#!/bin/bash
# Build a Theos tweak from the bind-mounted project directory.
#
# Sources are copied into the container first. Windows bind mounts expose every
# directory as 0777, and dpkg-deb refuses a DEBIAN directory with permissions
# outside 0755-0775 — so building in place fails on Windows hosts only.
set -euo pipefail

rel="${1:?usage: build-tweak <path relative to /work>}"
src="/work/$rel"
[ -d "$src" ] || { echo "no such tweak: $src" >&2; exit 1; }

staging="$(mktemp -d)"
cp -a "$src/." "$staging/"
cd "$staging"

# Undo what the bind mount mangled.
find . -type d -exec chmod 0755 {} +
if [ -d layout/DEBIAN ]; then
  find layout/DEBIAN -type f -exec chmod 0755 {} +
fi

make clean package FINALPACKAGE=1

mkdir -p "$src/packages"
cp -f packages/*.deb "$src/packages/"
echo "built: $(cd packages && ls *.deb)"
