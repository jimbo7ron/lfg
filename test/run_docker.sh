#!/bin/bash
# Build and run the test container
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Building test container..."
docker build -f test/Dockerfile -t lfg-test .

echo ""
echo "Running tests..."
docker run --rm lfg-test
