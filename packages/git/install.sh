#!/usr/bin/env bash
# Git package install hook — set up SSH signing key and allowed_signers.
# Idempotent: generates the keypair only if missing, appends to
# allowed_signers only if absent, uploads to GitHub only if not already there.
set -euo pipefail

key="$HOME/.ssh/id_ed25519"
pub="$key.pub"

mkdir -p "$HOME/.ssh" "$HOME/.config/git"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$key" ]]; then
    printf '\nNo SSH key at %s — generating ed25519 keypair (no passphrase).\n' "$key"
    printf 'To add a passphrase later: ssh-keygen -p -f %s\n\n' "$key"
    ssh-keygen -t ed25519 -C "$DOTS_GIT_EMAIL" -f "$key" -N ""
fi

# Load into agent (macOS stores passphrase in Keychain, Linux just adds).
if [[ "$(uname)" == "Darwin" ]]; then
    ssh-add --apple-use-keychain "$key" 2>/dev/null || true
else
    ssh-add "$key" 2>/dev/null || true
fi

# Append this machine's pubkey to allowed_signers if not already present.
allowed="$HOME/.config/git/allowed_signers"
touch "$allowed"
line="$DOTS_GIT_EMAIL $(awk '{print $1, $2}' "$pub")"
if ! grep -qxF "$line" "$allowed"; then
    echo "$line" >> "$allowed"
    echo "Added pubkey to $allowed"
fi

# Upload to GitHub if gh is authed and the key isn't already registered.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    pub_data=$(awk '{print $2}' "$pub")
    if ! gh ssh-key list 2>/dev/null | grep -q "$pub_data"; then
        host=$(hostname -s)
        echo "Uploading pubkey to GitHub as auth + signing key ($host)"
        gh ssh-key add "$pub" --title "$host" --type authentication || true
        gh ssh-key add "$pub" --title "$host" --type signing || true
    fi
else
    printf '\n────────────────────────────────────────────────────────────\n'
    printf 'gh not installed or not authenticated. Install: ./lfg install\n'
    printf 'Then add this pubkey to GitHub (as BOTH authentication and signing key):\n'
    printf '  https://github.com/settings/ssh/new\n\n'
    cat "$pub"
    printf '────────────────────────────────────────────────────────────\n\n'
fi

# Offer to copy pubkey to remote hosts via ssh-copy-id. Read directly from
# /dev/tty so this works even when the hook's own stdin is /dev/null; skip
# silently if there's no controlling terminal.
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
