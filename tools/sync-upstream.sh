#!/usr/bin/env bash
# sync-upstream.sh — merge the original repository, then refresh the Chinese reference copies.
#
# Conflict policy (see FORK.md):
#   README.md / scripts/README.md                      -> keep ours (English)
#   .github/workflows/build-rootfs-releases.yml        -> keep ours (English preset);
#                                                         port behavioural changes from
#                                                         upstream's *-en.yml by hand
#   build-rootfs-releases-en.yml (modify/delete)       -> keep deleted, port behaviour
#   translated comment lines                           -> take upstream code, re-apply English
set -euo pipefail

cd "$(dirname "$0")/.."

if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "error: no 'upstream' remote. Add it with:" >&2
    echo "  git remote add upstream https://github.com/Goldzxcbug/Droidspaces-rootfs-Desktop-builder.git" >&2
    exit 1
fi

echo "== fetching upstream =="
git fetch upstream --prune

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is dirty; commit or stash before syncing." >&2
    exit 1
fi

echo
echo "== merging upstream/main =="
if ! git merge --no-edit upstream/main; then
    cat >&2 <<'EOF'

Merge stopped on conflicts. Resolve them with this policy:

  README.md, scripts/README.md
      keep OUR English version:
        git checkout --ours README.md scripts/README.md
        git add README.md scripts/README.md

  .github/workflows/build-rootfs-releases.yml
      keep OURS, then port any real behavioural change from upstream's English preset:
        git checkout --ours .github/workflows/build-rootfs-releases.yml
        git show upstream/main:.github/workflows/build-rootfs-releases-en.yml | less
        git add .github/workflows/build-rootfs-releases.yml

  .github/workflows/build-rootfs-releases-en.yml (modify/delete)
      keep it deleted:
        git rm .github/workflows/build-rootfs-releases-en.yml

  translated comments in scripts/, *.Dockerfile, .github/workflows/*
      take upstream's code and re-apply the English comment, then:
        git add <file>

Then finish with:
  git commit
  bash tools/sync-upstream.sh     # re-run to refresh the Chinese copies
EOF
    exit 1
fi

echo
echo "== refreshing Chinese reference copies =="
git show upstream/main:README.md > README.zh.md
git show upstream/main:scripts/README.md > scripts/README_zh.md

if [[ -n "$(git status --porcelain -- README.zh.md scripts/README_zh.md)" ]]; then
    git add README.zh.md scripts/README_zh.md
    git commit -q -m "chore: refresh Chinese reference docs from upstream"
    echo "committed refreshed Chinese copies"
else
    echo "Chinese copies already current"
fi

echo
echo "Now verify before pushing:"
echo "  perl tools/check-translation.pl && bash tools/verify.sh"
