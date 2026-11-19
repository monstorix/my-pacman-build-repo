# CAVS / AVS mpv and iCast DKMS for Arch Linux

Personal Arch Linux packaging for two things:

1. **mpv** built against a statically linked, patched **FFmpeg 9.0.2** with
   CAVS (AVS/AVS+), AVS2 10-bit, AVS3 and AV3A ("Audio Vivid") decoding, plus
   DRA audio — the same decoder stack used by
   [nilaoda/mpv-iina-avs](https://github.com/nilaoda/mpv-iina-avs) on macOS,
   adapted to Linux/x86_64.
2. **iCast DKMS**: an out-of-tree driver for the SMIT (国微) iCast USB
   DVB-T2/C adapter (`29df:0001`), built automatically for every installed
   kernel.

Everything is built from source; nothing here is submitted to the AUR.

The pre-existing checkouts in this workspace (`iCast/`,
`mpv-full-build-cavs-git/`) are ignored by git. Their old `.git` directories
were moved to `.work/legacy-git/` so this repository has no nested repositories
or inherited remotes; the working files are untouched.

## Layout

```
packages/
  mpv-full-build-cavs-git/   mpv + static FFmpeg 9.0.2 + 8 decoder patches
  davs2-10bit-git/           AVS2 10-bit decoder (provides davs2)
  av3a-git/                  AVS3 audio reference decoder + binaural renderer
  icast-dkms/                SMIT iCast DVB-T2/C USB driver (DKMS)
ci/                          build + repository publishing scripts
.github/workflows/build.yml  weekly / on-change build, publishes repo branch
docs/                        package, patch, CI and local-build notes
```

## Install from the prebuilt repository

The `repo` branch of this repository is a pacman repository (x86_64) that the
GitHub Actions workflow refreshes. This checkout is configured for
`monstorix/my-pacman-build-repo`; change the URL if you fork it:

```ini
# /etc/pacman.conf — put this before the official repositories so that
# davs2-10bit-git can replace the 8-bit davs2 from [extra].
[cavs]
Server = https://raw.githubusercontent.com/monstorix/my-pacman-build-repo/repo/$arch
SigLevel = Optional TrustAll
```

```bash
sudo pacman -Syu
sudo pacman -S mpv-full-build-cavs-git icast-dkms
```

`SigLevel` is relaxed because the repository is unsigned. See
[docs/ci.md](docs/ci.md) if you want to add GPG signing.

The repository was verified end to end: `pacman -Sy` against
`https://raw.githubusercontent.com/monstorix/my-pacman-build-repo/repo/x86_64`
lists `mpv-full-build-cavs-git`, `icast-dkms`, `davs2-10bit-git`, `av3a-git`,
`uavs3d` and `chromaprint-fftw`.

## Push to GitHub

This checkout is already a git repository pushed to
`https://github.com/monstorix/my-pacman-build-repo`. For a fresh fork:

```bash
git remote add origin git@github.com:<owner>/<repo>.git
git push -u origin main
```

The workflow runs on the next push and creates the `repo` branch on its first
successful build. Nothing else (secrets, servers) is required.

## Build locally

```bash
sudo pacman -S --needed base-devel git dkms linux-headers
cd packages/av3a-git           && makepkg -si
cd ../davs2-10bit-git          && makepkg -si
cd ../mpv-full-build-cavs-git  && makepkg -si
cd ../icast-dkms               && makepkg -si
```

Details, ordering and troubleshooting: [docs/local-build.md](docs/local-build.md).

## Documentation

| Document | Contents |
|---|---|
| [docs/packages.md](docs/packages.md) | What each package contains and how they depend on each other |
| [docs/patches.md](docs/patches.md) | FFmpeg patch stack, provenance, differences from mpv-iina-avs |
| [docs/ci.md](docs/ci.md) | GitHub Actions design, repository branch, signing options |
| [docs/local-build.md](docs/local-build.md) | Building, installing and testing the packages locally |

## Status

- FFmpeg 9.0.2 with all eight patches configures and compiles cleanly; all
  four PKGBUILDs pass `namcap` with no errors.
- `icast-dkms` builds, packages and compiles its modules against the running
  CachyOS kernel (clang-built kernels handled via `LLVM=1`).
- The complete `makepkg` run for mpv was not possible on the author's machine
  (no root, many build-only dependencies missing); the CI workflow performs
  the full build.

## Licensing

- mpv, FFmpeg, libass, libplacebo: GPL/LGPL as upstream.
- davs2-10bit: GPL-2.0-only.
- uavs3d: BSD-3-Clause.
- av3a-git: the upstream snapshot carries **no license file**; the package is
  tagged `LicenseRef-proprietary` and is intended for personal use only. Do not redistribute
  the built binaries without clarifying the license.
