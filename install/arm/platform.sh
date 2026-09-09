# Platform helpers shared by the install scripts of the ARM64 fork.
#
# Upstream Omarchy only ever runs on x86_64, so its install tree wires in
# leaves that cannot apply on aarch64 at all: NVIDIA and Intel drivers, the
# Intel Panther Lake kernel swap, the T2 Mac quirks, and the x86-only pacman
# repositories. Rather than delete those leaves -- which would make every
# rebase on upstream a conflict -- this fork gates them.
#
# Sourced by install/hardware/all.sh, install/post-install/all.sh and
# install.sh. It defines functions only, so sourcing it is free of side effects.

omarchy_arm_bin() {
  # The install tree runs before $OMARCHY_PATH/bin is guaranteed to be on PATH
  # in every context (the ISO exports it, a manual install.sh run may not).
  if command -v omarchy-hw-platform >/dev/null 2>&1; then
    echo "omarchy-hw-platform"
  else
    echo "${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-hw-platform"
  fi
}

omarchy_arm_platform() {
  "$(omarchy_arm_bin)"
}

omarchy_arm_is_arm() {
  local arch="${OMARCHY_ARCH:-$(uname -m)}"
  [[ $arch == "aarch64" || $arch == "arm64" ]]
}

# Log through the install log when there is one, and to stdout otherwise.
#
# omarchy-provision-user only sources install/helpers/logging.sh when an
# install log file is configured; without one it defines a minimal run_logged
# of its own and omarchy_log_line does not exist. A gate that assumed it was
# there took down the user setup phase it was meant to protect.
omarchy_arm_log() {
  if declare -F omarchy_log_line >/dev/null 2>&1; then
    omarchy_log_line "$1"
  else
    echo "$1"
  fi
}

# Run an install leaf only on x86_64. On aarch64 the leaf is logged as skipped
# rather than silently dropped, so a machine's install log still accounts for
# every step upstream would have run.
run_logged_x86() {
  local script="$1"

  if omarchy_arm_is_arm; then
    omarchy_arm_log "[$(date '+%Y-%m-%d %H:%M:%S')] Skipped (x86_64 only): $script"
    return 0
  fi

  run_logged "$script"
}

# Run an install leaf only on aarch64, for the mirror-image case.
run_logged_arm() {
  local script="$1"

  if ! omarchy_arm_is_arm; then
    omarchy_arm_log "[$(date '+%Y-%m-%d %H:%M:%S')] Skipped (aarch64 only): $script"
    return 0
  fi

  run_logged "$script"
}

# Add packages only if the configured repositories actually carry them.
#
# Arch Linux ARM tracks Arch's [core] and [extra] for aarch64 but not every
# package is built for it, and board-specific repositories (the Asahi ones in
# particular) may or may not be configured. A hard omarchy-pkg-add would abort
# the whole install over one optional driver, so leaves that install
# platform extras go through this instead and report what was skipped.
omarchy_arm_pkg_add_available() {
  local pkg
  local -a available=() unavailable=()

  for pkg in "$@"; do
    if pacman -Si "$pkg" &>/dev/null; then
      available+=("$pkg")
    else
      unavailable+=("$pkg")
    fi
  done

  if (( ${#unavailable[@]} > 0 )); then
    echo "Not in any configured repository, skipped: ${unavailable[*]}"
  fi

  if (( ${#available[@]} > 0 )); then
    omarchy-pkg-add "${available[@]}"
  fi
}

# Run an install leaf only when the command it is built around exists.
#
# Several leaves assume a package that is present on every x86_64 install but
# optional here, because it only ships in the AUR and this fork compiles those
# on request. A missing optional tool must cost that leaf, not the run.
run_logged_cmd() {
  local cmd="$1" script="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    run_logged "$script"
  else
    omarchy_arm_log "[$(date '+%Y-%m-%d %H:%M:%S')] Skipped (no $cmd): $script"
    return 0
  fi
}
