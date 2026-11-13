#!/usr/bin/env bash
set -euo pipefail

config="${DROIDSPACES_DESKTOP_CONFIG:-/etc/droidspaces-desktop.conf}"
[[ -r "$config" ]] || { echo "Desktop configuration file is missing: $config" >&2; exit 1; }
source "$config"

case "${DESKTOP:-}:${DISPLAY_BACKEND:-}" in
    none:x11) command_line='exit 0' ;;
    kde:x11) command_line='export DISPLAY="${DISPLAY:-:5}"; exec startplasma-x11' ;;
    kde:anland-wayland) command_line='exec startplasma-wayland' ;;
    kde-mobile:anland-wayland) command_line='exec startplasmamobile' ;;
    gnome:anland-wayland) command_line='exec gnome-session --session=gnome' ;;
    # The Anland Next session is the bundled anland-session (session D-Bus + wayland link +
    # rootless Xwayland + mini-wm) and does not go through any desktop environment. It uses the
    # system /usr/bin path instead of a per-user copy; XDG_RUNTIME_DIR is computed by the script,
    # which only warns and continues when the systemd user manager is unavailable.
    anland-next:anland-wayland) command_line='exec /usr/bin/anland-session' ;;
    niri:anland-wayland) command_line='exec /usr/bin/niri-anland' ;;
    hyprland:anland-wayland) command_line='exec /usr/bin/hyprland-anland' ;;
    mango:anland-wayland) command_line='exec /usr/bin/mango-anland' ;;
    denial:anland-wayland) command_line='exec /usr/bin/denial-anland' ;;
    *)
        echo "Unsupported desktop session: ${DESKTOP:-unset}/${DISPLAY_BACKEND:-unset}" >&2
        exit 1
        ;;
esac

if [[ "${DROIDSPACES_SESSION_DRY_RUN:-false}" == true ]]; then
    printf '%s\n' "$command_line"
    exit 0
fi

exec /bin/bash -lc "$command_line"
