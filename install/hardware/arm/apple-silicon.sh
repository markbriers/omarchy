# Apple Silicon (Asahi) quirks.
#
# This is not the Intel T2 Mac path: install/hardware/apple/ owns that, and its
# leaves are gated to x86_64 in install/hardware/all.sh. A T2 Mac is an Intel
# machine with an Apple coprocessor; an M-series Mac is aarch64 and shares none
# of those workarounds.

source "$OMARCHY_INSTALL/arm/platform.sh"

omarchy-hw-apple-silicon || return 0

# speakersafetyd enforces the thermal limits of the internal speakers. Asahi
# ships it because the hardware has no protection of its own and driving it
# without the daemon can physically damage the drivers, so this is the one
# package here whose absence is worth shouting about.
if pacman -Si speakersafetyd &>/dev/null; then
  omarchy-pkg-add speakersafetyd
  systemctl enable speakersafetyd.service 2>/dev/null || true
else
  echo "WARNING: speakersafetyd is not in any configured repository."
  echo "WARNING: the internal speakers are unprotected until it is installed."
  echo "WARNING: it ships in the Asahi repositories -- check that they are enabled."
fi

# The Asahi DCP driver hands the panel over at its native resolution; the
# display is HiDPI on every M-series machine, so seed a 2x default the user can
# override in ~/.config/hypr/monitors.lua.
state_dir="${OMARCHY_STATE_DIR:-/var/lib/omarchy}"
mkdir -p "$state_dir"
echo "apple-silicon" >"$state_dir/platform"
