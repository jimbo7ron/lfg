# CLAUDE.md

## Project overview

lfg ("Let's F***ing Go") is a bash dotfile and machine setup tool. It deploys config files from `packages/` to `$HOME`, supports `{{VAR}}` template substitution, installs system software via brew/apt, and tracks drift.

## Key conventions

- All shell scripts use `set -euo pipefail`
- Template variables use `DOTS_` prefix in config, referenced as `{{VAR}}` (without prefix) in `.tmpl` files
- Install hooks must live at `packages/<name>/install.sh` (package root, not nested)
- Hooks run in a subshell `( source "$hook" )` for isolation
- Files are copied, not symlinked
- `machine.conf` is gitignored and per-machine; `defaults.conf` is committed
- Empty arrays use `${arr[@]+"${arr[@]}"}` pattern for `set -u` compatibility

## Testing

```bash
# Run tests locally (uses temp $HOME)
TEMP_HOME=$(mktemp -d)
cp -r . "$TEMP_HOME/lfg"
printf 'DOTS_GIT_NAME="Test User"\nDOTS_GIT_EMAIL="test@example.com"\nDOTS_GIT_CREDENTIAL_HELPER="cache"\n' > "$TEMP_HOME/lfg/machine.conf"
cd "$TEMP_HOME/lfg" && git init && git add -A && git commit -m "init"
chmod +x lfg software/common.sh packages/claude/install.sh test/run_tests.sh
HOME="$TEMP_HOME" bash test/run_tests.sh

# Or via Docker
./test/run_docker.sh
```

Tests must pass before committing. CI runs on GitHub Actions (Ubuntu).

## File layout

- `lfg` -- entry point, argument parsing, command dispatch
- `lib/helpers.sh` -- all helper functions (template processing, file ops, backup, etc.)
- `defaults.conf` -- default `DOTS_*` variable values
- `packages/<name>/` -- dotfile packages, files mirror `$HOME` structure
- `test/run_tests.sh` -- test suite (53 assertions)
