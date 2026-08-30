# agentawake

`agentawake` is a root LaunchDaemon for macOS laptops. It keeps the machine awake while Claude Code, Codex, or Oh My Pi (OMP) are actively running turns, even when the lid is closed on battery power.

## Why standard tools fail on battery

Apple provides one public assertion that can prevent sleep when the lid closes: `caffeinate -s`, which creates a `PreventSystemSleep` assertion. Apple documents that this assertion only works on AC power. On battery power, macOS ignores it and puts the machine to sleep when the lid closes.

`agentawake` works around this by toggling the undocumented root power setting:

```sh
pmset -a disablesleep 1
```

When active turns finish, `agentawake` turns sleep back on.

## Warnings and limits

- **Undocumented private setting:** `pmset -a disablesleep` is not a public or supported Apple API. It can break or disappear in a future macOS release.
- **Battery drain and heat:** With the lid closed on battery, the Mac stays fully awake, drains the battery, and gets warm.
- **macOS only:** This project depends on `pmset`, `launchd`, and macOS power assertions.

## How it works

### Agent detection

`agentawake` checks for active work every 30 seconds and reacts immediately when the power source changes:

- **Claude Code:** Detects the active `caffeinate` child created while a turn runs.
- **Codex:** Detects the `Codex is running an active turn` power assertion.
- **Oh My Pi (OMP):** Detects the `Oh My Pi agent session` power assertion.

Idle agent windows do not keep the machine awake.

### Cooldown and battery thresholds

- **10-minute cooldown:** Sleep stays disabled for 10 minutes after the last active turn, then returns to normal.
- **Below 20% cutoff:** On battery, sleep is restored when the charge falls below 20%, even if an agent is still working.
- **25% resume threshold:** After the cutoff trips, agent work can disable sleep again once the battery reaches 25%. The gap prevents repeated switching around one battery percentage.

## Optional Pager panels

`agentawake` can use [Pager](https://github.com/SignedAdam/pager) for native desktop panels.

When Pager is installed, panels report:

- unplugging the Mac while an agent is working;
- the low-battery cutoff;
- a failure to change the sleep setting.

Pager is detected at the logged-in user's `~/.local/bin/pager`, `/opt/homebrew/bin/pager`, or `/usr/local/bin/pager`. The daemon starts Pager as the logged-in user through `launchctl asuser`. Pager never runs as root.

Pager is optional. Without it, every sleep-control feature still works and state changes are written to `/var/log/agentawake.log`.

## Install

The installer first proves that `pmset disablesleep` works on the machine, then restores the previous setting. It also refuses to place a root daemon under a directory that another user can modify.

```sh
git clone https://github.com/SignedAdam/agentawake.git
cd agentawake
sudo ./install.sh
```

To update, pull the repository and run `sudo ./install.sh` again.

Installed files:

- executables: `/usr/local/libexec/agentawake` and `/usr/local/libexec/agentawake-pslog`;
- LaunchDaemons: `/Library/LaunchDaemons/com.albastov.agentawake.plist` and `/Library/LaunchDaemons/com.albastov.agentawake-pslog.plist`;
- log: `/var/log/agentawake.log`.

## Test and inspect

Run the behavioral tests. They make no changes to system sleep:

```sh
make test
```

Test the private `pmset` flag and the optional Pager bridge:

```sh
sudo ./probe.sh
```

`probe.sh` restores the previous sleep setting even when interrupted.

Watch state changes:

```sh
tail -f /var/log/agentawake.log
```

Inspect the current setting:

```sh
pmset -g | grep SleepDisabled
```

`SleepDisabled 1` means the block is active. `SleepDisabled 0`, or no line, means normal sleep is allowed.

## Uninstall

```sh
sudo ./uninstall.sh
```

This unloads both LaunchDaemons, removes the installed executables, clears runtime state, and sets `disablesleep` back to `0`.

## License

[MIT](LICENSE), copyright 2026 Adam Albastov.
