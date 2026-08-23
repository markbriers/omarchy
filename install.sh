#!/bin/bash

# Omarchy ARM64 installer.
#
# Upstream Omarchy is installed from an ISO that pacstraps a fixed package set
# onto a fresh x86_64 disk. That ISO does not exist for aarch64, and the
# packages it would pull are not built for it, so this fork installs onto an
# Arch Linux ARM system that is already running:
#
#   - an Apple Silicon Mac under Asahi's Arch Linux ARM port
#   - a Raspberry Pi 5 under Arch Linux ARM
#   - an aarch64 virtual machine under Arch Linux ARM
#
# Run it as your normal user from a checkout of this repository:
#
#   ./install.sh --dry-run     # print the whole plan, change nothing
#   ./install.sh
#
# See docs/arm64-port.md for what differs from upstream and why.

set -euo pipefail

CHECKOUT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

DRY_RUN=0
ASSUME_YES=0
SKIP_PACKAGES=0
SKIP_AUR=0
LINK_CHECKOUT=0
TARGET="/usr/share/omarchy"
FORCED_PLATFORM=""

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Installs Omarchy onto a running Arch Linux ARM (aarch64) system.

Options:
  --dry-run          Print every action without changing anything
  -y, --yes          Do not prompt for confirmation
  --skip-packages    Leave package installation to you entirely
  --no-aur           Install repository packages only; skip everything that
                     would have to be compiled from the AUR
  --target DIR       Where Omarchy is installed (default: $TARGET)
  --link             Point the target at this checkout with a symlink instead
                     of copying it, for working on the fork itself
  --profile NAME     Override hardware detection: apple-silicon,
                     raspberry-pi-5, raspberry-pi or generic-aarch64
  -h, --help         Show this message
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --no-aur) SKIP_AUR=1; shift ;;
    --link) LINK_CHECKOUT=1; shift ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --profile) FORCED_PLATFORM="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

step() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$1" "$RESET"; }
say() { printf '    %s\n' "$1"; }
ok() { printf '    %s%s%s\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '    %s%s%s\n' "$YELLOW" "$1" "$RESET"; }
die() { printf '\n%sError: %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

# Every mutating command goes through run(), which is what makes --dry-run
# honest: there is no second code path that could drift from the real one.
run() {
  if (( DRY_RUN )); then
    # ${*@Q} keeps a path with a space in it readable as the single argument
    # it actually is, instead of printing a command nobody could paste back.
    printf '    %s[dry-run]%s %s\n' "$YELLOW" "$RESET" "${*@Q}"
  else
    "$@"
  fi
}

confirm() {
  (( ASSUME_YES || DRY_RUN )) && return 0

  local reply
  read -r -p "    $1 [y/N] " reply
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

# Read a manifest under install/arm/, dropping comments and blank lines and
# keeping only the first field of each line.
manifest() {
  local file="$CHECKOUT/install/arm/$1"

  [[ -f $file ]] || return 0
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$file" | awk '{print $1}'
}

########################################################################
step "Preflight"
########################################################################

(( BASH_VERSINFO[0] >= 5 )) ||
  die "Omarchy needs bash 5 or newer; this shell is $BASH_VERSION."

(( EUID != 0 )) ||
  die "Run install.sh as your normal user, not as root. It calls sudo where it needs to."

export PATH="$CHECKOUT/bin:$PATH"

arch=$(uname -m)
if [[ $arch != "aarch64" ]]; then
  die "This fork installs on aarch64 only; this machine reports '$arch'.
       Upstream Omarchy (github.com/basecamp/omarchy) is what you want on x86_64."
fi
ok "Architecture: $arch"

# Overridable so the test suite can drive this against a fixture instead of
# the machine it runs on.
os_release="${OMARCHY_OS_RELEASE:-/etc/os-release}"
[[ -r $os_release ]] || die "$os_release is missing; cannot identify this distribution."
# shellcheck disable=SC1091
. "$os_release"
distro_id="${ID:-unknown}"
distro_like="${ID_LIKE:-}"

# Arch Linux ARM reports ID=archarm; a machine set up from Arch's own aarch64
# instructions may report ID=arch, and derivatives put arch in ID_LIKE.
case " $distro_id $distro_like " in
  *" arch "*|*" archarm "*)
    ok "Distribution: ${PRETTY_NAME:-$distro_id}"
    ;;
  *)
    die "This fork targets Arch Linux ARM; this machine reports '${PRETTY_NAME:-$distro_id}'.
       Porting Omarchy's 400-odd commands off pacman is a different project --
       see docs/arm64-port.md for why that road was not taken."
    ;;
esac

command -v pacman >/dev/null || die "pacman is not installed; this is not an Arch-based system."
command -v sudo >/dev/null || die "sudo is not installed."

# A pacstrapped Arch Linux ARM system can arrive without its own keyring, in
# which case every single package below would fail verification. Catch it here
# rather than 200 signature errors into the install.
source "$CHECKOUT/install/arm/keyring.sh"
if ! OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_keyring_repair; then
  die "pacman cannot verify Arch Linux ARM packages on this machine."
fi

if [[ -n $FORCED_PLATFORM ]]; then
  platform="$FORCED_PLATFORM"
  warn "Platform forced to '$platform' (detection said '$(omarchy-hw-platform)')"
else
  platform=$(omarchy-hw-platform)
fi

case "$platform" in
  apple-silicon)
    ok "Platform: Apple Silicon Mac (Asahi)"
    ;;
  raspberry-pi-5)
    ok "Platform: Raspberry Pi 5"
    ;;
  raspberry-pi)
    ok "Platform: Raspberry Pi (pre-5)"
    warn "Only the Pi 5 is tested. Older Pis have no Vulkan-capable GPU for Hyprland."
    ;;
  generic-aarch64)
    ok "Platform: generic aarch64 (virtual machine or unrecognised board)"
    ;;
  *)
    die "Unknown platform '$platform'."
    ;;
esac

(( DRY_RUN )) && warn "Dry run: nothing on this machine will be changed."

########################################################################
step "Package plan"
########################################################################

declare -a repo_pkgs=() aur_pkgs=() unavailable_pkgs=() unknown_pkgs=()

if (( SKIP_PACKAGES )); then
  warn "--skip-packages: package installation skipped entirely."
else
  declare -A replace=() excluded=() known_aur=() known_unavailable=()

  while read -r from to; do
    [[ -n ${from:-} && -n ${to:-} ]] && replace[$from]="$to"
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CHECKOUT/install/arm/packages.replace" 2>/dev/null || true)

  while read -r pkg; do excluded[$pkg]=1; done < <(manifest packages.exclude)
  while read -r pkg; do known_aur[$pkg]=1; done < <(manifest packages.aur)
  while read -r pkg; do known_unavailable[$pkg]=1; done < <(manifest packages.unavailable)

  # pacman -Si only knows what the last sync knew, so an unsynced machine would
  # report the entire package set as missing.
  sync_dir="${OMARCHY_PACMAN_SYNC_DIR:-/var/lib/pacman/sync}"
  if [[ ! -d $sync_dir ]] || [[ -z $(ls -A "$sync_dir" 2>/dev/null) ]]; then
    warn "The package databases have never been synced."
    run sudo pacman -Sy --noconfirm
  fi

  while read -r pkg; do
    [[ -n ${excluded[$pkg]:-} ]] && continue
    [[ -n ${replace[$pkg]:-} ]] && pkg="${replace[$pkg]}"

    if pacman -Si "$pkg" &>/dev/null; then
      repo_pkgs+=("$pkg")
    elif [[ -n ${known_aur[$pkg]:-} ]]; then
      aur_pkgs+=("$pkg")
    elif [[ -n ${known_unavailable[$pkg]:-} ]]; then
      unavailable_pkgs+=("$pkg")
    else
      unknown_pkgs+=("$pkg")
    fi
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CHECKOUT/install/omarchy-base.packages")

  say "From the configured repositories: ${#repo_pkgs[@]}"
  aur_note=""
  (( SKIP_AUR )) && aur_note=" (skipped: --no-aur)"
  say "Compiled from the AUR:            ${#aur_pkgs[@]}$aur_note"
  say "No aarch64 source at all:         ${#unavailable_pkgs[@]}"

  if (( ${#unknown_pkgs[@]} > 0 )); then
    warn "Not in the repositories and not in any manifest: ${unknown_pkgs[*]}"
    warn "Add them to install/arm/packages.{aur,unavailable,replace} so this stays honest."
  fi

  if (( ${#unavailable_pkgs[@]} > 0 )); then
    say ""
    say "These are skipped; the desktop comes up without them:"
    say "  ${unavailable_pkgs[*]}"
  fi

  say ""
  confirm "Install ${#repo_pkgs[@]} packages now?" || die "Cancelled."

  run sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
  ok "Repository packages installed."

  if (( ${#aur_pkgs[@]} > 0 )) && (( ! SKIP_AUR )); then
    if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
      say "No AUR helper found; building yay from source first."
      if confirm "Build and install yay?"; then
        run sudo pacman -S --needed --noconfirm base-devel git go
        # mktemp has to run for real even in a dry run, or the commands below
        # would be printed with an empty path and read as nonsense.
        build_dir=$(mktemp -d)
        run git clone --depth 1 https://aur.archlinux.org/yay.git "$build_dir/yay"
        run bash -c "cd '$build_dir/yay' && makepkg -si --noconfirm"
        rm -rf "$build_dir"
      else
        SKIP_AUR=1
      fi
    fi
  fi

  if (( ${#aur_pkgs[@]} > 0 )) && (( ! SKIP_AUR )); then
    warn "Compiling ${#aur_pkgs[@]} AUR packages. On a Raspberry Pi this takes a long time."
    if confirm "Continue?"; then
      # One at a time: a single package that will not build on aarch64 should
      # cost that package, not the whole run.
      for pkg in "${aur_pkgs[@]}"; do
        if ! run omarchy-pkg-aur-add "$pkg"; then
          warn "$pkg failed to build on aarch64; continuing without it."
          unavailable_pkgs+=("$pkg")
        fi
      done
    fi
  fi
fi

########################################################################
step "Deploy Omarchy to $TARGET"
########################################################################

if [[ $CHECKOUT == "$TARGET" ]]; then
  ok "Already running from $TARGET."
elif (( LINK_CHECKOUT )); then
  run sudo rm -rf "$TARGET"
  run sudo mkdir -p "$(dirname "$TARGET")"
  run sudo ln -sfn "$CHECKOUT" "$TARGET"
  ok "$TARGET now points at $CHECKOUT."
else
  if [[ -e $TARGET && ! -L $TARGET ]]; then
    run sudo rm -rf "$TARGET.omarchy-arm.bak"
    run sudo mv "$TARGET" "$TARGET.omarchy-arm.bak"
    say "Previous install moved to $TARGET.omarchy-arm.bak"
  fi
  run sudo mkdir -p "$TARGET"
  run sudo cp -a "$CHECKOUT/." "$TARGET/"
  run sudo rm -rf "$TARGET/.git"
  ok "Checkout copied to $TARGET."
fi

# /etc/omarchy.conf is what every Omarchy entry point reads to resolve
# $OMARCHY_PATH, so it is what makes a non-default target actually work.
run sudo mkdir -p /etc
if (( DRY_RUN )); then
  printf '    %s[dry-run]%s write /etc/omarchy.conf: export OMARCHY_PATH="%s"\n' "$YELLOW" "$RESET" "$TARGET"
else
  printf 'export OMARCHY_PATH="%s"\n' "$TARGET" | sudo tee /etc/omarchy.conf >/dev/null
fi

export OMARCHY_PATH="$TARGET"
export OMARCHY_INSTALL="$TARGET/install"

########################################################################
step "Install the files the omarchy-settings package would own"
########################################################################

say "There is no aarch64 build of omarchy-settings, so its file map is"
say "replayed straight from the checkout. See install/arm/settings.sh."

if (( DRY_RUN )); then
  OMARCHY_ARM_DRY_RUN=1 OMARCHY_PATH="$CHECKOUT" bash "$CHECKOUT/install/arm/settings.sh"
else
  sudo OMARCHY_PATH="$TARGET" bash "$TARGET/install/arm/settings.sh"
fi

########################################################################
step "System setup"
########################################################################

run sudo -E "$TARGET/bin/omarchy-apply-system" --install-user "$USER" --first-install

########################################################################
step "User setup"
########################################################################

run "$TARGET/bin/omarchy-provision-user" --first-install

########################################################################
step "Done"
########################################################################

if (( ${#unavailable_pkgs[@]} > 0 )); then
  warn "Installed without these, which have no aarch64 build:"
  warn "  ${unavailable_pkgs[*]}"
  say "docs/arm64-port.md records where each of them comes from."
fi

if (( DRY_RUN )); then
  ok "Dry run complete. Nothing was changed."
else
  ok "Omarchy is installed."
  say "Enable the display manager and reboot into the session:"
  say "  sudo systemctl enable sddm.service && sudo reboot"
fi
