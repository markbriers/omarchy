# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
#
# ARM64 fork: this restore is x86_64-only and must never run on aarch64.
# Omarchy's pacman.conf pins three things that do not exist for ARM:
#   - the [omarchy] repository at pkgs.omarchy.org/stable/$arch, which serves
#     x86_64 only (aarch64 is a 404),
#   - Omarchy's own Arch mirror, which likewise has no aarch64 tree,
#   - [multilib], which has no meaning on aarch64 at all.
# Copying it over an Arch Linux ARM machine's pacman.conf leaves that machine
# unable to resolve a single package, so the ARM path keeps the host's own
# configuration and only layers Omarchy's pacman behaviour onto it.
source "$OMARCHY_INSTALL/arm/platform.sh"

if omarchy_arm_is_arm; then
  source "$OMARCHY_INSTALL/arm/pacman.sh"
else
  cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
  cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist
fi

# omarchy-settings skips this override until cups-browsed is actually present
# to avoid pacman creating cups-browsed.conf.pacnew during ISO package install.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf && -d /etc/cups ]]; then
  cp -f "$OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf" /etc/cups/cups-browsed.conf
  rm -f /etc/cups/cups-browsed.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
