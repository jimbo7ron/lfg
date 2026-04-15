#!/usr/bin/env bash
# Hostname package install hook — apply DOTS_HOSTNAME if it's set and
# differs from the current hostname. Idempotent: no-op when already matching.
# Dry-run aware: inspects current state and reports what would change.
set -euo pipefail

: "${DOTS_HOSTNAME:=}"
if [[ -z "$DOTS_HOSTNAME" ]]; then
    [[ "${DRY_RUN:-false}" == "true" ]] && echo "Hostname: DOTS_HOSTNAME unset — no change"
    exit 0
fi

current=""
if command -v scutil >/dev/null 2>&1; then
    current=$(scutil --get HostName 2>/dev/null || true)
elif command -v hostnamectl >/dev/null 2>&1; then
    current=$(hostnamectl --static 2>/dev/null || true)
fi

if [[ "$current" == "$DOTS_HOSTNAME" ]]; then
    [[ "${DRY_RUN:-false}" == "true" ]] && echo "Hostname: already $DOTS_HOSTNAME — no change"
    exit 0
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "Hostname: would change ${current:-unset} → $DOTS_HOSTNAME (via sudo)"
    exit 0
fi

# Sudo will prompt on /dev/tty; bail cleanly if there's no controlling terminal.
if ! { true </dev/tty; } 2>/dev/null; then
    echo "Cannot set hostname without a controlling terminal (sudo needs tty) — skipping"
    exit 0
fi

echo "Setting hostname to $DOTS_HOSTNAME (current: ${current:-unset})"
if [[ "$(uname)" == "Darwin" ]]; then
    sudo scutil --set HostName "$DOTS_HOSTNAME"
    sudo scutil --set LocalHostName "$DOTS_HOSTNAME"
    sudo scutil --set ComputerName "$DOTS_HOSTNAME"
elif command -v hostnamectl >/dev/null 2>&1; then
    sudo hostnamectl set-hostname "$DOTS_HOSTNAME"
else
    echo "Unknown OS — no hostname setter available"
    exit 1
fi
