#!/usr/bin/env bash
# Git package install hook — set up SSH signing key and allowed_signers.
#
# First-run setup (gh upload, ssh-copy-id prompt) runs once then touches
# ~/.ssh/.lfg-setup-done. Subsequent runs skip those steps silently.
# To re-trigger: rm ~/.ssh/.lfg-setup-done && ./lfg config git
#
# Always-run steps (keygen, agent load, allowed_signers) are idempotent
# and silent when nothing changes — handled by ssh_ensure_key in helpers.sh,
# shared with the `lfg ssh` command so there's one source of truth.
#
# Dry-run aware: reports what each step would do.
set -euo pipefail

# SSH_KEY / SSH_PUB / SSH_ALLOWED_SIGNERS come from helpers.sh (sourced by lfg
# before this hook runs in its subshell).
setup_marker="$HOME/.ssh/.lfg-setup-done"

# ── Dry-run branch: inspect only ────────────────────────────────────────────

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "SSH key: would generate ed25519 at $SSH_KEY"
    else
        echo "SSH key: exists at $SSH_KEY"
    fi

    if [[ -f "$SSH_PUB" ]]; then
        line="$DOTS_GIT_EMAIL $(awk '{print $1, $2}' "$SSH_PUB")"
        if [[ ! -f "$SSH_ALLOWED_SIGNERS" ]] || ! grep -qxF "$line" "$SSH_ALLOWED_SIGNERS" 2>/dev/null; then
            echo "allowed_signers: would append this machine's pubkey"
        else
            echo "allowed_signers: already contains this machine's pubkey"
        fi
    else
        echo "allowed_signers: would run after key generation"
    fi

    if [[ -f "$setup_marker" ]]; then
        echo "GitHub + ssh-copy-id: setup already complete (marker: $setup_marker)"
    else
        echo "GitHub: would upload pubkey (auth + signing) if gh authenticated"
        echo "ssh-copy-id: would prompt for remote host(s) interactively"
    fi
    exit 0
fi

# ── Always-run: keygen, agent, allowed_signers (shared helper) ──────────────

ssh_ensure_key

# ── First-run only: gh upload + ssh-copy-id ─────────────────────────────────

if [[ -f "$setup_marker" ]]; then
    exit 0
fi

# Upload to GitHub
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    host=$(hostname -s)
    echo "Uploading pubkey to GitHub as auth + signing key ($host)"
    gh ssh-key add "$SSH_PUB" --title "$host" --type authentication 2>/dev/null || true
    gh ssh-key add "$SSH_PUB" --title "$host" --type signing 2>/dev/null || true
else
    printf '\n────────────────────────────────────────────────────────────\n'
    printf 'gh not installed or not authenticated. Install: ./lfg install\n'
    printf 'Then add this pubkey to GitHub (as BOTH authentication and signing key):\n'
    printf '  https://github.com/settings/ssh/new\n\n'
    cat "$SSH_PUB"
    printf '────────────────────────────────────────────────────────────\n\n'
fi

# Offer to copy pubkey to remote hosts (ssh-copy-id via the shared helper)
if { true </dev/tty; } 2>/dev/null; then
    printf '\nCopy this pubkey to a remote host? (You can also do this later with\n'
    printf "'./lfg ssh copy user@host'.)\n"
    printf "Enter 'user@host' (blank to skip): "
    read -r target </dev/tty
    while [[ -n "$target" ]]; do
        ssh_copy_one "$target" </dev/tty || true
        printf "Another host? (blank to finish): "
        read -r target </dev/tty
    done
fi

# Mark setup as done
touch "$setup_marker"
