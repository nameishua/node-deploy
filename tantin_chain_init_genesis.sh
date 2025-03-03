#!/usr/bin/env bash

# Exit on error and undefined variables
set -eu

# Define constants
readonly BASEDIR=$(cd "$(dirname "$0")" && pwd)
readonly WORKSPACE="${BASEDIR}"
readonly ENV_FILE="${WORKSPACE}/.env"

# Source environment variables
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || { echo "Error: .env file not found"; exit 1; }

# reset genesis, but keep edited genesis-template.json
function reset_genesis() {
    if [ ! -f "${WORKSPACE}/genesis/genesis-template.json" ]; then
        cd ${WORKSPACE} &&  git submodule update --init --recursive && cd ${WORKSPACE}/genesis
        git reset --hard ${GENESIS_COMMIT}
    else
        cd ${WORKSPACE}/genesis
        cp genesis-template.json genesis-template.json.bk
        git stash
        cd ${WORKSPACE} && git submodule update --remote --recursive && cd ${WORKSPACE}/genesis
        git reset --hard ${GENESIS_COMMIT}
        mv genesis-template.json.bk genesis-template.json
    fi
    
    poetry install --no-root
    npm install
    rm -rf lib/forge-std
    forge install --no-git --no-commit foundry-rs/forge-std@v1.7.3
    cd lib/forge-std/lib
    rm -rf ds-test
    git clone https://github.com/dapphub/ds-test
}

function prepare_genesis() {
    cd ${WORKSPACE}/genesis/
    git checkout HEAD contracts

    sed -i -e '/registeredContractChannelMap\[VALIDATOR_CONTRACT_ADDR\]\[STAKING_CHANNELID\]/d' ${WORKSPACE}/genesis/contracts/CrossChain.sol
    sed -i -e  's/alreadyInit = true;/turnLength = 4;alreadyInit = true;/' ${WORKSPACE}/genesis/contracts/BSCValidatorSet.sol
    sed -i -e  's/public onlyCoinbase onlyZeroGasPrice {/public onlyCoinbase onlyZeroGasPrice {if (block.number < 30) return;/' ${WORKSPACE}/genesis/contracts/BSCValidatorSet.sol
    
    poetry run python -m scripts.generate generate-validators
    poetry run python -m scripts.generate generate-init-holders "${INIT_HOLDER}"
    poetry run python -m scripts.generate dev \
      --epoch 200 \
      --init-felony-slash-scope "60" \
      --breathe-block-interval "10 minutes" \
      --block-interval 3 \
      --stake-hub-protector "${INIT_HOLDER}" \
      --unbond-period "2 minutes" \
      --downtime-jail-time "2 minutes" \
      --felony-jail-time "3 minutes" \
      --init-voting-delay "1 minutes / BLOCK_INTERVAL" \
      --init-voting-period "2 minutes / BLOCK_INTERVAL" \
      --init-min-period-after-quorum "uint64(1 minutes / BLOCK_INTERVAL)" \
      --governor-protector "${INIT_HOLDER}" \
      --init-minimal-delay "1 minutes"
}

# Main logic
echo "Initializing genesis..."
reset_genesis
prepare_genesis
echo "Genesis initialization completed." 