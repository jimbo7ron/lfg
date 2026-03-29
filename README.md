# lfg

A dotfile and machine setup tool. Deploy configs, install software, track drift, and keep multiple machines in sync.

## Quick start

```bash
git clone https://github.com/jimbo7ron/lfg.git ~/lfg
cd ~/lfg
cp machine.conf.example machine.conf   # edit with your details
./lfg config                            # deploy all dotfiles
./lfg install                           # install system software
```

## Commands

| Command | Description |
|---------|-------------|
| `config [pkgs...]` | Deploy dotfile configs (all if none specified) |
| `install [pkgs...]` | Install system software via brew (macOS) or apt (Linux) |
| `save [pkgs...]` | Copy deployed dotfiles back into the repo |
| `verify [pkgs...]` | Check for drift between deployed files and repo |
| `update` | Pull remote changes and re-apply configs |
| `restore <timestamp>` | Restore configs from a backup |
| `add <name>` | Scaffold a new dotfile package |
| `list` | Show available packages and status |

### Options

```
--dry-run       Preview changes without applying
--no-backup     Skip backup step (config only)
--push          Commit and push after save
-v, --version   Show version
-h, --help      Show help
```

### Examples

```bash
./lfg config zsh vim        # deploy only zsh and vim
./lfg config --dry-run      # preview what would change
./lfg verify                # check all packages for drift
./lfg save zsh --push       # save local zsh changes, commit, push
./lfg install ripgrep fzf   # install specific packages
```

## How it works

### Packages

Each directory under `packages/` is a package. Files inside mirror the `$HOME` directory structure:

```
packages/
  zsh/
    .zshrc.tmpl           -> ~/.zshrc (template, processed)
  vim/
    .vimrc                -> ~/.vimrc (plain copy)
  git/
    .gitconfig.tmpl       -> ~/.gitconfig (template)
  ssh/
    .ssh/config           -> ~/.ssh/config
  claude/
    .claude/settings.json.tmpl -> ~/.claude/settings.json
    install.sh            -> runs after deploy (hook)
  tmux/
    .tmux.conf.tmpl       -> ~/.tmux.conf
  bash/
    .bashrc.tmpl          -> ~/.bashrc
```

- **Plain files** are copied as-is.
- **`.tmpl` files** have `{{VAR}}` placeholders replaced with values from config before deploying. The `.tmpl` suffix is stripped in the deployed path.
- **`install.sh`** at the package root runs after the package is deployed (skipped in dry-run). Hooks run in a subshell for isolation.

### Template variables

Variables are defined in `defaults.conf` (committed) and optionally overridden in `machine.conf` (gitignored, per-machine). All variables use the `DOTS_` prefix. In templates, reference them without the prefix:

| Variable | Template | Default |
|----------|----------|---------|
| `DOTS_GIT_NAME` | `{{GIT_NAME}}` | *(empty -- set in machine.conf)* |
| `DOTS_GIT_EMAIL` | `{{GIT_EMAIL}}` | *(empty -- set in machine.conf)* |
| `DOTS_GIT_CREDENTIAL_HELPER` | `{{GIT_CREDENTIAL_HELPER}}` | `osxkeychain` |
| `DOTS_EDITOR` | `{{EDITOR}}` | `vim` |
| `DOTS_SHELL` | `{{SHELL}}` | `zsh` |
| `DOTS_TERM` | `{{TERM}}` | `xterm-256color` |
| `DOTS_ZSH_THEME` | `{{ZSH_THEME}}` | `robbyrussell` |
| `DOTS_ZSH_PLUGINS` | `{{ZSH_PLUGINS}}` | `git docker z` |
| `DOTS_TMUX_PREFIX` | `{{TMUX_PREFIX}}` | `C-b` |
| `DOTS_TMUX_SHELL` | `{{TMUX_SHELL}}` | `/bin/zsh` |
| `DOTS_HISTSIZE` | `{{HISTSIZE}}` | `10000` |
| `DOTS_PATH_EXTRA` | `{{PATH_EXTRA}}` | *(empty)* |
| `DOTS_CLAUDE_MODEL` | `{{CLAUDE_MODEL}}` | `claude-sonnet-4-6` |
| `DOTS_CLAUDE_PERMISSIONS_ALLOW` | `{{CLAUDE_PERMISSIONS_ALLOW}}` | `["Read", "Edit", ...]` |

`GIT_NAME` and `GIT_EMAIL` are required -- lfg will error if they are empty when deploying templates that use them.

### Machine config

Copy the example and customize for each machine:

```bash
cp machine.conf.example machine.conf
```

`machine.conf` is gitignored so per-machine values (name, email, credential helper) never leak into the repo.

### Backups

Before overwriting any file, lfg creates a timestamped backup under `backups/`. Use `--no-backup` to skip, or restore with:

```bash
./lfg restore 2024-01-15T10-30-00
```

### Software installation

Software manifests live in `software/`:

- `brew.txt` -- Homebrew packages (macOS)
- `apt.txt` -- APT packages (Linux)
- `common.sh` -- Cross-platform installs (runs after the package manager)

## Adding a new package

```bash
./lfg add mypackage
```

Then add your dotfiles under `packages/mypackage/`, mirroring the `$HOME` structure. Use `.tmpl` for files that need variable substitution.

## Security

- Sensitive files (`.ssh/*`, `.gitconfig`, `.claude/*`) are deployed with `chmod 600`; directories with `chmod 700`.
- `machine.conf` is gitignored to keep credentials out of version control.
- Backup directories are created with `chmod 700`.
- Install hooks run in a subshell, isolated from the parent process.
- `save --push` only stages files that were actually saved (not `git add -A`).
- Template `save` refuses to bake secrets into the repo -- warns about drift instead.
- Package names and restore timestamps are validated against path traversal.

## Testing

Tests run in Docker (Ubuntu 22.04, non-root user):

```bash
./test/run_docker.sh
```

Or directly (uses your real `$HOME` -- be careful):

```bash
bash test/run_tests.sh
```

CI runs automatically on push via GitHub Actions.

## Project structure

```
lfg                     Main script
lib/helpers.sh          All helper functions
defaults.conf           Default variable values (committed)
machine.conf.example    Template for per-machine overrides
machine.conf            Per-machine overrides (gitignored)
packages/               Dotfile packages (one dir per package)
software/               Software manifests (brew.txt, apt.txt, common.sh)
backups/                Timestamped backups (gitignored)
test/                   Test suite and Docker harness
```

## License

MIT
