FROM ubuntu:24.04 AS customizer

#######################################################
ARG DESKTOP
ARG DESKTOP_AUTOSTART
ARG DISPLAY_BACKEND
ARG PulseAudio
ARG ENABLE_zh_tz_ARG
ARG ENABLE_binfmt_ARG
ARG ENABLE_yj_ARG
ARG ENABLE_mesa_ARG
ARG MESA_VERSION
ARG ENABLE_kfgj_ARG
ARG ENABLE_zip_ARG
ARG ENABLE_docker_ARG
ARG ENABLE_srf_ARG
ARG ENABLE_nosnap_ARG
ARG ENABLE_systemd257_ARG
ARG ENABLE_chrome_ARG
ARG ENABLE_usb_manager_ARG
ARG USERNAME
######################################################

ENV DEBIAN_FRONTEND=noninteractive

# Enable APT parallel connections, HTTP(S) pipeline, and download retries
RUN printf '%s\n' \
    'Acquire::Queue-Mode "host";' \
    'Acquire::http::Pipeline-Depth "10";' \
    'Acquire::https::Pipeline-Depth "10";' \
    'Acquire::Retries "3";' \
    > /etc/apt/apt.conf.d/99parallel-downloads

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/
COPY scripts/nosnap.sh /usr/local/sbin/nosnap
COPY scripts/systemd257.sh /usr/local/sbin/systemd257

# Copy the custom bashrc script into the RootFS profile directory
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Generic Droidspaces USB Manager installer
COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager
COPY scripts/tui/install-anland-kde.sh /usr/local/sbin/install-anland-kde
COPY scripts/tui/install-anland-gnome.sh /usr/local/sbin/install-anland-gnome
COPY scripts/tui/install-anland-next.sh /usr/local/sbin/install-anland-next
COPY scripts/tui/install-mesa.sh /usr/local/sbin/install-mesa
COPY scripts/tui/install-hangover-wine.sh /usr/local/sbin/install-hangover-wine
COPY scripts/tui/install-winefonts.sh /usr/local/sbin/install-winefonts
COPY scripts/tui/droidspaces-tui.sh /usr/local/bin/droidspaces-tui
COPY scripts/tui/droidspaces-gpu.sh /usr/local/bin/droidspaces-gpu
COPY scripts/install-desktop.sh /usr/local/sbin/install-desktop
COPY scripts/configure-desktop.sh /usr/local/sbin/configure-desktop
COPY scripts/configure-chrome.sh /usr/local/sbin/configure-chrome
COPY scripts/start-desktop-session.sh /usr/local/bin/start-desktop-session
COPY scripts/desktops/ /usr/local/lib/droidspaces/desktops/
COPY scripts/etc/wireplumber/wireplumber.conf.d/Anland-Audio.conf /tmp/Anland-Audio.conf
RUN if [ "$DISPLAY_BACKEND" = "anland-wayland" ]; then \
        install -D -m 0644 /tmp/Anland-Audio.conf /etc/wireplumber/wireplumber.conf.d/Anland-Audio.conf; \
    fi && \
    rm -f /tmp/Anland-Audio.conf

# Make the relevant scripts executable
RUN chmod +x /usr/local/bin/download-firmware /usr/local/sbin/nosnap /etc/profile.d/ds-aliases.sh /usr/local/sbin/install-anland-* /usr/local/sbin/install-mesa /usr/local/sbin/install-hangover-wine /usr/local/sbin/install-winefonts /usr/local/sbin/install-desktop /usr/local/sbin/configure-desktop /usr/local/sbin/configure-chrome /usr/local/bin/droidspaces-tui /usr/local/bin/droidspaces-gpu /usr/local/bin/start-desktop-session /usr/local/lib/droidspaces/desktops/*.sh && \
    ln -s droidspaces-tui /usr/local/bin/dstui && \
    ln -s droidspaces-tui /usr/local/bin/ds-tui

# The Ubuntu base image skips .mo translation files by default via dpkg path-exclude; re-enable them globally
# so software installed by every desktop profile ships complete language translations.
RUN sed -i 's|^path-exclude=/usr/share/locale/\*/LC_MESSAGES/\*.mo|#&|' \
        /etc/dpkg/dpkg.cfg.d/excludes 2>/dev/null || true

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl wget && \
    if [ "$ENABLE_nosnap_ARG" = "true" ]; then \
        echo "--> [enabled] nosnap: pre-configuring and removing Ubuntu Snap..." && \
        bash /usr/local/sbin/nosnap; \
    else \
        echo "--> [skipped] nosnap not enabled"; \
    fi

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Core tool components
    bash jq dialog coreutils diffutils file findutils grep sed gawk curl wget ca-certificates locales bash-completion udev dbus systemd-sysv systemd-resolved neofetch \
    # User-requested base development/editor tools
    git nano  sudo \
    # Networking and SSH tools
    openssh-server net-tools iptables iputils-ping iproute2 dnsutils \
    # procps process tools for system monitoring
    procps \
    # Core kernel module support
    kmod tzdata && \
    /usr/local/sbin/install-desktop "$DESKTOP" && \
    #Input method fcitx5 (optional)
    if [ "$ENABLE_srf_ARG" = "true" ]; then \
        apt-get install -y fcitx5; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        apt-get install -y  fcitx5-chinese-addons; \
    fi && \
    ## Development tools integration (optional)
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        build-essential gcc g++ make cmake autoconf automake libtool pkg-config clang llvm python3 python3-pip python3-dev python3-venv python-is-python3; \
    fi && \
    ## Compression tools extension (optional)
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        zip unzip p7zip-full bzip2 xz-utils tar gzip; \
    fi && \
    ## docker (optional)
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        docker.io docker-compose-v2; \
    fi && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Force the use of iptables-legacy (a hard requirement for Android kernel compatibility)
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "Asia/Shanghai" > /etc/timezone && \
        dpkg-reconfigure -f noninteractive tzdata && \
        sed -i '/zh_CN.UTF-8/s/^# //' /etc/locale.gen && \
        locale-gen && \
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; \
    else \
        locale-gen && \
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    fi && \
    # Configure the SSH service (disable root password login but allow regular password authentication)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Delete the default debian user, together with its home directory, if present in the container
    (deluser --remove-home ubuntu || true) && \
    useradd -m -s /bin/bash ${USERNAME} && echo "${USERNAME}:1234" | chpasswd && \
    systemctl enable ssh

# Optional: the USB manager pulls python3/PyQt5 and a third-party application.
RUN if [ "$ENABLE_usb_manager_ARG" = "true" ]; then \
    /usr/local/sbin/install-droidspaces-usb-manager --user "${USERNAME}"; \
    fi

# Initialize the environment variables file; desktop-specific variables are managed by the matching profile.
RUN : > /etc/environment
# Audio selection
RUN if [ "$PulseAudio" = "socket" ]; then \
        echo "PULSE_SERVER=unix:/tmp/.pulse-socket" >> /etc/environment; \
    elif [ "$PulseAudio" = "tcp" ]; then \
        echo "PULSE_SERVER=tcp:127.0.0.1:4713" >> /etc/environment; \
    fi

# Input method autostart
COPY scripts/start/ /tmp/droidspaces-start/
RUN <<'EOF_RUN'
    if [ "$ENABLE_srf_ARG" = "true" ]; then
    mkdir -p /home/${USERNAME}/.config/autostart
    cat <<'EOF' > /home/${USERNAME}/.config/autostart/fcitx5.desktop
[Desktop Entry]
Name=Fcitx5
GenericName=Input Method
Comment=Start Input Method
Exec=fcitx5 -d
Icon=fcitx
Terminal=false
Type=Application
Categories=System;Utility;
StartupNotify=false
NoDisplay=true
EOF
    cat <<'EOF' >> /etc/environment
XMODIFIERS=@im=fcitx5
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
SDL_IM_MODULE=fcitx5
GLFW_IM_MODULE=fcitx
EOF
fi
    if [ "$ENABLE_mesa_ARG" = "true" ] ; then
        cat <<'EOF' >> /etc/environment
MESA_LOADER_DRIVER_OVERRIDE=kgsl
TU_DEBUG=noconform
EOF
    fi

    echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> /home/${USERNAME}/.bashrc
    /usr/local/sbin/configure-desktop "$DESKTOP" "$DISPLAY_BACKEND" "$DESKTOP_AUTOSTART" "$USERNAME"
    rm -rf /tmp/droidspaces-start
EOF_RUN

RUN if [ "$ENABLE_mesa_ARG" = "true" ]; then \
        if [ -n "$MESA_VERSION" ]; then /usr/local/sbin/install-mesa --1 --mesa-version "$MESA_VERSION"; else /usr/local/sbin/install-mesa --1; fi; \
    else \
        echo "--> [skipped] Mesa driver installation not enabled"; \
    fi

# Optional: installs Google Chrome (a large download) and its desktop integration.
RUN if [ "$ENABLE_chrome_ARG" = "true" ]; then \
    /usr/local/sbin/configure-chrome "$DESKTOP" "$DISPLAY_BACKEND"; \
    fi

# Fix the DHCP network service configuration inside the container
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# Apply Android runtime compatibility fixes (mainly for systemd and udev)
RUN <<'EOF_RUN'

# --- 1. General compatibility fixes ---
# Create Android network permission groups (running a Linux container on an Android kernel requires these GIDs to access network sockets)
grep -q '^aid_inet:' /etc/group     || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Check for and create the droidspaces-gpu group
getent group droidspaces-gpu >/dev/null || groupadd -g 786 -r droidspaces-gpu
# Grant root the permission groups for Android hardware and network access
usermod -a -G aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu root || true
usermod -a -G aid_inet,aid_net_raw,input,video,tty,sudo,droidspaces-gpu ${USERNAME} || true

# Change the primary group of _apt to aid_inet so the apt package manager can reach the network under Android
grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

# Ensure every future user created via adduser is added to these Android hardware and network groups by default
if [ -f /etc/adduser.conf ]; then
    sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
    echo 'ADD_EXTRA_GROUPS=1' >> /etc/adduser.conf
    echo 'EXTRA_GROUPS="aid_inet aid_net_raw input video tty"' >> /etc/adduser.conf
fi

# --- 2. Systemd-specific fixes ---
# Mask the blocking services that easily cause errors or deadlocks on the Android kernel
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# Tune the Journald logging configuration (skip kernel audit, KMsg, and other log sources that are incompatible with or restricted on the Android kernel)
cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/lib/systemd/system"

if [ -f "$GUEST_SYSTEMD_PATH/dbus.service" ]; then
    ln -sf "$GUEST_SYSTEMD_PATH/dbus.service" "/etc/systemd/system/multi-user.target.wants/dbus.service"
fi

if [ "$ENABLE_yj_ARG" = "true" ]; then
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
            ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
        fi
    done
else
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        ln -sf /dev/null "/etc/systemd/system/$service"
    done
fi

# Disable power key handling in systemd-logind (prevents the container from intercepting or handling the host's physical power key events)
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

# Apply the udev override configuration
# 1. Trigger override: limit the scan scope of udevadm trigger (prevents a full scan of Android host hardware on coldplug, which can hang or conflict)
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

# 2. Overrides for read-only filesystem paths (ConditionPathIsReadWrite) so udev-related services do not fail on read-only paths
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# Restrict specific network services: only allow them to start when the container is configured in NAT mode
# This effectively prevents the container from breaking the phone's cellular data network when running in Host network mode
for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done
# Only restrict udev service startup when hardware access is enabled
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-hwaccess-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q 'enable_hw_access=1' /run/droidspaces/container.config"
EOF
    fi
done

# Fine-tune the maximum size limit of log rotation (logrotate) for the Android environment
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi



# Write the completion marker and timestamp for the applied fixes
echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN


COPY scripts/binfmt/qemu-binfmt-register.sh /usr/local/bin/
COPY scripts/binfmt/qemu-binfmt-register.service /etc/systemd/system/
RUN if [ "$ENABLE_binfmt_ARG" = "false" ]; then \
        rm -rf /usr/local/bin/qemu-binfmt-register.sh && \
        rm -rf /etc/systemd/system/qemu-binfmt-register.service ; \
    fi

RUN if [ "$ENABLE_binfmt_ARG" = "true" ]; then \
        chmod +x /usr/local/bin/qemu-binfmt-register.sh && \
        chmod 644 /etc/systemd/system/qemu-binfmt-register.service && \
        mkdir -p /etc/systemd/system/multi-user.target.wants && \
        ln -sf /etc/systemd/system/qemu-binfmt-register.service /etc/systemd/system/multi-user.target.wants/qemu-binfmt-register.service && \
        (apt-get purge -y qemu-* binfmt-support || true) && \
        apt-get autoremove -y && \
        apt-get autoclean && \
        rm -rf /var/lib/binfmts/* && \
        rm -rf /etc/binfmt.d/* && \
        rm -rf /usr/lib/binfmt.d/qemu-* && \
        apt-get update && \
        apt-get install -y qemu-user-static && \
        apt-get install -y binfmt-support && \
        dpkg --add-architecture amd64 && \
        sed -i '/^Types: deb$/a Architectures: arm64 armhf' /etc/apt/sources.list.d/ubuntu.sources && \
        echo "" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "Types: deb" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "URIs: http://archive.ubuntu.com/ubuntu/" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "Suites: noble noble-updates noble-security" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "Components: main universe restricted multiverse" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "Architectures: amd64" >> /etc/apt/sources.list.d/ubuntu.sources && \
        echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" >> /etc/apt/sources.list.d/ubuntu.sources && \
        apt-get update && \
        apt-get install -y libc6:amd64; \
    else \
        rm -f /usr/local/bin/qemu-binfmt-register.sh /etc/systemd/system/qemu-binfmt-register.service; \
    fi

# Ubuntu 24.04 ships a systemd older than 257, so the script detects that and skips.
RUN if [ "$ENABLE_systemd257_ARG" = "true" ]; then \
        bash /usr/local/sbin/systemd257; \
    else \
        echo "--> [skipped] systemd 257 old-kernel compatibility not enabled"; \
    fi

# Final APT cache cleanup to shrink the image layers as much as possible
# Remove one-off scripts used only at build time before packaging; the TUI and runtime scripts are kept.
RUN rm -f \
        /usr/local/sbin/configure-chrome \
        /usr/local/sbin/configure-desktop \
        /usr/local/sbin/install-desktop \
        /usr/local/sbin/install-anland-desktop \
        /usr/local/sbin/install-droidspaces-usb-manager \
        /usr/local/sbin/systemd257 \
        /usr/local/sbin/nosnap && \
    rm -rf /usr/local/lib/droidspaces/desktops && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: export the complete RootFS to scratch (a blank layer) so it can be extracted or packed into tarfs directly from outside
FROM scratch AS export

# Copy all customized RootFS content out of the customizer build stage as a whole
COPY --from=customizer / /
