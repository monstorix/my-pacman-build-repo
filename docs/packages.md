# Packages

All packages are built from source with `makepkg`. The dependency graph is:

```
uavs3d (AUR, 8+10-bit shared) ─┬─> mpv-full-build-cavs-git (static FFmpeg link)
chromaprint-fftw (AUR) ────────┤
av3a-git (local, static) ──────┴─> ffmpeg-full-git-cavs (shared FFmpeg)
davs2-10bit-git (local) ──> both
icast-dkms ──> dkms, linux-headers
```

## mpv-full-build-cavs-git

mpv with a **statically linked** FFmpeg 9.0.2 (`#tag=n9.0.2`), libass,
libplacebo and ffnvcodec, following the AUR `mpv-full-build-git` recipe with
these changes:

- FFmpeg 9.0.2 pinned with `#tag=n9.0.2` instead of the AUR's floating
  `ffmpeg.git`, plus the eight decoder patches in this directory.
- `--enable-libarcdav3a`, `--enable-libdavs2`, `--enable-libuavs3d`; the
  dynamic "is davs2 installed?" check of the AUR PKGBUILD is removed because
  the dependency is now declared outright.
- Depends on `davs2`, `uavs3d`, `libdvdread` (the last one is now required by
  FFmpeg 9 and was added by the AUR package as well).
- `prepare()` applies the patches in filename order and exports
  `CPPFLAGS=-I${srcdir}/ffmpeg`, which is needed because FFmpeg's `configure`
  probe compiles from `/tmp` and must find the AV3A headers that patch 0003
  embeds (`libavcodec/arcdav3a.h`).

Provided soname: `libmpv.so=2-64`.

## ffmpeg-full-git-cavs

A shared-library FFmpeg built from the AUR `ffmpeg-full-git` recipe, i.e.
from `git+https://github.com/ffmpeg/ffmpeg.git` (master) rather than a tagged
release: `pkgver()` produces `9.x.rNNNNN.gHASH` and every scheduled CI run
picks up whatever upstream has merged. This is the same "track git" approach
the mpv package uses for the FFmpeg it vendors, and it avoids waiting for the
AUR maintainer to bump the stable `ffmpeg-full`.

The AUR patches (010, 020, 030, 040, 050, 060, 070) are applied first, then
the same eight decoder patches as the mpv package. On top of the
`--enable-libdavs2` / `--enable-libuavs3d` that ffmpeg-full enables, it adds
`--enable-libarcdav3a` (and `--enable-libcurl`, new in the git recipe);
`av3a-git` is a `makedepends`.

It `provides` and `conflicts` with `ffmpeg` (plus the `libav*.so` names), so
installing it replaces the official package. mpv is unaffected: it statically
links its own FFmpeg.

Nineteen ffmpeg-full features are disabled because their libraries exist only
in the AUR and would drag ~19 extra source recipes into unattended CI:

```
astc-encoder decklink-sdk flite1 lcevcdec libklvanc mpeghdec openapv opencv4
quirc libaribcaption shine rockchip-mpp svt-jpeg-xs vo-amrwbenc vvenc xavs
xavs2 xevd xeve
```

`astc-encoder` is new in the git recipe (it enables `--enable-libastcenc`);
`--enable-libcurl` is kept because `curl` is in the official repositories.

AMF is enabled explicitly, but the headers are vendored from the upstream
AMF v1.5.3 tag instead of using `amf-headers`: FFmpeg master requires AMF
1.5.3 (`AMF_VERSION_RELEASE >= 3`), while Arch's `amf-headers` 1.5.3-1 still
ships headers that report 1.5.2, which makes `--enable-amf` abort configure
with `amf requested but not found`. The tarball is laid out as
`amf-include/AMF/...` in `prepare()` and put first in `CPPFLAGS`, so the
build is independent of the installed headers. AMD users therefore get the
`*_amf` encoders/decoders (the runtime is loaded with `dlopen` at run time,
so no libamfrt dependency is needed).

The removed `depends`, patches and `--enable-*` lines are recorded in a
comment at the top of the PKGBUILD (`--enable-libastcenc` and its
`astc-encoder` dependency included); restore them (and install the AUR
packages) for a truly complete build. Everything available in the official
repositories stays enabled: CUDA/NVENC/NVDEC, svt-av1, svt-hevc, svt-vp9,
vulkan, vaapi, vdpau, whisper, lensfun, x264/x265, dav1d, rav1e and the rest
of the ffmpeg-full feature list. libfdk-aac (non-free) is opt-in, see below.

Non-free components are **off**: `libfdk-aac`, `--enable-nonfree` and the
other entries that ffmpeg-full marks non-free are removed from `depends` and
from the `./configure` line, so the package is redistributable
(`GPL-3.0-or-later`). A personal build can opt back in:

```bash
sudo pacman -S libfdk-aac
FFMPEG_NONFREE=1 makepkg -si
```

FFmpeg also classifies `cuda-nvcc` (and `cuda_sdk`) as non-free, so the
default build only enables `cuda-llvm` (clang-based CUDA compilation) plus the
free `nvenc`/`nvdec`/`cuvid` hwaccels; `cuda-nvcc` is part of the non-free
switch.

The same switch works for `mpv-full-build-cavs-git` (its static FFmpeg). The
result is then non-redistributable and must stay local; the CI artifacts of a
`nonfree` workflow run are never published to the `repo` branch.

## davs2-10bit-git

[xatabhk/davs2-10bit](https://github.com/xatabhk/davs2-10bit) at commit
`21d64c8`, built with `--bit-depth=10`. It **provides and conflicts with**
`davs2` / `davs2-git`, so it replaces the official 8-bit decoder. The five
patches are the x86_64/Linux subset of the mpv-iina-avs stack; aarch64 NEON
patches are intentionally not included.

## av3a-git

The AVS3 audio ("Audio Vivid") reference decoder and binaural renderer from
the `zlxyc/Sourcecodeforplayer` snapshot pinned by mpv-iina-avs. Only
`av3adecoder` and `av3a_binaural_render/AudioDecoder` are compiled; the
vendored FFmpeg and AudioFilter trees are ignored. Outputs two static
libraries in `/usr/lib`, which FFmpeg's `libarcdav3a` decoder links against.

No license file exists upstream; the package is tagged
`LicenseRef-proprietary` and is personal-use only.

## icast-dkms

Out-of-tree DKMS package for the SMIT iCast USB DVB-T2/C adapter
(`29df:0001`). It installs the vendor sources to `/usr/src/icast-1.0.0` and
builds only two modules:

- `dvb-usb-icast-fe.ko` — frontend/tuner glue (`smit.o` + `icast-fe.o`)
- `dvb-usb-icast-smit.ko` — DVB USB bridge (`smit.o` + `icast-smit.o`)

The vendor `dvb-core` / `dvb-usb` / `dvb-usb-v2` copies are **not** rebuilt;
the in-tree modules of the running kernel are used instead. `dvb-usb-icast-smit`
links against the exported `dvb_usb_*` symbols of `dvb-usb.ko`.

The Makefile detects clang-built kernels by grepping
`$(KDIR)/include/config/auto.conf` for `CONFIG_CC_IS_CLANG=y` and passes
`LLVM=1`; without that, GCC fails on CachyOS kernels with errors such as
`unrecognized command-line option '-fms-anonymous-structs'`.

### Automatic loading

`dvb-usb-icast-smit` resolves `icast_fe_attach()` from `dvb-usb-icast-fe`
through `dvb_attach()`, which is a `symbol_request()`: if the frontend module
is not loaded at probe time the attach fails with `not attached iCast usb
device`. The package therefore ships:

- `/usr/lib/modprobe.d/icast-dkms.conf` — `softdep dvb-usb-icast-smit pre:
  dvb-usb-icast-fe`, so every `modprobe` of the bridge (including the one udev
  runs for the USB modalias `usb:v29DFp0001d*...`) loads the frontend first;
- `/usr/lib/modules-load.d/icast-dkms.conf` — loads the bridge at boot, so the
  frontend is registered before udev coldplug probes an already connected
  adapter;
- the `.install` script runs `modprobe dvb-usb-icast-smit` after
  `dkms install`, covering adapters that were plugged in before the package
  was installed (udev does not re-send their add event), and unloads the
  modules before an upgrade/removal.

Verified with `modprobe -C ... --show-depends`: the alias and the plain module
name both resolve to `dvb-usb-icast-fe.ko` followed by `dvb-usb-icast-smit.ko`.

## Repository packages used by the CI, not packaged here

- `uavs3d` (AUR) — AVS3 video, 8+10-bit shared library; not in the official
  repositories.
- `chromaprint-fftw` (AUR) — required by FFmpeg's chromaprint filter; also
  not in the official repositories.

The CI builds these from the AUR on every run instead of vendoring them.

## Keeping in sync with the AUR

`mpv-full-build-cavs-git` started from AUR `mpv-full-build-git` (snapshot
`0.42.0.r5.g55d3feb45c`, saved as `.aur-PKGBUILD` in the original working
directory). To refresh it:

```bash
curl -fsSL 'https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=mpv-full-build-git' \
  -o /tmp/aur-mpv/PKGBUILD
diff -u /tmp/aur-mpv/PKGBUILD packages/mpv-full-build-cavs-git/PKGBUILD
```

Port over dependency changes, new `_ffmpeg_options` / `_mpv_options` entries
and prepare/build fixes. Keep the local deltas listed above (pinned FFmpeg tag,
decoder patches, `CPPFLAGS`, the three `--enable-lib*` flags, `davs2` /
`uavs3d` / `libdvdread`) and re-run `makepkg --printsrcinfo > .SRCINFO` plus
`namcap PKGBUILD`.
