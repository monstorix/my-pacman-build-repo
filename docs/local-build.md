# Building and installing locally

## Prerequisites

```bash
sudo pacman -S --needed base-devel git dkms nasm cmake pkgconf
sudo pacman -S --needed linux-headers        # or linux-cachyos-headers on CachyOS
```

`nasm` is needed by davs2's assembly code; without it, add `--disable-asm` to
the davs2 `configure` line for a slower C-only build.

## Build order

`ffmpeg` is linked statically into mpv, so the AVS decoders must be installed
before mpv is configured:

```bash
cd packages
( cd av3a-git           && makepkg -si )   # static AVS3 audio libs
( cd davs2-10bit-git    && makepkg -si )   # replaces davs2 / davs2-git
( cd mpv-full-build-cavs-git && makepkg -si )
( cd ffmpeg-full-cavs    && makepkg -si )   # optional, replaces ffmpeg
( cd icast-dkms         && makepkg -si )
```

`ffmpeg-full-cavs` is the AUR `ffmpeg-full` feature set with the same decoder
patches. It pulls in ~110 build dependencies (including `cuda`) and
`provides`/`conflicts` with `ffmpeg`, so `makepkg -si` asks before replacing
the official package. Skip it if you only need mpv.

`davs2-10bit-git` conflicts with `davs2`/`davs2-git`; `makepkg -si` asks
before replacing them. `uavs3d` and `chromaprint-fftw` are not in the official
repositories — install them from the AUR first (`paru -S uavs3d
chromaprint-fftw`), or let the CI build them.

Useful `makepkg` flags:

| Flag | Purpose |
|---|---|
| `-s` | install missing repository dependencies |
| `-i` | install the resulting package |
| `-f` | rebuild even if the package file exists |
| `--cleanbuild` | build from a fresh source tree (used by CI) |
| `--nocheck` | skip `check()`, which the AUR recipes do not define |

## Verifying the mpv build

```bash
mpv --version                     # should mention FFmpeg n9.0.2
mpv --vd=help | grep -E 'cavs|davs2|uavs3d'
mpv --ad=help | grep -E 'libdra|libarcdav3a'
ffprobe -hide_banner -decoders | grep -E 'cavs|libdavs2|libuavs3d|libarcdav3a|libdra'
```

Test files: any AVS/AVS+ (`.avs`), AVS2 10-bit, AVS3, and AV3A-in-TS sample.
For a quick sanity check `mpv --no-config --vo=null --ao=null file.ts` should
decode without "Could not open codec" errors.

## Verifying the ffmpeg-full-cavs build

```bash
ffmpeg -hide_banner -decoders | grep -E 'cavs|libdavs2|libuavs3d|libarcdav3a|libdra'
ffmpeg -hide_banner -version | head -n 3
```

The decoder names are `cavs` (AVS1/AVS+), `libdavs2`, `libuavs3d`,
`libarcdav3a` (AV3A) and `libdra`; `libcavs` and `libdradec` are *not*
registered names. `ffmpeg -h decoder=cavs` should print the codec help.

## Optional: non-free components

Both FFmpeg builds are free by default. `libfdk-aac` and `--enable-nonfree`
can be enabled for a personal build:

```bash
sudo pacman -S libfdk-aac
FFMPEG_NONFREE=1 makepkg -si          # in ffmpeg-full-cavs or mpv-full-build-cavs-git
```

Do not redistribute the result. The same builds are available from a manual
`nonfree` workflow run; download the `*-nonfree` artifacts and `pacman -U`
them by hand.

## DKMS package

`icast-dkms` installs sources into `/usr/src/icast-1.0.0` and registers
`icast/1.0.0` with DKMS. The `post_install` script runs `dkms add`/`dkms
build`/`dkms install` for the running kernel when its headers are present.

```bash
# after makepkg -si
dkms status                        # icast/1.0.0, <kernel>: installed
modinfo dvb-usb-icast-smit | head
modprobe -n -v --show-depends dvb-usb-icast-smit
lsmod | grep icast                 # should already list both modules
dmesg | tail -30                   # "iCast" / frontend attach messages
```

Both modules load without manual intervention:

- `/usr/lib/modprobe.d/icast-dkms.conf` makes `modprobe` load
  `dvb-usb-icast-fe` before `dvb-usb-icast-smit`, so the frontend is present
  when the USB bridge attaches it (the driver looks it up with `dvb_attach()`
  / `symbol_request()`, which is not reliable on its own);
- `/usr/lib/modules-load.d/icast-dkms.conf` loads the bridge at boot, before
  udev coldplug runs;
- the package's `.install` script modprobes the bridge right after
  `dkms install`, which covers an adapter that was already plugged in.

If you installed an older build (1.0.0-1) or want to load the driver by hand:

```bash
sudo modprobe dvb-usb-icast-smit   # pulls in dvb-usb-icast-fe via softdep
```

The device is `29df:0001`; the module has no firmware download step, so no
`*.fw` file is required. Two modules are built:

- `dvb-usb-icast-fe.ko`
- `dvb-usb-icast-smit.ko`

On kernel updates DKMS rebuilds them automatically (`AUTOINSTALL=yes`),
provided the matching `linux*-headers` package is installed. If headers are
missing at install time, install them and run `sudo dkms autoinstall`.

Uninstall:

```bash
sudo dkms remove icast/1.0.0 --all
sudo pacman -R icast-dkms
```

### Secure Boot

The modules are unsigned. With Secure Boot enforced, sign them after DKMS
builds, e.g. with `sbctl`:

```bash
sudo sbctl sign -s /usr/lib/modules/$(uname -r)/updates/dkms/dvb-usb-icast-smit.ko
sudo sbctl sign -s /usr/lib/modules/$(uname -r)/updates/dkms/dvb-usb-icast-fe.ko
```

Re-run the signing after every kernel/DKMS rebuild (or hook it into a pacman
hook). Module loading fails silently apart from a `dmesg` "Key was rejected by
service" message otherwise.

## Verifying the decoder stack

The FFmpeg patch stack registers five decoders; mpv exposes them through
`--vd=help` (video) and `--ad=help` (audio):

```bash
mpv --vd=help | grep -E '^ *cavs$|libdavs2|libuavs3d'
mpv --ad=help | grep -E 'libdra|libarcdav3a'
```

Expected: `cavs` (AVS/AVS+, native), `libdavs2` (AVS2, 10-bit capable),
`libuavs3d` (AVS3 video), `libdra` (DRA audio) and `libarcdav3a` (AV3A /
Audio Vivid). A missing entry means the corresponding configure probe or
library was not found at build time.

Playback smoke test (any AVS/AVS2/AVS3 sample):

```bash
mpv --no-config --msg-level=all=v,vd=v,ad=v sample.avs
```

`ffmpeg -decoders | grep -E 'cavs|davs2|uavs3d|dradec|arcdav3a'` is not
available here: this package does not install the FFmpeg CLI.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `error: xxx 没有在创建目录中找到` | A local `source` entry points into a subdirectory. makepkg looks up local files by basename in the package directory — keep them flat next to the PKGBUILD. |
| `gcc: error: unrecognized command-line option '-fms-anonymous-structs'` | CachyOS kernel was built with clang. Build with `make LLVM=1`; the DKMS Makefile detects this automatically from `auto.conf`. |
| FFmpeg configure cannot find `libarcdav3a` | The AV3A headers live in the FFmpeg source tree; `CPPFLAGS=-I${srcdir}/ffmpeg` must be exported (the PKGBUILD does this). |
| davs2 patch rejects with `different line endings` | Upstream uses CRLF; use `git apply --whitespace=nowarn` (the PKGBUILD does). |
| `libdavs2.so.16` missing at mpv link time | Install `davs2-10bit-git` before configuring FFmpeg. |
| mpv starts but no AVS2 10-bit | Check `davs2-10bit-git` (not the 8-bit `davs2`) is the installed provider: `pacman -Qi davs2-10bit-git`. |
