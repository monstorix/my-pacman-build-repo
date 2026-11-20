# GitHub Actions and the pacman repository branch

## Workflow

`.github/workflows/build.yml` runs in an `archlinux:latest` container on
`ubuntu-latest`:

| Trigger | When |
|---|---|
| `schedule` | Every Monday, 03:17 UTC (`cron: "17 3 * * 1"`) |
| `push` to `main` | Changes under `packages/`, `ci/` or `.github/workflows/` |
| `workflow_dispatch` | Manual run from the Actions tab |

The workflow is split into four jobs that run in separate containers and
exchange packages through artifacts, so the two long FFmpeg builds never wait
for each other:

| Job | Contents | Timeout |
|---|---|---|
| `deps` | builds `chromaprint-fftw` and `uavs3d` from the AUR, plus `av3a-git` and `davs2-10bit-git`; uploads `deps-packages` | 90 min |
| `build` (matrix) | one job each for `mpv-full-build-cavs-git` and `ffmpeg-full-cavs`: installs `deps-packages`, builds its single package, smoke-tests it, uploads `<package>-packages` | 350 min |
| `icast` | builds `icast-dkms` (does not depend on either FFmpeg) | 30 min |
| `publish` | downloads every `*-packages` artifact and runs `ci/push-repo.sh` once | 30 min |

Every job starts from `archlinux:latest`, installs `base-devel git sudo
namcap`, creates a `builder` user with passwordless sudo and chowns the
workspace (the checkout is owned by root). The two matrix jobs install the
dependency packages with `pacman -U` before `makepkg --syncdeps` runs, so the
local `davs2` / `av3a-git` names resolve. The ffmpeg job also removes the CUDA
Nsight debuggers (several GB) before building.

Smoke tests: the mpv package must list `cavs`, `libdavs2` and `libuavs3d` in
`--vd=help` and `libdra`, `libarcdav3a` in `--ad=help`; `ffmpeg-full-cavs`
must list the same five in `-decoders`. A missing decoder fails the job.

`namcap` runs on the PKGBUILDs and packages (`|| true`: it is a report, not a
gate). Artifacts are kept for 7 days.

`timeout-minutes: 350` keeps a stuck build under GitHub's 6-hour job limit.
The workflow needs `permissions: contents: write`; it uses the built-in
`GITHUB_TOKEN`, no additional secret is required.

## Non-free builds (artifacts only)

The default build is free: `--enable-nonfree` and `libfdk-aac` are not
enabled anywhere, so everything the workflow publishes can be redistributed.
For personal use, run the workflow manually with **nonfree** checked
(`workflow_dispatch`). That run installs `libfdk-aac`, passes
`FFMPEG_NONFREE=1` to both FFmpeg builds (this adds libfdk-aac and
`cuda-nvcc`, which FFmpeg also treats as non-free), uploads the packages as
`<pkg>-packages-nonfree`, and **skips the publish job** — those binaries never
enter git. Download them from the run page and `pacman -U` them yourself.

## The `repo` branch

`ci/push-repo.sh` checks out (or creates as an orphan) the `repo` branch,
calls `ci/publish-repo.sh`, and force-pushes the result as a **single fresh
commit**. The branch is a download endpoint, not a history, so replacing it
every run keeps the repository from accumulating hundreds of megabytes of
superseded package blobs (GitHub rejects files over 100 MB). The branch
layout is:

```
x86_64/
  cavs.db            (copy of cavs.db.tar.gz — see below)
  cavs.db.tar.gz
  cavs.files         (copy of cavs.files.tar.gz)
  cavs.files.tar.gz
  *.pkg.tar.zst   (runtime packages only)
```

Debug packages (`*-debug-*`) are never copied into the artifacts: the mpv
debug package alone is over 100 MB, above GitHub's per-file limit. The publish
step additionally skips any single package above ~95 MB with a warning.

`repo-add` normally creates `cavs.db` as a symlink to `cavs.db.tar.gz`.
raw.githubusercontent.com serves symlinks as their target *text*, which would
break `pacman -Sy`, so `ci/publish-repo.sh` replaces both links with regular
copies after every `repo-add`.

Package files are copied in, and only the **newest build of each package** is
kept. Packages are pruned by name and `vercmp` order before
`repo-add --remove --prevent-downgrade` runs; `--prevent-downgrade` stops an
older build from overwriting a newer database entry, and `--remove` deletes
the superseded package file.

`raw.githubusercontent.com` serves the branch over HTTPS, so pacman needs no
special transport:

```ini
[cavs]
Server = https://raw.githubusercontent.com/monstorix/my-pacman-build-repo/repo/$arch
SigLevel = Optional TrustAll
```

`SigLevel = Optional TrustAll` is required because `repo-add` does not sign
the database. If you prefer signatures, see below.

> `raw.githubusercontent.com` sits behind a CDN. After a workflow run, the new
> database and packages can take a few minutes to appear; retry `pacman -Syu`
> instead of assuming the publish step failed.

> Put `[cavs]` **before** `[extra]` in `pacman.conf`. `davs2-10bit-git`
> provides `davs2`, and repository order decides which one wins when both
> repositories offer it.

## First run checklist

1. Create the GitHub repository and push `main` (already done for
   `monstorix/my-pacman-build-repo`).
2. Actions → *build-packages* → *Run workflow* (or wait for the next cron).
3. After the run, check that a `repo` branch exists and contains
   `x86_64/cavs.db.tar.gz`.
4. On the target machine add the `[cavs]` section and run
   `sudo pacman -Syu`.
5. `pacman -Si mpv-full-build-cavs-git icast-dkms` should list the packages
   from `[cavs]`.

If the repository lives under a different name, only the URL in
`pacman.conf` changes; the workflow uses `${{ github.repository }}`
implicitly through `GITHUB_REPOSITORY`.

## Costs and scheduling

A full run takes roughly 1.5–3 hours: the `deps` job is a few minutes, then
mpv (~15 min) and ffmpeg-full (the longest step, because of LTO and the ~100
codecs) run concurrently, and the DKMS package finishes in about a minute. On a **public**
repository Actions minutes are free. On a **private** repository the free
plan includes 2000 minutes/month, which is about 4–6 full runs — the weekly
schedule fits, but manual runs should be used sparingly. Reducing the matrix
to x86_64 (as now) and keeping `ccache` out of the picture is deliberate:
a cold build is predictable.

## Optional: GPG-signed repository

Not implemented, but the path is short:

1. Create a dedicated key and export the private key.
2. Store it as an Actions secret (`GPG_PRIVATE_KEY`), import it into a
   temporary `GNUPGHOME` in the workflow.
3. Change `repo-add` to `repo-add --sign`, and remove `--prevent-downgrade`
   only if you want old signatures to be regenerated.
4. Publish the public key (e.g. `key.asc` in the branch), import it on
   clients with `pacman-key --add`, and set
   `SigLevel = Required DatabaseOptional` for `[cavs]`.

For a private, single-user repository the unsigned setup is usually
sufficient; the packages themselves are still checksummed by pacman's `.db`.

## Why not lilac / an AUR helper?

The packages are intentionally **not** published to the AUR and the mpv
package does not exist under this name anywhere. `lilac`/`nvchecker` are
designed around an AUR/archlinuxcn repository layout and a long-running build
host; GitHub Actions plus the `repo` branch gives the same result (a pacman
repository refreshed on a schedule) without running a server.
