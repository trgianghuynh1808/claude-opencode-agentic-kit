#!/usr/bin/env bash
# Regression: while a long Claude call blocks the daemon, `room-ops.py inbox-ro` answers /status and /usage only.
#   tools/test-inbox-readonly.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null)
git -C "$P" add -A; git -C "$P" commit -qm kit; git -C "$P" branch staging; git -C "$P" checkout -q staging
cd "$P"; mkdir -p .agents/inbox/processed .agents/outbox
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
printf '{"command":"/status","args":""}' > .agents/inbox/1-a.json
printf '{"command":"/task","args":"Việc mới"}' > .agents/inbox/2-b.json
printf '{"command":"/stop","args":""}' > .agents/inbox/3-c.json
board_before="$(cat .agents/board.md)"
python3 scripts/room-ops.py inbox-ro
check "/status is answered (outbox message)" 'ls .agents/outbox/*.json >/dev/null 2>&1'
check "/status file moved to processed" '[[ -f .agents/inbox/processed/1-a.json && ! -f .agents/inbox/1-a.json ]]'
check "/task and /stop stay queued for the daemon" '[[ -f .agents/inbox/2-b.json && -f .agents/inbox/3-c.json ]]'
check "the board was not rewritten" '[[ "$(cat .agents/board.md)" == "$board_before" ]]'
python3 scripts/room-ops.py inbox-ro; n="$(ls .agents/outbox/*.json | wc -l | tr -d ' ')"
check "a second pass does not answer again" '[[ "$n" == 1 ]]'
exit $fail
