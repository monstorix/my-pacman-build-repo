# Packages

All packages are built from source with `makepkg`. The dependency graph is:

```
uavs3d (AUR, 8+10-bit shared) ─┐
chromaprint-fftw (AUR) ────────┤
av3a-git (local, static) ──────┼─> mpv-full-build-cavs-git
davs2-10bit-git (local) ───────┘
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

No license file exists upstream; the package is `custom` and personal-use
only.

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

## Repository packages used by the CI, not packaged here

- `uavs3d` (AUR) — AVS3 video, 8+10-bit shared library; not in the official
  repositories.
- `chromaprint-fftw` (AUR) — required by FFmpeg's chromaprint filter; also
  not in the official repositories.

The CI builds these from the AUR on every run instead of vendoring them.
