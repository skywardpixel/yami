#!/bin/bash
# Integration checks for the process lifecycle — the half unit tests cannot
# reach, and where two of this project's real bugs lived.
#
# Runs against a scratch YAMI_HOME with its own config, so it never touches the
# real subscription, cache, or system proxy. It does need port 7890, so it stops
# a running Yami first and puts it back afterwards.
set -uo pipefail
set +m  # no job-control chatter when background processes are signalled

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$ROOT/build/Yami.app/Contents/MacOS/Yami"
SCRATCH="$(mktemp -d /tmp/yami-verify.XXXXXX)"
ORIGIN_PORT=8897
PORT=7890
PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected $3, got $2)"; fi; }

scratch_pids() { pgrep -f "YAMI_HOME|$SCRATCH" 2>/dev/null; }
app_pid()  { pgrep -f "$BINARY" | head -1; }
core_count() { pgrep -f "mihomo -d $SCRATCH" | wc -l | tr -d ' '; }
core_pid() { pgrep -f "mihomo -d $SCRATCH" | head -1; }
listening() { lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | wc -l | tr -d ' '; }

start_app() { YAMI_HOME="$SCRATCH" "$BINARY" >/dev/null 2>&1 & sleep 6; }

# Wait for a shell condition, up to N seconds.
await() {
    local seconds=$1; shift
    for _ in $(seq 1 $((seconds * 2))); do
        if eval "$@"; then return 0; fi
        sleep 0.5
    done
    return 1
}

cleanup() {
    pkill -f "$BINARY" 2>/dev/null
    sleep 1
    pkill -f "mihomo -d $SCRATCH" 2>/dev/null
    [ -n "${ORIGIN_PID:-}" ] && kill "$ORIGIN_PID" 2>/dev/null
    [ -n "${LEAK_PID:-}" ] && kill "$LEAK_PID" 2>/dev/null
    defaults delete dev.yami.verify 2>/dev/null
    rm -rf "$SCRATCH"
    if [ "${WAS_RUNNING:-0}" = "1" ]; then
        echo "restarting your Yami…"
        open /Applications/Yami.app 2>/dev/null
    fi
}
trap cleanup EXIT

[ -x "$BINARY" ] || { echo "build first: ./build.sh"; exit 1; }

# Park the user's instance for the duration. Their settings are never touched:
# YAMI_HOME sends the test instance to its own defaults domain.
if pgrep -f "Yami.app/Contents/MacOS/Yami" >/dev/null; then WAS_RUNNING=1; fi
pkill -f "Yami.app/Contents/MacOS/Yami" 2>/dev/null
sleep 2
pkill -x mihomo 2>/dev/null
sleep 1

if [ "$(listening)" != "0" ]; then
    echo "port $PORT is held by something else; cannot run"
    exit 1
fi

# A config that needs no network: everything routes DIRECT.
cat > "$SCRATCH/config.yaml" <<'EOF'
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
external-controller: ""
proxies:
  - {name: "unused", type: socks5, server: 127.0.0.1, port: 1080}
rules:
  - MATCH,DIRECT
EOF

echo "verifying in $SCRATCH"
echo "hello-from-origin" > "$SCRATCH/probe.txt"
# No subshell: `$!` must be python's own pid, or cleanup kills the wrapper and
# leaves the server squatting on the port for the next run.
lsof -nP -iTCP:$ORIGIN_PORT -sTCP:LISTEN -t 2>/dev/null | xargs -r kill 2>/dev/null
python3 -m http.server $ORIGIN_PORT --bind 127.0.0.1 --directory "$SCRATCH" >/dev/null 2>&1 &
ORIGIN_PID=$!
await 5 'curl -sf --max-time 1 -o /dev/null "http://127.0.0.1:'$ORIGIN_PORT'/probe.txt"' \
    || echo "  (origin server did not come up)"

echo
echo "1. core starts and actually serves"
start_app
check "core process running" "$(core_count)" "1"
check "listening on $PORT" "$(listening)" "1"
BODY=$(curl -s --max-time 8 -x http://127.0.0.1:$PORT "http://127.0.0.1:$ORIGIN_PORT/probe.txt")
check "traffic passes through the proxy" "$BODY" "hello-from-origin"

echo
echo "2. SIGTERM (the logout and shutdown path) leaves nothing behind"
kill -TERM "$(app_pid)" 2>/dev/null
await 10 '[ "$(core_count)" = "0" ]'
check "core terminated with the app" "$(core_count)" "0"
check "port released" "$(listening)" "0"

echo
echo "3. an orphan from a crash is reaped on next launch"
start_app
ORPHAN=$(core_pid)
kill -9 "$(app_pid)" 2>/dev/null
sleep 1
check "core orphaned by the crash" "$(core_count)" "1"
start_app
check "exactly one core after relaunch" "$(core_count)" "1"
NEW=$(core_pid)
if [ "$NEW" != "$ORPHAN" ]; then pass "orphan replaced, not left running"; else fail "orphan survived"; fi
check "new core is serving" "$(listening)" "1"

echo
echo "4. core restarts even with a client holding a half-closed connection"
python3 -c "
import socket, time
s = socket.create_connection(('127.0.0.1', $PORT))
time.sleep(60)
" &
LEAK_PID=$!
sleep 2
DIED=$(core_pid)
kill -TERM "$DIED" 2>/dev/null
await 20 '[ -n "$(core_pid)" ] && [ "$(core_pid)" != "'"$DIED"'" ]'
check "core came back" "$(core_count)" "1"
check "serving again despite FIN_WAIT_2" "$(listening)" "1"
if ! grep -q "address already in use" "$SCRATCH/core.log" 2>/dev/null; then
    pass "no phantom port conflict"
else
    fail "reported a port conflict"
fi

echo
echo "─────────────────────────────"
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
