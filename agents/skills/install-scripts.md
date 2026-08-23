# Install Scripts

Read this before working under `install/` or on the system/user setup commands.

The ISO owns installation orchestration. This repo ships target-side setup
commands and reusable setup leaves:

- `bin/omarchy-apply-system` runs root-owned system setup during ISO finalization.
- `bin/omarchy-apply-hardware` runs idempotent hardware-specific setup and is called by `omarchy-apply-system`.
- `bin/omarchy-finalize-user` runs the per-user runtime finalization (skill symlinks, xdg-user-dirs, mime defaults, `install/user/all.sh`). Shipped user defaults are seeded by `/etc/skel` from `omarchy-settings`, not by this command. `bin/omarchy-reinstall-configs` is the explicit destructive resync of those defaults into an existing user's `$HOME`.
- leaf scripts under `install/` are sourced by `run_logged $OMARCHY_INSTALL/path/to/script.sh` and intentionally do not have shebangs.
- avoid `exit` in sourced setup scripts unless intentionally aborting setup.
- use `$OMARCHY_INSTALL` and `$OMARCHY_PATH` instead of hard-coded Omarchy paths.
- keep root-scoped hardware setup under `install/hardware/` and orchestrate it through `install/hardware/all.sh`.
- keep every per-user setup leaf under `install/user/` (including `install/user/hardware/` and `install/user/first-run/`) so it is clear what must run for each user.
- prefer helper commands for package and command checks where available.

## Architecture gating (ARM64 fork)

`install/hardware/all.sh` and `install/post-install/all.sh` source
`install/arm/platform.sh`, which adds two wrappers next to `run_logged`:

- `run_logged_x86` — run the leaf on x86_64 only. Use it for anything that
  installs a driver, firmware or kernel that has no aarch64 build: NVIDIA,
  the Intel leaves, the T2 Mac quirks, limine.
- `run_logged_arm` — the mirror image, for `install/hardware/arm/`.

A gated leaf is logged as skipped rather than dropped, so an install log still
accounts for every step upstream would have run.

Gate rather than delete. Every leaf upstream ships stays where upstream put
it, which is what keeps this fork rebasable on `main`. A leaf that is wrong on
ARM for a reason other than architecture — a package that exists but should
not be installed — belongs in `install/arm/packages.exclude` with its reason,
not in a special case inside `install.sh`.

Two things must never be touched from an ARM install leaf: mkinitcpio hooks
and bootloader configuration. A Raspberry Pi boots through its own firmware
and `linux-rpi`; an Apple Silicon Mac boots through m1n1 and U-Boot. Neither
is recoverable from inside the session once it is broken.

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in package-helper
contexts where direct package-manager behavior is the point of the script.
