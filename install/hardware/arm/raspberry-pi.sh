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

# Compressed swap is not a Pi-specific concern and is not configured here.
# Omarchy already ships the tuning as a vendor drop-in
# (/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf: the whole of RAM,
# zstd, priority above the disk swapfile), and install/arm/packages.extra
# installs the generator that reads it on every aarch64 machine.
#
# This leaf used to write /etc/systemd/zram-generator.conf with a 4 GB cap.
# That file is the admin's, and writing it took precedence over the drop-in and
# silently dropped the swap priority -- upstream migration 1785013000 exists
# precisely to move tuning out of it.

state_dir="${OMARCHY_STATE_DIR:-/var/lib/omarchy}"
mkdir -p "$state_dir"
omarchy-hw-platform >"$state_dir/platform"
