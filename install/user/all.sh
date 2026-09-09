# mise only ships in the AUR for aarch64, so it may legitimately be absent.
# See install/hardware/all.sh for the gating helpers.
source "$OMARCHY_INSTALL/arm/platform.sh"

run_logged "$OMARCHY_INSTALL/user/theme.sh"
run_logged "$OMARCHY_INSTALL/user/chromium.sh"
run_logged "$OMARCHY_INSTALL/user/git.sh"
run_logged "$OMARCHY_INSTALL/user/xcompose.sh"
run_logged_cmd mise "$OMARCHY_INSTALL/user/mise-work.sh"

run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-audio-mixer.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-mic.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/framework/fix-f13-amd-audio-input.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/dell/xps13-text-scaling.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/fix-nouveau-cursor.sh"

run_logged "$OMARCHY_INSTALL/user/default-keyring.sh"
run_logged_cmd mise "$OMARCHY_INSTALL/user/mise.sh"
