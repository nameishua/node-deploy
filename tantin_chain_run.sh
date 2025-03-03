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
gcmode="full"
sleepBeforeStart=10

# stop geth client
function exit_previous() {
    ValIdx=$1
    ps -ef  | grep geth$ValIdx | grep mine |awk '{print $2}' | xargs kill
    sleep ${sleepBeforeStart}
}

function native_start() {
    LastHardforkTime=${LAST_FORK_MORE_DELAY}
    ValIdx=$1
    
    for ((i = 0; i < size; i++));do
        if [ ! -z $ValIdx ] && [ $i -ne $ValIdx ]; then
            continue
        fi

        for j in ${workspace}/local/chain/node${i}/keystore/*;do
            cons_addr="0x$(cat ${j} | jq -r .address)"
        done

        HTTPPort=$((8545 + i))
        WSPort=${HTTPPort}
        MetricsPort=$((6060 + i))
 
        # geth may be replaced
        rm -f ${workspace}/local/chain/node${i}/geth${i}
        cp ${workspace}/bin/geth ${workspace}/local/chain/node${i}/geth${i}

        initLog=${workspace}/local/chain/node${i}/init.log
        rialtoHash=`cat ${initLog}|grep "database=chaindata"|awk -F"=" '{print $NF}'|awk -F'"' '{print $1}'`

        # run BSC node
        nohup  ${workspace}/local/chain/node${i}/geth${i} --config ${workspace}/local/chain/node${i}/config.toml \
            --datadir ${workspace}/local/chain/node${i} \
            --password ${workspace}/local/chain/node${i}/password.txt \
            --blspassword ${workspace}/local/chain/node${i}/password.txt \
            --nodekey ${workspace}/local/chain/node${i}/geth/nodekey \
            --unlock ${cons_addr} --miner.etherbase ${cons_addr} --rpc.allow-unprotected-txs --allow-insecure-unlock  \
            --ws.addr 0.0.0.0 --ws.port ${WSPort} --http.addr 0.0.0.0 --http.port ${HTTPPort} --http.corsdomain "*" \
            --metrics --metrics.addr localhost --metrics.port ${MetricsPort} --metrics.expensive \
            --gcmode ${gcmode} --syncmode full --mine --vote --monitor.maliciousvote \
            --rialtohash ${rialtoHash} --override.pascal ${LastHardforkTime} --override.prague ${LastHardforkTime} \
            --override.immutabilitythreshold ${FullImmutabilityThreshold} --override.breatheblockinterval ${BreatheBlockInterval} \
            --override.minforblobrequest ${MinBlocksForBlobRequests} --override.defaultextrareserve ${DefaultExtraReserveForBlobRequests} \
            > ${workspace}/local/chain/node${i}/chain-node.log 2>&1 &
        
        pid=$!
        echo "节点 ${i} 启动中，PID: ${pid}"
        
        # 等待检查节点是否成功启动
        sleep 5
        if ! ps -p $pid > /dev/null; then
            echo "错误：节点 ${i} 启动失败。请检查日志文件：${workspace}/local/chain/node${i}/chain-node.log"
            tail -n 20 ${workspace}/local/chain/node${i}/chain-node.log
            return 1
        fi
        
        # 简化的检查逻辑
        if [ -S "${workspace}/local/chain/node${i}/geth/geth.ipc" ]; then
            echo "节点 ${i} 启动成功！"
            echo "IPC端点: ${workspace}/local/chain/node${i}/geth/geth.ipc"
            echo "HTTP端点: http://localhost:$((8545 + i))"
            echo "WS端点: ws://localhost:$((8545 + i))"
        else
            echo "警告：未检测到IPC端点，但进程已启动。请手动检查节点状态。"
        fi
    done
}

function start_node() {
    local node_num=$1
    local node_dir="${WORKSPACE}/local/chain/node${node_num}"
    local log_file="${node_dir}/geth.log"

    echo "Starting node ${node_num}..."
    
    # 启动节点
    ${WORKSPACE}/bin/geth --config "${node_dir}/config.toml" \
        --datadir "${node_dir}" \
        --port $((30303 + node_num)) \
        --http.port $((8545 + node_num)) \
        --ws.port $((8546 + node_num)) \
        --unlock $(cat "${node_dir}/keystore/UTC--"* | jq -r '.address') \
        --password "${node_dir}/password.txt" \
        --mine \
        >> "${log_file}" 2>&1 &
    
    local pid=$!
    echo "Node started with PID: ${pid}"
    
    # 等待几秒检查节点是否成功启动
    sleep 5
    if ! ps -p $pid > /dev/null; then
        echo "Error: Node failed to start. Check logs at ${log_file}"
        tail -n 20 "${log_file}"
        return 1
    fi
    
    # 检查是否可以连接到节点
    for i in {1..12}; do
        if [ -S "${node_dir}/geth.ipc" ]; then
            echo "Node ${node_num} started successfully"
            echo "IPC endpoint: ${node_dir}/geth.ipc"
            echo "HTTP endpoint: http://localhost:$((8545 + node_num))"
            echo "WS endpoint: ws://localhost:$((8546 + node_num))"
            return 0
        fi
        sleep 5
    done
    
    echo "Error: Node failed to create IPC endpoint"
    tail -n 20 "${log_file}"
    return 1
}

CMD=$1
ValidatorIdx=$2
case ${CMD} in
stop)
    exit_previous $ValidatorIdx
    ;;
start)
    native_start $ValidatorIdx
    ;;
restart)
    exit_previous $ValidatorIdx
    native_start $ValidatorIdx
    ;;
*)
    echo "Usage: node.sh stop [vidx]| start [vidx]| restart [vidx]"
    ;;
esac
