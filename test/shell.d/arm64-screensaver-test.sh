#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# ttfx draws the screensaver and has no aarch64 build. TTFX_PRESENT switches
# between the two machines this has to behave correctly on.
cat >"$stub_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
[[ ${TTFX_PRESENT:-0} == 1 ]] && exit 1
exit 0
STUB

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$stub_bin/omarchy-toggle-enabled" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$stub_bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUB

# Nothing past the guard may run. Each of these records the fact that it was
# reached, which is the failure this test is about.
for reached in xdg-terminal-exec omarchy-hyprland-monitor-focused hyprctl socat ttfx; do
  cat >"$stub_bin/$reached" <<STUB
#!/bin/bash
printf '%s\n' "$reached" >>"\$REACHED_LOG"
exit 1
STUB
done

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$ROOT/bin:$PATH"
export NOTIFY_LOG="$test_tmp/notify.log" REACHED_LOG="$test_tmp/reached.log"
: >"$NOTIFY_LOG"
: >"$REACHED_LOG"

# The idle service treats a screensaver window that opens and closes as the
# user dismissing it, and cancels the pending lock. Opening a window that dies
# on "ttfx: command not found" would therefore stop an idle machine from ever
# locking, which is worse than having no screensaver.
if omarchy-launch-screensaver </dev/null >/dev/null 2>&1; then
  fail "the screensaver does not launch without ttfx"
fi
[[ ! -s $REACHED_LOG ]] || fail "no terminal is spawned without ttfx" "$(cat "$REACHED_LOG")"
pass "the screensaver does not launch without ttfx, and spawns no window"

# Idle fires this every few minutes. Notifying each time would be noise, so the
# message is only for someone who picked Screensaver from the menu.
[[ ! -s $NOTIFY_LOG ]] || fail "the idle path stays quiet" "$(cat "$NOTIFY_LOG")"
pass "the idle path stays quiet"

omarchy-launch-screensaver force </dev/null >/dev/null 2>&1 || true
grep -q ttfx "$NOTIFY_LOG" || fail "asking for it from the menu explains why nothing happened" "$(cat "$NOTIFY_LOG")"
pass "asking for it from the menu explains why nothing happened"

# omarchy-screensaver respawns ttfx in a loop for as long as it keeps running.
# Missing, it fails instantly, and the loop turns into a spin that pins a core
# and floods the terminal. It has to refuse before reaching the loop.
: >"$REACHED_LOG"
# timeout keeps a regression from hanging the suite where it exists; where it
# does not, the assertion still holds, it just would not be bounded.
bounded() {
  if command -v timeout >/dev/null; then timeout 5 "$@"; else "$@"; fi
}

if bounded omarchy-screensaver </dev/null >/dev/null 2>&1; then
  fail "the screensaver itself refuses to start without ttfx"
fi
[[ ! -s $REACHED_LOG ]] || fail "it refuses before the respawn loop" "$(cat "$REACHED_LOG")"
pass "the screensaver itself refuses, before the respawn loop"

# On a machine that has ttfx, none of this may change what happens.
: >"$REACHED_LOG"
TTFX_PRESENT=1 omarchy-launch-screensaver </dev/null >/dev/null 2>&1 || true
grep -q . "$REACHED_LOG" || fail "with ttfx installed the launcher proceeds as before"
pass "with ttfx installed the launcher proceeds as before"
