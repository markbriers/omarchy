#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# aarch64 is the whole premise of these commands, and the machine running the
# tests is not one.
cat >"$stub_bin/uname" <<'STUB'
#!/bin/bash
[[ $1 == -m ]] && echo aarch64 || exit 1
STUB

# PACMAN_REPO lists what "pacman -Si" resolves, PACMAN_LOCAL what "pacman -Q"
# and "pacman -Qq" report. Anything else is a miss, which is what an aarch64
# machine says about the [omarchy] repository's packages.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$@" >>"$PACMAN_LOG"
case $1 in
-Si) grep -qx "$2" <<<"${PACMAN_REPO:-}" ;;
-Q) grep -qx "$2" <<<"${PACMAN_LOCAL:-}" ;;
-Qq) printf '%s\n' ${PACMAN_LOCAL:-} ;;
*) exit 0 ;;
esac
STUB

# The AUR is a network call. A package with a measured answer in
# packages.unavailable must never reach it, so make the attempt visible.
cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
echo "$*" >>"$CURL_LOG"
exit 22
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/omarchy-pkg-aur-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$AUR_LOG"
STUB

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export PACMAN_LOG="$test_tmp/pacman.log" CURL_LOG="$test_tmp/curl.log" AUR_LOG="$test_tmp/aur.log"

reset_logs() {
  : >"$PACMAN_LOG"
  : >"$CURL_LOG"
  : >"$AUR_LOG"
}

reset_logs

########################################################################
# omarchy-pkg-arm-name
########################################################################

[[ $(omarchy-pkg-arm-name ripgrep) == ripgrep ]] ||
  fail "a package with no substitution comes back unchanged"
pass "a package with no substitution comes back unchanged"

# packages.replace is the installer's data. The runtime path has to read the
# same file, or a name that installs during setup fails from the menu.
[[ $(omarchy-pkg-arm-name nvim) == neovim ]] ||
  fail "packages.replace is applied at runtime" "$(omarchy-pkg-arm-name nvim)"
pass "packages.replace is applied at runtime"

# Arch Linux ARM names the headers after the installed kernel. Guessing one
# name would break xpadneo-dkms on whichever of the two targets guessed wrong.
[[ $(PACMAN_LOCAL='linux-aarch64' omarchy-pkg-arm-name linux-headers) == linux-aarch64-headers ]] ||
  fail "linux-headers resolves to the generic ARM kernel's headers"
[[ $(PACMAN_LOCAL='linux-rpi' omarchy-pkg-arm-name linux-headers) == linux-rpi-headers ]] ||
  fail "linux-headers resolves to the Raspberry Pi kernel's headers"
pass "linux-headers follows the kernel that is actually installed"

########################################################################
# omarchy-pkg-arm-source
########################################################################

[[ $(PACMAN_REPO='chromium' omarchy-pkg-arm-source chromium) == repo ]] ||
  fail "a package the repositories carry is answered from the repositories"
[[ ! -s $CURL_LOG ]] || fail "a repository package does not reach for the network"
pass "a package the repositories carry is answered from the repositories"

verdict=$(PACMAN_REPO='' omarchy-pkg-arm-source spotify)
[[ $verdict == none* ]] || fail "a measured x86-only package is refused" "$verdict"
[[ $verdict == *"x86_64 only"* ]] || fail "the refusal carries the reason from packages.unavailable" "$verdict"
[[ ! -s $CURL_LOG ]] || fail "packages.unavailable answers offline" "$(cat "$CURL_LOG")"
pass "a measured x86-only package is refused offline, with its reason"

# An unreachable AUR is not evidence. Inventing "none" from a timeout would
# turn a flaky network into a permanent verdict.
[[ $(PACMAN_REPO='' omarchy-pkg-arm-source some-unlisted-package) == aur ]] ||
  fail "an unreachable AUR does not become an architecture verdict"
pass "an unreachable AUR does not become an architecture verdict"

########################################################################
# omarchy-pkg-add
########################################################################

reset_logs

if PACMAN_REPO='' omarchy-pkg-add spotify >"$test_tmp/out" 2>&1; then
  fail "installing an x86-only package fails"
fi
grep -q "no aarch64 build" "$test_tmp/out" || fail "the failure says what is wrong" "$(cat "$test_tmp/out")"
grep -q "x86_64 only" "$test_tmp/out" || fail "the failure carries the reason" "$(cat "$test_tmp/out")"
grep -q -- '-S ' "$PACMAN_LOG" && fail "pacman is never asked for a package that cannot exist" "$(cat "$PACMAN_LOG")"
pass "an x86-only package fails with its reason, before pacman is involved"

reset_logs

# Not a tty, so the AUR build has to be offered as a command rather than run.
if PACMAN_REPO='' omarchy-pkg-add some-unlisted-package </dev/null >"$test_tmp/out" 2>&1; then
  fail "a scripted caller does not silently start an AUR build"
fi
grep -q "omarchy pkg aur add" "$test_tmp/out" ||
  fail "a scripted caller is told how to build it" "$(cat "$test_tmp/out")"
[[ ! -s $AUR_LOG ]] || fail "no AUR build starts without someone saying yes" "$(cat "$AUR_LOG")"
pass "an AUR-buildable package is offered, not compiled behind the user's back"

reset_logs

PACMAN_REPO='ripgrep' PACMAN_LOCAL='ripgrep' omarchy-pkg-add ripgrep >/dev/null 2>&1 ||
  fail "a normal repository package still installs the way it always did"
pass "a normal repository package still installs the way it always did"

########################################################################
# the measured lists
########################################################################

# Every line the runtime reads has to carry a reason, since that reason is the
# whole message the user gets.
for manifest in packages.unavailable apps.unavailable; do
  while read -r name reason; do
    [[ -z $name || $name == \#* ]] && continue
    [[ -n $reason ]] || fail "every unavailable package states a reason" "$manifest: $name"
  done <"$ROOT/install/arm/$manifest"
done
pass "every unavailable package states a reason"

# The two lists answer different questions -- what the installer skips, and what
# a user cannot install afterwards -- and a package that drifted into both would
# make packages.unavailable's base-list invariant unenforceable.
base=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/omarchy-base.packages")
while read -r name _; do
  [[ -z $name || $name == \#* ]] && continue
  grep -qxF "$name" <<<"$base" &&
    fail "apps.unavailable stays out of the base package list" "$name is a base package"
done <"$ROOT/install/arm/apps.unavailable"
pass "apps.unavailable stays out of the base package list"

# The refusal has to survive the split: a base package that a menu entry needs
# is still answered, from the other file.
[[ $(PACMAN_REPO='' omarchy-pkg-arm-source ttfx) == none* ]] ||
  fail "packages.unavailable is still consulted at runtime"
pass "packages.unavailable is still consulted at runtime"
