#!/usr/bin/env bash
# Vim package install hook — install the dracula colorscheme referenced in
# .vimrc. Idempotent: downloads only if not present.
# Dry-run aware: reports what would change.
set -euo pipefail

colors_file="$HOME/.vim/colors/dracula.vim"
autoload_file="$HOME/.vim/autoload/dracula.vim"
base_url="https://raw.githubusercontent.com/dracula/vim/master"

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    if [[ -f "$colors_file" && -f "$autoload_file" ]]; then
        echo "Vim dracula theme: already installed"
    else
        echo "Vim dracula theme: would download colors/ and autoload/ files"
    fi
    exit 0
fi

if [[ -f "$colors_file" && -f "$autoload_file" ]]; then
    exit 0
fi

mkdir -p "$HOME/.vim/colors" "$HOME/.vim/autoload"
echo "Downloading dracula.vim theme"
curl -fsSL "$base_url/colors/dracula.vim"   -o "$colors_file"
curl -fsSL "$base_url/autoload/dracula.vim" -o "$autoload_file"
