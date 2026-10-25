#!/bin/bash
set -e
[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET=/usr/local/libexec/agentawake
LABEL=com.albastov.agentawake
WATCHER_LABEL=com.albastov.agentawake-pslog

was=0
pmset -g | grep -qE 'SleepDisabled[[:space:]]+1' && was=1
trap 'pmset -a disablesleep "$was" 2>/dev/null; echo "preflight interrupted, disablesleep restored to $was"' EXIT INT TERM

echo "preflight 1: can pmset set and read back disablesleep?"
pmset -a disablesleep 1 2>/dev/null || true
if pmset -g | grep -qE 'SleepDisabled[[:space:]]+1'; then
  echo "  ok"
else
  echo "  FAILED. pmset did not take. Raw output:"; pmset -g | sed 's/^/    /'
  echo "  Nothing installed."; exit 1
fi
pmset -a disablesleep "$was"
trap - EXIT INT TERM
echo "  restored to $was"

mkdir -p /usr/local/libexec
chown root:wheel /usr/local/libexec
chmod 755 /usr/local/libexec

echo "preflight 2: root runs this file every 10s, so nothing but root may write to it or its parents"
bad=0
p=$(dirname "$TARGET")
while [ "$p" != "/" ]; do
  owner=$(stat -f '%u' "$p"); mode=$(stat -f '%Lp' "$p"); mode=${mode: -3}
  gw=${mode:1:1}; ow=${mode:2:1}
  if [ "$owner" != "0" ]; then echo "  UNSAFE $p owned by uid $owner, not root"; bad=1
  elif [ $(( gw & 2 )) -ne 0 ] || [ $(( ow & 2 )) -ne 0 ]; then echo "  UNSAFE $p is group or world writable (mode $mode)"; bad=1
  else echo "  ok    $p  $mode root"
  fi
  p=$(dirname "$p")
done
if [ "$bad" = 1 ]; then
  echo "  Refusing to install a root daemon on a writable path. Nothing installed."
  exit 1
fi

install -o root -g wheel -m 755 "$SRC/agentawake" "$TARGET"
install -o root -g wheel -m 755 "$SRC/agentawake-pslog" /usr/local/libexec/agentawake-pslog
install -o root -g wheel -m 644 "$SRC/$LABEL.plist" "/Library/LaunchDaemons/$LABEL.plist"
install -o root -g wheel -m 644 "$SRC/$WATCHER_LABEL.plist" "/Library/LaunchDaemons/$WATCHER_LABEL.plist"

touch /var/log/agentawake.log && chmod 644 /var/log/agentawake.log
for label in "$LABEL" "$WATCHER_LABEL"; do
  launchctl bootout "system/$label" 2>/dev/null || true
  launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
done
echo "installed. first tick:"
"$TARGET"
echo "power watcher: $(launchctl print "system/$WATCHER_LABEL" >/dev/null 2>&1 && echo running || echo NOT running)"
