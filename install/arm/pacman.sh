# Apply Omarchy's pacman behaviour to an Arch Linux ARM machine without
# replacing its repositories.
#
# The x86 path copies a whole pacman.conf. Here the host's [core]/[extra]
# definitions and its mirrorlist are the only ones that work, so this edits the
# cosmetic and behavioural options in place and leaves every Server line alone.

conf="${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}"

[[ -f $conf ]] || return 0

set_option() {
  local key="$1" line="$2"

  if grep -qE "^[[:space:]]*#?[[:space:]]*${key}\b" "$conf"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}\b.*|${line}|" "$conf"
  else
    sed -i "/^\[options\]/a ${line}" "$conf"
  fi
}

set_option "Color" "Color"
set_option "VerbosePkgLists" "VerbosePkgLists"
set_option "ParallelDownloads" "ParallelDownloads = 5"

# ILoveCandy is not a stock option, so it is only ever appended.
grep -q '^ILoveCandy' "$conf" || sed -i '/^\[options\]/a ILoveCandy' "$conf"

# [multilib] is x86-only. An Arch Linux ARM host will not have it, but a
# machine migrated from an x86 config might, and pacman fails hard on a
# repository whose mirrors 404.
if grep -q '^\[multilib\]' "$conf"; then
  echo "Removing [multilib] from $conf: it has no aarch64 packages."
  sed -i '/^\[multilib\]/,/^Include/d' "$conf"
fi

# Same for Omarchy's own repository, which is not built for aarch64.
if grep -q '^\[omarchy\]' "$conf"; then
  echo "Removing [omarchy] from $conf: pkgs.omarchy.org has no aarch64 tree."
  sed -i '/^\[omarchy\]/,/^Server/d' "$conf"
fi
