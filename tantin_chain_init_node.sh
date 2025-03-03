#!/usr/bin/env bash

# Exit script on error
set -e

basedir=$(
    cd $(dirname $0)
    pwd
)
workspace=${basedir}
source ${workspace}/.env
size=$((BSC_CLUSTER_SIZE))
stateScheme="hash"
dbEngine="leveldb"

function create_validator() {
    local node_index=$1
    
    mkdir -p ${workspace}/local/chain
    cp -r ${workspace}/keys/validator${node_index} ${workspace}/local/chain/
    cp -r ${workspace}/keys/bls${node_index} ${workspace}/local/chain/
}

function prepare_config() {
    local node_index=$1
    
    rm -f ${workspace}/genesis/validators.conf
    
    passedHardforkTime=$(expr $(date +%s) + ${PASSED_FORK_DELAY})
    echo "passedHardforkTime "${passedHardforkTime} > ${workspace}/local/chain/hardforkTime.txt
    
    # 处理单个节点的配置
    for f in ${workspace}/local/chain/validator${node_index}/keystore/*; do
        cons_addr="0x$(cat ${f} | jq -r .address)"
        fee_addr=${cons_addr}
    done
    
    mkdir -p ${workspace}/local/chain/node${node_index}
    cp ${workspace}/keys/password.txt ${workspace}/local/chain/node${node_index}/
    cp ${workspace}/local/chain/hardforkTime.txt ${workspace}/local/chain/node${node_index}/
    bbcfee_addrs=${fee_addr}
    powers="0x000001d1a94a2000" #2000000000000
    mv ${workspace}/local/chain/bls${node_index}/bls ${workspace}/local/chain/node${node_index}/ && rm -rf ${workspace}/local/chain/bls${node_index}
    vote_addr=0x$(cat ${workspace}/local/chain/node${node_index}/bls/keystore/*json | jq .pubkey | sed 's/"//g')
    echo "${cons_addr},${bbcfee_addrs},${fee_addr},${powers},${vote_addr}" >> ${workspace}/genesis/validators.conf
    echo "validator ${node_index}: ${cons_addr}"
    echo "validatorFee ${node_index}: ${fee_addr}"
    echo "validatorVote ${node_index}: ${vote_addr}"
}

function init_node() {
    local node_index=$1
    
    if [ "$node_index" -ge "$size" ]; then
        echo "错误：节点索引 ${node_index} 超出集群大小 ${size}"
        exit 1
    fi
    
    # 创建并准备节点目录
    create_validator ${node_index}
    prepare_config ${node_index}
    
    # 初始化节点
    mkdir -p ${workspace}/local/chain/node${node_index}/geth
    cp ${workspace}/keys/nodekey${node_index} ${workspace}/local/chain/node${node_index}/geth/nodekey
    
    # 移动密钥文件
    mv ${workspace}/local/chain/validator${node_index}/keystore ${workspace}/local/chain/node${node_index}/ && rm -rf ${workspace}/local/chain/validator${node_index}
    
    # 初始化genesis
    initLog=${workspace}/local/chain/node${node_index}/init.log
    ${workspace}/bin/geth --datadir ${workspace}/local/chain/node${node_index} init \
        --state.scheme path --db.engine pebble \
        ${workspace}/genesis/genesis.json > "${initLog}" 2>&1
    
    echo "节点 ${node_index} 初始化成功"
}

# Main logic
if [ $# -ne 1 ]; then
    echo "用法: $0 <节点索引>"
    exit 1
fi

init_node "$1"
