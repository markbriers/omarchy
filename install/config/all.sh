# See install/hardware/all.sh for what run_logged_x86 is and why gating
# beats deleting.
source "$OMARCHY_INSTALL/arm/platform.sh"

run_logged "$OMARCHY_INSTALL/config/theme-system.sh"
run_logged "$OMARCHY_INSTALL/config/increase-lockout-limit.sh"
run_logged "$OMARCHY_INSTALL/config/lockscreen-pam.sh"
run_logged "$OMARCHY_INSTALL/config/fix-powerprofilesctl-shebang.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-command-path.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-keepalive.sh"
run_logged "$OMARCHY_INSTALL/config/docker.sh"
run_logged_x86 "$OMARCHY_INSTALL/config/snapper.sh"
run_logged "$OMARCHY_INSTALL/config/locate.sh"
run_logged "$OMARCHY_INSTALL/config/enable-services.sh"
run_logged "$OMARCHY_INSTALL/config/firewall.sh"
