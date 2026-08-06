#!/usr/bin/env bash
# One-shot setup: toolchain, deps, ZK fixtures, tests.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v forge >/dev/null 2>&1; then
  echo ">> Installing Foundry..."
  curl -L https://foundry.paradigm.xyz | bash
  export PATH="$HOME/.foundry/bin:$PATH"
  foundryup
fi

echo ">> Installing npm deps (Solidity libs + Semaphore JS for fixtures)..."
npm install

if [ ! -d lib/forge-std ]; then
  echo ">> Installing forge-std..."
  [ -d .git ] || git init -q
  forge install foundry-rs/forge-std --no-commit 2>/dev/null || forge install foundry-rs/forge-std
fi

echo ">> Generating ZK proof fixtures (first run downloads Semaphore snark artifacts)..."
npm run fixtures

echo ">> Running tests..."
forge test -vv
