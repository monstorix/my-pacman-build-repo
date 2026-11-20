# FFmpeg patch stack and comparison with mpv-iina-avs

The mpv package builds FFmpeg **9.0.2** (`git+.../ffmpeg.git#tag=n9.0.2`) and
`ffmpeg-full-git-cavs` builds **FFmpeg master**
(`git+https://github.com/ffmpeg/ffmpeg.git`); both carry the same eight patches taken
from [nilaoda/mpv-iina-avs](https://github.com/nilaoda/mpv-iina-avs)
(`tools/patches/ffmpeg/`). They are vendored next to the PKGBUILD and applied
in filename order by `prepare()`.

| Patch | Effect |
|---|---|
| `0001-libcavs-add-avs-avsplus-dra-base.patch` | Adds the CAVS (AVS1/AVS+) video decoder `cavs` and the DRA audio decoder `libdra` (sources `libcavsdec.c`, `libcavs.c`, `libdradec.c`, `dradec.c`), codec IDs, descriptors, MPEG-TS registration. This is the Linux/portable replacement for the older monolithic `ffmpeg_cavs_dra.patch` that used to live in the local PKGBUILD. |
| `0002-libdavs2-export-sequence-display-color-metadata.patch` | Lets the `libdavs2` decoder forward the AVS2 sequence display colour description (primaries/transfer/matrix) to FFmpeg. |
| `0003-libarcdav3a-add-av3a-audio-vivid-decoder.patch` | Adds the `libarcdav3a` decoder and its glue headers (`libavcodec/arcdav3a.h`, `avs3_stat_*.h`, ...), plus the `--enable-libarcdav3a` configure option. Links `-lAVS3AudioDec -lav3a_binaural_render`; **changed for GCC**: the upstream `-lc++` is `-lstdc++` here. |
| `0004-av3a-container-parser-demux.patch` | AV3A parser and container demuxer (`libavformat/av3adec.c`), MPEG-TS/MOV wiring and muxer hooks. |
| `0005-av3a-content-probing.patch` | Content probing for AV3A streams, `av3a_parse` helper and `demux.c`/`mpegts.c` integration. |
| `0006-av3a-stream-metadata.patch` | Propagates AV3A stream metadata through the demuxer. |
| `0007-libdavs2-reset-reference-state-on-seek.patch` | Resets the davs2 reference state when seeking, avoiding corruption after a seek. |
| `0008-libcavs-propagate-output-picture-field-metadata.patch` | Propagates output picture field/interlace metadata from libcavs. |

The same eight patches are used by both `mpv-full-build-cavs-git` (against
the static FFmpeg it vendors) and `ffmpeg-full-git-cavs` (against the FFmpeg
master checkout, after the AUR patches).

When FFmpeg master changes underneath them the patches need a rebase. Two
hunks were rebased when `ffmpeg-full-git-cavs` was introduced:

- `0001`: `libavcodec/Makefile` now also lists `cavs_aec.o` on the
  `CONFIG_CAVS_DECODER` line, so the removed-lines hunk was updated.
- `0004`: `mov_write_audio_tag()` gained the `AV_CODEC_ID_MPEGH_3D_AUDIO`
  branch between `AV_CODEC_ID_TRUEHD` and `MOV_MP4_IPCM_TAG`; the AV3A branch
  is now inserted after it.

## Verification performed

- All eight patches apply to a pristine FFmpeg 9.0.2 tree in order, with no
  fuzz and no rejects. All twelve (AUR 010/030/040/050 + these eight) also
  apply in order to FFmpeg master `7ddf7bc` (2026-11-20), and the patched
  master configures and compiles with the five decoders enabled.
- A minimal configuration enabling only the new decoders
  (`--enable-libarcdav3a --enable-libdavs2 --enable-libuavs3d
  --enable-decoder=cavs,libdra,libdavs2,libuavs3d,libarcdav3a`) configures with
  `CONFIG_CAVS_DECODER`, `CONFIG_LIBDRA_DECODER`, `CONFIG_LIBDAVS2_DECODER`,
  `CONFIG_LIBUAVS3D_DECODER` and `CONFIG_LIBARCDAV3A_DECODER` all `1`, and
  **compiles to completion**; `ff_*_decoder` is present in `codec_list.c`.
- `patch -Np1` is used so a re-run does not fail on already-applied hunks.

## What mpv-iina-avs has that this repository does not

| Item | Why it is not used here |
|---|---|
| `tools/patches/mpv/` (5 patches: gpu-next `vo_libmpv`, screenshot/JXL, AVIF, ICC, downmix) | They target the **macOS IINA libmpv bundle** and mpv v0.41.0. Linux builds use upstream mpv; the AUR recipe tracks mpv git. |
| `tools/patches/av3a-decoder/0001-...patch` | Only needed when compiling the AV3A SDK; it **is** applied by `av3a-git`. |
| aarch64/macOS davs2 patches (`0003`–`0009`, `0012` partly) | Target Apple silicon NEON and Xcode toolchains; this repository is x86_64. `0011`–`0013` that are relevant to x86_64/Linux are kept. |
| IINA dylib bundle, code-signing, notarization | macOS-only distribution concerns. |
| Sparkle/appcast updates | Not applicable to pacman packages. |

Feature coverage is otherwise the same decoder set:

- AVS1/AVS+ video (`cavs`), DRA audio (`libdra`)
- AVS2 8/10-bit (`libdavs2`, from `davs2-10bit`)
- AVS3 video 8/10-bit (`libuavs3d`)
- AV3A / Audio Vivid audio (`libarcdav3a`)

## Updating to a newer FFmpeg

1. Change the `ffmpeg::git+...#tag=nX.Y.Z` line in the mpv PKGBUILD.
2. Apply the patch stack to a clean tree and check for rejects:
   ```bash
   git clone --depth 1 --branch nX.Y.Z https://github.com/ffmpeg/ffmpeg.git
   cd ffmpeg
   for p in ../0*.patch; do patch -Np1 -i "$p" || break; done
   ```
3. If a patch fails, refresh it against the new FFmpeg (prefer rebasing on the
   current mpv-iina-avs patch of the same name) and recompute its
   `sha256sum`.
4. Re-check the `-lc++` → `-lstdc++` change in patch 0003: a refreshed patch
   may reintroduce `-lc++`.
5. Update `pkgver` if mpv changed; regenerate `.SRCINFO`.
