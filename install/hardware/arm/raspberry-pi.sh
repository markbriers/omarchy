# Raspberry Pi quirks.
#
# The Pi 5 runs Hyprland on VideoCore VII through Mesa's V3D driver. It is a
# capable enough GPU for a tiling compositor but it has no headroom for the
# blur and shadow passes Omarchy leaves off by default anyway, and its memory
# bandwidth is shared with the CPU. The Hyprland side of that is handled at
# runtime by default/hypr/platform/raspberry-pi.lua; this leaf owns the system
# side.

source "$OMARCHY_INSTALL/arm/platform.sh"

omarchy-hw-raspberry-pi || return 0

# The Pi tops out at 8 GB and has no swap partition by default, so a compressed
# swap device is what keeps a browser and an editor coexisting.
omarchy_arm_pkg_add_available zram-generator

if [[ ! -f /etc/systemd/zram-generator.conf ]]; then
  mkdir -p /etc/systemd
  cat >/etc/systemd/zram-generator.conf <<'CONF'
[zram0]
zram-size = min(ram, 4096)
compression-algorithm = zstd
CONF
fi

state_dir="${OMARCHY_STATE_DIR:-/var/lib/omarchy}"
mkdir -p "$state_dir"
omarchy-hw-platform >"$state_dir/platform"
