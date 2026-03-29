#!/bin/bash
# Build and run the test container
set -e

cd "$(dirname "$0")/.."

echo "Building test container..."
docker build -f test/Dockerfile -t lfg-test .

echo ""
echo "Running tests..."
docker run --rm lfg-test
