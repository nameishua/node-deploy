#!/usr/bin/env bash

# Exit on error and undefined variables
set -eu

# Define constants
readonly BASEDIR=$(cd "$(dirname "$0")" && pwd)
readonly WORKSPACE="${BASEDIR}"
readonly ENV_FILE="${WORKSPACE}/.env"

# Source environment variables
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || { echo "Error: .env file not found"; exit 1; }

# Create necessary directories
function create_directories() {
    mkdir -p "${WORKSPACE}/bin"
    mkdir -p "${WORKSPACE}/local/chain"
}

# Copy geth binary from chain build directory
function copy_geth() {
    echo "Copying geth binary..."
    local geth_source="${WORKSPACE}/chain/build/bin/geth"
    local geth_dest="${WORKSPACE}/bin/geth"
    
    if [ ! -f "$geth_source" ]; then
        echo "Error: geth binary not found at ${geth_source}"
        exit 1
    fi
    
    cp "$geth_source" "$geth_dest"
    chmod +x "$geth_dest"
    echo "Geth binary copied successfully"
}

# Initialize node with existing keys
function init_node() {
    create_directories
    copy_geth
    
    # 初始化网络
    ${WORKSPACE}/bin/geth init-network \
        --init.dir ${WORKSPACE}/local/chain \
        --init.size=${BSC_CLUSTER_SIZE} \
        --config ${WORKSPACE}/config.toml \
        ${WORKSPACE}/genesis/genesis.json

    # 复制现有密钥
    for ((i=0; i<${BSC_CLUSTER_SIZE}; i++)); do
        NODE_DIR="${WORKSPACE}/local/chain/node${i}"
        
        # 创建必要的目录
        mkdir -p "${NODE_DIR}/keystore"
        mkdir -p "${NODE_DIR}/bls"
        
        # 创建密码文件
        echo "${KEYPASS}" > "${NODE_DIR}/password.txt"
        
        # 复制validator密钥
        cp "${WORKSPACE}/keys/validator${i}/keystore/UTC--"* "${NODE_DIR}/keystore/"
        
        # 复制BLS密钥
        cp -r "${WORKSPACE}/keys/bls${i}/bls/"* "${NODE_DIR}/bls/"
        
        # 复制节点密钥
        mkdir -p "${NODE_DIR}/geth"
        cp "${WORKSPACE}/keys/nodekey${i}" "${NODE_DIR}/geth/nodekey"
        
        # 初始化节点
        ${WORKSPACE}/bin/geth --datadir "${NODE_DIR}" init \
            --state.scheme path \
            --db.engine pebble \
            "${WORKSPACE}/genesis/genesis.json" > "${NODE_DIR}/init.log" 2>&1
        
        echo "Node ${i} initialized successfully"
    done
}

# Main logic
case "$1" in
    "init")
        init_node
        ;;
    *)
        echo "Usage: $0 init"
        exit 1
        ;;
esac 