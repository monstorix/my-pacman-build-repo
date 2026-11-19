#!/usr/bin/env bash
# Build every package in a clean Arch Linux environment.
#
# Intended to run as a non-root user with sudo rights (GitHub Actions) or on a
# local machine after installing base-devel, git, sudo and an AUR helper is
# NOT required: the two AUR dependencies are built from source here as well.
#
# Runs from .github/workflows/build.yml on schedule, on push to main touching
# packages/, ci/ or the workflow itself, and on manual workflow_dispatch.
#
# Environment:
#   ARTIFACTS  output directory for *.pkg.tar.zst (default: <repo>/artifacts)
#   JOBS       parallel make jobs (default: nproc)
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
packages_dir="$repo_root/packages"
artifacts="${ARTIFACTS:-$repo_root/artifacts}"
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"
# Keep the bare VCS mirrors out of the package directories (makepkg defaults
# SRCDEST to $startdir when it is unset).
export SRCDEST="${SRCDEST:-$HOME/.cache/makepkg/srcdest}"
mkdir -p "$SRCDEST"

mkdir -p "$artifacts"
rm -f "$artifacts"/*.pkg.tar.zst

msg() { printf '\n==> %s\n' "$*"; }

build_aur() {
  local name=$1
  local dir="/tmp/aur/$name"
  msg "AUR dependency: $name"
  rm -rf "$dir"
  mkdir -p "$(dirname "$dir")"
  git clone --depth 1 "https://aur.archlinux.org/$name.git" "$dir"
  ( cd "$dir" && makepkg -si --noconfirm --needed --nocheck )
  # Publish these as well: mpv depends on uavs3d at runtime, and the package
  # is not in the official repositories.
  cp -f "$dir"/*.pkg.tar.zst "$artifacts/"
}

build_local() {
  local name=$1 install=${2:-}
  msg "Package: $name"
  (
    cd "$packages_dir/$name"
    makepkg -f --noconfirm --cleanbuild --syncdeps --nocheck
    if [[ $install == install ]]; then
      # Later packages need these installed: mpv declares "davs2" and
      # "av3a-git" as depends/makedepends, but no pacman repository carries
      # those names (davs2-10bit-git provides davs2), so --syncdeps would
      # otherwise fail with "target not found".
      local pkgfile
      pkgfile=$(ls -1 ./*.pkg.tar.zst | grep -v -- "-debug-" | head -n 1)
      sudo pacman -U --noconfirm --needed "$pkgfile"
    fi
    cp -f ./*.pkg.tar.zst "$artifacts/"
  )
}

verify_mpv() {
  msg "Smoke test: the built mpv exposes the CAVS/AVS decoders"
  local pkg dir out_v out_a missing=0 try
  pkg=$(ls -1 "$artifacts"/mpv-full-build-cavs-git-*.pkg.tar.zst | head -n 1)
  dir=$(mktemp -d)
  bsdtar -xf "$pkg" -C "$dir" usr/bin/mpv
  # A deterministic locale avoids any output differences on the runner.
  export LC_ALL=C
  # The first invocation right after unpacking occasionally lost part of the
  # output on the GitHub runner; retry once before declaring failure.
  for try in 1 2; do
    out_v="$dir/video.txt"
    out_a="$dir/audio.txt"
    "$dir/usr/bin/mpv" --no-config --vd=help >"$out_v" 2>&1 || true
    "$dir/usr/bin/mpv" --no-config --ad=help >"$out_a" 2>&1 || true
    missing=0
    local dec
    for dec in cavs libdavs2 libuavs3d; do
      grep -qw -- "$dec" "$out_v" || { echo "!! video decoder $dec is missing" >&2; missing=1; }
    done
    for dec in libdra libarcdav3a; do
      grep -qw -- "$dec" "$out_a" || { echo "!! audio decoder $dec is missing" >&2; missing=1; }
    done
    if [[ $missing -eq 0 ]]; then break; fi
    [[ $try -eq 1 ]] && sleep 2
  done
  "$dir/usr/bin/mpv" --no-config --version | head -n 2 || true
  if [[ $missing -ne 0 ]]; then
    echo "--- video decoder list (lines matching AVS/DRA) ---" >&2
    grep -i -E 'avs|dra|cavs' "$out_v" >&2 || true
    echo "--- first 40 lines of --vd=help ---" >&2
    head -n 40 "$out_v" >&2 || true
    echo "--- package contents (usr/bin) ---" >&2
    bsdtar -tf "$pkg" | grep -E 'usr/(bin|lib)/' | head -n 20 >&2 || true
  fi
  rm -rf "$dir"
  [[ $missing -eq 0 ]]
}

# The patched FFmpeg needs these at configure/link time.
build_aur chromaprint-fftw
build_aur uavs3d

# Local dependencies first; they are installed so the mpv build can find them.
build_local av3a-git install
build_local davs2-10bit-git install

# mpv is only built, not installed, but --syncdeps pulls in its repository
# dependencies. davs2/uavs3d/av3a are already satisfied by the packages above.
build_local mpv-full-build-cavs-git

# DKMS package: the module is compiled on the target machine, not here.
build_local icast-dkms

# Run the smoke test last so a failure cannot hide the DKMS package from the
# published artifacts.
verify_mpv

msg "Artifacts in $artifacts"
ls -lh "$artifacts"
