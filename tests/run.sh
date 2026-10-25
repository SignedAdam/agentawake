#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
USER_NAME=$(id -un)
PASSED=0

pass() {
  PASSED=$((PASSED + 1))
  printf '  ok  %s\n' "$1"
}

assert_contains() {
  local name="$1" actual="$2" expected="$3"
  case "$actual" in
    *"$expected"*) pass "$name" ;;
    *)
      printf 'FAIL  %s\nexpected: %s\nactual:   %s\n' "$name" "$expected" "$actual" >&2
      exit 1
      ;;
  esac
}

assert_equals() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    printf 'FAIL  %s\nexpected: %s\nactual:   %s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
}

# Every detector run gets a user home so the tests never read the real ~/.hermes.
DETECT_HOME="$TMP/home-empty"
mkdir -p "$DETECT_HOME"

detect() {
  local name="$1" parent="$2" assertions="$3" state
  state="$TMP/$name"
  mkdir -p "$state"
  env \
    AGENTAWAKE_DRY_RUN=1 \
    AGENTAWAKE_STATE="$state" \
    AGENTAWAKE_LOG="$state/log" \
    AGENTAWAKE_FAKE_BATT='batt 80' \
    AGENTAWAKE_FAKE_CURRENT=0 \
    AGENTAWAKE_FAKE_CAFFEINATE_PARENT="$parent" \
    AGENTAWAKE_FAKE_ASSERTIONS="$assertions" \
    AGENTAWAKE_USER_HOME="$DETECT_HOME" \
    "$ROOT/agentawake"
}

run_detector() {
  assert_contains "$1 detector" "$(detect "$1" "$3" "$4")" "reason=agent working ($2)"
}

run_idle() {
  assert_contains "$1 allows sleep" "$(detect "$1" '/usr/bin/not-an-agent' "$2")" 'reason=no agents'
}

run_detector claude 'caffeinate<-claude' '/usr/local/bin/claude' ''
run_detector codex 'codex-turn' '/usr/bin/not-an-agent' 'Codex is running an active turn'
run_detector omp 'omp-turn' '/usr/bin/not-an-agent' \
  'pid 81187(omp): [0x000fe13200018919] 00:00:46 PreventUserIdleSystemSleep named: "omp agent session"'
run_detector amphetamine 'amphetamine' '/usr/bin/not-an-agent' \
  'pid 61081(Amphetamine): [0x000e98e90001a300] 00:09:29 PreventUserIdleSystemSleep named: "Amphetamine (Single-Use - System)"'

# gateway_state HOME PROFILE ACTIVE PID   (empty PROFILE = the default ~/.hermes)
gateway_state() {
  local dir="$1/.hermes"
  [ -n "$2" ] && dir="$dir/profiles/$2"
  mkdir -p "$dir"
  printf '{"pid": %s, "active_agents": %s, "gateway_state": "running"}\n' "$4" "$3" > "$dir/gateway_state.json"
}

DETECT_HOME="$TMP/home-hermes-busy"
gateway_state "$DETECT_HOME" '' 0 $$
gateway_state "$DETECT_HOME" narkis 1 $$
run_detector hermes-gateway 'hermes-gateway:narkis' '/usr/bin/not-an-agent' ''

DETECT_HOME="$TMP/home-hermes-idle"
gateway_state "$DETECT_HOME" '' 0 $$
gateway_state "$DETECT_HOME" narkis 0 $$
run_idle hermes-idle-gateways ''

sleep 0 & dead_pid=$!
wait "$dead_pid"
DETECT_HOME="$TMP/home-hermes-dead"
gateway_state "$DETECT_HOME" narkis 1 "$dead_pid"
run_idle hermes-dead-gateway ''

DETECT_HOME="$TMP/home-hermes-stale"
gateway_state "$DETECT_HOME" narkis 1 $$
touch -A -2000 "$DETECT_HOME/.hermes/profiles/narkis/gateway_state.json"
run_idle hermes-stale-gateway ''

desktop_blocker='pid 9438(Hermes): [0x0008c32300019c17] 01:00:00 NoIdleSleepAssertion named: "Electron"'
DETECT_HOME="$TMP/home-desktop-working"
mkdir -p "$DETECT_HOME/Library/Application Support/Hermes"
printf '{"mode": "while-working"}' > "$DETECT_HOME/Library/Application Support/Hermes/keep-awake.json"
run_detector hermes-desktop 'hermes-desktop' '/usr/bin/not-an-agent' "$desktop_blocker"

DETECT_HOME="$TMP/home-desktop-always"
mkdir -p "$DETECT_HOME/Library/Application Support/Hermes"
printf '{"mode": "always"}' > "$DETECT_HOME/Library/Application Support/Hermes/keep-awake.json"
run_idle hermes-desktop-always "$desktop_blocker"

state="$TMP/idle"
mkdir -p "$state"
output=$(env \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 80' \
  AGENTAWAKE_FAKE_CURRENT=0 \
  AGENTAWAKE_FAKE_AGENT=none \
  "$ROOT/agentawake")
assert_contains 'idle sessions allow sleep' "$output" 'desired=0'
assert_contains 'idle reason' "$output" 'reason=no agents'

state="$TMP/grace"
mkdir -p "$state"
printf '%s' "$(( $(date +%s) - 900 ))" > "$state/last_active"
output=$(env \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 80' \
  AGENTAWAKE_FAKE_CURRENT=1 \
  AGENTAWAKE_FAKE_AGENT=none \
  "$ROOT/agentawake")
assert_contains 'fifteen minutes stays in grace' "$output" 'desired=1'
assert_contains 'fifteen minute grace reason' "$output" 'reason=grace'

printf '%s' "$(( $(date +%s) - 1201 ))" > "$state/last_active"
output=$(env \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 80' \
  AGENTAWAKE_FAKE_CURRENT=1 \
  AGENTAWAKE_FAKE_AGENT=none \
  "$ROOT/agentawake")
assert_contains 'twenty minutes ends grace' "$output" 'desired=0'
assert_contains 'expired grace reason' "$output" 'reason=no agents'

state="$TMP/floor"
mkdir -p "$state"
output=$(env \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 19' \
  AGENTAWAKE_FAKE_CURRENT=0 \
  AGENTAWAKE_FAKE_AGENT=omp-turn \
  "$ROOT/agentawake")
assert_contains 'battery floor overrides active agent' "$output" 'desired=0'
assert_contains 'battery floor reason' "$output" 'battery 19%, floor tripped'

state="$TMP/no-pager"
mkdir -p "$state"
printf ac > "$state/last_source"
env \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 80' \
  AGENTAWAKE_FAKE_CURRENT=1 \
  AGENTAWAKE_FAKE_AGENT=omp-turn \
  AGENTAWAKE_FAKE_CONSOLE_USER="$USER_NAME" \
  AGENTAWAKE_PAGER="$TMP/not-installed" \
  "$ROOT/agentawake" >/dev/null
assert_contains 'missing Pager is optional' "$(cat "$state/log")" 'pager not installed; notification skipped'

stub="$TMP/pager"
capture="$TMP/pager-args"
cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$PAGER_CAPTURE"
[ -n "${PAGER_CALLS:-}" ] && printf 'call\n' >> "$PAGER_CALLS"
STUB
chmod +x "$stub"
state="$TMP/with-pager"
mkdir -p "$state"
printf ac > "$state/last_source"
env \
  PAGER_CAPTURE="$capture" \
  AGENTAWAKE_DRY_RUN=1 \
  AGENTAWAKE_STATE="$state" \
  AGENTAWAKE_LOG="$state/log" \
  AGENTAWAKE_FAKE_BATT='batt 80' \
  AGENTAWAKE_FAKE_CURRENT=1 \
  AGENTAWAKE_FAKE_AGENT=omp-turn \
  AGENTAWAKE_FAKE_CONSOLE_USER="$USER_NAME" \
  AGENTAWAKE_PAGER="$stub" \
  "$ROOT/agentawake" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$capture" ] && break
  sleep 0.05
done
[ -s "$capture" ] || { echo 'FAIL  installed Pager was not called' >&2; exit 1; }
args=$(cat "$capture")
assert_contains 'installed Pager is used' "$args" '**Safe to close the lid.**'
assert_contains 'Pager names OMP' "$args" 'OMP running'
assert_contains 'Pager action opens the log' "$args" 'Log:open -e '

state="$TMP/concurrent-unplug"
mkdir -p "$state"
printf ac > "$state/last_source"
calls="$TMP/pager-calls"
for _ in 1 2 3 4 5 6 7 8; do
  env \
    PAGER_CAPTURE="$TMP/concurrent-pager-args" \
    PAGER_CALLS="$calls" \
    AGENTAWAKE_DRY_RUN=1 \
    AGENTAWAKE_STATE="$state" \
    AGENTAWAKE_LOG="$state/log" \
    AGENTAWAKE_FAKE_BATT='batt 80' \
    AGENTAWAKE_FAKE_CURRENT=1 \
    AGENTAWAKE_FAKE_AGENT=omp-turn \
    AGENTAWAKE_FAKE_CONSOLE_USER="$USER_NAME" \
    AGENTAWAKE_PAGER="$stub" \
    "$ROOT/agentawake" >/dev/null &
done
wait
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$calls" ] && break
  sleep 0.05
done
sleep 0.1
[ -f "$calls" ] || : > "$calls"
call_count=$(wc -l < "$calls" | tr -d ' ')
assert_equals 'concurrent unplug sends one Pager panel' "$call_count" 1

printf '\n%d checks passed\n' "$PASSED"
