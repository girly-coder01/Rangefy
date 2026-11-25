#!/usr/bin/env bash
# Deploys Rangefy to Unichain Sepolia, verifies on Blockscout and syncs addresses into the apps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$PATH:$HOME/.foundry/bin"
set -a; source "$ROOT/contracts/.env"; set +a
RPC="${UNICHAIN_SEPOLIA_RPC_URL:-https://sepolia.unichain.org}"
VERIFY=(--verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/)
[[ "${NO_VERIFY:-0}" == 1 ]] && VERIFY=()

[[ "$(cast chain-id --rpc-url "$RPC")" == 1301 ]] || { echo "RPC is not Unichain Sepolia"; exit 1; }
PM=${POOL_MANAGER:-0x00B036B58a818B1BC34d502D3fE730Db729e62AC}
[[ "$(cast codesize "$PM" --rpc-url "$RPC")" -gt 0 ]] || { echo "no PoolManager at $PM"; exit 1; }

for k in PRIVATE_KEY CURATOR_ATLAS_KEY CURATOR_HARBOR_KEY CURATOR_VECTOR_KEY; do
  a=$(cast wallet address --private-key "${!k}")
  [[ "$(cast balance "$a" --rpc-url "$RPC")" -gt 1000000000000000 ]] || { echo "$k ($a) needs ETH; run fund-wallets.sh"; exit 1; }
done

cd "$ROOT/contracts"
run() { echo "→ $1"; forge script "$1" --rpc-url "$RPC" --broadcast --slow "${@:2}" ${FORGE_FLAGS:-}; }
run script/00_DeployTokens.s.sol "${VERIFY[@]}"
run script/01_DeployCore.s.sol "${VERIFY[@]}"
run script/02_InitPool.s.sol
run script/03_SeedCurators.s.sol

cd "$ROOT"
CHAIN_ID=1301 ./scripts/sync-abis.sh
if [[ ! -f ai-engine/.env ]]; then
  cat > ai-engine/.env <<E
RPC_URL=$RPC
CHAIN_ID=1301
SIGNAL_UPDATER_KEY=$SIGNAL_UPDATER_KEY
KEEPER_KEY=$KEEPER_KEY
MIRROR_KEY=$MIRROR_KEY
PRICE_SOURCE=coinbase
API_CORS_ORIGINS=http://localhost:3000,${FRONTEND_URL:-https://rangefy.vercel.app}
E
  chmod 600 ai-engine/.env
  echo "→ ai-engine/.env"
fi
echo
echo "✓ deployed. next:"
echo "  - commit frontend/src/config/deployments/1301.json and redeploy Vercel"
echo "  - copy ai-engine/.env.addresses next to ai-engine/.env on the keeper host"
