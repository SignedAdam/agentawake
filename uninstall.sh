#!/bin/bash
set -e
[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }
LABEL=com.albastov.agentawake
WATCHER_LABEL=com.albastov.agentawake-pslog
launchctl bootout "system/$WATCHER_LABEL" 2>/dev/null || true
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/LaunchDaemons/$WATCHER_LABEL.plist" \
  /usr/local/libexec/agentawake /usr/local/libexec/agentawake-pslog
rmdir /usr/local/libexec 2>/dev/null || true
rm -rf /var/run/agentawake
pmset -a disablesleep 0
echo "removed. disablesleep set to 0, so sleep is back to normal:"
pmset -g | grep -i sleepdisabled || echo "  (no SleepDisabled line, which also means off)"
