#!/usr/bin/env bash
# Build every package in a clean Arch Linux environment.
#
# Intended to run as a non-root user with sudo rights (GitHub Actions) or on a
# local machine after installing base-devel, git, sudo and an AUR helper is
# NOT required: the two AUR dependencies are built from source here as well.
#
# Environment:
#   ARTIFACTS  output directory for *.pkg.tar.zst (default: <repo>/artifacts)
#   JOBS       parallel make jobs (default: nproc)
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
packages_dir="$repo_root/packages"
artifacts="${ARTIFACTS:-$repo_root/artifacts}"
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"

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
}

build_local() {
  local name=$1
  msg "Package: $name"
  (
    cd "$packages_dir/$name"
    makepkg -f --noconfirm --cleanbuild --syncdeps --nocheck
    cp -f ./*.pkg.tar.zst "$artifacts/"
  )
}

# The patched FFmpeg needs these at configure/link time.
build_aur chromaprint-fftw
build_aur uavs3d

# Local dependencies first; they are installed so the mpv build can find them.
build_local av3a-git
build_local davs2-10bit-git

# mpv is only built, not installed, but --syncdeps pulls in its repository
# dependencies. davs2/uavs3d are already satisfied by the packages above.
build_local mpv-full-build-cavs-git

# DKMS package: the module is compiled on the target machine, not here.
build_local icast-dkms

msg "Artifacts in $artifacts"
ls -lh "$artifacts"
