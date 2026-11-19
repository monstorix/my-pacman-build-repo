# GitHub Actions and the pacman repository branch

## Workflow

`.github/workflows/build.yml` runs in an `archlinux:latest` container on
`ubuntu-latest`:

| Trigger | When |
|---|---|
| `schedule` | Every Monday, 03:17 UTC (`cron: "17 3 * * 1"`) |
| `push` to `main` | Changes under `packages/`, `ci/` or `.github/workflows/` |
| `workflow_dispatch` | Manual run from the Actions tab |

Steps:

1. `pacman -Syu base-devel git sudo namcap`, create a `builder` user with
   passwordless sudo, and `chown` the workspace (the container's checkout is
   owned by root).
2. `ci/build.sh` as `builder`:
   - builds the AUR dependencies `chromaprint-fftw` and `uavs3d` from source
     and installs them;
   - builds and installs `av3a-git` and `davs2-10bit-git` (needed to link
     FFmpeg);
   - builds `mpv-full-build-cavs-git` (build only, not installed) and
     smoke-tests the package: `--vd=help` must list `cavs`, `libdavs2` and
     `libuavs3d` and `--ad=help` must list `libdra` and `libarcdav3a`,
     otherwise the run fails;
   - builds `icast-dkms`;
   - copies all `*.pkg.tar.zst` into `artifacts/`.
3. `namcap` runs on the PKGBUILDs and packages (`|| true`, it is a report,
   not a gate).
4. The artifacts are uploaded with `actions/upload-artifact@v4`
   (`arch-packages`, 14 days).
5. `ci/push-repo.sh` publishes to the `repo` branch (skipped for pull
   requests).

`timeout-minutes: 350` keeps a stuck build under GitHub's 6-hour job limit.
The workflow needs `permissions: contents: write`; it uses the built-in
`GITHUB_TOKEN`, no additional secret is required.

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
  *.pkg.tar.zst
```

`repo-add` normally creates `cavs.db` as a symlink to `cavs.db.tar.gz`.
raw.githubusercontent.com serves symlinks as their target *text*, which would
break `pacman -Sy`, so `ci/publish-repo.sh` replaces both links with regular
copies after every `repo-add`.

Package files are copied in, and only the **two newest builds of each
package** are kept (pruned by name and mtime before `repo-add --remove
--prevent-downgrade`). `--prevent-downgrade` stops an older build from
overwriting a newer version in the database.

`raw.githubusercontent.com` serves the branch over HTTPS, so pacman needs no
special transport:

```ini
[cavs]
Server = https://raw.githubusercontent.com/<owner>/<repo>/repo/$arch
SigLevel = Optional TrustAll
```

`SigLevel = Optional TrustAll` is required because `repo-add` does not sign
the database. If you prefer signatures, see below.

> Put `[cavs]` **before** `[extra]` in `pacman.conf`. `davs2-10bit-git`
> provides `davs2`, and repository order decides which one wins when both
> repositories offer it.

## First run checklist

1. Create the GitHub repository and push `main`.
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

A full run takes roughly 1.5–3 hours (FFmpeg + mpv dominate). On a **public**
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
