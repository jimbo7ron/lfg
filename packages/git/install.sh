#!/usr/bin/env bash
# Git package install hook — set up SSH signing key and allowed_signers.
#
# First-run setup (gh upload, ssh-copy-id prompt) runs once then touches
# ~/.ssh/.lfg-setup-done. Subsequent runs skip those steps silently.
# To re-trigger: rm ~/.ssh/.lfg-setup-done && ./lfg config git
#
# Always-run steps (keygen, agent load, allowed_signers) are idempotent
# and silent when nothing changes.
#
# Dry-run aware: reports what each step would do.
set -euo pipefail

key="$HOME/.ssh/id_ed25519"
pub="$key.pub"
allowed="$HOME/.config/git/allowed_signers"
setup_marker="$HOME/.ssh/.lfg-setup-done"

# ── Dry-run branch: inspect only ────────────────────────────────────────────

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    if [[ ! -f "$key" ]]; then
        echo "SSH key: would generate ed25519 at $key"
    else
        echo "SSH key: exists at $key"
    fi

    if [[ -f "$pub" ]]; then
        line="$DOTS_GIT_EMAIL $(awk '{print $1, $2}' "$pub")"
        if [[ ! -f "$allowed" ]] || ! grep -qxF "$line" "$allowed" 2>/dev/null; then
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

# ── Always-run: keygen, agent, allowed_signers ──────────────────────────────

mkdir -p "$HOME/.ssh" "$HOME/.config/git"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$key" ]]; then
    printf '\nNo SSH key at %s — generating ed25519 keypair (no passphrase).\n' "$key"
    printf 'To add a passphrase later: ssh-keygen -p -f %s\n\n' "$key"
    ssh-keygen -t ed25519 -C "$DOTS_GIT_EMAIL" -f "$key" -N ""
fi

if [[ "$(uname)" == "Darwin" ]]; then
    ssh-add --apple-use-keychain "$key" 2>/dev/null || true
else
    ssh-add "$key" 2>/dev/null || true
fi

touch "$allowed"
line="$DOTS_GIT_EMAIL $(awk '{print $1, $2}' "$pub")"
if ! grep -qxF "$line" "$allowed"; then
    echo "$line" >> "$allowed"
    echo "Added pubkey to $allowed"
fi

# ── First-run only: gh upload + ssh-copy-id ─────────────────────────────────

if [[ -f "$setup_marker" ]]; then
    exit 0
fi

# Upload to GitHub
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    host=$(hostname -s)
    echo "Uploading pubkey to GitHub as auth + signing key ($host)"
    gh ssh-key add "$pub" --title "$host" --type authentication 2>/dev/null || true
    gh ssh-key add "$pub" --title "$host" --type signing 2>/dev/null || true
else
    printf '\n────────────────────────────────────────────────────────────\n'
    printf 'gh not installed or not authenticated. Install: ./lfg install\n'
    printf 'Then add this pubkey to GitHub (as BOTH authentication and signing key):\n'
    printf '  https://github.com/settings/ssh/new\n\n'
    cat "$pub"
    printf '────────────────────────────────────────────────────────────\n\n'
fi

# Offer to copy pubkey to remote hosts
if { true </dev/tty; } 2>/dev/null; then
    printf '\nCopy this pubkey to a remote host via ssh-copy-id?\n'
    printf "Enter 'user@host' (blank to skip): "
    read -r target </dev/tty
    while [[ -n "$target" ]]; do
        if ssh-copy-id "$target" </dev/tty; then
            echo "Copied pubkey to $target"
        else
            echo "Failed to copy to $target"
        fi
        printf "Another host? (blank to finish): "
        read -r target </dev/tty
    done
fi

# Mark setup as done
touch "$setup_marker"
