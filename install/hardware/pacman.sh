# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.
#
# The arch-mact2 repository below ships x86_64 kernels and firmware for Intel
# T2 Macs. There is no aarch64 tree, and lspci is not guaranteed to exist on a
# device-tree machine, so this leaf is a no-op on ARM.
source "$OMARCHY_INSTALL/arm/platform.sh"

if omarchy_arm_is_arm; then
  return 0
fi

if lspci -nn | grep "106b:180[12]" >/dev/null; then
  if ! grep -q '^\[arch-mact2\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF2'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF2
  fi
fi
