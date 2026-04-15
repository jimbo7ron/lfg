#!/usr/bin/env bash
# Claude package install hook — lock down config dir perms and ensure the
# native Claude Code install is the one on PATH. Removes any npm-global
# non-native install first, then runs the official installer if missing.
# Dry-run aware.
set -euo pipefail

native_path="$HOME/.local/bin/claude"

has_npm_global_claude() {
    command -v npm >/dev/null 2>&1 && \
        npm ls -g --depth=0 2>/dev/null | grep -q '@anthropic-ai/claude-code'
}

# ── Dry-run branch: inspect only ────────────────────────────────────────────

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    mode=$(stat -f '%Lp' "$HOME/.claude" 2>/dev/null || stat -c '%a' "$HOME/.claude" 2>/dev/null || echo "?")
    if [[ "$mode" != "700" ]]; then
        echo "~/.claude: would chmod 700 (currently $mode)"
    else
        echo "~/.claude: already chmod 700"
    fi

    if has_npm_global_claude; then
        echo "claude CLI: would uninstall npm-global @anthropic-ai/claude-code"
    fi

    if [[ -x "$native_path" ]]; then
        echo "claude CLI: native install present at $native_path"
    else
        echo "claude CLI: would install native via curl -fsSL https://claude.ai/install.sh | bash"
    fi
    exit 0
fi

# ── Real install path ───────────────────────────────────────────────────────

chmod 700 "$HOME/.claude" 2>/dev/null || true

# Remove any non-native npm-global install so PATH doesn't shadow the native
# one. If `npm uninstall` fails (e.g. stale `.claude-code-*` temp dir from a
# previous interrupted uninstall left behind by npm's remove-by-rename), fall
# back to rm -rf on the known npm prefix paths.
if has_npm_global_claude; then
    echo "Removing npm-global @anthropic-ai/claude-code (non-native)"
    if ! npm uninstall -g @anthropic-ai/claude-code 2>/dev/null; then
        echo "npm uninstall failed — removing files directly"
        npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
        rm -rf \
            "$npm_prefix/lib/node_modules/@anthropic-ai/claude-code" \
            "$npm_prefix/lib/node_modules/@anthropic-ai/.claude-code-"* \
            "$npm_prefix/bin/claude" 2>/dev/null || true
        # Retry so npm's own metadata is also cleared
        npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    fi
fi

# Install native if not present
if [[ ! -x "$native_path" ]]; then
    echo "Installing Claude Code (native, official installer)"
    curl -fsSL https://claude.ai/install.sh | bash
fi
