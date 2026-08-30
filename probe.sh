#!/bin/bash
# Checks the private pmset flag and the optional Pager bridge. Installs nothing.
[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }

was=0
pmset -g | grep -qE 'SleepDisabled[[:space:]]+1' && was=1
trap 'pmset -a disablesleep "$was" 2>/dev/null; echo "restored disablesleep=$was"' EXIT INT TERM

echo "== 1. does pmset disablesleep set and read back? =="
echo "   before: $(pmset -g | grep -iE 'sleepdisabled' || echo '(no SleepDisabled line at all)')"
err=$(pmset -a disablesleep 1 2>&1 >/dev/null)
[ -n "$err" ] && echo "   stderr: $err"
echo "   after : $(pmset -g | grep -iE 'sleepdisabled' || echo '(no SleepDisabled line at all)')"
echo "   full pmset -g:"; pmset -g | sed 's/^/     /'

echo
echo "== 2. can root raise an optional Pager panel in the user session? =="
user=$(stat -f%Su /dev/console 2>/dev/null)
[ -n "$user" ] && [ "$user" != root ] || { echo "   skipped: no console user"; exit 0; }
uid=$(id -u "$user")
home=$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null)
home=${home#*: }; [ -n "$home" ] || home="/Users/$user"
pager=
for candidate in "$home/.local/bin/pager" /opt/homebrew/bin/pager /usr/local/bin/pager; do
  [ -x "$candidate" ] && { pager=$candidate; break; }
done
if [ -z "$pager" ]; then
  echo "   skipped: Pager is not installed; agentawake will run without panels"
  exit 0
fi
echo "   console user=$user uid=$uid pager=$pager"
launchctl asuser "$uid" sudo -u "$user" "$pager" \
  --title "Root reached your screen" --app agentawake --corner top-right \
  --accent "#c8ff00" --sound tick \
  --body "This test came from a root process. Pager itself still ran as your logged-in user." \
  --seconds 30
echo "   exit status: $?"
