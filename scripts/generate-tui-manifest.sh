#!/usr/bin/env bash
# generate-tui-manifest.sh — build the TUI update manifest for a release.
#
# install-tui.sh and droidspaces-tui.sh read this manifest to update the toolkit, so
# publishing our own assets is what stops them from pulling upstream's Chinese scripts.
#
# Usage: generate-tui-manifest.sh <assets-dir> <release-tag> <revision> [generated-at]
#   assets-dir    directory holding the .sh files (normally scripts/tui)
#   release-tag   tag the manifest declares; must match RELEASE_TAG in the installers
#   revision      commit SHA or other identifier recorded in the manifest
#   generated-at  ISO-8601 timestamp; defaults to now (UTC)
#
# Writes the manifest to stdout. The format is the one the installers validate:
#   format=1
#   release_tag=<tag>
#   revision=<revision>
#   generated_at=<timestamp>
#   sha256<TAB>size<TAB>role<TAB>target<TAB>asset
set -euo pipefail

dir="${1:?usage: generate-tui-manifest.sh <assets-dir> <release-tag> <revision> [generated-at]}"
tag="${2:?missing release tag}"
revision="${3:?missing revision}"
generated_at="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

[[ -d "$dir" ]] || { echo "error: not a directory: $dir" >&2; exit 1; }

# asset:role:target — the installers accept exactly these shapes.
entries=(
    "droidspaces-tui.sh:tui:/usr/local/bin/droidspaces-tui"
    "droidspaces-gpu.sh:tui:/usr/local/bin/droidspaces-gpu"
    "install-tui.sh:bootstrap:-"
)

# Every installer script in the directory is shipped as an installer asset.
for path in "$dir"/install-*.sh; do
    [[ -e "$path" ]] || continue
    name="$(basename "$path")"
    [[ "$name" == "install-tui.sh" ]] && continue
    entries+=("$name:installer:/usr/local/sbin/${name%.sh}")
done

printf 'format=1\n'
printf 'release_tag=%s\n' "$tag"
printf 'revision=%s\n' "$revision"
printf 'generated_at=%s\n' "$generated_at"
printf 'sha256\tsize\trole\ttarget\tasset\n'

for entry in "${entries[@]}"; do
    asset="${entry%%:*}"
    rest="${entry#*:}"
    role="${rest%%:*}"
    target="${rest#*:}"

    path="$dir/$asset"
    [[ -f "$path" ]] || { echo "error: missing asset: $path" >&2; exit 1; }

    sha="$(sha256sum "$path" | awk '{print $1}')"
    size="$(wc -c < "$path" | tr -d ' ')"
    [[ "$size" -gt 0 ]] || { echo "error: empty asset: $path" >&2; exit 1; }

    printf '%s\t%s\t%s\t%s\t%s\n' "$sha" "$size" "$role" "$target" "$asset"
done
