#!/usr/bin/env bash
set -euo pipefail

readonly CNB_API_URL="${CNB_API_URL:-https://api.cnb.cool}"
readonly RELEASE_TAG="${1:?usage: publish-cnb-release.sh RELEASE_TAG}"
readonly GITHUB_RELEASE_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
readonly CNB_RELEASE_REPOSITORY="${CNB_REPO:?CNB_REPO is not set}"

: "${CNB_TOKEN:?CNB_TOKEN is not set}"
: "${GH_TOKEN:?GH_TOKEN is not set}"

for command_name in curl gh jq stat; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing command: $command_name" >&2
        exit 1
    }
done

work_dir="$(mktemp -d)"
asset_dir="$work_dir/assets"
response_file="$work_dir/response.json"
payload_file="$work_dir/payload.json"
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p "$asset_dir"

api_repo="$CNB_API_URL/$CNB_RELEASE_REPOSITORY"
auth_header="Authorization: Bearer $CNB_TOKEN"
accept_header='Accept: application/vnd.cnb.api+json'
http_status=''

cnb_request() {
    local method="$1"
    local url="$2"
    local expected_statuses="$3"
    local body_file="${4:-}"
    local output_file="${5:-$response_file}"
    local -a curl_arguments=(
        --silent
        --show-error
        --output "$output_file"
        --write-out '%{http_code}'
        --request "$method"
        --header "$auth_header"
        --header "$accept_header"
    )

    if [[ -n "$body_file" ]]; then
        curl_arguments+=(
            --header 'Content-Type: application/json'
            --data-binary "@$body_file"
        )
    fi

    if ! http_status="$(curl "${curl_arguments[@]}" "$url")"; then
        echo "CNB API request failed: $method $url" >&2
        exit 1
    fi
    case ",$expected_statuses," in
        *",$http_status,"*) ;;
        *)
            echo "CNB API request failed: $method $url (HTTP $http_status)" >&2
            jq . "$output_file" 2>/dev/null || sed -n '1,80p' "$output_file" >&2
            exit 1
            ;;
    esac
}

prepare_cnb_uploads() {
    local index payload upload_response upload_url verify_url

    for index in "$@"; do
        payload="$work_dir/upload-request-$index.json"
        upload_response="$work_dir/upload-request-response-$index.json"
        jq -n \
            --arg asset_name "${upload_asset_names[$index]}" \
            --argjson size "${upload_asset_sizes[$index]}" \
            '{asset_name:$asset_name,size:$size,overwrite:true,ttl:0}' \
            > "$payload"
        cnb_request POST \
            "$api_repo/-/releases/$release_id/asset-upload-url" \
            201 \
            "$payload" \
            "$upload_response"
        upload_url="$(jq -er '.upload_url' "$upload_response")"
        verify_url="$(jq -er '.verify_url' "$upload_response")"
        if [[ "$verify_url" != http://* && "$verify_url" != https://* ]]; then
            verify_url="$CNB_API_URL$verify_url"
        fi
        if [[ "$verify_url" == *\?* ]]; then
            verify_url="${verify_url}&ttl=0"
        else
            verify_url="${verify_url}?ttl=0"
        fi
        upload_urls[$index]="$upload_url"
        verify_urls[$index]="$verify_url"
    done
}

upload_cnb_asset() {
    local index="$1"
    local asset_name="${upload_asset_names[$index]}"
    local asset_path="${upload_asset_paths[$index]}"
    local asset_size="${upload_asset_sizes[$index]}"
    local upload_url="${upload_urls[$index]}"
    local verify_url="${verify_urls[$index]}"
    local started_at finished_at elapsed upload_metrics upload_status upload_speed verify_status
    local attempt=1 max_attempts=3 upload_body verify_body

    started_at="$(date +%s)"
    echo "[$(date --iso-8601=seconds)] Starting CNB asset upload: $asset_name"
    while :; do
        upload_url="${upload_urls[$index]}"
        verify_url="${verify_urls[$index]}"
        upload_body="$work_dir/upload-body-$index-$attempt.txt"
        if ! upload_metrics="$(curl --fail-with-body --silent --show-error \
            --connect-timeout 30 \
            --speed-limit 10240 \
            --speed-time 120 \
            --request PUT \
            --header 'Content-Type: application/octet-stream' \
            --header "Content-Length: $asset_size" \
            --header 'Expect:' \
            --upload-file "$asset_path" \
            --output "$upload_body" \
            --write-out '%{http_code}\t%{time_total}\t%{speed_upload}' \
            "$upload_url")"; then
            upload_status="${upload_metrics%%$'\t'*}"
            echo "CNB asset upload failed: $asset_name (HTTP ${upload_status:-connection failed})" >&2
            if [[ -s "$upload_body" ]]; then
                sed -n '1,80p' "$upload_body" >&2
            fi
            case "$upload_status" in
                ''|000|408|429|5??)
                    if (( attempt < max_attempts )); then
                        attempt=$((attempt + 1))
                        echo "Requesting a new upload URL for $asset_name before retrying ($attempt/$max_attempts)" >&2
                        sleep 2
                        # CNB presigned upload URLs are single-use; a new URL must be requested before retrying.
                        prepare_cnb_uploads "$index"
                        continue
                    fi
                    ;;
            esac
            return 1
        fi
        IFS=$'\t' read -r upload_status _ upload_speed <<< "$upload_metrics"
        case "$upload_status" in
            200|201|204) ;;
            *)
                echo "CNB asset upload failed: $asset_name (HTTP $upload_status)" >&2
                if [[ -s "$upload_body" ]]; then
                    sed -n '1,80p' "$upload_body" >&2
                fi
                return 1
                ;;
        esac

        verify_body="$work_dir/verify-response-$index-$attempt.json"
        if ! verify_status="$(curl --silent --show-error \
            --connect-timeout 30 \
            --request POST \
            --header "$auth_header" \
            --header "$accept_header" \
            --output "$verify_body" \
            --write-out '%{http_code}' \
            "$verify_url")"; then
            echo "CNB asset verification failed: $asset_name (HTTP ${verify_status:-connection failed})" >&2
            if [[ -s "$verify_body" ]]; then
                sed -n '1,80p' "$verify_body" >&2
            fi
            case "$verify_status" in
                ''|000|408|429|5??)
                    if (( attempt < max_attempts )); then
                        attempt=$((attempt + 1))
                        echo "Requesting a new upload URL for $asset_name before retrying ($attempt/$max_attempts)" >&2
                        sleep 2
                        prepare_cnb_uploads "$index"
                        continue
                    fi
                    ;;
            esac
            return 1
        fi
        if [[ "$verify_status" != 200 ]]; then
            echo "CNB asset verification failed: $asset_name (HTTP $verify_status)" >&2
            if ! jq . "$verify_body" 2>/dev/null; then
                sed -n '1,80p' "$verify_body" >&2
            fi
            case "$verify_status" in
                408|429|5??)
                    if (( attempt < max_attempts )); then
                        attempt=$((attempt + 1))
                        echo "Requesting a new upload URL for $asset_name before retrying ($attempt/$max_attempts)" >&2
                        sleep 2
                        prepare_cnb_uploads "$index"
                        continue
                    fi
                    ;;
            esac
            return 1
        fi
        break
    done

    finished_at="$(date +%s)"
    elapsed=$((finished_at - started_at))
    printf '%s\t%s\t%s\t%s\n' \
        "$asset_name" "$asset_size" "$elapsed" "$upload_speed" \
        > "$work_dir/upload-result-$index.tsv"
    awk \
        -v name="$asset_name" \
        -v elapsed="$elapsed" \
        -v speed="$upload_speed" \
        'BEGIN {
            printf "[%s] upload complete: %d:%02d, %.3f MiB/s\n",
                name, int(elapsed / 60), elapsed % 60, speed / 1048576
        }'
}

upload_cnb_group() {
    local description="$1"
    shift
    local index pid failed=0 batch_size=0
    local concurrency="${CNB_UPLOAD_CONCURRENCY:-9999}"
    local -a pids=()

    [[ "$#" -gt 0 ]] || return 0
    if [[ ! "$concurrency" =~ ^[1-9][0-9]*$ ]]; then
        echo "CNB_UPLOAD_CONCURRENCY must be a positive integer: $concurrency" >&2
        return 1
    fi
    echo "Uploading CNB ${description} in parallel batches ($# items, concurrency limit $concurrency)..."
    for index in "$@"; do
        upload_cnb_asset "$index" &
        pids+=("$!")
        batch_size=$((batch_size + 1))
        if (( batch_size >= concurrency )); then
            failed=0
            for pid in "${pids[@]}"; do
                if ! wait "$pid"; then
                    failed=1
                fi
            done
            pids=()
            batch_size=0
            if [[ "$failed" -ne 0 ]]; then
                echo "CNB ${description} upload failed; stopping remaining batches." >&2
                return 1
            fi
        fi
    done
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done
    if [[ "$failed" -ne 0 ]]; then
        echo "At least one CNB ${description} upload failed." >&2
        return 1
    fi
}

local_assets_dir=''
if [[ -n "${CNB_LOCAL_ASSETS_DIR:-}" ]]; then
    [[ -d "$CNB_LOCAL_ASSETS_DIR" ]] || {
        echo "Local asset directory does not exist: $CNB_LOCAL_ASSETS_DIR" >&2
        exit 1
    }
    local_assets_dir="$(cd "$CNB_LOCAL_ASSETS_DIR" && pwd)"
    release_name=''
    release_body=''
    release_prerelease=false
    mapfile -t expected_assets < <(
        find "$local_assets_dir" -maxdepth 1 -type f \
            \( -name '*-zh.tar.xz' -o -name 'rootfs_zh.json' -o -name 'rootfs.json' \) \
            -printf '%f\n' | sort
    )
    archive_count=0
    for asset_name in "${expected_assets[@]}"; do
        [[ "$asset_name" == *-zh.tar.xz ]] && archive_count=$((archive_count + 1))
    done
    if [[ "$archive_count" -ne 40 || ! -f "$local_assets_dir/rootfs_zh.json" || ! -f "$local_assets_dir/rootfs.json" ]]; then
        echo "Local CNB assets are incomplete: 40 zh archives plus rootfs_zh.json and rootfs.json are required." >&2
        exit 1
    fi
else
    echo "Reading GitHub Release: $RELEASE_TAG"
    github_release_json="$work_dir/github-release.json"
    gh api \
        "repos/$GITHUB_RELEASE_REPOSITORY/releases/tags/$RELEASE_TAG" \
        > "$github_release_json"

    release_name="$(jq -er '.name // .tag_name' "$github_release_json")"
    release_body="$(jq -r '.body // ""' "$github_release_json")"
    release_prerelease="$(jq -r '
        if (.prerelease | type) == "boolean" then .prerelease
        else error("prerelease is not a boolean")
        end
    ' "$github_release_json")"
    mapfile -t expected_assets < <(jq -er --arg language "${CNB_ROOTFS_LANGUAGE:-}" '
        .assets[].name
        | select(
            $language != "zh" or
            endswith("-zh.tar.xz") or
            . == "rootfs_zh.json" or
            . == "rootfs.json"
          )
    ' "$github_release_json")
    if [[ "${#expected_assets[@]}" -eq 0 ]]; then
        echo "GitHub Release $RELEASE_TAG has no assets; refusing to create an empty CNB mirror." >&2
        exit 1
    fi
fi

if [[ "${CNB_ROOTFS_LANGUAGE:-}" == zh ]]; then
    release_name='Droidspaces 全桌面 Wayland RootFS（简体中文）'
    release_body=$'## 简体中文 RootFS\n\n面向 Droidspaces 的 ARM64 滚动 RootFS，提供 Debian 13、Ubuntu 26.04、Fedora 43、Fedora 44 和 Arch Linux 的 Anland Wayland 桌面镜像。\n\n- 覆盖 8 种桌面环境：KDE Plasma、KDE Plasma Mobile、GNOME、Anland Next、Niri、Hyprland、Mango 和 Denial。\n- 共 40 个简体中文 `.tar.xz` 镜像，均面向 ARM64。\n- `rootfs.json` 包含全部中文 RootFS 地址；`rootfs_zh.json` 是订阅清单，包含版本、文件大小、SHA-256 校验值及 CNB 下载地址。\n- 镜像包含 Droidspaces 桌面自动启动配置和高通 Adreno/Mesa 支持。\n\n在 Droidspaces RootFS 管理中添加 `rootfs_zh.json` 即可订阅。本 CNB Release 仅发布简体中文 RootFS，并随每周滚动构建更新。'
fi

# Prefer reusing local assets the caller has already downloaded, to avoid downloading tens of GiB again and exhausting the runner disk.
# Fall back to gh release download only when an expected asset is missing from the local directory.
reuse_local_assets=0
if [[ -n "$local_assets_dir" ]]; then
    reuse_local_assets=1
    for asset_name in "${expected_assets[@]}"; do
        if [[ ! -f "$local_assets_dir/$asset_name" ]]; then
            reuse_local_assets=0
            break
        fi
    done
fi

if [[ "$reuse_local_assets" -eq 1 ]]; then
    echo "Reusing ${#expected_assets[@]} CNB assets already prepared locally: $local_assets_dir"
    for asset_name in "${expected_assets[@]}"; do
        ln -sfn -- "$local_assets_dir/$asset_name" "$asset_dir/$asset_name"
    done
else
    echo "Downloading ${#expected_assets[@]} GitHub Release assets..."
    download_args=(gh release download "$RELEASE_TAG" --repo "$GITHUB_RELEASE_REPOSITORY" --dir "$asset_dir")
    for asset_name in "${expected_assets[@]}"; do
        download_args+=(--pattern "$asset_name")
    done
    "${download_args[@]}"
fi
for asset_name in "${expected_assets[@]}"; do
    [[ -f "$asset_dir/$asset_name" ]] || {
        echo "Missing declared GitHub Release asset: $asset_name" >&2
        exit 1
    }
done
if [[ "${CNB_ROOTFS_LANGUAGE:-}" == zh ]]; then
    manifest="$asset_dir/rootfs_zh.json"
    [[ -f "$manifest" ]] || {
        echo "The Chinese RootFS Release is missing rootfs_zh.json." >&2
        exit 1
    }
    jq --arg base "https://cnb.cool/$CNB_RELEASE_REPOSITORY/-/releases/download/$RELEASE_TAG" \
        'map(.download_url = ($base + "/" + (.file + ".tar.xz")))' \
        "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    jq . "$manifest" > "$asset_dir/rootfs.json.tmp"
    mv "$asset_dir/rootfs.json.tmp" "$asset_dir/rootfs.json"
    release_build_id="${BUILD_ID:-$(jq -er '.[0].version' "$manifest")}"
    release_build_time="${BUILD_TIME:-$(jq -er '.[0].build_date' "$manifest")}"
    release_body+=$'\n\n### Build information\n\n'
    release_body+="- Build ID: $release_build_id"$'\n'
    release_body+="- Build time (UTC): $release_build_time"$'\n'
    release_body+='- Rolling tag: '"$RELEASE_TAG"$'\n'
    release_body+='- Architecture: ARM64; 40 Simplified Chinese RootFS images.'
    release_body+=$'\n\n### Index of all RootFS URLs\n\n'
    release_body+="[rootfs.json](https://cnb.cool/$CNB_RELEASE_REPOSITORY/-/releases/download/$RELEASE_TAG/rootfs.json) — download URLs for all 40 Simplified Chinese RootFS images."
    release_body+=$'\n\n'
    release_body+="[rootfs_zh.json](https://cnb.cool/$CNB_RELEASE_REPOSITORY/-/releases/download/$RELEASE_TAG/rootfs_zh.json) — Droidspaces Simplified Chinese subscription manifest."
fi

cnb_request GET "$api_repo/-/releases/tags/$RELEASE_TAG" '200,404'
if [[ "$http_status" == 200 ]]; then
    release_id="$(jq -er '.id' "$response_file")"
    jq -n \
        --arg name "$release_name" \
        --arg body "$release_body" \
        --argjson prerelease "$release_prerelease" \
        '{name:$name,body:$body,draft:false,prerelease:$prerelease,make_latest:"false"}' \
        > "$payload_file"
    cnb_request PATCH "$api_repo/-/releases/$release_id" 200 "$payload_file"
    echo "Updating CNB Release: $RELEASE_TAG"
else
    jq -n \
        --arg tag "$RELEASE_TAG" \
        --arg name "$release_name" \
        --arg body "$release_body" \
        --argjson prerelease "$release_prerelease" \
        '{tag_name:$tag,target_commitish:"main",name:$name,body:$body,draft:false,prerelease:$prerelease,make_latest:"false"}' \
        > "$payload_file"
    cnb_request POST "$api_repo/-/releases" 201 "$payload_file"
    release_id="$(jq -er '.id' "$response_file")"
    echo "Created CNB Release: $RELEASE_TAG"
fi

declare -A expected_asset_names=()
declare -a upload_asset_names=()
declare -a upload_asset_paths=()
declare -a upload_asset_sizes=()
declare -a upload_urls=()
declare -a verify_urls=()
declare -a parallel_upload_indexes=()
declare -a manifest_upload_indexes=()
upload_index=0
for asset_name in "${expected_assets[@]}"; do
    expected_asset_names["$asset_name"]=1
    asset_path="$asset_dir/$asset_name"
    asset_size="$(stat --format='%s' "$asset_path")"
    upload_asset_names[$upload_index]="$asset_name"
    upload_asset_paths[$upload_index]="$asset_path"
    upload_asset_sizes[$upload_index]="$asset_size"
    case "$asset_name" in
        rootfs.json|rootfs_zh.json|rootfs_en.json|*-manifest|SHA256SUMS|SHA256SUMS.*)
            manifest_upload_indexes+=("$upload_index")
            ;;
        *)
            parallel_upload_indexes+=("$upload_index")
            ;;
    esac
    upload_index=$((upload_index + 1))
done

upload_started_at="$(date +%s)"
prepare_cnb_uploads "${parallel_upload_indexes[@]}"
upload_cnb_group "assets" "${parallel_upload_indexes[@]}"

# Publish the manifest last so a failed sync cannot reference packages that are not ready yet.
prepare_cnb_uploads "${manifest_upload_indexes[@]}"
upload_cnb_group "manifest" "${manifest_upload_indexes[@]}"
upload_finished_at="$(date +%s)"
upload_elapsed=$((upload_finished_at - upload_started_at))
(( upload_elapsed > 0 )) || upload_elapsed=1

total_uploaded_bytes=0
for result_file in "$work_dir"/upload-result-*.tsv; do
    IFS=$'\t' read -r _ asset_size _ _ < "$result_file"
    total_uploaded_bytes=$((total_uploaded_bytes + asset_size))
done
awk \
    -v bytes="$total_uploaded_bytes" \
    -v elapsed="$upload_elapsed" \
    'BEGIN {
        printf "CNB parallel upload complete: %d:%02d, aggregate speed %.3f MiB/s (%.2f Mbit/s)\n",
            int(elapsed / 60), elapsed % 60,
            bytes / 1048576 / elapsed, bytes / 1048576 / elapsed * 8
    }'

# Delete old assets only after the upload finishes, so an interrupted sync cannot damage the previous complete mirror.
cnb_request GET "$api_repo/-/releases/$release_id" 200
mapfile -t cnb_asset_rows < <(jq -r '.assets[] | [.id, .name] | @tsv' "$response_file")
for asset_row in "${cnb_asset_rows[@]}"; do
    IFS=$'\t' read -r asset_id asset_name <<< "$asset_row"
    [[ -n "$asset_id" && -n "$asset_name" ]] || continue
    if [[ -z "${expected_asset_names[$asset_name]:-}" ]]; then
        echo "Deleting stale CNB asset: $asset_name"
        cnb_request DELETE \
            "$api_repo/-/releases/$release_id/assets/$asset_id" \
            '200,204'
    fi
done

echo "CNB Release sync complete: https://cnb.cool/$CNB_RELEASE_REPOSITORY/-/releases"
