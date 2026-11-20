#!/usr/bin/env bash
# Build the packages of this repository.
#
# Usage:
#   ci/build.sh deps                # libraries every package needs
#   ci/build.sh package <pkgname>   # one package, plus a smoke test
#
# The workflow splits these into separate jobs so that the two long FFmpeg
# builds (mpv and ffmpeg-full-git) run in parallel:
#   deps      -> av3a-git, davs2-10bit-git, chromaprint-fftw, uavs3d
#   package   -> mpv-full-build-cavs-git, ffmpeg-full-git-cavs, icast-dkms
#
# Meant to run as a non-root user with sudo rights (GitHub Actions) or on a
# local machine; no AUR helper is required, the AUR dependencies are built from
# source here as well.
#
# Environment:
#   ARTIFACTS  output directory for *.pkg.tar.zst (default: <repo>/artifacts)
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

msg() { printf '\n==> %s\n' "$*"; }

collect() {
  # Debug packages are huge and never published; keep them out of the
  # artifacts so the jobs exchange as little data as possible.
  local dir=$1 f
  shopt -s nullglob
  for f in "$dir"/*.pkg.tar.zst; do
    case "$f" in
      *-debug-*) continue ;;
    esac
    cp -f "$f" "$artifacts/"
  done
}

build_aur() {
  local name=$1
  local dir="/tmp/aur/$name"
  msg "AUR dependency: $name"
  rm -rf "$dir"
  mkdir -p "$(dirname "$dir")"
  git clone --depth 1 "https://aur.archlinux.org/$name.git" "$dir"
  ( cd "$dir" && makepkg -si --noconfirm --needed --nocheck )
  collect "$dir"
}

build_local() {
  local name=$1 install=${2:-}
  msg "Package: $name"
  (
    cd "$packages_dir/$name"
    makepkg -f --noconfirm --cleanbuild --syncdeps --nocheck
    if [[ $install == install ]]; then
      # Later packages need these installed: mpv and ffmpeg-full declare
      # "davs2" and "av3a-git" as depends/makedepends, but no pacman
      # repository carries those names (davs2-10bit-git provides davs2).
      local pkgfile
      pkgfile=$(ls -1 ./*.pkg.tar.zst | grep -v -- "-debug-" | head -n 1)
      sudo pacman -U --noconfirm --needed "$pkgfile"
    fi
    collect "$PWD"
  )
}

verify_mpv() {
  msg "Smoke test: the built mpv exposes the CAVS/AVS decoders"
  local pkg dir out_v out_a missing=0 try dec
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
  fi
  rm -rf "$dir"
  [[ $missing -eq 0 ]]
}

verify_ffmpeg() {
  msg "Smoke test: the built ffmpeg exposes the CAVS/AVS decoders"
  local pkg dir out missing=0 dec
  pkg=$(ls -1 "$artifacts"/ffmpeg-full-git-cavs-*.pkg.tar.zst | head -n 1)
  dir=$(mktemp -d)
  bsdtar -xf "$pkg" -C "$dir" usr/bin/ffmpeg usr/lib
  out="$dir/decoders.txt"
  LC_ALL=C LD_LIBRARY_PATH="$dir/usr/lib:${LD_LIBRARY_PATH:-}" \
    "$dir/usr/bin/ffmpeg" -hide_banner -decoders >"$out" 2>&1 || true
  head -n 3 "$out" >&2 || true
  for dec in cavs libdavs2 libuavs3d libarcdav3a libdra; do
    grep -qw -- "$dec" "$out" || { echo "!! decoder $dec is missing" >&2; missing=1; }
  done
  if [[ $missing -ne 0 ]]; then
    echo "--- decoder lines matching AVS/DRA ---" >&2
    grep -i -E 'avs|dra' "$out" >&2 || true
  fi
  rm -rf "$dir"
  [[ $missing -eq 0 ]]
}

cmd=${1:-}
case "$cmd" in
  deps)
    # The patched FFmpeg builds need these at configure/link time, and mpv
    # needs uavs3d/davs2 at run time.
    build_aur chromaprint-fftw
    build_aur uavs3d
    build_local av3a-git install
    build_local davs2-10bit-git install
    ;;
  package)
    name=${2:?usage: ci/build.sh package <pkgname>}
    build_local "$name"
    case "$name" in
      mpv-full-build-cavs-git) verify_mpv ;;
      ffmpeg-full-git-cavs) verify_ffmpeg ;;
    esac
    ;;
  *)
    echo "usage: ci/build.sh deps | ci/build.sh package <pkgname>" >&2
    exit 2
    ;;
esac

msg "Artifacts in $artifacts"
ls -lh "$artifacts"
