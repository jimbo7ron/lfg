#!/usr/bin/env bash
# lib/helpers.sh -- Shared functions for lfg

# ── Colours ──────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
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

        # Replace all occurrences using bash string replacement
        content="${content//"{{${var_name}}}"/"$var_value"}"
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
            # Template: process and copy
            local processed
            processed=$(process_template "$file")

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

    # Run install hook if present (always at package root)
    local hook="$pkg_dir/install.sh"
    if [[ -f "$hook" && "$DRY_RUN" != "true" ]]; then
        log_blue "Running install hook for $package"
        ( source "$hook" )
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
            expected=$(process_template "$file")
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

    # Filter already-installed packages
    local missing=()
    for pkg in "${to_install[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            missing+=("$pkg")
        else
            [[ "$DRY_RUN" == "true" ]] && printf "${GREEN}✓ Already installed: %s${RESET}\n" "$pkg"
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
