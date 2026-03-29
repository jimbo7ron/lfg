#!/bin/bash
# Run this once to set up permissions and clean old files
cd "$(dirname "$0")"

# Make scripts executable
chmod +x lfg software/common.sh packages/claude/.claude/install.sh
chmod +x test/run_tests.sh test/run_docker.sh

# Remove old non-mirrored files from v1 structure
rm -f packages/vim/.vimrc.tmpl
rm -f packages/claude/settings.json.tmpl
rm -f packages/claude/install.sh

# Remove empty old dirs if present
rmdir packages/claude 2>/dev/null || true

# Init git repo
if [[ ! -d .git ]]; then
    git init
    git add -A
    git commit -m "Initial lfg setup"
fi

echo ""
echo "Done! Run ./lfg to get started."
echo ""
echo "To run tests in Docker:"
echo "  ./test/run_docker.sh"
