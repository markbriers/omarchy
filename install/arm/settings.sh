#!/bin/bash

# Install the files that the omarchy-settings package normally owns.
#
# On x86_64 every file below arrives through pacman: the ISO pacstraps
# omarchy-settings, which drops the /etc tree, seeds /etc/skel, and installs
# the session, unit, font and theme files under /usr and /usr/lib. There is no
# aarch64 build of that package, so on ARM this script places the same files
# straight from the checkout.
#
# The mapping follows docs/file-layout.md. Two groups are deliberately left
# out, because on ARM they would touch a boot chain this fork does not own:
#
#   - mkinitcpio.conf.d/ and the plymouth initramfs hook. A Raspberry Pi boots
#     through its own firmware and linux-rpi; an Apple Silicon Mac boots
#     through m1n1 and U-Boot. Rewriting initramfs hooks on either is how a
#     machine stops booting.
#   - limine-entry-tool.d/ and default/limine/. Limine is the x86 bootloader
#     Omarchy installs; neither target uses it.
#
# Run as root. Honours OMARCHY_ARM_DRY_RUN=1.

set -euo pipefail

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
dry="${OMARCHY_ARM_DRY_RUN:-0}"
skel="${OMARCHY_ARM_SKEL:-/etc/skel}"
root="${OMARCHY_ARM_SYSROOT:-}"

say() { printf '  %s\n' "$1"; }

# Every destination goes through here so a dry run can show the whole plan and
# a real run always leaves a backup of anything it overwrote.
place() {
  local mode="$1" src="$2" dest="$3"
  dest="$root$dest"

  if [[ ! -e $src ]]; then
    say "skip (not in checkout): ${src#$OMARCHY_PATH/}"
    return 0
  fi

  if (( dry )); then
    if [[ -e $dest ]]; then
      say "would replace $dest (backup: $dest.omarchy-arm.bak)"
    else
      say "would install  $dest"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest && ! -e $dest.omarchy-arm.bak ]]; then
    cp -a "$dest" "$dest.omarchy-arm.bak"
  fi
  install -Dm"$mode" "$src" "$dest"
}

# Directory equivalent of place(), for trees copied wholesale.
place_tree() {
  local src="$1" dest="$2"
  dest="$root$dest"

  if [[ ! -d $src ]]; then
    say "skip (not in checkout): ${src#$OMARCHY_PATH/}"
    return 0
  fi

  if (( dry )); then
    say "would sync     $dest/  ($(find "$src" -type f | wc -l | tr -d ' ') files)"
    return 0
  fi

  mkdir -p "$dest"
  cp -a "$src/." "$dest/"
}

echo "==> /etc drop-ins"
# The whole etc/ tree except the boot-chain directories called out above.
while IFS= read -r -d '' file; do
  rel="${file#"$OMARCHY_PATH"/etc/}"
  case "$rel" in
    mkinitcpio.conf.d/*|limine-entry-tool.d/*)
      say "skip (boot chain, not ours on ARM): /etc/$rel"
      continue
      ;;
  esac
  place 644 "$file" "/etc/$rel"
done < <(find "$OMARCHY_PATH/etc" -type f -print0 | sort -z)

if (( ! dry )); then
  # A malformed drop-in locks the machine out of sudo, so refuse to leave one
  # behind even if it means removing what we just wrote.
  if command -v visudo >/dev/null 2>&1; then
    for f in "$root/etc/sudoers.d"/omarchy-*; do
      [[ -e $f ]] || continue
      chmod 440 "$f"
      if ! visudo -cf "$f" >/dev/null; then
        echo "Error: $f is not valid sudoers syntax; removing it." >&2
        rm -f "$f"
      fi
    done
  fi
fi

echo "==> session, units and shared data"
place 644 "$OMARCHY_PATH/default/wayland-sessions/omarchy.desktop" /usr/local/share/wayland-sessions/omarchy.desktop
place 644 "$OMARCHY_PATH/default/uwsm/env.d/10-omarchy" /usr/share/uwsm/env.d/10-omarchy
place 644 "$OMARCHY_PATH/default/applications/mimeapps.list" /usr/share/applications/mimeapps.list
place 644 "$OMARCHY_PATH/default/fontconfig/conf.avail/50-omarchy.conf" /usr/share/fontconfig/conf.avail/50-omarchy.conf
place_tree "$OMARCHY_PATH/default/environment.d" /usr/lib/environment.d
place_tree "$OMARCHY_PATH/default/systemd/user" /usr/lib/systemd/user
place_tree "$OMARCHY_PATH/default/systemd/system-sleep" /usr/lib/systemd/system-sleep
place_tree "$OMARCHY_PATH/default/systemd/zram-generator.conf.d" /usr/lib/systemd/zram-generator.conf.d
place_tree "$OMARCHY_PATH/default/xdg-terminal-exec" /usr/share/xdg-terminal-exec
place_tree "$OMARCHY_PATH/default/fonts/omarchy" /usr/share/fonts/omarchy
place_tree "$OMARCHY_PATH/default/sddm/omarchy" /usr/share/sddm/themes/omarchy
place 644 "$OMARCHY_PATH/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua
place_tree "$OMARCHY_PATH/default/plymouth" /usr/share/plymouth/themes/omarchy
place 644 "$OMARCHY_PATH/icon.png" /usr/share/pixmaps/omarchy.png
place 644 "$OMARCHY_PATH/icon.png" /usr/share/icons/hicolor/256x256/apps/omarchy.png

if [[ -d $OMARCHY_PATH/applications/icons ]]; then
  for icon in "$OMARCHY_PATH"/applications/icons/*; do
    [[ -f $icon ]] || continue
    place 644 "$icon" "/usr/share/icons/hicolor/scalable/apps/$(basename "$icon")"
  done
fi

if (( ! dry )); then
  ln -sf /usr/share/fontconfig/conf.avail/50-omarchy.conf "$root/etc/fonts/conf.d/50-omarchy.conf" 2>/dev/null || true
fi

echo "==> /etc/skel (seeds every new user)"
place_tree "$OMARCHY_PATH/config" "$skel/.config"
place_tree "$OMARCHY_PATH/applications" "$skel/.local/share/applications"
place_tree "$OMARCHY_PATH/default/nautilus-python/extensions" "$skel/.local/share/nautilus-python/extensions"
place_tree "$OMARCHY_PATH/default/hypr/toggles" "$skel/.local/state/omarchy/toggles/hypr"
place 644 "$OMARCHY_PATH/default/tensaku/state.toml" "$skel/.local/state/tensaku/state.toml"
place 644 "$OMARCHY_PATH/default/bashrc" "$skel/.bashrc"
place 644 "$OMARCHY_PATH/logo.txt" "$skel/.config/omarchy/branding/about.txt"
place 644 "$OMARCHY_PATH/logo.txt" "$skel/.config/omarchy/branding/screensaver.txt"

# The icons directory is a build input for the desktop files, not something a
# user's ~/.local/share/applications should carry.
if (( ! dry )); then
  rm -rf "$root$skel/.local/share/applications/icons"
fi

# Migration markers: a fresh install has not missed anything, so record every
# shipped migration as already applied rather than replaying years of them.
if [[ -d $OMARCHY_PATH/migrations ]]; then
  if (( dry )); then
    say "would mark $(find "$OMARCHY_PATH/migrations" -name '*.sh' | wc -l | tr -d ' ') migrations as already applied in $skel"
  else
    mkdir -p "$root$skel/.local/state/omarchy/migrations"
    for migration in "$OMARCHY_PATH"/migrations/*.sh; do
      [[ -e $migration ]] || continue
      touch "$root$skel/.local/state/omarchy/migrations/$(basename "$migration" .sh)"
    done
  fi
fi

echo "==> settings installed"
