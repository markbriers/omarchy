#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/seed-home.sh"

skel="$test_tmp/skel"
home="$test_tmp/home"

fixture() {
  rm -rf "$skel" "$home"
  mkdir -p "$skel/.config/hypr" "$home"
  printf 'shipped\n' >"$skel/.bashrc"
  printf 'shipped bindings\n' >"$skel/.config/hypr/bindings.lua"
}

seed() {
  OMARCHY_ARM_SKEL="$skel" omarchy_arm_seed_home "$home"
}

# The bug this whole file exists for: /etc/skel only fires at user creation, so
# on a running machine the shipped defaults have to be copied in by hand.
fixture
out=$(seed)
[[ $(cat "$home/.bashrc") == shipped ]] || fail "a missing default is copied in"
[[ $out == *"2 shipped defaults"* ]] || fail "the count is reported" "$out"
pass "a missing default is copied in"

# A machine that has been running has its own .bashrc. Replacing it is right --
# without it the Omarchy environment never loads -- but it has to be recoverable.
fixture
printf 'the user had this\n' >"$home/.bashrc"
seed >/dev/null
[[ $(cat "$home/.bashrc") == shipped ]] || fail "a pre-Omarchy file is replaced"
[[ $(cat "$home/.bashrc.omarchy-arm.bak") == "the user had this" ]] ||
  fail "the file that was replaced is recoverable"
pass "a pre-Omarchy file is replaced, and backed up"

# The destructive case. Someone customises a config after the install, then the
# installer runs again -- to pick up a fix, or because they reran it. Copying
# over that edit destroys work, and the backup is no help: it holds the
# pre-Omarchy file, not what they wrote.
printf 'my own keybindings\n' >"$home/.config/hypr/bindings.lua"
out=$(seed)
[[ $(cat "$home/.config/hypr/bindings.lua") == "my own keybindings" ]] ||
  fail "a second run does not overwrite what the user edited"
[[ $out == *"1 left as you edited them"* ]] || fail "the run says what it left alone" "$out"
pass "a second run leaves the user's own edits alone, and says so"

# Nothing to do is not the same as replacing a file with itself: a needless copy
# would leave a backup of the installer's own output in the user's home.
fixture
seed >/dev/null
out=$(seed)
[[ ! -e $home/.bashrc.omarchy-arm.bak ]] || fail "an unchanged file is not backed up over and over"
[[ $out == *"2 already current"* ]] || fail "unchanged files are reported as current" "$out"
pass "a file that already matches is left completely alone"

fixture
out=$(OMARCHY_ARM_DRY_RUN=1 seed)
[[ ! -e $home/.bashrc ]] || fail "a dry run copies nothing"
[[ $out == \[dry-run\]* ]] || fail "a dry run says so" "$out"
pass "a dry run copies nothing"

# A home seeded by an earlier version of this installer has no marker, only the
# backups that version left. Treating it as never-seeded would cost it exactly
# the destructive pass this change is about.
fixture
printf 'the user had this\n' >"$home/.bashrc"
seed >/dev/null
rm -rf "$home/.local"
printf 'my own bashrc\n' >"$home/.bashrc"
out=$(seed)
[[ $(cat "$home/.bashrc") == "my own bashrc" ]] ||
  fail "an existing backup counts as evidence the home was already seeded"
[[ $out == *"1 left as you edited them"* ]] || fail "and it is reported as left alone" "$out"
pass "a home seeded before the marker existed is still recognised"
