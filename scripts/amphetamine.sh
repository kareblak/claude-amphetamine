#!/usr/bin/env bash
#
# Claude Code <-> Amphetamine keep-awake hook
#
#   amphetamine.sh acquire   # agent starting work  (UserPromptSubmit)
#   amphetamine.sh refresh   # agent still working  (PostToolUse, Notification)
#   amphetamine.sh release   # agent idle / done    (Stop, SessionEnd)
#   amphetamine.sh status    # inspect locks / Amphetamine state
#
# Reads the hook JSON payload on stdin to get session_id, so several
# concurrent Claude Code sessions refcount correctly.
#
# Sessions are timed (default 30 min) and refreshed as a heartbeat while
# the agent works, so a crashed Claude Code lets the session expire
# instead of pinning the Mac awake forever.
#
# Config via env (set them in your shell profile or settings.json "env"):
#   CLAUDE_AWAKE_MINUTES        session length, refreshed while working (default 30)
#   CLAUDE_AWAKE_DISPLAY_SLEEP  "true" = let the screen sleep, Mac stays awake (default true)

set -uo pipefail

# No-op quietly on machines without Amphetamine, so the plugin is safe
# to enable in shared/project settings.
[ -e "/Applications/Amphetamine.app" ] || [ -e "$HOME/Applications/Amphetamine.app" ] || exit 0

DURATION_MINUTES="${CLAUDE_AWAKE_MINUTES:-30}"
DISPLAY_SLEEP_ALLOWED="${CLAUDE_AWAKE_DISPLAY_SLEEP:-true}"
REFRESH_EVERY_SECONDS=300
STALE_LOCK_MINUTES=120

STATE_DIR="${TMPDIR:-/tmp}/claude-amphetamine"
LOCKS_DIR="$STATE_DIR/locks"
EXTERNAL_FLAG="$STATE_DIR/external-session"
LAST_REFRESH="$STATE_DIR/last-refresh"

mkdir -p "$LOCKS_DIR"

# --- helpers ---------------------------------------------------------------

amph() { /usr/bin/osascript -e "tell application \"Amphetamine\" to $1" 2>/dev/null; }

session_is_active() { [ "$(amph 'session is active')" = "true" ]; }

start_or_extend() {
  # Amphetamine overrides any running session, so this doubles as "refresh".
  amph "start new session with options {duration:${DURATION_MINUTES}, interval:minutes, displaySleepAllowed:${DISPLAY_SLEEP_ALLOWED}}" >/dev/null
  date +%s >"$LAST_REFRESH"
}

end_our_session() {
  amph "end session" >/dev/null
  rm -f "$LAST_REFRESH"
}

prune_stale_locks() {
  find "$LOCKS_DIR" -type f -mmin "+${STALE_LOCK_MINUTES}" -delete 2>/dev/null
}

lock_count() { find "$LOCKS_DIR" -type f | wc -l | tr -d ' '; }

# Extract session_id from the hook payload without needing jq/python.
read_session_id() {
  local payload sid
  payload="$(cat 2>/dev/null)"
  sid="$(printf '%s' "$payload" \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"
  [ -n "$sid" ] || sid="ppid-$PPID"
  printf '%s' "$sid"
}

# --- actions ---------------------------------------------------------------

ACTION="${1:-}"
SESSION_ID="$(read_session_id)"
LOCK="$LOCKS_DIR/$SESSION_ID"

prune_stale_locks

case "$ACTION" in
  acquire|refresh)
    # If you already had Amphetamine running manually before any agent work
    # started, stay hands-off: don't hijack or later kill your own session.
    if [ "$(lock_count)" -eq 0 ] && [ ! -e "$EXTERNAL_FLAG" ]; then
      if session_is_active; then
        : >"$EXTERNAL_FLAG"
      fi
    fi

    touch "$LOCK"
    [ -e "$EXTERNAL_FLAG" ] && exit 0

    if [ "$ACTION" = "refresh" ] && [ -f "$LAST_REFRESH" ]; then
      last="$(cat "$LAST_REFRESH" 2>/dev/null || echo 0)"
      now="$(date +%s)"
      # Throttle: avoid an osascript round-trip on every single tool call.
      if [ $((now - last)) -lt "$REFRESH_EVERY_SECONDS" ]; then
        exit 0
      fi
    fi

    start_or_extend
    ;;

  release)
    rm -f "$LOCK"
    [ "$(lock_count)" -gt 0 ] && exit 0

    if [ -e "$EXTERNAL_FLAG" ]; then
      rm -f "$EXTERNAL_FLAG"   # your manual session keeps running
      exit 0
    fi

    end_our_session
    ;;

  status)
    echo "locks:    $(lock_count)"
    echo "external: $([ -e "$EXTERNAL_FLAG" ] && echo yes || echo no)"
    echo "active:   $(amph 'session is active')"
    echo "left:     $(amph 'session time remaining')"
    ;;

  *)
    echo "usage: $(basename "$0") {acquire|refresh|release|status}" >&2
    exit 1
    ;;
esac

exit 0
