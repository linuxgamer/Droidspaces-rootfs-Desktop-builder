# Fork notes

This repository is an **English-first fork** of
[Goldzxcbug/Droidspaces-rootfs-Desktop-builder](https://github.com/Goldzxcbug/Droidspaces-rootfs-Desktop-builder).
Upstream is MIT-licensed; this fork keeps the same licence and attribution (see [LICENSE](LICENSE)).

The goal is to keep upstream's engineering while making English the default language for
readers, Actions users, and future maintainers.

## What differs from upstream

| Area | Upstream | This fork |
| --- | --- | --- |
| Project README | `README.md` (Chinese) + `README_english.md` | `README.md` (English) + `README.zh.md` |
| Script guide | `scripts/README.md` (Chinese) + `scripts/README_english.md` | `scripts/README.md` (English) + `scripts/README_zh.md` |
| Docs | `docs/zh/` and `docs/en/` | same, with `docs/en/` as the primary set |
| Release workflow | `build-rootfs-releases.yml` (Chinese) **and** `build-rootfs-releases-en.yml` (English) | a single `build-rootfs-releases.yml`, using the English preset defaults |
| Release feeds | point at the upstream repository's releases | point at **this** repository's releases |
| Code comments | Chinese | English |

The canonical release workflow carries the **English preset** defaults that upstream ships in
`build-rootfs-releases-en.yml`:

- `ui_language: en`
- `use_chinese: false` (Chinese locale and Asia/Shanghai timezone stay opt-in)
- `display_backend: x11`
- `remove_snap: false`
- `enable_fcitx5: false`

Upstream's bilingual runtime strings are deliberately preserved. Installers call
`msg '中文' 'English'`, `log "中文" "English"` and `die "中文" "English"`, picking the second
string unless the locale is `zh*`. Keeping both halves means Chinese still works for `zh`
locales, and it keeps merges with upstream small.

## RootFS composition

The image is trimmed compared with upstream. These were unconditional before and are now opt-in
flags, or gone:

| Component | Before | Now |
| --- | --- | --- |
| Google Chrome | installed in every image | `enable_chrome`, default `false` |
| USB manager (pulls python3/PyQt5) | installed in every image | `enable_usb_manager`, default `false` |
| `fastfetch` | in the base package list | removed |
| Compression tools | `enable_zip` default `true` | default `false` |

New flags are wired end to end: `ENABLE_chrome_ARG` / `ENABLE_usb_manager_ARG` in every
Dockerfile, `-j` / `-k` in both build scripts, and `enable_chrome` / `enable_usb_manager`
inputs in the core, release and all-desktop workflows.

Keeping `enable_mesa` and `enable_yj` on is intentional: they carry GPU acceleration and the
networking/hardware services the images exist for.

## Release feeds point at this repository

The subscription indexes (`rootfs_zh.json`, `rootfs_en.json`) and the documentation that
describes them reference `linuxgamer/Droidspaces-rootfs-Desktop-builder`, not upstream. They
resolve only after the first **Publish All-Desktop Wayland RootFS** run creates the rolling
release; until then the links return 404.

The CNB mirror link was dropped: CNB publishing targets upstream's account, and `sync_cnb` is
disabled by default.

Dependency repositories are intentionally still upstream: `Goldzxcbug/droidspaces-package`
(the Anland/Mesa/media-decode packages), `lfdevs/mesa-for-android-container`,
`Re-s/droidspaces-media-decode`, and `Yizhou147/Droidspaces-USB-Manager`. Those host the
binaries the build downloads; repointing them would break builds.

One consequence worth knowing: the in-image toolchain updates itself from
`Goldzxcbug/droidspaces-package` (`DROIDSPACES_TUI_REPOSITORY`, `DROIDSPACES_COMPONENT_*`).
Running "update TUI" inside the image therefore installs *upstream's* scripts, not this
fork's. To make the fork fully self-contained you would publish your own TUI/component
release and point those variables at it.

## Syncing with upstream

`upstream` is the original repository:

```bash
git remote -v          # origin = this fork, upstream = Goldzxcbug/...
```

Run the helper, which fetches, merges, and re-applies the Chinese reference copies:

```bash
bash tools/sync-upstream.sh
```

Or do it by hand:

```bash
git fetch upstream
git merge upstream/main
# Then refresh the Chinese copies we keep on different paths:
git show upstream/main:README.md         > README.zh.md
git show upstream/main:scripts/README.md > scripts/README_zh.md
```

### Resolving conflicts

Only four kinds of conflicts are expected:

1. **`README.md`, `scripts/README.md`** — upstream writes Chinese here, this fork writes
   English. Keep **ours** (the English text), then refresh `README.zh.md` /
   `scripts/README_zh.md` from upstream as shown above. Do not copy upstream's Chinese back
   into the English files.
2. **`.github/workflows/build-rootfs-releases.yml`** — upstream changes the Chinese preset,
   this fork holds the English preset. Keep **ours** by default, then compare with
   `git show upstream/main:.github/workflows/build-rootfs-releases-en.yml`: if upstream
   changed *behaviour* (new input, new default, new step) rather than wording, port that
   change in English.
3. **`.github/workflows/build-rootfs-releases-en.yml`** — deleted in this fork, so a modify/
   delete conflict may appear. Keep it deleted, but port any behavioural change as in (2).
4. **Translated comment lines** in `scripts/`, `*.Dockerfile`, `.github/workflows/*` — take
   upstream's code, re-apply the English comment. Comment-only conflicts are safe: the code
   on both sides is identical.

Release-feed URLs will also conflict if upstream rewrites them: keep the `linuxgamer/...`
versions from this fork.

After resolving, re-run the checks in [Verifying changes](#verifying-changes).

## Verifying changes

There is no CI for translation correctness, so verify locally before pushing:

```bash
# 1. No Chinese left outside the Chinese reference docs
perl tools/check-translation.pl

# 2. Shell syntax, workflow YAML and documentation links still valid
bash tools/verify.sh
```

`tools/check-translation.pl` lists any remaining Chinese outside `README.zh.md`,
`scripts/README_zh.md` and `docs/zh/`, ignoring the intentional `msg/log/die`
Chinese/English pairs. A clean run prints `OK`.

`tools/verify.sh` runs `bash -n` over every shell script, loads every workflow with a YAML
parser, and checks relative documentation links. It needs `python3`; it installs nothing.

The real proof is still a build: workflow and Dockerfile changes are only exercised by running
**Build and Release Droidspaces RootFS** from the Actions tab (or
**Publish All-Desktop Wayland RootFS** for the rolling release). Do that before announcing a
release.

## Keeping this file current

When you change what the fork does differently (rename a file, drop a workflow, flip a
default, repoint a feed), update the table above in the same commit.
