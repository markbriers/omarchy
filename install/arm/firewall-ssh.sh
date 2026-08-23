#!/bin/bash

# Keep SSH reachable on a machine being installed over SSH.
#
# Omarchy's firewall leaf sets ufw to deny everything inbound and arms it for
# the next boot. On a desktop that is exactly right. On a Raspberry Pi in a
# cupboard, or a VM with no console attached, it means the machine comes back
# from its first reboot with no way in, and the only fix is physical.
#
# The rule here is deliberately narrow: the port is opened only when this
# installer is itself running over SSH. Someone installing from a local
# console gets upstream's policy untouched.
#
# Honours OMARCHY_ARM_DRY_RUN=1.

omarchy_arm_keep_ssh_reachable() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"
  local ufw_conf="${OMARCHY_ARM_UFW_CONF:-/etc/ufw/ufw.conf}"

  # SSH_CONNECTION alone is not enough: sudo resets the environment, so an
  # installer invoked through sudo never sees it. An enabled sshd is the
  # durable signal, and enabling it is a deliberate act -- upstream leaves it
  # off and offers `omarchy setup security sshd` instead.
  if [[ -z ${SSH_CONNECTION:-} ]] && ! systemctl is-enabled sshd >/dev/null 2>&1; then
    return 0
  fi

  command -v ufw >/dev/null 2>&1 || return 0

  # Upstream only arms the firewall for the next boot; if it did not, there is
  # nothing that will lock anyone out.
  grep -q '^ENABLED=yes' "$ufw_conf" 2>/dev/null || return 0

  echo "sshd is enabled and the firewall is armed to deny everything inbound"
  echo "from the next boot. Opening SSH so this machine stays reachable."

  if (( dry )); then
    echo "[dry-run] sudo ufw allow OpenSSH"
    return 0
  fi

  sudo ufw allow OpenSSH || sudo ufw allow 22/tcp
}
