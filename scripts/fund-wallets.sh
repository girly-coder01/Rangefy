#!/usr/bin/env bash
# Sends gas money from the deployer to every other role.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$PATH:$HOME/.foundry/bin"
set -a; source "$ROOT/contracts/.env"; set +a
RPC="${UNICHAIN_SEPOLIA_RPC_URL:-https://sepolia.unichain.org}"
AMOUNT="${AMOUNT:-0.005ether}"

for k in SIGNAL_UPDATER_KEY KEEPER_KEY MIRROR_KEY CURATOR_ATLAS_KEY CURATOR_HARBOR_KEY CURATOR_VECTOR_KEY; do
  to=$(cast wallet address --private-key "${!k}")
  bal=$(cast balance "$to" --rpc-url "$RPC")
  if [[ "$bal" -lt 1000000000000000 ]]; then
    echo "→ $k $to"
    cast send "$to" --value "$AMOUNT" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" > /dev/null
  else
    echo "  $k $to already funded"
  fi
done
