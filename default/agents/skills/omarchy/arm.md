# ARM64 (aarch64)

Read this when the machine is an Apple Silicon Mac, a Raspberry Pi, or any
other aarch64 board. Everything in the other guides still applies; this one
covers only what differs.

## Which machine is this?

```bash
omarchy hw platform          # apple-silicon | raspberry-pi-5 | raspberry-pi | generic-aarch64 | x86_64
omarchy hw aarch64           # exit 0 on 64-bit ARM
omarchy hw apple silicon     # exit 0 on an M-series Mac, never on an Intel T2 Mac
omarchy hw raspberry pi      # exit 0 on any Pi; --5 restricts to the Pi 5
```

These read the flattened device tree (`/proc/device-tree`), so they work
before any package is installed and cost nothing to call from a hook or a
config file.

## Hyprland

Configuration, reload and validation are identical to x86: edit the Lua files
in `~/.config/hypr/`, then

```bash
hyprctl reload
hyprctl configerrors
```

On a Raspberry Pi, Omarchy loads `default/hypr/platform/raspberry-pi.lua`
after its own defaults. It turns animations off and pins blur, shadows and
rounding off, because the VideoCore VII GPU shares memory bandwidth with the
CPU and full-screen passes are what make the desktop feel slow there.

That file is a default, not a lock. `~/.config/hypr/looknfeel.lua` loads after
it and wins:

```lua
-- Bring the animations back on a Pi
hl.config({ animations = { enabled = true } })
```

Never edit `default/hypr/platform/raspberry-pi.lua` itself: it lives under
`$OMARCHY_PATH`, which an update overwrites.

## Packages

`omarchy pkg add` and `omarchy pkg aur add` work exactly as they do on x86,
against Arch Linux ARM's aarch64 repositories.

What is different is what those repositories carry. Some packages Omarchy
ships on x86_64 have no aarch64 build at all, and an install on this machine
will have skipped them. `install/arm/packages.unavailable` in `$OMARCHY_PATH`
is the list, with a reason per package. Before telling the user a stock
Omarchy command is broken, check whether the package behind it is on that
list.

An AUR package is compiled on the machine. On a Raspberry Pi that can mean
tens of minutes for one package, so say so before starting one rather than
leaving the user watching a silent terminal.

## Never add these repositories

Two of Omarchy's own pacman repositories are x86_64-only and will break
`pacman -Sy` outright if they are added to `/etc/pacman.conf` here:

- `[omarchy]` at `pkgs.omarchy.org`, which has no aarch64 tree
- `[multilib]`, which has no meaning on aarch64

If `/etc/pacman.conf` on this machine ever ends up with either, remove the
section. `install/arm/pacman.sh` is what normally keeps them out.

## The boot chain is not Omarchy's

On x86 Omarchy owns the bootloader: it installs limine, writes
`/etc/limine-entry-tool.d/` drop-ins and adds mkinitcpio hooks. None of that
runs on ARM, because a Raspberry Pi boots through its own firmware and
`linux-rpi`, and an Apple Silicon Mac boots through m1n1 and U-Boot.

So: do not run `omarchy refresh limine`, do not edit mkinitcpio hooks, and
treat any suggestion to change the boot configuration as out of scope for this
skill. Getting it wrong on either machine means a device that no longer boots
and cannot be recovered from inside the session.
