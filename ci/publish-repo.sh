#!/usr/bin/env bash
# Add built packages to a pacman repository directory and refresh its database.
#
# Usage: publish-repo.sh <repo-dir> <artifacts-dir>
# The repository layout is <repo-dir>/x86_64/{*.pkg.tar.zst,cavs.db.tar.gz}.
set -euo pipefail

repo_dir=${1:?usage: publish-repo.sh <repo-dir> <artifacts-dir>}
artifacts=${2:?usage: publish-repo.sh <repo-dir> <artifacts-dir>}
arch=${CARCH:-x86_64}
dest="$repo_dir/$arch"

mkdir -p "$dest"
shopt -s nullglob
pkgs=("$artifacts"/*.pkg.tar.zst)
if ((${#pkgs[@]} == 0)); then
  echo "no packages in $artifacts" >&2
  exit 1
fi
cp -f "${pkgs[@]}" "$dest/"

# Keep the repository bounded: only the newest build of each package.
python3 - "$dest" <<'PY'
import functools
import glob
import os
import subprocess
import sys

dest = sys.argv[1]


def vercmp(a, b):
    out = subprocess.run(
        ["vercmp", a, b], check=True, capture_output=True, text=True
    ).stdout.strip()
    return int(out)


by_name = {}
for path in glob.glob(os.path.join(dest, "*.pkg.tar.zst")):
    try:
        info = subprocess.run(
            ["bsdtar", "-xOf", path, ".PKGINFO"],
            check=True, capture_output=True, text=True,
        ).stdout
    except subprocess.CalledProcessError:
        continue
    fields = {}
    for line in info.splitlines():
        for key in ("pkgname", "pkgver"):
            if line.startswith(key + " = "):
                fields[key] = line.split(" = ", 1)[1]
    if fields.get("pkgname") and fields.get("pkgver"):
        by_name.setdefault(fields["pkgname"], []).append(
            (fields["pkgver"], path)
        )

for name, entries in by_name.items():
    # Sort by pacman's version comparison, not mtime: a fresh clone gives every
    # file the same checkout timestamp.
    entries.sort(key=functools.cmp_to_key(
        lambda a, b: vercmp(a[0], b[0])), reverse=True)
    for ver, old in entries[1:]:
        print(f"prune {os.path.basename(old)} ({ver})")
        os.unlink(old)
PY

cd "$dest"
repo-add --quiet --remove --prevent-downgrade cavs.db.tar.gz ./*.pkg.tar.zst

# repo-add creates cavs.db / cavs.files as symlinks. Raw file hosts such as
# raw.githubusercontent.com return the link target as text instead of the
# archive, so materialize them as regular files.
for f in cavs.db cavs.files; do
  cp -f --remove-destination "$f.tar.gz" "$f"
done

echo "repository updated: $dest"
