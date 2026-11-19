#!/usr/bin/env bash
# Publish the built packages to the orphan `repo` branch of this repository.
#
# The branch contains a pacman repository:
#   https://raw.githubusercontent.com/<owner>/<repo>/repo/x86_64/cavs.db.tar.gz
#
# Requires: GITHUB_REPOSITORY, TOKEN (a token with contents:write).
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
artifacts="${ARTIFACTS:-$repo_root/artifacts}"
remote="https://x-access-token:${TOKEN:?TOKEN is required}@github.com/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}.git"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if git ls-remote --exit-code --heads "$remote" repo >/dev/null 2>&1; then
  git clone --quiet --depth 1 --branch repo "$remote" "$work"
else
  echo "creating orphan branch 'repo'"
  git init --quiet --initial-branch=repo "$work"
  git -C "$work" remote add origin "$remote"
fi

bash "$repo_root/ci/publish-repo.sh" "$work" "$artifacts"

cd "$work"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
if git diff --cached --quiet; then
  echo "repository already up to date"
  exit 0
fi
git commit --quiet -m "repo: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push --quiet origin HEAD:repo
echo "pushed repo branch"
