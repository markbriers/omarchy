#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/keyboard.sh"

detect() {
  OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
  OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
    omarchy_arm_detect_keyboard
}

fixture() {
  rm -f "$test_tmp/vconsole.conf" "$test_tmp/00-keyboard.conf"
  [[ -n ${1:-} ]] && printf '%s\n' "$1" >"$test_tmp/vconsole.conf"
  [[ -n ${2:-} ]] && printf '%s\n' "$2" >"$test_tmp/00-keyboard.conf"
  return 0
}

# The whole point: default/hypr/input.lua reads XKBLAYOUT and falls back to us.
# A machine that already declares a layout must not end up in US.
fixture 'XKBLAYOUT=fr'
[[ $(detect | cut -f1) == "fr" ]] || fail "XKBLAYOUT is used when it is already set" "$(detect)"
[[ $(detect | cut -f3) == "$test_tmp/vconsole.conf" ]] ||
  fail "an already-correct vconsole.conf is reported as needing nothing"
pass "XKBLAYOUT is used when it is already set"

fixture 'XKBLAYOUT="be"
XKBVARIANT="oss"'
[[ $(detect | cut -f1,2) == $'be\toss' ]] || fail "the variant comes along, quotes stripped" "$(detect)"
pass "the variant comes along, and quoting is stripped"

# localectl set-x11-keymap writes this, and it is the authoritative xkb answer.
fixture '' 'Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "de"
        Option "XkbVariant" "nodeadkeys"
EndSection'
[[ $(detect | cut -f1,2) == $'de\tnodeadkeys' ]] || fail "the X11 keymap is read when vconsole has no XKBLAYOUT" "$(detect)"
pass "the X11 keymap is read when vconsole has no XKBLAYOUT"

# XKBLAYOUT wins: it is what Omarchy actually reads, so anything else would be
# reporting a layout the desktop will not use.
fixture 'XKBLAYOUT=fr' 'Section "InputClass"
        Option "XkbLayout" "de"
EndSection'
[[ $(detect | cut -f1) == "fr" ]] || fail "XKBLAYOUT wins over the X11 config" "$(detect)"
pass "XKBLAYOUT wins over the X11 config"

# A command-line Arch install very often sets KEYMAP and nothing else. Console
# keymap names are not xkb layout names.
for case in "fr-latin9 fr" "de-latin1-nodeadkeys de" "fr fr" "es es" "br-abnt2 br"; do
  set -- $case
  fixture "KEYMAP=$1"
  [[ $(detect | cut -f1) == "$2" ]] || fail "the console keymap $1 maps to $2" "$(detect)"
done
pass "console keymaps are reduced to their xkb layout"

# The ones where the base name itself differs.
fixture 'KEYMAP=uk'
[[ $(detect | cut -f1) == "gb" ]] || fail "uk maps to gb, not uk" "$(detect)"
fixture 'KEYMAP=dvorak'
[[ $(detect | cut -f1,2) == $'us\tdvorak' ]] || fail "dvorak maps to us with a variant" "$(detect)"
fixture 'KEYMAP=sg'
[[ $(detect | cut -f1,2) == $'ch\tde' ]] || fail "sg maps to ch/de" "$(detect)"
pass "aliased keymaps map to their real xkb layout and variant"

# Guessing at a keymap nobody recognises would be worse than the default: a
# layout Hyprland rejects leaves a desktop with no working keyboard at all.
fixture 'KEYMAP=some-unknown-thing-42'
[[ -z $(detect) ]] || fail "an unrecognised keymap is left alone" "$(detect)"
fixture ''
[[ -z $(detect) ]] || fail "a machine that declares nothing detects nothing" "$(detect)"
pass "an unrecognised or absent keymap falls through to the shipped default"

# A dry run must not write to the file it is reporting on.
fixture 'KEYMAP=fr-latin9'
before=$(cat "$test_tmp/vconsole.conf")
out=$(OMARCHY_ARM_DRY_RUN=1 OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
      OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" omarchy_arm_apply_keyboard)
[[ $(cat "$test_tmp/vconsole.conf") == "$before" ]] || fail "a dry run changes nothing" "$(cat "$test_tmp/vconsole.conf")"
grep -q "XKBLAYOUT=fr" <<<"$out" || fail "a dry run says what it would write" "$out"
pass "a dry run reports without writing"

grep -q 'step "Keyboard layout"' "$ROOT/install.sh" ||
  fail "install.sh runs the keyboard step"
pass "install.sh runs the keyboard step"
