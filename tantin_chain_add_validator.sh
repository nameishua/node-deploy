#!/usr/bin/env bash

# Exit on error and undefined variables
set -eu

# Define constants
readonly BASEDIR=$(cd "$(dirname "$0")" && pwd)
readonly WORKSPACE="${BASEDIR}"
readonly ENV_FILE="${WORKSPACE}/.env"
readonly SLEEP_DURATION=10
readonly STAKE_AMOUNT=20001

# Source environment variables
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || { echo "Error: .env file not found"; exit 1; }

# Stop an existing node process
stop_node() {
    local val_idx="$1"
    local pids
    pids=$(ps -ef | grep "geth${val_idx}" | grep mine | awk '{print $2}' | tr '\n' ' ')
    if [[ -n "$pids" ]]; then
        echo "Stopping existing node${val_idx} with PIDs: $pids"
        kill -9 $pids 2>/dev/null || true
    fi
    sleep "$SLEEP_DURATION"
}

# Prepare validator files
prepare_new_validator() {
    local val_idx="$1"
    local node_dir="${WORKSPACE}/local/chain/node${val_idx}"
    local cons_key_dir="${WORKSPACE}/keys/validator${val_idx}/keystore"
    local bls_key_dir="${WORKSPACE}/keys/bls${val_idx}/bls"

    # Check if key directories exist
    [[ -d "$cons_key_dir" ]] || { echo "Error: Consensus key directory $cons_key_dir not found"; exit 1; }
    [[ -d "$bls_key_dir" ]] || { echo "Error: BLS key directory $bls_key_dir not found"; exit 1; }

    # Create directories
    mkdir -p "${node_dir}/keystore" "${node_dir}/bls" "${node_dir}/geth"

    # Copy keystore and BLS directories
    cp -r "$cons_key_dir"/* "${node_dir}/keystore/" || { echo "Error: Failed to copy consensus keystore"; exit 1; }
    cp -r "$bls_key_dir"/* "${node_dir}/bls/" || { echo "Error: Failed to copy BLS directories"; exit 1; }
    cp "${WORKSPACE}/keys/password.txt" "${node_dir}/" || { echo "Error: password.txt not found"; exit 1; }
    cp "${WORKSPACE}/config.toml" "${node_dir}/" || { echo "Error: config.toml not found"; exit 1; }
    cp "${WORKSPACE}/keys/nodekey${val_idx}" "${node_dir}/geth/nodekey" || { echo "Error: nodekey${val_idx} not found"; exit 1; }
}

# Register validator to StakeHub
register_validator() {
    local val_idx="$1"
    local cons_addr
    cons_addr=$(find "${WORKSPACE}/local/chain/node${val_idx}/keystore/" -type f -name "UTC--*" -exec cat {} \; | jq -r .address) || { echo "Error: Failed to extract consensus address"; exit 1; }
    local cons_addr_full="0x${cons_addr}"

    echo "Registering validator${val_idx} ($cons_addr_full) to StakeHub..."
    # Check balance before registration
    local balance
    balance=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${cons_addr_full}\",\"latest\"],\"id\":1}" "$RPC_URL" | jq -r .result)
    if [[ -z "$balance" || "$balance" == "null" ]]; then
        echo "Error: Failed to retrieve balance for $cons_addr_full"
        exit 1
    fi
    local required
    required=$(printf '0x%x' "$((STAKE_AMOUNT * 10**18))")
    if [[ $(echo "ibase=16; $(echo "${balance#0x}" | tr '[:lower:]' '[:upper:]') < $(echo "${required#0x}" | tr '[:lower:]' '[:upper:]')" | bc) -eq 1 ]]; then
        echo "Error: Insufficient balance for $cons_addr_full: $(printf '%.0f' "$(bc <<< "scale=18; $balance / 10^18")") BNB, required: $STAKE_AMOUNT BNB"
        exit 1
    fi

    "${WORKSPACE}/create-validator/create-validator" \
        --consensus-key-dir "${WORKSPACE}/keys/validator${val_idx}" \
        --vote-key-dir "${WORKSPACE}/keys/bls${val_idx}" \
        --password-path "${WORKSPACE}/keys/password.txt" \
        --amount "$STAKE_AMOUNT" \
        --validator-desc "Validator${val_idx}" \
        --rpc-url "$RPC_URL" || { echo "Error: Registration failed"; exit 1; }

    echo "Waiting ${SLEEP_DURATION}s for transaction to settle..."
    sleep "$SLEEP_DURATION"
}

# Main logic
CMD="${1:-}"
VAL_IDX="${2:-}"

if [[ -z "$VAL_IDX" ]]; then
    echo "Error: Validator index (ValIdx) is required."
    echo "Usage: $0 add <validator_index>"
    exit 1
fi

case "$CMD" in
add)
    echo "Adding validator${VAL_IDX} dynamically..."
    prepare_new_validator "$VAL_IDX"
    register_validator "$VAL_IDX"
    ${BASEDIR}/tantin_chain_run.sh start "$VAL_IDX"
    echo "Validator${VAL_IDX} added successfully. Check logs and validator list."
    ;;
*)
    echo "Usage: $0 add <validator_index>"
    exit 1
    ;;
esac