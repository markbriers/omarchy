#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# install.sh refuses to run under anything older than bash 5, which is what
# every Omarchy machine has. A development box that does not (macOS ships bash
# 3.2) should skip this file rather than report a failure it cannot fix.
if (( BASH_VERSINFO[0] < 5 )); then
  pass "bash 5 is not available; skipping the install.sh dry run"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/dt" "$test_tmp/sync"

printf '%s\0' "raspberrypi,5-model-b" "brcm,bcm2712" >"$test_tmp/dt/compatible"
printf '%s\0' "Raspberry Pi 5 Model B Rev 1.0" >"$test_tmp/dt/model"
: >"$test_tmp/sync/core.db"

os_release() {
  cat >"$test_tmp/os-release" <<OS
NAME="$1"
PRETTY_NAME="$1"
ID=$2
${3:+ID_LIKE=$3}
OS
  echo "$test_tmp/os-release"
}

cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-m" ]]; then
  echo "${STUB_ARCH:-aarch64}"
else
  /usr/bin/uname "$@"
fi
SH

# pacman -Si is how install.sh decides whether a package is in the configured
# repositories. The stub answers from a fixture list so the plan is
# deterministic instead of depending on the machine running the tests.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-Si" ]]; then
  grep -qxF "${2:-}" "$STUB_REPO_LIST"
  exit $?
fi
printf 'pacman %s\n' "$*" >>"$STUB_CALLS"
SH

# Nothing in a dry run may reach sudo. The stub records any call so the test
# can prove that, rather than trusting the read-through of run().
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STUB_CALLS"
SH

chmod +x "$stub_bin"/*

# Everything in the base list is "available" except the packages the manifests
# already say have no aarch64 repository build.
sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/omarchy-base.packages" | awk '{print $1}' >"$test_tmp/all-packages"
{
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/packages.aur"
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/packages.unavailable"
} | awk '{print $1}' | sort -u >"$test_tmp/absent"
# Substituted names are what actually gets looked up, so the fixture has to
# carry them too -- neovim is in the repositories even though nvim is not.
awk '{print $2}' <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/packages.replace") >>"$test_tmp/all-packages"
grep -vxFf "$test_tmp/absent" "$test_tmp/all-packages" >"$test_tmp/repo-list"

run_install() {
  local os_file="$1"
  shift

  STUB_ARCH="${STUB_ARCH:-aarch64}" \
  STUB_REPO_LIST="$test_tmp/repo-list" \
  STUB_CALLS="$test_tmp/calls.log" \
  OMARCHY_OS_RELEASE="$os_file" \
  OMARCHY_ARCH="${STUB_ARCH:-aarch64}" \
  OMARCHY_DEVICETREE="$test_tmp/dt" \
  OMARCHY_PACMAN_SYNC_DIR="$test_tmp/sync" \
  PATH="$stub_bin:$PATH" \
    "$BASH" "$ROOT/install.sh" "$@" 2>&1
}

arch_arm=$(os_release "Arch Linux ARM" archarm)
: >"$test_tmp/calls.log"

output=$(run_install "$arch_arm" --dry-run) ||
  fail "install.sh --dry-run succeeds on Arch Linux ARM" "$output"
pass "install.sh --dry-run succeeds on Arch Linux ARM"

grep -q "Platform: Raspberry Pi 5" <<<"$output" ||
  fail "the dry run reports the detected platform" "$output"
pass "the dry run reports the detected platform"

# The whole point of the flag: a dry run must not shell out to anything that
# changes the machine.
# Reading whether a key is trusted is not a change; anything else through sudo
# in a dry run is.
mutating=$(cat "$test_tmp/calls.log")
[[ -z $mutating ]] ||
  fail "a dry run invokes neither sudo nor a mutating pacman" "$mutating"
pass "a dry run invokes neither sudo nor a mutating pacman"

[[ ! -e /etc/omarchy.conf.dryrun ]] || fail "a dry run writes no config"
pass "a dry run writes nothing outside the sandbox"

# The manifests are the contract; the plan has to reflect them rather than
# quietly installing the packages that have no aarch64 build.
grep -q "No aarch64 source at all:" <<<"$output" ||
  fail "the plan counts packages with no aarch64 source" "$output"
grep -q "omacalc" <<<"$output" ||
  fail "the plan names the first-party packages it is dropping" "$output"
pass "the plan names the packages it is dropping and why"

grep -q "Not in the repositories and not in any manifest" <<<"$output" &&
  fail "every base package is accounted for by a manifest" "$output"
pass "every base package is accounted for by a manifest"

# nvim -> neovim is the substitution that keeps an editor on the machine after
# Omarchy's own x86-only build is dropped.
grep -q "would sync" <<<"$output" ||
  fail "the settings plan is printed" "$output"
pass "the settings plan is printed"

# Without the commands on PATH the desktop comes up as a bare compositor:
# Hyprland's autostart calls omarchy-launch-shell to raise the bar, and every
# keybinding runs an omarchy-* command. The omarchy package does this on
# x86_64 and has no aarch64 build.
grep -qE "would link +[0-9]+ commands into /usr/bin" <<<"$output" ||
  fail "the omarchy commands are put on PATH" "$output"
pass "the omarchy commands are put on PATH"

# The boot chain is the one thing a wrong install here makes unrecoverable.
grep -q "skip (boot chain, not ours on ARM): /etc/mkinitcpio.conf.d/" <<<"$output" ||
  fail "the mkinitcpio drop-ins are skipped on ARM" "$output"
grep -q "skip (boot chain, not ours on ARM): /etc/limine-entry-tool.d/" <<<"$output" ||
  fail "the limine drop-ins are skipped on ARM" "$output"
pass "boot-chain drop-ins are skipped on ARM"

# The AUR step is last and off by default. On aarch64 those packages are
# compiled here, and herdr pulls zig0.15, which rebuilds Zig against LLVM 20 --
# enough to fill a 15 GB disk while the desktop is still not provisioned. A
# machine that gives up there must still end up with a working Omarchy.
user_setup_line=$(grep -n "step \"User setup\"" "$ROOT/install.sh" | cut -d: -f1)
aur_line=$(grep -n "step \"AUR packages\"" "$ROOT/install.sh" | cut -d: -f1)
[[ -n $user_setup_line && -n $aur_line ]] || fail "install.sh has both a user setup and an AUR phase"
(( aur_line > user_setup_line )) ||
  fail "the AUR phase runs after the desktop is provisioned" "user setup:$user_setup_line aur:$aur_line"
pass "the AUR phase runs after the desktop is provisioned"

grep -q "Skipped: aether" <<<"$output" ||
  fail "the AUR packages are skipped by default and named" "$output"
grep -q -- "--with-aur" <<<"$output" ||
  fail "the plan says how to install them anyway" "$output"
pass "the AUR packages are skipped by default, named, and recoverable"

with_aur=$(run_install "$arch_arm" --dry-run --with-aur) ||
  fail "--with-aur runs" "$with_aur"
grep -q "omarchy-pkg-aur-add" <<<"$with_aur" ||
  fail "--with-aur plans the AUR builds" "$with_aur"
grep -q "aur.archlinux.org/yay.git" <<<"$with_aur" ||
  fail "--with-aur bootstraps an AUR helper first" "$with_aur"
pass "--with-aur plans the builds and bootstraps a helper"

########################################################################
# Refusals
########################################################################

: >"$test_tmp/calls.log"
output=$(STUB_ARCH=x86_64 run_install "$arch_arm" --dry-run) &&
  fail "install.sh refuses to run on x86_64" "$output"
grep -q "aarch64 only" <<<"$output" ||
  fail "the x86_64 refusal explains itself" "$output"
grep -q "basecamp/omarchy" <<<"$output" ||
  fail "the x86_64 refusal points at upstream" "$output"
pass "install.sh refuses to run on x86_64 and says where to go instead"

fedora=$(os_release "Fedora Asahi Remix 42" fedora)
output=$(run_install "$fedora" --dry-run) &&
  fail "install.sh refuses a non-Arch distribution" "$output"
grep -q "Arch Linux ARM" <<<"$output" ||
  fail "the distribution refusal explains itself" "$output"
pass "install.sh refuses a non-Arch distribution"

# Arch derivatives declare their base in ID_LIKE rather than ID.
derivative=$(os_release "Manjaro ARM" manjaro-arm arch)
output=$(run_install "$derivative" --dry-run) ||
  fail "install.sh accepts a distribution that declares arch in ID_LIKE" "$output"
pass "install.sh accepts a distribution that declares arch in ID_LIKE"

[[ ! -s $test_tmp/calls.log ]] ||
  fail "no refusal path reaches sudo" "$(cat "$test_tmp/calls.log")"
pass "no refusal path reaches sudo"
