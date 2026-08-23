# The ARM64 port

This fork installs Omarchy on 64-bit ARM: an Apple Silicon Mac, a Raspberry Pi
5, or an aarch64 virtual machine. Upstream Omarchy is x86_64 only, and not by
accident: its installation model, its package repositories and a third of its
hardware setup tree are all built around that assumption.

This document records what those assumptions are, which of them were adapted,
which were left alone, and what still does not work.

## Why Arch Linux ARM, and not Fedora Asahi

Fedora Asahi Remix is the best-supported distribution on Apple Silicon, so it
is the obvious target for a Mac. It was not chosen, for one reason: Omarchy is
not a desktop environment that happens to run on Arch. Its 433 commands in
`bin/` call `pacman` and `yay` directly, its update pipeline is built on
pacman hooks and AUR rebuilds, and its own software is distributed as pacman
packages. Moving that to `dnf` is not a port, it is a rewrite of the layer
that makes Omarchy Omarchy.

Keeping pacman means one distribution across both targets:

| Machine | Distribution |
|---|---|
| Apple Silicon Mac | Arch Linux ARM (the Asahi community port) |
| Raspberry Pi 5 | Arch Linux ARM |
| aarch64 VM | Arch Linux ARM |

The cost is that the Mac runs a community port rather than the officially
supported Fedora Asahi Remix. The benefit is that everything above the package
layer -- every command, every hook, the whole update pipeline -- keeps working
without being touched.

## What the repository looks like from a porting point of view

Two layers, and only one of them needed work.

**Architecture-agnostic (untouched).** The Hyprland Lua configuration under
`config/hypr/` and `default/hypr/`, the Quickshell desktop under `shell/`, the
themes, the agent skills under `default/agents/skills/`, and the great
majority of `bin/`. None of it contains an architecture assumption. Note that
upstream has moved on from what older Omarchy documentation describes: there
is no `hyprland.conf` any more (the configuration is Lua), no Waybar (the bar
is Quickshell) and no Rofi (the launcher is Omarchy's own menu).

**System and packaging (adapted).** 87 files mention `pacman`, `yay` or
`makepkg`, but almost all of them go through the same five helpers --
`omarchy-pkg-add`, `-drop`, `-present`, `-missing`, `-aur-add` -- which stayed
exactly as they are, because pacman stayed. What actually needed adapting was
narrower than the file count suggests:

- the absence of an installer at all
- the x86-only leaves under `install/hardware/`
- `/etc/pacman.conf`, which upstream replaces wholesale
- the packages that have no aarch64 build

## There is no `install.sh` upstream

Upstream Omarchy 4 is installed from an ISO. `archinstall` partitions the
disk, pacstraps `install/omarchy-base.packages`, and the target-side setup
commands (`omarchy-apply-system`, `omarchy-apply-hardware`,
`omarchy-provision-user`) run in the chroot. There is no script that installs
Omarchy onto a system that is already running.

That ISO cannot be rebuilt for aarch64 without also solving everything below,
so this fork adds `install.sh` at the repository root instead. It installs
onto a running Arch Linux ARM system, and it drives the same target-side
commands the ISO drives, in the same order:

```
preflight            architecture, distribution, platform
package plan         resolve the base list against the live repositories
deploy               copy the checkout to /usr/share/omarchy, write /etc/omarchy.conf
settings             install what the omarchy-settings package would own
system setup         omarchy-apply-system --install-user $USER --first-install
user setup           omarchy-provision-user --first-install
```

`--dry-run` prints every one of those steps and changes nothing. Every
mutating command in the script goes through a single `run()` wrapper, so there
is no second code path for the dry run to drift away from.

## The packaging problem, measured

Omarchy's own packages come from `[omarchy]` at `pkgs.omarchy.org/stable/$arch`,
and its Arch mirror is pinned to `stable-mirror.omarchy.org`. Neither has an
aarch64 tree:

```
https://pkgs.omarchy.org/stable/x86_64/omarchy.db        200
https://pkgs.omarchy.org/stable/aarch64/omarchy.db       404
https://stable-mirror.omarchy.org/core/os/aarch64/core.db 404
http://mirror.archlinuxarm.org/aarch64/core/core.db      302
```

So `install/post-install/pacman.sh`, which on x86 copies Omarchy's
`pacman.conf` and mirrorlist over the machine's own, is the single most
destructive step in the tree for an ARM install: it would leave the machine
unable to resolve a single package. On aarch64 it is replaced by
`install/arm/pacman.sh`, which edits pacman's cosmetic and behavioural options
in place, never writes a `Server` line, and strips `[multilib]` and
`[omarchy]` if they are present.

Resolving `install/omarchy-base.packages` (148 packages) against the live
Arch Linux ARM aarch64 databases gives:

| | Count |
|---|---|
| In `core`/`extra`/`alarm` for aarch64 | 123 |
| Available in the AUR, compiled on the machine | 11 |
| No aarch64 source at all | 13 |
| Bootstrapped from source by `install.sh` | 1 (`yay`) |
| **Total** | **148** |

Two of the 123 arrive under a different name: `nvim` becomes `neovim` and
`ttf-jetbrains-mono-nerd-basic` becomes `ttf-jetbrains-mono-nerd`, replacing
Omarchy's own builds with their upstream equivalents.

Those four categories are manifests under `install/arm/`, not logic inside
`install.sh`: `packages.aur`, `packages.replace`, `packages.unavailable`,
`packages.exclude`. A base package that appears in none of them is reported as
unaccounted for rather than silently dropped, and the test suite fails if the
manifests and the base list drift apart.

### The AUR is not a free substitute on ARM

On x86_64 an AUR package with a `-bin` suffix is a download. On aarch64 there
are no prebuilt binaries, so every one of the 11 is compiled on the machine,
and the dependency chain is not shallow: `herdr` pulls `zig0.15`, which
rebuilds Zig against LLVM 20. On the first real install that filled a 15 GB
disk and was still compiling long after the desktop itself was ready.

So the AUR step is last, after the desktop is provisioned, and off unless
`--with-aur` is passed. A machine that runs out of space or patience there
still ends up with a working Omarchy, and the cost is an optional app. On a
Raspberry Pi booting from an SD card, that default is not a nicety.

### What is lost

The 13 packages with no aarch64 build, and why:

- `omacalc`, `omacut`, `omawrite`, `omarchy-nvim`, `ttfx`, `tobi-try`,
  `hyprland-preview-share-picker` -- Omarchy's own software, published only
  through the x86_64 repository above. Building them for aarch64 means
  building them from their upstream sources, which is the largest remaining
  piece of work on this fork.
- `obs-studio`, `pinta`, `dotnet-runtime` -- Arch builds them for x86_64 only.
- `obsidian` -- proprietary Electron application with no aarch64 Arch package.
- `asdcontrol`, `qemu-user-static-binfmt` -- x86-only packaging.

None of them is needed for the desktop to come up. Hyprland, Quickshell, SDDM,
uwsm, foot, Chromium and the whole theming stack are all in Arch Linux ARM's
aarch64 `extra`.

## Hardware setup

`install/hardware/all.sh` wires 39 leaves. On ARM, 29 of them install a
driver, firmware or kernel that has no aarch64 build; 7 are hardware-neutral
and run everywhere; 3 are new and ARM-only. They are gated with
`run_logged_x86` rather than deleted, which keeps this fork rebasable on
upstream and keeps a machine's install log accounting for every step upstream
would have run.

Three ARM leaves were added, each self-gating on the detected platform the way
upstream's leaves self-gate on PCI IDs and DMI strings:

- `install/hardware/arm/vulkan.sh` -- `vulkan-asahi` on a Mac,
  `vulkan-broadcom` on a Pi, `vulkan-virtio` plus the software rasterizer in a
  VM. The x86 leaf matches GPU vendors on the PCI bus, and neither the Apple
  Silicon GPU nor the Pi's VideoCore VII is a PCI device.
- `install/hardware/arm/apple-silicon.sh` -- `speakersafetyd`, which enforces
  the thermal limits of the internal speakers. Asahi ships it because the
  hardware has no protection of its own.
- `install/hardware/arm/raspberry-pi.sh` -- zram, because the Pi tops out at
  8 GB with no swap by default.

One leaf outside `install/hardware/` needed the same treatment:
`install/config/snapper.sh`. Snapper is wired to limine on x86 -- the same
step enables `limine-snapper-sync.service` -- and snapper is not in the ARM
package set at all. Left ungated it would abort the first ARM install
outright, because the leaf runs under `set -e` and `snapper create-config`
fails when the command does not exist.

Note that `install/hardware/apple/` is **not** about Apple Silicon. Those are
T2 quirks for Intel Macs, which are x86_64 machines, and they are gated off on
ARM.

### Platform detection

Four commands, reading the flattened device tree at `/proc/device-tree`:

```bash
omarchy hw platform            # apple-silicon | raspberry-pi-5 | raspberry-pi | generic-aarch64 | x86_64
omarchy hw aarch64
omarchy hw apple silicon
omarchy hw raspberry pi [--5]
```

They cost nothing to call, work before any package is installed, and are what
the install leaves, the Hyprland profile and the agent skill all branch on.

## The boot chain is deliberately untouched

On x86 Omarchy owns the bootloader: limine, `/etc/limine-entry-tool.d/`
drop-ins, mkinitcpio hooks, snapper integration. A Raspberry Pi boots through
its own firmware and `linux-rpi`; an Apple Silicon Mac boots through m1n1 and
U-Boot. This fork installs none of it, and `install/arm/settings.sh` skips
those drop-ins explicitly and says so as it goes.

This is the one place where being conservative is not a style preference: a
wrong initramfs hook on either machine produces a device that no longer boots
and cannot be recovered from inside the session.

## The agent layer

Omarchy ships an agent skill at `default/agents/skills/omarchy/` that lets an
AI CLI edit the desktop configuration in natural language. It needed no
porting: it already targets `~/.config/`, and its hot-reload contract
(`hyprctl reload` followed by `hyprctl configerrors`) is architecture-neutral.

What was added is `arm.md`, one more topic guide covering what an agent
working on an ARM machine needs to know that it cannot infer: how to identify
the board, that some stock packages are absent by design and where the list
is, that `[omarchy]` and `[multilib]` must never be added to `pacman.conf`,
and that the boot chain is out of scope.

## Raspberry Pi tuning

`default/hypr/platform/raspberry-pi.lua` loads after Omarchy's own
look'n'feel and before the user's. It turns animations off and pins blur,
shadows and rounding off. The Pi 5's VideoCore VII renders a tiling desktop
perfectly well but shares memory bandwidth with the CPU, and full-screen
per-frame passes are what make it feel like it is catching up.

It is a default, not a lock: `~/.config/hypr/looknfeel.lua` loads afterwards
and wins.

## Testing

```bash
./install.sh --dry-run            # on the target machine
./install.sh                      # the real thing
./install.sh --with-aur --skip-packages   # add the AUR extras later
bash test/shell                   # the full suite, on any Linux box
```

Three test files cover this fork specifically:

- `test/shell.d/arm64-platform-test.sh` -- device-tree detection against
  fixtures for a Pi 5, an older Pi, two generations of Mac, and a VM;
  including that an Intel T2 Mac never matches the Apple Silicon predicate.
- `test/shell.d/arm64-install-test.sh` -- drives `install.sh --dry-run` in a
  stubbed sandbox and asserts that it reaches neither `sudo` nor a mutating
  `pacman`, that it refuses x86_64 and non-Arch distributions, and that the
  boot-chain drop-ins are skipped.
- `test/shell.d/arm64-gating-test.sh` -- asserts every x86-only hardware leaf
  is still gated, the pacman.conf restore cannot run on ARM, and the manifests
  have not drifted from the base package list.

## What the first real install found

Everything above the packaging layer was covered by tests before any of it
ran. The tests found nothing. The machine found seven things, and every one of
them was fatal to the install or to the session:

| | |
|---|---|
| The Arch Linux ARM keyring is not installed by a pacstrap from archboot | 200-odd `unknown trust` errors, no package installable, and the fix is signed by the untrusted key |
| `herdr` pulls `zig0.15`, which rebuilds Zig against LLVM 20 | filled a 15 GB disk with the desktop still not deployed |
| `ufw-docker` is AUR-only | `omarchy-apply-system` aborted on a Docker convenience rule |
| `mise` is AUR-only | `omarchy-provision-user` aborted with `mise: command not found` |
| The `omarchy` package puts `bin/*` on PATH, and has no aarch64 build | session came up as a bare compositor: no bar, no menu, no keybinding |
| `/etc/skel` only fires at user creation | the user ran on Hyprland's autogenerated config, missing 136 shipped files, and nothing logged an error |
| `misc.vfr` is not a Hyprland 0.56.1 config key | the Pi profile applied but left a config error behind |

The last two are the instructive ones. Both produced a broken desktop with a
completely clean log, because nothing had failed: a compositor with no
commands on its PATH starts perfectly, and a user with no shipped config gets
Hyprland's own default and runs it happily.

The ordering trap is worth stating on its own. The ISO seeds `/etc/skel` and
*then* creates the user. Installing onto a running machine inverts that, and
`/etc/skel` reaches nobody. Anything that relies on user creation to deliver a
file has the same problem here.

## Validated on an aarch64 machine

An Arch Linux ARM aarch64 VM, installed from archboot, driven end to end:

- `./install.sh --dry-run` and then the real run, to completion
- package resolution against the live Arch Linux ARM databases matching what
  the manifests predicted exactly: 123 from the repositories, 11 AUR-only, 13
  with no aarch64 build, nothing unaccounted for
- Hyprland 0.56.1 running under Wayland, `hyprctl configerrors` clean, 228
  keybindings loaded, the Omarchy menu bound
- the Quickshell bar running: idle service, polkit agent, idle monitor
- a rule added to `~/.config/hypr/bindings.lua`, applied with `hyprctl
  reload`, visible in `hyprctl binds` a second later and gone again when
  reverted -- the loop the agent skill prescribes, on ARM
- the Raspberry Pi profile proven by forcing the platform predicate: animations
  off under `raspberry-pi-5`, on again when the predicate is restored, no
  config errors either way

## What is not done

- **Omarchy's first-party packages have no aarch64 build.** Seven packages,
  listed above. This is the largest remaining piece of work and the only one
  that costs the desktop anything visible.
- **Neither target machine has run this yet.** A VM proves the software; it
  does not prove Asahi's GPU stack on a Mac, or V3D and the thermal behaviour
  on a Pi 5. The platform-specific leaves under `install/hardware/arm/` have
  never executed on the hardware they are written for.
- **The AUR path is untested end to end.** It is off by default and the one
  run that attempted it ran out of disk.
- **The ISO is not ported.** Installation is onto a running system only. An
  aarch64 ISO would need an ARM bootloader story per board, which is a
  different project.
- **`omarchy update` is untested on ARM.** It runs AUR rebuilds and pacman
  hooks; the pacman configuration it expects is not the one an ARM machine
  has.
