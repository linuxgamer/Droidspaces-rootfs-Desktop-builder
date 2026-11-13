#!/bin/bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib/desktop-config.sh"
source "$REPO_DIR/scripts/lib/anland-build.sh"
source "$REPO_DIR/scripts/lib/rootfs-config.sh"

: "${VERSION:=dev}"
TARGET_ARCH="aarch64"     # Target architecture used in artifact naming
PLATFORM="linux/arm64"    # Platform argument for Docker buildx

ENABLE_binfmt="false"
DESKTOP_AUTOSTART="false"
ENABLE_nosnap="false"
ENABLE_8gen2_wayland="false"
ENABLE_systemd257="false"
DISPLAY_BACKEND_INPUT="X11"
# Parse input arguments (-i specifies the Dockerfile, -v specifies the version)
while getopts "i:v:K:L:B:P:a:b:c:d:e:f:g:h:j:k:n:S:t:u:A:" opt; do
  case $opt in
    i) DOCKERFILE="$OPTARG" ;; 
    v) VERSION="$OPTARG" ;;    
    K) DESKTOP_INPUT="$OPTARG"  ;;
    L) DESKTOP_AUTOSTART="$OPTARG"  ;;
    B) DISPLAY_BACKEND_INPUT="$OPTARG" ;;
    P) PulseAudio="$OPTARG"  ;;
    g) ENABLE_zh_tz="$OPTARG"  ;; 
    a) ENABLE_binfmt="$OPTARG" ;; 
    b) ENABLE_yj="$OPTARG" ;;
    c) ENABLE_mesa="$OPTARG" ;;
    d) ENABLE_kfgj="$OPTARG" ;;
    e) ENABLE_zip="$OPTARG" ;;
    f) ENABLE_docker="$OPTARG" ;;
    h) ENABLE_srf="$OPTARG" ;; 
    j) ENABLE_chrome="$OPTARG" ;; # Install Google Chrome (optional, large download)
    k) ENABLE_usb_manager="$OPTARG" ;; # Install the USB manager (optional, pulls PyQt5)
    n) ENABLE_nosnap="$OPTARG" ;;
    S) ENABLE_systemd257="$OPTARG" ;; # systemd 257 legacy kernel compatibility
    t) ENABLE_8gen2_wayland="$OPTARG" ;; # Fix Snapdragon 8 Gen 2 Wayland display corruption
    u) USERNAME="$OPTARG" ;; 
    A) LEGACY_ANLAND_INPUT="$OPTARG" ;; # Legacy argument compatibility
    *) echo "Usage: $0 -i <template.Dockerfile> -K <none|KDE|'KDE mobile'|GNOME> [-B <x11|anland-wayland>]" ; exit 1 ;;
  esac
done

: "${USERNAME:=Gold}"
: "${ANLAND_RELEASE_REPOSITORY:=Goldzxcbug/droidspaces-package}"
: "${ANLAND_PACKAGE_REVISION:=}"

if ! DESKTOP="$(desktop_normalize "${DESKTOP_INPUT:-}")"; then
  echo "Error: invalid -K desktop name." >&2
  exit 1
fi
if [[ -n "${LEGACY_ANLAND_INPUT:-}" ]]; then
  case "$LEGACY_ANLAND_INPUT" in
    true) DISPLAY_BACKEND_INPUT="anland-wayland" ;;
    false) DISPLAY_BACKEND_INPUT="x11" ;;
    *) echo "Error: legacy argument -A only accepts true or false." >&2; exit 1 ;;
  esac
fi
if ! DISPLAY_BACKEND="$(display_backend_normalize "$DISPLAY_BACKEND_INPUT")"; then
  echo "Error: -B only accepts x11 or anland-wayland." >&2
  exit 1
fi
case "$DESKTOP_AUTOSTART" in true|false) ;; *) echo "Error: -L only accepts true or false." >&2; exit 1 ;; esac
case "$ENABLE_systemd257" in
  true)
    case "$DESKTOP" in
      kde)
        echo "Note: systemd 257 is enabled; regular KDE is on the verified support whitelist."
        ;;
      none)
        DISPLAY_BACKEND="x11"
        DESKTOP_AUTOSTART="false"
        ;;
      *)
        echo "Note: systemd 257 does not support $DESKTOP yet; forcing the none desktop and disabling desktop autostart."
        DESKTOP="none"
        DISPLAY_BACKEND="x11"
        DESKTOP_AUTOSTART="false"
        ;;
    esac
    ;;
  false) ;;
  *) echo "Error: -S only accepts true or false." >&2; exit 1 ;;
esac

if [[ "$DESKTOP" == kde-mobile || "$DESKTOP" == gnome || "$DESKTOP" == anland-next || \
      "$DESKTOP" == niri || "$DESKTOP" == hyprland || "$DESKTOP" == mango || "$DESKTOP" == denial ]]; then
  DISPLAY_BACKEND="anland-wayland"
fi
if [[ "$DISPLAY_BACKEND" == anland-wayland ]]; then
  PulseAudio="none"
fi
ANLAND_PACKAGE_FAMILY="$(anland_package_family "$DESKTOP" "$DISPLAY_BACKEND" || true)"

# Validation: check that a Dockerfile template was provided
if [ -z "$DOCKERFILE" ]; then
    echo "Error: the -i option must specify a template file."
    exit 1
fi

# Validation: check that the specified Dockerfile exists locally
if [ ! -f "$DOCKERFILE" ]; then
    echo "Error: template file '$DOCKERFILE' not found."
    exit 1
fi

# Extract the distribution target name
PREFIX="$(basename "${DOCKERFILE%.Dockerfile}")"

if ! desktop_target_supported "$PREFIX" "$DESKTOP"; then
  echo "Error: $PREFIX does not support desktop $DESKTOP." >&2
  exit 1
fi
if ! desktop_backend_supported "$PREFIX" "$DESKTOP" "$DISPLAY_BACKEND"; then
  echo "Error: $PREFIX does not support the $DESKTOP/$DISPLAY_BACKEND combination." >&2
  exit 1
fi
if [[ "$DESKTOP" == none && "$DESKTOP_AUTOSTART" == true ]]; then
  echo "Error: desktop autostart cannot be enabled when the desktop is none." >&2
  exit 1
fi

echo "========================================================="
echo " Starting build : $PREFIX"
echo " Template file : $DOCKERFILE"
echo " Build version : $VERSION"
echo " Target platform : $PLATFORM"
echo " Cross-architecture : $ENABLE_binfmt"
echo " Container detects some hardware and networking: $ENABLE_yj"
echo " Ubuntu nosnap: $ENABLE_nosnap"
echo " systemd 257 legacy kernel compatibility: $ENABLE_systemd257"
echo " Fix Snapdragon 8 Gen 2 Wayland display corruption: $ENABLE_8gen2_wayland"
echo " Desktop: $DESKTOP"
echo " Display backend: $DISPLAY_BACKEND"
echo " Desktop autostart: $DESKTOP_AUTOSTART"
echo "========================================================="

if [ -n "$ANLAND_PACKAGE_FAMILY" ]; then
  if ! anland_prepare_release "$ANLAND_PACKAGE_FAMILY" "$ANLAND_RELEASE_REPOSITORY" "$ANLAND_PACKAGE_REVISION"; then
    exit 1
  fi
  ANLAND_RELEASE_TAG="$ANLAND_RESOLVED_RELEASE_TAG"
  ANLAND_PACKAGE_REVISION="$ANLAND_RESOLVED_REVISION"
  echo " Anland ${ANLAND_PACKAGE_FAMILY^^} package Release: $ANLAND_RELEASE_REPOSITORY @ $ANLAND_RELEASE_TAG"
else
  ANLAND_PACKAGE_REVISION="disabled"
fi

# 1. Environment initialization (cross-architecture QEMU mode)
echo "Initializing QEMU/binfmt cross-architecture support..."
docker run --privileged --rm tonistiigi/binfmt --install all > /dev/null 2>&1

# 2. Cross-platform compiler (Buildx builder) setup
if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
    echo "Creating a new buildx builder: droidspaces-builder"
    docker buildx create --name droidspaces-builder --driver docker-container --use
else
    echo "Using the existing buildx builder: droidspaces-builder"
    docker buildx use droidspaces-builder
fi

# Bootstrap the builder to make sure it is ready
docker buildx inspect --bootstrap || echo "Warning: bootstrap failed, attempting to continue..."

# Enable strict mode
set -e

# 3. Core build flow
TEMP_TAR="custom-${PREFIX}-${DESKTOP}-rootfs.tar"
if [ "$DESKTOP" = "none" ]; then
  DISPLAY_LABEL="CLI"
else
  DISPLAY_LABEL="$(display_backend_label "$DISPLAY_BACKEND")"
fi
FINAL_NAME="${PREFIX}-${DESKTOP}-${DISPLAY_LABEL}-Droidspaces-rootfs-${TARGET_ARCH}-${VERSION}.tar.xz"

echo "Running Docker Buildx ($PLATFORM cross-architecture mode)..."

docker buildx build \
  --platform "$PLATFORM" \
  --target export \
  --output type=tar,dest="$TEMP_TAR" \
  --build-arg DESKTOP="$DESKTOP" \
  --build-arg DESKTOP_AUTOSTART="$DESKTOP_AUTOSTART" \
  --build-arg DISPLAY_BACKEND="$DISPLAY_BACKEND" \
  --build-arg PulseAudio="$PulseAudio" \
  --build-arg ENABLE_zh_tz_ARG="$ENABLE_zh_tz" \
  --build-arg ENABLE_binfmt_ARG="$ENABLE_binfmt" \
  --build-arg ENABLE_yj_ARG="$ENABLE_yj" \
  --build-arg ENABLE_mesa_ARG="$ENABLE_mesa" \
  --build-arg ENABLE_kfgj_ARG="$ENABLE_kfgj" \
  --build-arg ENABLE_zip_ARG="$ENABLE_zip" \
  --build-arg ENABLE_docker_ARG="$ENABLE_docker" \
  --build-arg ENABLE_srf_ARG="$ENABLE_srf" \
  --build-arg ENABLE_chrome_ARG="$ENABLE_chrome" \
  --build-arg ENABLE_usb_manager_ARG="$ENABLE_usb_manager" \
  --build-arg ENABLE_nosnap_ARG="$ENABLE_nosnap" \
  --build-arg ENABLE_systemd257_ARG="$ENABLE_systemd257" \
  --build-arg ENABLE_8gen2_wayland_ARG="$ENABLE_8gen2_wayland" \
  --build-arg ANLAND_RELEASE_REPOSITORY="$ANLAND_RELEASE_REPOSITORY" \
  --build-arg ANLAND_PACKAGE_REVISION="$ANLAND_PACKAGE_REVISION" \
  --build-arg USERNAME="$USERNAME" \
  -f "$DOCKERFILE" \
  .

echo "Writing the recommended configuration and compressing the build artifact..."
package_rootfs_with_config "$TEMP_TAR" "$FINAL_NAME" "$DESKTOP" "$DISPLAY_BACKEND" \
  "${PulseAudio:-none}" "${ENABLE_docker:-false}" "${ENABLE_mesa:-false}" "${ENABLE_zh_tz:-false}"

echo "========================================================="
echo " Congratulations! Build completed successfully: $FINAL_NAME"
echo "========================================================="
