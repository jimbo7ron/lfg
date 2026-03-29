#!/usr/bin/env bash
# Post-install hook for claude package

mkdir -p "$HOME/.claude"

# Basic JSON validation
settings="$HOME/.claude/settings.json"
if [[ -f "$settings" ]]; then
    open_braces=$(tr -cd '{[' < "$settings" | wc -c)
    close_braces=$(tr -cd '}]' < "$settings" | wc -c)
    if [[ "$open_braces" -ne "$close_braces" ]]; then
        log_warn "settings.json may have invalid JSON (mismatched braces/brackets)"
    else
        log_info "settings.json passes basic JSON validation"
    fi
fi
