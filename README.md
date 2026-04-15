# lfg

A dotfile and machine setup tool. Deploy configs, install software, track drift, and keep multiple machines in sync.

## Getting started

### Prerequisites

- macOS or Linux (tested on macOS Sequoia, Ubuntu 22.04)
- `bash`, `git`, `curl`
- macOS: [Homebrew](https://brew.sh) installed first
- Linux: sudo rights for `apt`
- A GitHub account (the `git` install hook auto-registers your SSH key with GitHub via `gh`)

### Walkthrough

**1. Clone the repo**

```bash
git clone https://github.com/jimbo7ron/lfg.git ~/lfg
cd ~/lfg
```

**2. Install software**

```bash
./lfg install
```

Installs `vim`, `tmux`, `ripgrep`, `fzf`, `jq`, `git`, `gh`, `node`, `python3`. Skip if you've installed these another way.

**3. Authenticate `gh` (recommended)**

```bash
gh auth login
```

Lets the `git` install hook auto-register your SSH key with GitHub. Without it the hook prints the key and a manual-upload URL — you can do it later.

**4. (Optional) Create `machine.conf` for per-machine overrides**

```bash
cp machine.conf.example machine.conf
```

Edit to override anything in `defaults.conf` — typically `DOTS_GIT_NAME`, `DOTS_GIT_EMAIL`, `DOTS_HOSTNAME`. Skip if the defaults work.

**5. Preview the deploy**

```bash
./lfg config --dry-run
```

Shows every file that would be created or changed. Hooks don't run in dry-run.

**6. Deploy**

```bash
./lfg config
```

On a fresh machine:
- Existing dotfiles get backed up under `backups/<timestamp>/`
- 8 packages deploy: `bash`, `claude`, `git`, `hostname`, `ssh`, `tmux`, `vim`, `zsh`
- The `git` hook generates `~/.ssh/id_ed25519` if missing, loads it into ssh-agent (Keychain-backed on macOS), appends the pubkey to `~/.config/git/allowed_signers`, and uploads to GitHub as auth + signing key
- The `git` hook then offers an interactive `ssh-copy-id` prompt — enter `user@host` to push the key to a remote, or blank to skip
- The `claude` hook installs Claude Code natively via the official installer (`curl -fsSL https://claude.ai/install.sh | bash`) if `claude` isn't already on `PATH`
- The `vim` hook downloads the dracula colorscheme into `~/.vim/{colors,autoload}/`
- The `hostname` hook applies `DOTS_HOSTNAME` if set (prompts for sudo)

**7. Verify**

```bash
git log --show-signature -1     # commit signing works (after your next commit)
gh ssh-key list                  # the key is registered (auth + signing)
ssh-add -l                       # key is loaded in the agent
./lfg verify                     # no drift between repo and deployed files
```

Subsequent `./lfg config` runs are idempotent — no re-keygen, no duplicate `allowed_signers` entries, no re-upload to GitHub.

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
--diff          Show full unified diff for drifted files (verify only)
--losses        Show only lines that would be lost on deploy (verify only)
-v, --version   Show version
-h, --help      Show help
```

### Checking what you'd lose before deploying

Before running `./lfg config`, see what live edits would be overwritten:

```bash
./lfg verify --losses           # show only lines that would disappear on deploy
./lfg verify --diff             # full unified diff for any drifted file
./lfg verify zsh --losses       # scope to one package
```

`--losses` prints each drifted file followed by the lines that exist in your live `$HOME` copy but won't be in the deployed version — exactly what you'd lose. Use it before any `./lfg config` to catch local edits you forgot to capture into the templates (see [Capturing config changes back into the repo](#capturing-config-changes-back-into-the-repo)).

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
    install.sh            -> downloads dracula colorscheme
  git/
    .gitconfig.tmpl       -> ~/.gitconfig (template)
    install.sh            -> SSH keygen, agent load, allowed_signers, gh upload
  ssh/
    .ssh/config           -> ~/.ssh/config
  claude/
    .claude/settings.json.tmpl -> ~/.claude/settings.json
    install.sh            -> installs native Claude Code + sets ~/.claude perms
  tmux/
    .tmux.conf.tmpl       -> ~/.tmux.conf
  bash/
    .bashrc.tmpl          -> ~/.bashrc
  hostname/
    install.sh            -> applies DOTS_HOSTNAME if set (no deployed files)
```

- **Plain files** are copied as-is.
- **`.tmpl` files** have `{{VAR}}` placeholders replaced with values from config before deploying. The `.tmpl` suffix is stripped in the deployed path.
- **`install.sh`** at the package root runs after the package is deployed. Hooks run in a subshell with stdin redirected to `/dev/null` so interactive commands can't consume the package loop's stdin; hooks that need to prompt read from `/dev/tty` directly.
- **Hook dry-run contract**: install hooks are *also* run under `./lfg config --dry-run`, with `DRY_RUN=true` exported. Hooks must branch on `DRY_RUN` at the top, inspect current state, print what they *would* change, and `exit 0` before doing anything destructive. This makes every mutation visible in the dry-run preview.

### Install hooks

| Package | What the hook does |
|---------|-------------------|
| `git` | Generates `~/.ssh/id_ed25519` if missing, loads into ssh-agent (Keychain-backed on macOS), appends pubkey to `~/.config/git/allowed_signers`, uploads to GitHub as auth + signing key via `gh` if authenticated, and optionally runs `ssh-copy-id` to remote hosts you enter interactively |
| `claude` | Sets `~/.claude` to `chmod 700`; installs Claude Code natively via `curl -fsSL https://claude.ai/install.sh \| bash` if `claude` isn't already on `PATH` |
| `vim` | Downloads the dracula colorscheme (referenced by `.vimrc`) into `~/.vim/colors/` and `~/.vim/autoload/` if missing |
| `hostname` | If `DOTS_HOSTNAME` is set and differs from the current hostname, applies it via `scutil` (macOS) or `hostnamectl` (Linux). Requires sudo and a tty. No-op otherwise |

All hooks are idempotent — they detect existing state and skip.

### Template variables

Variables are defined in `defaults.conf` (committed) and optionally overridden in `machine.conf` (gitignored, per-machine). All variables use the `DOTS_` prefix. In templates, reference them without the prefix:

| Variable | Template | Default |
|----------|----------|---------|
| `DOTS_GIT_NAME` | `{{GIT_NAME}}` | `James Morris` |
| `DOTS_GIT_EMAIL` | `{{GIT_EMAIL}}` | `james.s.morris@gmail.com` |
| `DOTS_GIT_CREDENTIAL_HELPER` | `{{GIT_CREDENTIAL_HELPER}}` | `osxkeychain` |
| `DOTS_EDITOR` | `{{EDITOR}}` | `vim` |
| `DOTS_SHELL` | `{{SHELL}}` | `zsh` |
| `DOTS_TERM` | `{{TERM}}` | `xterm-256color` |
| `DOTS_ZSH_THEME` | `{{ZSH_THEME}}` | `robbyrussell` |
| `DOTS_ZSH_PLUGINS` | `{{ZSH_PLUGINS}}` | `git docker z` |
| `DOTS_TMUX_PREFIX` | `{{TMUX_PREFIX}}` | `C-b` |
| `DOTS_TMUX_SHELL` | `{{TMUX_SHELL}}` | `/bin/zsh` |
| `DOTS_HISTSIZE` | `{{HISTSIZE}}` | `10000` |
| `DOTS_CLAUDE_MODEL` | `{{CLAUDE_MODEL}}` | `claude-sonnet-4-6` |
| `DOTS_CLAUDE_PERMISSIONS_ALLOW` | `{{CLAUDE_PERMISSIONS_ALLOW}}` | 11-entry list incl. `Bash(*)`, `Agent`, `Skill`, `NotebookEdit` |
| `DOTS_HOSTNAME` | *(not templated; read by hostname hook)* | `""` — empty means hostname is left untouched; override in `machine.conf` |

`GIT_NAME` and `GIT_EMAIL` are required — lfg will error if they are empty when deploying templates that use them. They have sensible defaults in `defaults.conf` so new machines work out of the box; override in `machine.conf` if needed.

The Claude settings template also hardcodes structured `permissions.deny` and `permissions.ask` lists: hard blocks for catastrophic git/filesystem ops (force-push to main, `rm -rf /`, `git reset --hard`, `mkfs`, `fdisk`), and confirmation prompts for publishing (`npm publish`, `pip upload`), privileged ops (`chown`, `diskutil`, `mount`), destructive docker subcommands, destructive AWS operations, and destructive `gh` commands.

### Machine config

`defaults.conf` (committed) holds every `DOTS_*` variable with its default. To override on a specific machine, create `machine.conf` (gitignored) next to it and redefine just the variables you care about:

```bash
cat > machine.conf <<'EOF'
DOTS_HOSTNAME="mbp-james"
DOTS_GIT_EMAIL="you@example.com"
EOF
```

`machine.conf` is sourced after `defaults.conf`, so its values win. Per-machine values never leak into the repo.

### Backups

Before overwriting any file, lfg creates a timestamped backup under `backups/`. Use `--no-backup` to skip, or restore with:

```bash
./lfg restore 2024-01-15T10-30-00
```

### Software installation

Software manifests live in `software/`:

- `brew.txt` — Homebrew packages (macOS)
- `apt.txt` — APT packages (Linux)
- `common.sh` — Cross-platform installs (runs after the package manager)

Default manifest includes `vim`, `tmux`, `ripgrep`, `fzf`, `jq`, `git`, `gh`, `node`/`nodejs`, `python3`. `gh` is required for the git package's install hook to auto-upload SSH keys to GitHub; without it the hook falls back to printing the key and a manual upload URL.

## Adding a new package

```bash
./lfg add mypackage
```

Then add your dotfiles under `packages/mypackage/`, mirroring the `$HOME` structure. Use `.tmpl` for files that need variable substitution.

## Capturing config changes back into the repo

You'll edit live dotfiles in `$HOME` from time to time and want those changes back in lfg. The flow depends on file type.

### Plain files (e.g. `.vimrc`, `.ssh/config`)

`./lfg save` copies the live file back into the package automatically:

```bash
vim ~/.vimrc                    # edit live
./lfg save vim                  # copies ~/.vimrc → packages/vim/.vimrc
./lfg save vim --push           # same, then git commit + push
```

### Template files (e.g. `.zshrc.tmpl`, `.gitconfig.tmpl`, `.claude/settings.json.tmpl`)

`./lfg save` does **not** auto-update templates — it only warns `Template drift in X — update the .tmpl file manually`. Reason: lfg can't tell which parts of your live edit should be templated as `{{VAR}}` vs hardcoded.

Manual flow:

```bash
vim ~/.zshrc                    # edit live

# 1. See what's different vs the rendered template
diff <(bash -c 'source defaults.conf; source lib/helpers.sh; \
  process_template packages/zsh/.zshrc.tmpl') ~/.zshrc

# 2. Edit the template to incorporate the diff
vim packages/zsh/.zshrc.tmpl

# 3. Confirm it now renders identically
diff <(bash -c 'source defaults.conf; source lib/helpers.sh; \
  process_template packages/zsh/.zshrc.tmpl') ~/.zshrc && echo OK

# 4. Commit + push
git add packages/zsh/.zshrc.tmpl
git commit -m "zsh: <what you added>"
git push
```

### Adding a new variable (per-machine value)

If your new setting should differ between machines (path, hostname, identity):

1. Add `DOTS_NEWVAR="default"` to `defaults.conf`
2. Reference it as `{{NEWVAR}}` in the template (or read it directly in an install hook, like `DOTS_HOSTNAME`)
3. Optionally override in `machine.conf` on the hosts that need a different value
4. Add a row to the variables table in this README

## Security

- Sensitive files (`.ssh/*`, `.gitconfig`, `.claude/*`) are deployed with `chmod 600`; directories with `chmod 700`.
- `machine.conf` is gitignored to keep per-machine credentials out of version control.
- Backup directories are created with `chmod 700`.
- Install hooks run in a subshell with stdin pinned to `/dev/null`, isolating them from the package loop and preventing commands like `ssh-keygen` from consuming package names as passphrase input.
- Generated SSH keys use ed25519, stored at `~/.ssh/id_ed25519` with `chmod 600`; `~/.ssh` is enforced to `chmod 700`.
- Commit signing (`gpg.format = ssh`, `commit.gpgsign = true`) is enabled by default in the git template; the install hook adds your generated pubkey to `~/.config/git/allowed_signers` so `git log --show-signature` verifies locally.
- Claude settings ship with structured `permissions.deny`/`permissions.ask` guardrails for catastrophic ops.
- `save --push` only stages files that were actually saved (not `git add -A`).
- Template `save` refuses to bake secrets into the repo — warns about drift instead.
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
