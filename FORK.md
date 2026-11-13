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

## Supported targets

Upstream builds `Debian-13`, `Ubuntu-24`, `Ubuntu-25`, `Ubuntu-26`, `Fedora-43`, `Fedora-44`
and `Arch`. This fork drops `Ubuntu-25` (an interim release, past its 9-month window, and
X11-only here) and `Fedora-43` (out of support now that Fedora 45 is current), and adds
`Fedora-45` as an X11-only target.

The all-desktop matrix is four targets times eight desktops, so the manifest generator expects
32 assets per language instead of 40.

### How Fedora 45 was added

The Mesa project publishes a `fedora_45` archive, but upstream's distribution release
(`Goldzxcbug/droidspaces-package`) does not forward it. This fork distributes its own Mesa
release from `linuxgamer/droidspaces-package`: `distribute-mesa.yml` gained the
`*_fedora_45_arm64.tar.gz` pattern, and `install-mesa.sh` now reads Mesa from that repository
(`DROIDSPACES_MESA_REPOSITORY`) while Anland, systemd257 and Wine still come from upstream
through `DROIDSPACES_COMPONENT_REPOSITORY`.

Fedora 45 has no Anland packages yet — no `producers/*/Fedora45_*` recipe exists in the Anland
source and no `fedora45` asset exists in any upstream release — so Wayland/Anland is
deliberately absent from the capability matrix. Adding it needs patched KWin/Mutter builds for
Fedora 45, which is a separate project spanning `SuperTurtleDev/anland` and
`droidspaces-package`.

Ubuntu 26.10 is deliberately not added, decided with the maintainer: it is an interim release
with nine months of support while Ubuntu 26.04 LTS is already covered with both Mesa and
Anland packages. Ubuntu targets stay at 24.04 and 26.04.

### Fedora 45 Anland status

The decisive check has been run: the KWin patch from the `Fedora44_v5` recipe applies to the
KWin 6.8.2 source that Fedora 45 ships (`patch --dry-run` succeeds, with offsets). Fedora 44
and Fedora 45 carry the same KWin version, which is why the patch set transfers. The Xwayland
patch in that recipe is a 31-byte stub rather than a real patch, and Xwayland is only rebuilt
when the recipe opts in, so it does not block anything.

What remains for Fedora 45 Wayland support is packaging, not patching: add a
`producers/kde/Fedora45_v5` recipe in a fork of `SuperTurtleDev/anland` (the Fedora 44 recipe
with the version gate changed to 45), build the patched KWin for Fedora 45, publish it as a
`fedora45` asset in `anland-kde-packages`, and only then add Fedora 45 to the Wayland lists in
`scripts/lib/desktop-config.sh`. Until that lands, Fedora 45 stays X11-only on purpose.

## Pinned versions

`mesa_version` and `anland_package_revision` default to empty, which means each build takes
whatever the rolling Mesa manifest and the Anland package release currently offer. Set them to
make a build reproducible:

- `mesa_version` selects that exact asset from Mesa's version catalogue and still verifies its
  SHA-256 from the catalogue entry. `install-mesa.sh` gained `--mesa-version <ver>` for this;
  unlike `--choose-version` it never prompts, so the Dockerfile can pass it during a build.
- `anland_package_revision` pins the Anland revision resolved by `anland_prepare_release`.

Both fail the build loudly when the requested version does not exist, instead of silently
falling back to the latest. To see which versions a build would pick, leave them empty and read
the build log, or run `install-mesa.sh --choose-version` inside an image to list the catalogue.

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
