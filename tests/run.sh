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

run_detector() {
  local name="$1" expected="$2" parent="$3" assertions="$4" state output
  state="$TMP/$name"
  mkdir -p "$state"
  output=$(env \
    AGENTAWAKE_DRY_RUN=1 \
    AGENTAWAKE_STATE="$state" \
    AGENTAWAKE_LOG="$state/log" \
    AGENTAWAKE_FAKE_BATT='batt 80' \
    AGENTAWAKE_FAKE_CURRENT=0 \
    AGENTAWAKE_FAKE_CAFFEINATE_PARENT="$parent" \
    AGENTAWAKE_FAKE_ASSERTIONS="$assertions" \
    "$ROOT/agentawake")
  assert_contains "$name detector" "$output" "reason=agent working ($expected)"
}

run_detector claude 'caffeinate<-claude' '/usr/local/bin/claude' ''
run_detector codex 'codex-turn' '/usr/bin/not-an-agent' 'Codex is running an active turn'
run_detector omp 'omp-turn' '/usr/bin/not-an-agent' 'Oh My Pi agent session'

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
