#!/usr/bin/env bash
# lib/helpers.sh -- Shared functions for lfg

# ── Colours ──────────────────────────────────────────────────────────────────

# ANSI-C quoting ($'...') embeds the real ESC byte so colour codes work
# both in printf (which would interpret escapes itself) and in cat heredocs
# (which pass bytes through verbatim) — e.g. the usage() output.
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

log_info()  { printf "${GREEN}●${RESET} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}●${RESET} %s\n" "$*"; }
log_error() { printf "${RED}●${RESET} %s\n" "$*" >&2; }
log_blue()  { printf "${BLUE}●${RESET} %s\n" "$*"; }
log_header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

# ── Input Validation ─────────────────────────────────────────────────────────

validate_name() {
    local name="$1"
    local label="${2:-name}"
    if [[ "$name" =~ [/\\] || "$name" == ".." || "$name" == "." || -z "$name" ]]; then
        log_error "Invalid $label: $name"
        return 1
    fi
    return 0
}

# ── OS Detection ─────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Darwin) DOTFILES_OS="macos" ;;
        Linux)  DOTFILES_OS="linux" ;;
        *)      log_error "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
    export DOTFILES_OS
}

# ── Config Loading ───────────────────────────────────────────────────────────

load_config() {
    if [[ -f "$LFG_DIR/defaults.conf" ]]; then
        source "$LFG_DIR/defaults.conf"
    else
        log_error "defaults.conf not found"
        exit 1
    fi

    if [[ -f "$LFG_DIR/machine.conf" ]]; then
        source "$LFG_DIR/machine.conf"
        log_info "Loaded machine.conf overrides"
    fi
}

# ── Template Processing ──────────────────────────────────────────────────────

# Variables that should not be empty when deploying
REQUIRED_VARS="GIT_NAME GIT_EMAIL"

process_template() {
    local src="$1"
    local content
    content=$(<"$src")

    # Find all {{VAR}} references
    local var_refs
    var_refs=$(printf '%s' "$content" | grep -oE '\{\{[A-Za-z_][A-Za-z0-9_]*\}\}' | sort -u)

    local has_unresolved=0
    for var_ref in $var_refs; do
        # Strip {{ and }} to get the var name
        local var_name="${var_ref#\{\{}"
        var_name="${var_name%\}\}}"
        # Look up DOTS_<var_name>
        local env_var="DOTS_${var_name}"
        local var_value="${!env_var:-}"

        if [[ -z "$var_value" ]]; then
            # Check if this is a required variable
            if [[ " $REQUIRED_VARS " == *" $var_name "* ]]; then
                log_error "Required variable DOTS_${var_name} is empty — set it in machine.conf"
                has_unresolved=1
            else
                log_warn "Unresolved template variable: {{${var_name}}} in $(basename "$src")"
            fi
            continue
        fi

        # Replace all occurrences using bash string replacement.
        # Pattern and replacement are left unquoted inside the expansion:
        # nesting quotes here causes bash to inject literal "…" around the
        # replacement, producing e.g. ""vim"" instead of "vim".
        local pattern="{{${var_name}}}"
        content="${content//$pattern/$var_value}"
    done

    if [[ "$has_unresolved" -eq 1 ]]; then
        return 1
    fi

    printf '%s\n' "$content"
}

# ── Path Resolution ──────────────────────────────────────────────────────────

resolve_target_path() {
    local package_dir="$1"
    local file="$2"
    # Get path relative to package dir
    local rel="${file#"${package_dir}/"}"
    # Strip .tmpl suffix
    rel="${rel%.tmpl}"
    echo "$HOME/$rel"
}

# ── File Operations ──────────────────────────────────────────────────────────

ensure_parent_dir() {
    local dir
    dir="$(dirname "$1")"
    [[ -d "$dir" ]] || mkdir -p "$dir"
}

set_secure_permissions() {
    local dest="$1"
    local rel="${dest#"$HOME/"}"

    case "$rel" in
        .ssh/*)
            chmod 700 "$HOME/.ssh" 2>/dev/null || true
            chmod 600 "$dest" 2>/dev/null || true
            ;;
        .gitconfig)
            chmod 600 "$dest" 2>/dev/null || true
            ;;
        .claude/*)
            chmod 700 "$HOME/.claude" 2>/dev/null || true
            chmod 600 "$dest" 2>/dev/null || true
            ;;
    esac
}

backup_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 0
    fi

    local rel="${file#"$HOME/"}"
    local backup_path="$BACKUP_DIR/$rel"
    ensure_parent_dir "$backup_path"
    cp "$file" "$backup_path"
    log_blue "Backed up: $rel"
}

copy_file() {
    local src="$1"
    local dest="$2"
    ensure_parent_dir "$dest"
    cp "$src" "$dest"
}

diff_file() {
    local new_content="$1"
    local dest="$2"
    local rel="${dest#"$HOME/"}"

    if [[ ! -f "$dest" ]]; then
        printf "${GREEN}+ New file: %s${RESET}\n" "$rel"
        printf '%s\n' "$new_content" | head -5
        [[ $(printf '%s\n' "$new_content" | wc -l) -gt 5 ]] && printf "${CYAN}  ... (%d more lines)${RESET}\n" "$(( $(printf '%s\n' "$new_content" | wc -l) - 5 ))"
        return 0
    fi

    local current
    current=$(<"$dest")
    if [[ "$new_content" == "$current" ]]; then
        printf "${GREEN}✓ Up to date: %s${RESET}\n" "$rel"
        return 0
    fi

    printf "${YELLOW}~ Changed: %s${RESET}\n" "$rel"
    diff -u --color=always "$dest" <(printf '%s\n' "$new_content") 2>/dev/null || \
        diff -u "$dest" <(printf '%s\n' "$new_content") 2>/dev/null || true
}

# ── Package Discovery ────────────────────────────────────────────────────────

list_packages() {
    local pkg_dir="$LFG_DIR/packages"
    for dir in "$pkg_dir"/*/; do
        [[ -d "$dir" ]] && basename "$dir"
    done | sort
}

get_package_files() {
    local package="$1"
    local pkg_dir="$LFG_DIR/packages/$package"

    # Find all files, excluding install.sh hooks
    while IFS= read -r -d '' file; do
        local base
        base="$(basename "$file")"
        [[ "$base" == "install.sh" ]] && continue
        echo "$file"
    done < <(find "$pkg_dir" -type f -print0 2>/dev/null)
}

# ── Install Config ───────────────────────────────────────────────────────────

install_package() {
    local package="$1"
    local pkg_dir="$LFG_DIR/packages/$package"

    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Package not found: $package"
        return 1
    fi

    log_header "$package"

    local files
    files=$(get_package_files "$package")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local dest
        dest=$(resolve_target_path "$pkg_dir" "$file")

        if [[ "$file" == *.tmpl ]]; then
            # Template: process and copy. Skip this file (not the whole run)
            # if required variables are missing — other packages can still
            # be previewed/installed.
            local processed
            if ! processed=$(process_template "$file"); then
                continue
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                diff_file "$processed" "$dest"
            else
                [[ "$NO_BACKUP" != "true" ]] && backup_file "$dest"
                ensure_parent_dir "$dest"
                printf '%s\n' "$processed" > "$dest"
                set_secure_permissions "$dest"
                log_info "Installed: ${dest#"$HOME/"}"
            fi
        else
            # Plain file: copy as-is
            local content
            content=$(<"$file")

            if [[ "$DRY_RUN" == "true" ]]; then
                diff_file "$content" "$dest"
            else
                [[ "$NO_BACKUP" != "true" ]] && backup_file "$dest"
                copy_file "$file" "$dest"
                set_secure_permissions "$dest"
                log_info "Installed: ${dest#"$HOME/"}"
            fi
        fi
    done <<< "$files"

    # Run install hook if present (always at package root). Always redirect
    # hook stdin to /dev/null so the package loop's stdin (fed from
    # list_packages) can't leak into hook commands like ssh-keygen. Hooks
    # that want interactive prompts should read from /dev/tty themselves.
    # Hooks run in dry-run too (DRY_RUN is exported); the hook itself must
    # branch early and do read-only reporting when DRY_RUN=true.
    local hook="$pkg_dir/install.sh"
    if [[ -f "$hook" ]]; then
        if [[ "${LFG_SKIP_HOOKS:-0}" == "1" ]]; then
            log_blue "Skipping install hook for $package (LFG_SKIP_HOOKS=1)"
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                log_blue "Dry-run: install hook for $package"
            else
                log_blue "Running install hook for $package"
            fi
            ( source "$hook" ) </dev/null
        fi
    fi
}

# ── Save Config ──────────────────────────────────────────────────────────────

save_package() {
    local package="$1"
    local pkg_dir="$LFG_DIR/packages/$package"

    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Package not found: $package"
        return 1
    fi

    log_header "Saving $package"

    local files
    files=$(get_package_files "$package")
    local changed=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local dest
        dest=$(resolve_target_path "$pkg_dir" "$file")

        if [[ ! -f "$dest" ]]; then
            log_warn "Deployed file not found: ${dest#"$HOME/"}"
            continue
        fi

        local deployed_content
        deployed_content=$(<"$dest")

        if [[ "$file" == *.tmpl ]]; then
            # Template file — compare against rendered template
            local repo_content=""
            [[ -f "$file" ]] && repo_content=$(process_template "$file") || true

            if [[ "$deployed_content" != "$repo_content" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    printf "${YELLOW}~ Drift detected: %s${RESET}\n" "${dest#"$HOME/"}"
                    diff -u --color=always <(printf '%s\n' "$repo_content") "$dest" 2>/dev/null || \
                        diff -u <(printf '%s\n' "$repo_content") "$dest" 2>/dev/null || true
                else
                    log_warn "Template drift in ${dest#"$HOME/"} — update the .tmpl file manually"
                    log_blue "  repo template: ${file#"$LFG_DIR/"}"
                    log_blue "  deployed file: $dest"
                    changed=1
                fi
            else
                log_info "No drift: ${dest#"$HOME/"}"
            fi
        else
            # Plain file — direct comparison and copy back
            local repo_content
            repo_content=$(<"$file")

            if [[ "$deployed_content" != "$repo_content" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    printf "${YELLOW}~ Drift detected: %s${RESET}\n" "${dest#"$HOME/"}"
                    diff -u --color=always "$file" "$dest" 2>/dev/null || \
                        diff -u "$file" "$dest" 2>/dev/null || true
                else
                    cp "$dest" "$file"
                    SAVED_FILES+=("$file")
                    log_info "Saved: ${dest#"$HOME/"}"
                    changed=1
                fi
            else
                log_info "No drift: ${dest#"$HOME/"}"
            fi
        fi
    done <<< "$files"

    return $changed
}

# ── Verify / Drift Check ────────────────────────────────────────────────────

verify_package() {
    local package="$1"
    local pkg_dir="$LFG_DIR/packages/$package"

    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Package not found: $package"
        return 1
    fi

    local files
    files=$(get_package_files "$package")
    local drift=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local dest
        dest=$(resolve_target_path "$pkg_dir" "$file")
        local rel="${dest#"$HOME/"}"

        if [[ ! -f "$dest" ]]; then
            printf "${RED}✗ Missing: %s${RESET}\n" "$rel"
            drift=1
            continue
        fi

        local expected
        if [[ "$file" == *.tmpl ]]; then
            if ! expected=$(process_template "$file"); then
                drift=1
                continue
            fi
        else
            expected=$(<"$file")
        fi

        local current
        current=$(<"$dest")

        if [[ "$expected" == "$current" ]]; then
            printf "${GREEN}✓ OK: %s${RESET}\n" "$rel"
        else
            printf "${YELLOW}~ Drift: %s${RESET}\n" "$rel"
            drift=1
            # --diff:   full unified diff (live → what deploy would write)
            # --losses: just the lines that would disappear (lines in live
            #           that aren't in the rendered template / repo file)
            if [[ "${VERIFY_DIFF:-false}" == "true" || "${VERIFY_LOSSES:-false}" == "true" ]]; then
                local diff_out
                diff_out=$(diff -u "$dest" <(printf '%s\n' "$expected") 2>/dev/null || true)
                if [[ "${VERIFY_LOSSES:-false}" == "true" ]]; then
                    # Skip diff headers (---/+++) and only show '-' lines
                    echo "$diff_out" | grep -E '^-[^-]' | sed 's/^-/  - /' || true
                else
                    echo "$diff_out"
                fi
            fi
        fi
    done <<< "$files"

    return $drift
}

# ── Software Installation ────────────────────────────────────────────────────

read_manifest() {
    local file="$1"
    [[ ! -f "$file" ]] && return

    while IFS= read -r line; do
        # Skip comments and blank lines
        line="${line%%#*}"
        # Trim leading and trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        echo "$line"
    done < "$file"
}

install_software() {
    local packages=("$@")

    detect_os
    log_header "Software Installation ($DOTFILES_OS)"

    local manifest
    if [[ "$DOTFILES_OS" == "macos" ]]; then
        manifest="$LFG_DIR/software/brew.txt"
    else
        manifest="$LFG_DIR/software/apt.txt"
    fi

    if [[ ! -f "$manifest" ]]; then
        log_error "Manifest not found: $manifest"
        return 1
    fi

    local to_install=()

    if [[ ${#packages[@]} -gt 0 ]]; then
        # Install specific packages
        to_install=("${packages[@]}")
    else
        # Install all from manifest
        while IFS= read -r pkg; do
            to_install+=("$pkg")
        done < <(read_manifest "$manifest")
    fi

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_info "No packages to install"
        return 0
    fi

    # Ask the package manager directly — authoritative when binary name
    # differs from package name (ripgrep→rg, awscli→aws, fd-find→fdfind)
    # or when there's no binary at all (nvm). Fall back to PATH lookup if
    # the package manager isn't available.
    local installed_list=""
    if [[ "$DOTFILES_OS" == "macos" ]] && command -v brew &>/dev/null; then
        installed_list=$'\n'$(brew list --formula -1 2>/dev/null)$'\n'$(brew list --cask -1 2>/dev/null)$'\n'
    elif [[ "$DOTFILES_OS" != "macos" ]] && command -v dpkg-query &>/dev/null; then
        installed_list=$'\n'$(dpkg-query -W -f='${Package}\n' 2>/dev/null)$'\n'
    fi

    local missing=()
    for pkg in "${to_install[@]}"; do
        if [[ -n "$installed_list" && "$installed_list" == *$'\n'"$pkg"$'\n'* ]] || \
           command -v "$pkg" &>/dev/null; then
            [[ "$DRY_RUN" == "true" ]] && printf "${GREEN}✓ Already installed: %s${RESET}\n" "$pkg"
        else
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_info "All packages already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "\n${BOLD}Would install:${RESET}\n"
        for pkg in "${missing[@]}"; do
            printf "${YELLOW}  + %s${RESET}\n" "$pkg"
        done
        return 0
    fi

    log_info "Installing ${#missing[@]} package(s)..."

    if [[ "$DOTFILES_OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            log_error "Homebrew not found. Install it first: https://brew.sh"
            return 1
        fi
        brew install "${missing[@]}"
    else
        sudo apt update -qq
        sudo apt install -y "${missing[@]}"
    fi

    # Run common.sh if it exists
    if [[ -f "$LFG_DIR/software/common.sh" ]]; then
        log_blue "Running common.sh"
        source "$LFG_DIR/software/common.sh"
    fi

    log_info "Software installation complete"
}

# ── Update Check ─────────────────────────────────────────────────────────────

check_for_updates() {
    # Skip if not a git repo or no remote
    if ! git -C "$LFG_DIR" rev-parse --git-dir &>/dev/null; then
        return 0
    fi

    if ! git -C "$LFG_DIR" remote get-url origin &>/dev/null; then
        return 0
    fi

    # Fetch quietly, skip on failure (offline)
    if ! git -C "$LFG_DIR" fetch --quiet 2>/dev/null; then
        return 0
    fi

    local local_ref
    local_ref=$(git -C "$LFG_DIR" rev-parse HEAD 2>/dev/null)
    local remote_ref
    remote_ref=$(git -C "$LFG_DIR" rev-parse '@{u}' 2>/dev/null) || return 0

    if [[ "$local_ref" == "$remote_ref" ]]; then
        return 0
    fi

    local behind
    behind=$(git -C "$LFG_DIR" rev-list --count HEAD..@{u} 2>/dev/null)

    if [[ "$behind" -gt 0 ]]; then
        log_warn "Remote has $behind new commit(s):"
        git -C "$LFG_DIR" log --oneline HEAD..@{u} 2>/dev/null | while read -r line; do
            printf "  ${CYAN}%s${RESET}\n" "$line"
        done

        if [[ -t 0 ]]; then
            printf "\n${BOLD}Pull and re-apply? [y/N]${RESET} "
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                do_update
            fi
        else
            log_warn "Run './lfg update' to pull and re-apply"
        fi
    fi
}

do_update() {
    log_header "Updating"

    if ! git -C "$LFG_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
        log_error "Working tree has uncommitted changes — commit or stash before updating"
        return 1
    fi

    git -C "$LFG_DIR" pull --rebase
    log_info "Pulled latest changes"

    # Re-source config
    load_config

    # Initialise a backup dir — install_package → backup_file needs BACKUP_DIR
    # set before touching any deployed file. Matches cmd_config's pattern.
    init_backup

    # Re-apply all configs
    local packages
    packages=$(list_packages)
    while IFS= read -r pkg; do
        install_package "$pkg"
    done <<< "$packages"

    log_info "Update complete"
}

# ── Backup / Restore ────────────────────────────────────────────────────────

init_backup() {
    if [[ "$NO_BACKUP" == "true" ]]; then
        return 0
    fi
    BACKUP_DIR="$LFG_DIR/backups/$(date +%Y-%m-%dT%H-%M-%S)"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    export BACKUP_DIR
}

restore_backup() {
    local timestamp="$1"
    local backup_dir="$LFG_DIR/backups/$timestamp"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $timestamp"
        echo "Available backups:"
        ls "$LFG_DIR/backups/" 2>/dev/null || echo "  (none)"
        return 1
    fi

    log_header "Restoring from $timestamp"

    # First, back up current state (use distinct dir to avoid overwriting the restore source)
    BACKUP_DIR="$LFG_DIR/backups/$(date +%Y-%m-%dT%H-%M-%S)-pre-restore"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    export BACKUP_DIR
    log_blue "Backing up current state first"

    find "$backup_dir" -type f -print0 | while IFS= read -r -d '' file; do
        local rel="${file#"$backup_dir/"}"
        local dest="$HOME/$rel"

        backup_file "$dest"
        ensure_parent_dir "$dest"
        cp "$file" "$dest"
        log_info "Restored: $rel"
    done

    log_info "Restore complete"
}

# ── Add Package ──────────────────────────────────────────────────────────────

add_package() {
    local name="$1"
    local pkg_dir="$LFG_DIR/packages/$name"

    if [[ -d "$pkg_dir" ]]; then
        log_error "Package already exists: $name"
        return 1
    fi

    mkdir -p "$pkg_dir"
    log_info "Created package: $name"
    log_blue "Add your dotfiles under: packages/$name/"
    log_blue "Files will be deployed relative to \$HOME"
    log_blue "Use .tmpl extension for files that need {{VAR}} substitution"
}

# ── SSH Key Management ───────────────────────────────────────────────────────
#
# Shared between the `ssh` command and the git package's install hook so there
# is one source of truth for the keypair, its agent registration, and the
# allowed_signers entry. Keys are never stored in the repo — these helpers
# operate purely on $HOME.

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_PUB="$SSH_KEY.pub"
SSH_ALLOWED_SIGNERS="$HOME/.config/git/allowed_signers"

# Print a $HOME-relative path with a leading ~ for tidy output.
tilde_path() {
    local p="$1"
    if [[ "$p" == "$HOME"/* || "$p" == "$HOME" ]]; then
        printf '~%s' "${p#"$HOME"}"
    else
        printf '%s' "$p"
    fi
}

# Generate the ed25519 keypair if missing, load it into the agent, and ensure
# the pubkey is registered in allowed_signers. Idempotent and silent when
# nothing changes. Uses DOTS_GIT_EMAIL for the key comment / signer identity,
# falling back to user@host when it isn't set.
ssh_ensure_key() {
    local email="${DOTS_GIT_EMAIL:-${USER:-user}@$(hostname -s 2>/dev/null || hostname)}"

    mkdir -p "$HOME/.ssh" "$(dirname "$SSH_ALLOWED_SIGNERS")"
    chmod 700 "$HOME/.ssh"

    if [[ ! -f "$SSH_KEY" ]]; then
        printf '\nNo SSH key at %s — generating ed25519 keypair (no passphrase).\n' "$SSH_KEY"
        printf 'To add a passphrase later: ssh-keygen -p -f %s\n\n' "$SSH_KEY"
        ssh-keygen -t ed25519 -C "$email" -f "$SSH_KEY" -N ""
    fi
    chmod 600 "$SSH_KEY" 2>/dev/null || true

    if [[ "$(uname)" == "Darwin" ]]; then
        ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || true
    else
        ssh-add "$SSH_KEY" 2>/dev/null || true
    fi

    touch "$SSH_ALLOWED_SIGNERS"
    local line="$email $(awk '{print $1, $2}' "$SSH_PUB")"
    if ! grep -qxF "$line" "$SSH_ALLOWED_SIGNERS"; then
        echo "$line" >> "$SSH_ALLOWED_SIGNERS"
        log_info "Added pubkey to $(tilde_path "$SSH_ALLOWED_SIGNERS")"
    fi
}

# Read-only health check: does this machine have a usable, registered SSH key?
# Never mutates state. Returns non-zero if the key itself is missing.
ssh_status() {
    log_header "SSH key status"

    if [[ ! -f "$SSH_KEY" ]]; then
        log_warn "No key at $(tilde_path "$SSH_KEY")"
        log_blue "Generate one with: ./lfg config git   (or ./lfg ssh copy <host>)"
        return 1
    fi

    log_info "Key present: $(tilde_path "$SSH_KEY")"
    local fp
    fp=$(ssh-keygen -lf "$SSH_KEY" 2>/dev/null) && printf '    %s\n' "$fp"

    # Permissions (best effort; BSD then GNU stat)
    local mode
    mode=$(stat -f '%Lp' "$SSH_KEY" 2>/dev/null || stat -c '%a' "$SSH_KEY" 2>/dev/null || echo "")
    if [[ -n "$mode" && "$mode" != "600" ]]; then
        log_warn "Key mode is $mode, expected 600 — run: chmod 600 $(tilde_path "$SSH_KEY")"
    fi

    # Loaded in the agent? Compare fingerprints.
    if [[ -f "$SSH_PUB" ]]; then
        local keyfp
        keyfp=$(ssh-keygen -lf "$SSH_PUB" 2>/dev/null | awk '{print $2}')
        if [[ -n "$keyfp" ]] && ssh-add -l 2>/dev/null | awk '{print $2}' | grep -qxF "$keyfp"; then
            log_info "Loaded in ssh-agent"
        else
            log_warn "Not loaded in ssh-agent — run: ssh-add $(tilde_path "$SSH_KEY")"
        fi
    fi

    # Registered in allowed_signers (local signature verification)?
    if [[ -f "$SSH_PUB" ]]; then
        local pubkey
        pubkey=$(awk '{print $1, $2}' "$SSH_PUB")
        if [[ -f "$SSH_ALLOWED_SIGNERS" ]] && grep -qF "$pubkey" "$SSH_ALLOWED_SIGNERS"; then
            log_info "Registered in allowed_signers"
        else
            log_warn "Not in allowed_signers ($(tilde_path "$SSH_ALLOWED_SIGNERS"))"
        fi
    fi

    # Registered on GitHub (auth + signing)?
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        local body matched
        body=$(awk '{print $2}' "$SSH_PUB")
        matched=$(gh ssh-key list 2>/dev/null | grep -F "$body" || true)
        if [[ -n "$matched" ]]; then
            echo "$matched" | grep -qi authentication \
                && log_info "GitHub: registered as authentication key" \
                || log_warn "GitHub: not registered as authentication key"
            echo "$matched" | grep -qi signing \
                && log_info "GitHub: registered as signing key" \
                || log_warn "GitHub: not registered as signing key"
        else
            log_warn "GitHub: this key is not registered — run: gh ssh-key add $(tilde_path "$SSH_PUB")"
        fi
    else
        log_blue "GitHub: skipped (gh not installed or not authenticated)"
    fi

    return 0
}

# Copy the local pubkey to a remote host with the standard ssh-copy-id, then
# verify key-based login works. ssh/ssh-copy-id read any password prompt from
# the controlling terminal directly, so this works under the hook's piped stdin.
ssh_copy_one() {
    local target="$1"
    log_header "Copying pubkey to $target"
    # ssh-copy-id treats a non-empty $DRY_RUN env var as its own -n (dry-run)
    # flag and never initialises it otherwise. lfg exports DRY_RUN ("false"),
    # which is non-empty — so it must be stripped from ssh-copy-id's
    # environment or it silently refuses to install the key.
    if env -u DRY_RUN ssh-copy-id "$target"; then
        log_info "Copied pubkey to $target"
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" true 2>/dev/null; then
            log_info "Key-based login to $target works"
        else
            log_warn "Copied, but key-based login test to $target did not succeed yet"
        fi
        return 0
    fi
    log_error "Failed to copy to $target"
    return 1
}

# `ssh copy` entry point: ensure a key exists, then copy it to one or more hosts.
ssh_copy() {
    if [[ $# -eq 0 ]]; then
        log_error "Usage: ./lfg ssh copy <user@host> [user@host...]"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        [[ -f "$SSH_KEY" ]] || log_blue "Dry-run: would generate $(tilde_path "$SSH_KEY")"
        local t
        for t in "$@"; do
            log_blue "Dry-run: would run ssh-copy-id $t"
        done
        return 0
    fi

    ssh_ensure_key

    local rc=0 target
    for target in "$@"; do
        ssh_copy_one "$target" || rc=1
    done
    return $rc
}

# `ssh test` entry point: confirm key-based auth works against GitHub and any
# extra hosts. GitHub's SSH endpoint exits non-zero even on success, so we match
# its greeting text rather than the exit code.
ssh_test() {
    log_header "SSH connectivity test"
    local rc=0

    log_blue "Testing GitHub (git@github.com)..."
    local out
    out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) || true
    if echo "$out" | grep -qi "successfully authenticated"; then
        log_info "GitHub: $(echo "$out" | head -1)"
    else
        log_warn "GitHub: $(echo "$out" | head -1)"
        rc=1
    fi

    local host
    for host in "$@"; do
        log_blue "Testing $host..."
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
            log_info "$host: key-based login works"
        else
            log_warn "$host: key-based login failed (unreachable, or key not installed there)"
            rc=1
        fi
    done

    return $rc
}
