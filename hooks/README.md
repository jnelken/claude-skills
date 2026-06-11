# Hooks

Symlinked into `~/.claude/hooks/` by `install.sh`. Each hook needs to be **wired up** in `~/.claude/settings.json` to actually fire — symlinking the script alone does nothing.

## post-yesterdays-ccusage.sh

Posts daily ccusage summaries (Claude + Codex token usage) to a Slack channel via incoming webhook. Triggered on every Claude Code session start; catches up any days missed since the last successful post.

### Requirements

- `$SLACK_CCUSAGE_WEBHOOK_URL` exported in your shell env (incoming webhook for the target Slack channel)
- `npx`, `jq`, `curl` on `PATH`
- `ccusage >= 20` for Codex usage data (older versions still post Claude-only data)
- State dir created on first run: `~/.claude/.ccusage-state/` (gitignored from anywhere)

### settings.json wiring

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/hooks/post-yesterdays-ccusage.sh\"",
            "timeout": 300,
            "async": true
          }
        ]
      }
    ]
  }
}
```

Why these options:
- `async: true` — runs in the background so session start isn't blocked while ccusage runs + the Slack POST happens.
- `timeout: 300` — caps at 5 minutes so a stuck request can't linger.
- `bash "$HOME/..."` — more portable than relying on the executable bit + shebang.

If you already have a `hooks.SessionStart` array, append the new entry rather than replacing.

### Behavior

- Reads `~/.claude/.ccusage-state/last-posted` (one line, `YYYY-MM-DD`) to track the last successfully-posted day.
- Posts one Slack message per missed day, from `last+1` through yesterday.
- Marker advances only after a successful POST, so transient Slack failures resume cleanly on the next session.
- Skips silently if any dependency (`npx` / `jq` / `curl`) is missing, or if the webhook env var is unset — never blocks a session.

### Disabling

Remove the entry from `settings.json` OR `unset SLACK_CCUSAGE_WEBHOOK_URL` to no-op.
