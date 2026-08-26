# claude-amphetamine

Keep your Mac awake while [Claude Code](https://claude.com/claude-code) agents are working, using [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704).

Long agent runs die quietly when the Mac goes to sleep. This plugin holds a keep-awake session exactly as long as an agent is actually working — and not a minute longer.

## How it works

| Claude Code event | Action |
|---|---|
| `UserPromptSubmit` | **acquire** — start (or extend) a timed Amphetamine session |
| `PostToolUse`, `Notification` | **refresh** — heartbeat, throttled to once per 5 minutes |
| `Stop`, `SessionEnd` | **release** — end the Amphetamine session when the last agent goes idle |

Design properties:

- **Timed sessions, not indefinite.** Each acquire/refresh starts a 30-minute Amphetamine session. If Claude Code crashes and never releases, the session simply expires instead of pinning your Mac awake forever.
- **Refcounted.** Concurrent Claude Code sessions each hold a lock file (keyed by `session_id` from the hook payload). The Mac stays awake until the *last* session releases.
- **Hands-off with manual sessions.** If you started an Amphetamine session yourself before any agent work, the plugin flags it as external and never touches it.
- **Cheap.** The refresh path is throttled — between heartbeats it's pure filesystem checks, no AppleScript round-trips on every tool call.
- **No dependencies.** Plain bash + sed; no jq or python required. Machines without Amphetamine installed no-op silently, so it's safe to enable everywhere.

## Requirements

- macOS with [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) installed (free, App Store)
- On first use, macOS may prompt to allow your terminal to control Amphetamine (Automation permission) — click Allow.

## Install

```
/plugin marketplace add kareblakstad/claude-amphetamine
/plugin install amphetamine@claude-amphetamine
```

Hooks are active immediately — no restart needed.

## Configuration

Set these in your shell profile or in the `env` block of `~/.claude/settings.json`:

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_AWAKE_MINUTES` | `30` | Length of each timed Amphetamine session (the heartbeat keeps extending it while the agent works) |
| `CLAUDE_AWAKE_DISPLAY_SLEEP` | `true` | `true` lets the display sleep while the Mac stays awake; `false` keeps the screen on too |

## Inspecting state

```bash
~/.claude/plugins/cache/*/claude-amphetamine/amphetamine*/scripts/amphetamine.sh status < /dev/null
```

Shows the current lock count, whether an external (manual) session was detected, and Amphetamine's active state and time remaining. Lock files live under `$TMPDIR/claude-amphetamine/locks` and stale locks are pruned after 120 minutes.

## License

MIT
