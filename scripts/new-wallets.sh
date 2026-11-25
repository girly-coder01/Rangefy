#!/usr/bin/env bash
# Creates contracts/.env with fresh keys for every role (skips if it already exists).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="$ROOT/contracts/.env"
export PATH="$PATH:$HOME/.foundry/bin"
[[ -f "$ENV" ]] && { echo "contracts/.env exists, not overwriting"; exit 0; }

key() { cast wallet new --json | jq -r '(.data // .) | if type == "array" then .[0] else . end | .private_key'; }
addr() { cast wallet address --private-key "$1"; }
DEPLOYER=$(key); UPDATER=$(key); KEEPER=$(key); MIRROR=$(key); ATLAS=$(key); HARBOR=$(key); VECTOR=$(key)

cat > "$ENV" <<E
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org
PRIVATE_KEY=$DEPLOYER
SIGNAL_UPDATER_KEY=$UPDATER
KEEPER_KEY=$KEEPER
MIRROR_KEY=$MIRROR
SIGNAL_UPDATER=$(addr $UPDATER)
KEEPER=$(addr $KEEPER)
MIRROR=$(addr $MIRROR)
CURATOR_ATLAS_KEY=$ATLAS
CURATOR_HARBOR_KEY=$HARBOR
CURATOR_VECTOR_KEY=$VECTOR
ETH_PRICE_USD=3000
E
chmod 600 "$ENV"
echo "wrote contracts/.env (keep it secret)"
echo "fund the deployer with Unichain Sepolia ETH, then run ./scripts/fund-wallets.sh:"
echo "  deployer $(addr $DEPLOYER)"
