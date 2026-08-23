#!/bin/bash

# Make pacman trust the Arch Linux ARM signing key.
#
# A system installed with pacstrap from an Arch Linux ARM environment can end
# up with Arch's keyring but not Arch Linux ARM's: /usr/share/pacman/keyrings/
# holds archlinux.gpg alone, archlinuxarm-keyring is not installed, and the
# build system's key sits in the keyring at unknown trust. Every package then
# fails verification:
#
#   error: alsa-lib: signature from "Arch Linux ARM Build System
#          <builder@archlinuxarm.org>" is unknown trust
#
# and the fix cannot come from the repositories, because archlinuxarm-keyring
# is signed by the very key that is not trusted yet. That circle is broken the
# same way pacman-key --populate breaks it: by pinning the fingerprint of the
# master key out of band and locally signing it.
#
# The fingerprint below is published by Arch Linux ARM in
# core/archlinuxarm-keyring/archlinuxarm-trusted, in their PKGBUILDs
# repository. Verify it there, over HTTPS from a host that is not the package
# mirror, before changing it:
#
#   https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/archlinuxarm-keyring/archlinuxarm-trusted
#
# Honours OMARCHY_ARM_DRY_RUN=1.

ALARM_KEY_FINGERPRINT="68B3537F39A313B3E574D06777193F152BDBE6A6"

# Read the key's validity straight out of pacman's keyring.
#
# pacman-key has no machine-readable output -- it takes no --with-colons -- so
# this asks gpg against pacman's homedir instead. That directory is
# world-readable, so the check needs no privileges and a dry run stays free of
# sudo; gpg's "unsafe ownership" warning on stderr is expected and harmless.
omarchy_arm_key_validity() {
  local homedir="${OMARCHY_ARM_PACMAN_GNUPG:-/etc/pacman.d/gnupg}"

  command -v gpg >/dev/null 2>&1 || return 0
  [[ -d $homedir ]] || return 0

  gpg --homedir "$homedir" --batch --with-colons --list-keys "$ALARM_KEY_FINGERPRINT" 2>/dev/null |
    awk -F: '/^pub:/ { print $2; exit }'
}

omarchy_arm_key_trusted() {
  # Nothing to check, and nothing this script could fix, without gpg.
  command -v gpg >/dev/null 2>&1 || return 0

  local validity
  validity=$(omarchy_arm_key_validity)

  # f = fully valid, u = ultimately trusted. Anything else (- q n m, or no key
  # at all) means pacman will reject Arch Linux ARM packages.
  [[ $validity == "f" || $validity == "u" ]]
}

# Returns 0 when nothing needed doing or the repair succeeded, 1 when the
# caller should stop.
omarchy_arm_keyring_repair() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"

  if omarchy_arm_key_trusted; then
    return 0
  fi

  echo "The Arch Linux ARM signing key is not trusted by pacman."
  echo "Without it every package fails verification as 'unknown trust'."
  echo "Key validity right now: '$(omarchy_arm_key_validity)' (wanted f or u)."
  echo "Pinned fingerprint: $ALARM_KEY_FINGERPRINT"

  if (( dry )); then
    echo "[dry-run] sudo pacman-key --init"
    echo "[dry-run] sudo pacman-key --recv-keys $ALARM_KEY_FINGERPRINT  (only if absent)"
    echo "[dry-run] sudo pacman-key --lsign-key $ALARM_KEY_FINGERPRINT"
    echo "[dry-run] sudo pacman -S --needed --noconfirm archlinuxarm-keyring"
    echo "[dry-run] sudo pacman-key --populate archlinuxarm"
    return 0
  fi

  sudo pacman-key --init >/dev/null 2>&1 || true

  # Fetch by full fingerprint, so what arrives can only be this key.
  if [[ -z $(omarchy_arm_key_validity) ]]; then
    if ! sudo pacman-key --recv-keys "$ALARM_KEY_FINGERPRINT"; then
      echo "Error: could not fetch $ALARM_KEY_FINGERPRINT from a keyserver." >&2
      return 1
    fi
  fi

  if ! sudo pacman-key --lsign-key "$ALARM_KEY_FINGERPRINT"; then
    echo "Error: could not locally sign $ALARM_KEY_FINGERPRINT." >&2
    return 1
  fi

  # Now that the master key is trusted, the keyring package installs, which is
  # what keeps this fixed across future key rotations.
  sudo pacman -S --needed --noconfirm archlinuxarm-keyring || true
  sudo pacman-key --populate archlinuxarm >/dev/null 2>&1 || true

  if omarchy_arm_key_trusted; then
    echo "The Arch Linux ARM signing key is trusted now."
    return 0
  fi

  echo "Error: the key is still untrusted after the repair." >&2
  return 1
}
