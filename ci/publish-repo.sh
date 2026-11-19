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

# Keep the repository bounded: only the two newest builds of each package.
python3 - "$dest" <<'PY'
import glob
import os
import subprocess
import sys

dest = sys.argv[1]
by_name = {}
for path in glob.glob(os.path.join(dest, "*.pkg.tar.zst")):
    try:
        info = subprocess.run(
            ["bsdtar", "-xOf", path, ".PKGINFO"],
            check=True, capture_output=True, text=True,
        ).stdout
    except subprocess.CalledProcessError:
        continue
    fields = dict(
        line.split(" = ", 1)
        for line in info.splitlines()
        if line.startswith("pkgname = ") or line.startswith("pkgver = ")
    )
    name = fields.get("pkgname")
    if name:
        by_name.setdefault(name, []).append(path)

for name, paths in by_name.items():
    paths.sort(key=os.path.getmtime, reverse=True)
    for old in paths[2:]:
        print(f"prune {os.path.basename(old)}")
        os.unlink(old)
PY

cd "$dest"
repo-add --quiet --remove --prevent-downgrade cavs.db.tar.gz ./*.pkg.tar.zst
echo "repository updated: $dest"
