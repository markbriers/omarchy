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

  # Read the port from sshd's own configuration rather than assuming 22.
  # Archboot, for one, runs sshd on a random high port, and opening the wrong
  # one would look like it worked right up until the reboot.
  local port
  port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ { print $2; exit }' /etc/ssh/sshd_config 2>/dev/null)
  port="${port:-22}"

  if (( dry )); then
    echo "[dry-run] sudo ufw allow $port/tcp"
    return 0
  fi

  # Arch's ufw ships no OpenSSH application profile, so name the port.
  #
  # ufw exits 1 here with a bare "ERROR: problem running", and it does it
  # precisely in the state this function exists for: armed for the next boot
  # but not yet active. Adding a rule ends in a status check that runs
  # `iptables -L ufw-user-input`, and that chain only exists once ufw has
  # started, so the check fails and the exit code follows it. The rule is
  # written to /etc/ufw/user.rules either way. Measured on a Raspberry Pi 5,
  # ufw 0.36.2 with python 3.14; the same command returns 0 once ufw is up.
  #
  # install.sh runs under `set -e`, so taking that exit at face value aborted
  # the install after every package was in but before the user was
  # provisioned. Judge it on whether the rule landed instead.
  local out status=0
  out=$(sudo ufw allow "$port/tcp" 2>&1) || status=$?
  if sudo ufw show added 2>/dev/null | grep -qE "ufw allow $port/tcp$"; then
    return 0
  fi

  # Failing here must not stop the install: the firewall was armed by an
  # earlier step, so aborting now would leave the machine both unreachable
  # after the reboot and half configured.
  echo "$out" >&2
  echo "Could not open port $port, and this machine is set to deny everything" >&2
  echo "inbound from the next boot. Run 'sudo ufw allow $port/tcp' before" >&2
  echo "rebooting, or you will need a keyboard and a monitor to get back in." >&2
  return 0
}
