#!/usr/bin/env bash
# test/run_tests.sh -- Test suite for lfg
set -euo pipefail

LFG="$HOME/lfg/lfg"
PASS=0
FAIL=0
TOTAL=0

# ── Test Helpers ─────────────────────────────────────────────────────────────

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf '\033[0;32m  ✓ %s\033[0m\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf '\033[0;31m  ✗ %s\033[0m\n' "$1"
    [[ -n "${2:-}" ]] && printf '    %s\n' "$2"
}

section() {
    printf '\n\033[1;36m── %s ──\033[0m\n' "$1"
}

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2" "File not found: $1"
    fi
}

assert_file_not_exists() {
    if [[ ! -f "$1" ]]; then
        pass "$2"
    else
        fail "$2" "File should not exist: $1"
    fi
}

assert_file_contains() {
    if grep -q "$2" "$1" 2>/dev/null; then
        pass "$3"
    else
        fail "$3" "File $1 does not contain: $2"
    fi
}

assert_file_not_contains() {
    if ! grep -q "$2" "$1" 2>/dev/null; then
        pass "$3"
    else
        fail "$3" "File $1 should not contain: $2"
    fi
}

assert_not_symlink() {
    if [[ -f "$1" && ! -L "$1" ]]; then
        pass "$2"
    else
        if [[ -L "$1" ]]; then
            fail "$2" "File is a symlink (should be a copy): $1"
        else
            fail "$2" "File not found: $1"
        fi
    fi
}

assert_exit_code() {
    local expected="$1"
    shift
    local actual
    set +e
    "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
        pass "Exit code $expected: $*"
    else
        fail "Exit code $expected: $*" "Got exit code: $actual"
    fi
}

assert_output_contains() {
    local pattern="$1"
    shift
    local output
    set +e
    output=$("$@" 2>&1)
    set -e
    if echo "$output" | grep -q "$pattern"; then
        pass "Output contains '$pattern': $*"
    else
        fail "Output contains '$pattern': $*" "Output was: $(echo "$output" | head -5)"
    fi
}

# ── Clean State ──────────────────────────────────────────────────────────────

clean_home() {
    rm -f "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.vimrc" "$HOME/.tmux.conf" "$HOME/.gitconfig"
    rm -rf "$HOME/.ssh/config" "$HOME/.claude/settings.json"
    rm -rf "$HOME/lfg/backups"/*
}

# ══════════════════════════════════════════════════════════════════════════════
# TESTS
# ══════════════════════════════════════════════════════════════════════════════

printf '\033[1;33m\n╔══════════════════════════════════════╗\n║      lfg test suite                  ║\n╚══════════════════════════════════════╝\033[0m\n'

# ── Test 1: Help / Usage ────────────────────────────────────────────────────

section "Help & Usage"

assert_output_contains "Usage" "$LFG"
assert_output_contains "config" "$LFG" --help
assert_output_contains "install" "$LFG" --help
assert_output_contains "save" "$LFG" --help
assert_output_contains "verify" "$LFG" --help

# ── Test 2: List ─────────────────────────────────────────────────────────────

section "List"

output=$("$LFG" list 2>&1)
for pkg in zsh bash vim tmux git ssh claude; do
    if echo "$output" | grep -q "$pkg"; then
        pass "list shows package: $pkg"
    else
        fail "list shows package: $pkg"
    fi
done

# ── Test 3: Config Dry Run ───────────────────────────────────────────────────

section "Config Dry Run"

clean_home

output=$("$LFG" config --dry-run 2>&1)
if echo "$output" | grep -q "Dry run"; then
    pass "config --dry-run shows dry run message"
else
    fail "config --dry-run shows dry run message"
fi

# Verify no files were created
assert_file_not_exists "$HOME/.zshrc" "dry-run does not create .zshrc"
assert_file_not_exists "$HOME/.gitconfig" "dry-run does not create .gitconfig"

# ── Test 4: Config Single Package Dry Run ────────────────────────────────────

section "Config Single Package"

clean_home

output=$("$LFG" config vim --dry-run 2>&1)
if echo "$output" | grep -qi "vim"; then
    pass "config vim --dry-run mentions vim"
else
    fail "config vim --dry-run mentions vim"
fi
assert_file_not_exists "$HOME/.vimrc" "dry-run vim does not create .vimrc"

# ── Test 5: Config Install ──────────────────────────────────────────────────

section "Config Install"

clean_home

"$LFG" config 2>&1

# Check all config files were created
assert_file_exists "$HOME/.zshrc" "config creates .zshrc"
assert_file_exists "$HOME/.bashrc" "config creates .bashrc"
assert_file_exists "$HOME/.vimrc" "config creates .vimrc"
assert_file_exists "$HOME/.tmux.conf" "config creates .tmux.conf"
assert_file_exists "$HOME/.gitconfig" "config creates .gitconfig"
assert_file_exists "$HOME/.ssh/config" "config creates .ssh/config"
assert_file_exists "$HOME/.claude/settings.json" "config creates .claude/settings.json"

# Verify files are copies, not symlinks
assert_not_symlink "$HOME/.zshrc" ".zshrc is a copy, not symlink"
assert_not_symlink "$HOME/.gitconfig" ".gitconfig is a copy, not symlink"
assert_not_symlink "$HOME/.claude/settings.json" "settings.json is a copy, not symlink"

# ── Test 6: Template Substitution ────────────────────────────────────────────

section "Template Substitution"

# Check that {{VAR}} placeholders were replaced
assert_file_not_contains "$HOME/.zshrc" "{{ZSH_THEME}}" "zshrc: ZSH_THEME resolved"
assert_file_contains "$HOME/.zshrc" "robbyrussell" "zshrc: ZSH_THEME = robbyrussell"

assert_file_not_contains "$HOME/.gitconfig" "{{GIT_NAME}}" "gitconfig: GIT_NAME resolved"
assert_file_contains "$HOME/.gitconfig" "Test User" "gitconfig: GIT_NAME = Test User"
assert_file_contains "$HOME/.gitconfig" "test@example.com" "gitconfig: GIT_EMAIL from machine.conf"
assert_file_contains "$HOME/.gitconfig" "cache" "gitconfig: GIT_CREDENTIAL_HELPER = cache (linux)"

assert_file_not_contains "$HOME/.claude/settings.json" "{{CLAUDE_MODEL}}" "claude: CLAUDE_MODEL resolved"

# Check plain files (no .tmpl) are copied as-is
assert_file_contains "$HOME/.vimrc" "syntax on" "vimrc: plain file copied correctly"
assert_file_contains "$HOME/.vimrc" "colorscheme dracula" "vimrc: content preserved"

# ── Test 7: Backup Created ───────────────────────────────────────────────────

section "Backup"

# Deploy once to create files
clean_home
echo "original content" > "$HOME/.vimrc"

"$LFG" config vim 2>&1

# Check backup was created
backup_count=$(find "$HOME/lfg/backups" -name ".vimrc" -type f 2>/dev/null | wc -l)
if [[ "$backup_count" -gt 0 ]]; then
    pass "backup created for existing .vimrc"
else
    fail "backup created for existing .vimrc"
fi

# Check backup content
backup_file=$(find "$HOME/lfg/backups" -name ".vimrc" -type f 2>/dev/null | head -1)
if [[ -n "$backup_file" ]] && grep -q "original content" "$backup_file"; then
    pass "backup contains original content"
else
    fail "backup contains original content"
fi

# ── Test 8: No Backup Flag ──────────────────────────────────────────────────

section "No Backup Flag"

rm -rf "$HOME/lfg/backups"/*
echo "will be overwritten" > "$HOME/.vimrc"

"$LFG" config vim --no-backup 2>&1

backup_count=$(find "$HOME/lfg/backups" -type f 2>/dev/null | wc -l)
if [[ "$backup_count" -eq 0 ]]; then
    pass "--no-backup skips backup"
else
    fail "--no-backup skips backup" "Found $backup_count backup files"
fi

# ── Test 9: Verify (No Drift) ───────────────────────────────────────────────

section "Verify"

clean_home
"$LFG" config 2>&1

output=$("$LFG" verify 2>&1)
if echo "$output" | grep -q "OK"; then
    pass "verify shows OK when no drift"
else
    fail "verify shows OK when no drift"
fi

# ── Test 10: Verify (With Drift) ────────────────────────────────────────────

section "Verify (Drift)"

echo "# I changed this" >> "$HOME/.vimrc"

output=$("$LFG" verify vim 2>&1)
if echo "$output" | grep -q "Drift"; then
    pass "verify detects drift in .vimrc"
else
    fail "verify detects drift in .vimrc"
fi

# ── Test 11: Save ────────────────────────────────────────────────────────────

section "Save"

# Make a local change
echo "# added locally" >> "$HOME/.vimrc"

"$LFG" save vim 2>&1

# Check repo file was updated
assert_file_contains "$HOME/lfg/packages/vim/.vimrc" "added locally" "save copies local changes back to repo"

# ── Test 12: Save Dry Run ───────────────────────────────────────────────────

section "Save Dry Run"

# Make another change
echo "# another change" >> "$HOME/.vimrc"
repo_before=$(<"$HOME/lfg/packages/vim/.vimrc")

"$LFG" save vim --dry-run 2>&1

repo_after=$(<"$HOME/lfg/packages/vim/.vimrc")
if [[ "$repo_before" == "$repo_after" ]]; then
    pass "save --dry-run does not modify repo"
else
    fail "save --dry-run does not modify repo"
fi

# ── Test 13: Add Package ────────────────────────────────────────────────────

section "Add Package"

"$LFG" add neovim 2>&1

if [[ -d "$HOME/lfg/packages/neovim" ]]; then
    pass "add creates package directory"
else
    fail "add creates package directory"
fi

# Adding same package again should fail
set +e
output=$("$LFG" add neovim 2>&1)
exit_code=$?
set -e
if echo "$output" | grep -qi "already exists"; then
    pass "add rejects duplicate package"
else
    fail "add rejects duplicate package"
fi

# ── Test 14: Restore ────────────────────────────────────────────────────────

section "Restore"

clean_home
echo "before backup" > "$HOME/.vimrc"

# Install (creates backup of "before backup")
"$LFG" config vim 2>&1

# Get the backup timestamp
backup_ts=$(ls "$HOME/lfg/backups/" | head -1)

if [[ -n "$backup_ts" ]]; then
    # Now restore
    "$LFG" restore "$backup_ts" 2>&1

    if grep -q "before backup" "$HOME/.vimrc" 2>/dev/null; then
        pass "restore recovers original file"
    else
        fail "restore recovers original file"
    fi
else
    fail "restore recovers original file" "No backup found"
fi

# ── Test 15: Config Single Package Only ──────────────────────────────────────

section "Selective Install"

clean_home

"$LFG" config zsh 2>&1

assert_file_exists "$HOME/.zshrc" "config zsh creates .zshrc"
assert_file_not_exists "$HOME/.gitconfig" "config zsh does NOT create .gitconfig"
assert_file_not_exists "$HOME/.vimrc" "config zsh does NOT create .vimrc"

# ── Test 16: Multiple Packages ───────────────────────────────────────────────

clean_home

"$LFG" config zsh vim 2>&1

assert_file_exists "$HOME/.zshrc" "config zsh vim creates .zshrc"
assert_file_exists "$HOME/.vimrc" "config zsh vim creates .vimrc"
assert_file_not_exists "$HOME/.gitconfig" "config zsh vim does NOT create .gitconfig"

# ── Test 17: Install Software Dry Run ────────────────────────────────────────

section "Software"

output=$("$LFG" install --dry-run 2>&1)
if echo "$output" | grep -qi "install\|already"; then
    pass "install --dry-run lists packages"
else
    fail "install --dry-run lists packages"
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

printf '\n\033[1;33m╔══════════════════════════════════════╗\033[0m\n'
printf '\033[1;33m║\033[0m  Results: '
if [[ "$FAIL" -eq 0 ]]; then
    printf '\033[1;32m%d/%d passed\033[0m' "$PASS" "$TOTAL"
else
    printf '\033[1;31m%d/%d passed (%d failed)\033[0m' "$PASS" "$TOTAL" "$FAIL"
fi
printf '\n\033[1;33m╚══════════════════════════════════════╝\033[0m\n'

exit "$FAIL"
