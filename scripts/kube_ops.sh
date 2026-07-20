#!/bin/bash

## Local debugging
#export KUBECONFIG=~/.kube/k3s-101.53.yaml

## default namespace
NAMESPACE="yasin"

#===============================================================================
# collect logs Config
#===============================================================================
## collect log since
log_since="24h"
## collect mongodb io interval
mongodb_io_interval="10"
## clickhouse query logs limit
clickhouse_limit="100"

#===============================================================================
# K8S and Helm Config
#===============================================================================
## helm chart路径
chart_path="/home/yasin/cache/aiop-1.0.4.tgz"
## helm chart custom-values.yaml
chart_custom_values_yaml="/home/yasin/cache/custom-values.yaml"
#chart_custom_values_yaml="./tmp/custom-values.yaml"
## helm timeout
helm_timeout="600s"

#===============================================================================
# Pprof Config
#===============================================================================
## 服务端口
pprof_port="6470"
## 采集间隔(秒)
collect_interval=10
## 最大采集次数
max_collections=10
## 每次profile持续时间(秒),只对profile类型有效
profile_duration=60

#===============================================================================
# Database Config
#===============================================================================
# shellcheck disable=SC2016
clickhouse_cmd='clickhouse-client --password ${CLICKHOUSE_ADMIN_PASSWORD}'
clickhouse_pod="clickhouse-0"

# shellcheck disable=SC2016
mongodb_auth='${MONGODB_CLIENT_EXTRA_FLAGS} --username ${MONGODB_ROOT_USER} --password ${MONGODB_ROOT_PASSWORD} --authenticationDatabase admin'
# shellcheck disable=SC2016
mongodb_top_auth='${MONGODB_TOP_EXTRA_FLAGS} --username ${MONGODB_ROOT_USER} --password ${MONGODB_ROOT_PASSWORD} --authenticationDatabase admin'
mongodb_pod="mongodb-0"

# shellcheck disable=SC2016
redis_cmd='redis-cli -p ${REDIS_PORT_NUMBER:-6379} -a ${REDIS_PASSWORD}'
redis_pod="redis-0"

#===============================================================================
# Basic Function
#===============================================================================
# shellcheck disable=SC2028
printHeader() {
  printf "\n\n"
  echo -e "\033[33;1m"
  echo "                   _ooOoo_"
  echo "                  o8888888o"
  echo "                  88\" . \"88"
  echo "                  (| -_- |)"
  echo "                  O\\  =  /O"
  echo "               ____/\`---'\____"
  echo "             .'  \\\\|     |//  \`."
  echo "            /  \\\\|||  :  |||//  \\"
  echo "           /  _||||| -:- |||||-  \\"
  echo "           |   | \\\\\\  -  /// |   |"
  echo "           | \_|  ''\\---/''  |   |"
  echo "           \\  .-\\__  \`-\`  ___/-. /"
  echo "         ___\`. .'  /--.--\\  \`. . __"
  echo "      .\"\" '<  \`.___\\_<|>_/___.'  >'\`\"\"."
  echo "     | | :  \`- \`.;\`\\ _ /\`;.\` - \` : | |"
  echo "     \\  \\ \`-.   \\_ __\\ /__ _/   .-\` /  /"
  echo "======\`-.____\`-.___\\_____/___.-'\`____.-'======"
  echo "                   \`=---='"
  echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
  echo "           佛祖保佑       永无BUG"
  echo -e "\033[0m"
  echo "============================================================"
  echo "               K8S 集群交互式运维工具"
  echo "               当前命名空间: ${NAMESPACE}"
  echo "------------------------------------------------------------"
  echo "  Copyright (C) 2026 Yasin. All rights reserved."
  echo "  Author: Yasin Wu <yasin_wu@qq.com>"
  echo "  Version: 1.0.0"
  echo "============================================================"
}

colorLog() {
  RESET=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  local level=${1}
  local message=${2}
  case "${level}" in
  "INFO") color=${BLUE} ;;
  "SUCCESS") color=${GREEN} ;;
  "WARNING") color=${YELLOW} ;;
  "ERROR") color=${RED} ;;
  *) color=${RESET} ;;
  esac
  printf '%b\n' "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")] [${color}${level}${GREEN}] ${message}${RESET}" >&2
  if [ "${level}" == "ERROR" ]; then
    exit 1
  fi
}

printBlock() {
  local msg="${1}"
  local file="${2:-}"
  if [ -n "${file}" ]; then
    {
      echo ""
      echo "================================================================================"
      echo "  >>> ${msg}"
      echo "================================================================================"
      echo ""
    } | tee -a "${file}" > /dev/null
  else
    echo ""
    echo "================================================================================"
    echo "  >>> ${msg}"
    echo "================================================================================"
    echo ""
  fi
}

checkKubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    colorLog "ERROR" "未安装 kubectl, 无法执行运维操作"
  fi
}

readInput() {
  local prompt="${1}"
  local input
  echo -n "${prompt}: " >&2
  read -r input
  echo "${input}"
}

selectFromList() {
  local items="${1}"
  local prompt="${2}"
  local sel
  local -a arr=()
  local line

  if [ -z "${items}" ]; then
    return 1
  fi

  while IFS= read -r line; do
    [ -n "${line}" ] && arr+=("${line}")
  done <<< "${items}"

  if [ "${#arr[@]}" -eq 0 ]; then
    return 1
  fi

  if [ "${#arr[@]}" -eq 1 ]; then
    echo "${arr[0]}"
    return 0
  fi

  local max_len=0
  local expanded_line len
  for ((i = 0; i < ${#arr[@]}; i++)); do
    expanded_line=$(printf '%s' "${arr[i]}" | awk '{gsub(/\t/, "    "); print}')
    len=${#expanded_line}
    if [ "${len}" -gt "${max_len}" ]; then
      max_len=${len}
    fi
  done

  echo "" >&2
  echo "${prompt}" >&2
  echo "----------------------------------------" >&2
  local i
  for ((i = 0; i < ${#arr[@]}; i++)); do
    expanded_line=$(printf '%s' "${arr[i]}" | awk '{gsub(/\t/, "    "); print}')
    printf "  [%2d] %-*s\n" $((i + 1)) "${max_len}" "${expanded_line}" >&2
  done
  printf "  [%2d] %s\n" 0 "取消" >&2
  echo "----------------------------------------" >&2
  printf "请输入序号: " >&2
  read -r sel

  if ! [[ "${sel}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [ "${sel}" -eq 0 ] || [ "${sel}" -lt 1 ] || [ "${sel}" -gt "${#arr[@]}" ]; then
    return 1
  fi

  echo "${arr[$((sel - 1))]}"
  return 0
}

getNamespace() {
  local namespaces namespace selected
  namespaces=$(kubectl get namespaces --no-headers | awk '{print $1}')
  selected=$(selectFromList "${namespaces}" "请选择命名空间:")
  namespace=$(echo "${selected}" | awk '{print $1}')
  echo "${namespace}"
}

getNodeName() {
  local nodes node_name selected
  nodes=$(kubectl get nodes --no-headers)
  selected=$(selectFromList "${nodes}" "请选择节点:")
  node_name=$(echo "${selected}" | awk '{print $1}')
  echo "${node_name}"
}

getPodName() {
  local pods pod_name selected args=()
  local label_filter="${1}"
  [ -n "${label_filter}" ] && args+=("-l ${label_filter}")
  pods=$(kubectl get pod -n "${NAMESPACE}" --no-headers -owide "${args[@]}")
  selected=$(selectFromList "${pods}" "请选择 Pod:")
  pod_name=$(echo "${selected}" | awk '{print $1}')
  echo "${pod_name}"
}

getContainerName() {
  local containers container_name
  local pod_name="${1}"
  containers=$(kubectl get pod -n "${NAMESPACE}" "${pod_name}" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}')
  if [ "$(countLines "${containers}")" -gt 1 ]; then
    container_name=$(selectFromList "${containers}" "该 Pod 包含多个容器, 请选择:")
  else
    container_name="${containers}"
  fi
  echo "${container_name}"
}

getCmName() {
  local cms cm_name
  cms=$(kubectl get cm -n "${NAMESPACE}" --no-headers | awk '{print $1}')
  cm_name=$(selectFromList "${cms}" "请选择 ConfigMap:")
  echo "${cm_name}"
}

getAllWorkloadName() {
  local all_workloads selected args=()
  local label_filter="${1}"
  [ -n "${label_filter}" ] && args+=("-l ${label_filter}")
  all_workloads=$(
    {
      kubectl get deploy -n "${NAMESPACE}" --no-headers "${args[@]}" 2>/dev/null | awk '{print "deploy/" $1}'
      kubectl get sts -n "${NAMESPACE}" --no-headers "${args[@]}" 2>/dev/null | awk '{print "sts/" $1}'
      kubectl get ds -n "${NAMESPACE}" --no-headers "${args[@]}" 2>/dev/null | awk '{print "ds/" $1}'
    }
  )
  selected=$(selectFromList "${all_workloads}" "请选择应用:")
  echo "${selected}"
}

countLines() {
  echo "${1}" | grep -c . || true
}

collectLogs() {
  local log_file="./${output_dir}/logs/${1}.log"
  local plog_file="./${output_dir}/logs/${1}-previous.log"
  kubectl logs --since="${log_since}" -n "${NAMESPACE}" "${1}" 2>&1 | tee "${log_file}" > /dev/null
  kubectl logs -p -n "${NAMESPACE}" "${1}" 2>&1 | tee "${plog_file}" > /dev/null
}

collectClusterInfo() {
  local output_file="./${output_dir}/cluster_info.txt"
  colorLog "INFO" "开始采集master宿主机基础信息"
  printBlock "host cpu" "${output_file}"
  lscpu 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "host memory" "${output_file}"
  free -g 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "host disk" "${output_file}"
  df -h 2>&1 | tee -a "${output_file}" > /dev/null
  colorLog "SUCCESS" "采集master宿主机基础信息成功"
  colorLog "INFO" "开始采集集群基础信息"
  printBlock "cluster info" "${output_file}"
  kubectl get node -owide 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "cluster resource" "${output_file}"
  kubectl top node 2>&1 | tee -a "${output_file}" > /dev/null
  local nodes
  nodes=$(kubectl get nodes --no-headers | awk '{print $1}')
  for d in ${nodes}; do
    printBlock "node ${d} describe" "${output_file}"
    kubectl describe node "${d}" 2>&1 | tee -a "${output_file}" > /dev/null
  done
  colorLog "SUCCESS" "采集集群基础信息成功"
}

collectPodOverview() {
  colorLog "INFO" "开始采集应用概览"
  local output_file="./${output_dir}/pod_overview.txt"
  local pvs
  pvs=$(kubectl get pv -A --no-headers | awk '{print $1}')
  printBlock "pv" "${output_file}"
  for pv in ${pvs}; do
    printBlock "pv ${pv} describe" "${output_file}"
    kubectl describe pv "${pv}" 2>&1 | tee -a "${output_file}" > /dev/null
  done
  printBlock "pvc" "${output_file}"
  local pvs
  pvcs=$(kubectl get pvc -n "${NAMESPACE}" --no-headers | awk '{print $1}')
  for pvc in ${pvcs}; do
    printBlock "pvc ${pvc} describe" "${output_file}"
    kubectl describe pvc -n "${NAMESPACE}" "${pvc}" 2>&1 | tee -a "${output_file}" > /dev/null
  done
  printBlock "pod list" "${output_file}"
  kubectl get pod -A -owide 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "pod resource" "${output_file}"
  kubectl top pod -n "${NAMESPACE}" 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "service" "${output_file}"
  kubectl get svc -n "${NAMESPACE}" 2>&1 | tee -a "${output_file}" > /dev/null
  colorLog "SUCCESS" "采集应用概览成功"
  colorLog "INFO" "开始采集应用详情信息"
  local pod_names
  pod_names=$(kubectl get pod -n "${NAMESPACE}" --no-headers | awk '{print $1}')
  printBlock "pod describe" "${output_file}"
  for d in ${pod_names}; do
    local app_name phase
    app_name=$(kubectl get pod -n "${NAMESPACE}" "${d}" -o jsonpath='{.metadata.labels.app}')
    phase=$(kubectl get pod -n "${NAMESPACE}" "${d}" -o jsonpath='{.status.phase}')
    printBlock "${app_name} describe, pod: ${d}, status: ${phase}" "${output_file}"
    kubectl describe pod -n "${NAMESPACE}" "${d}" 2>&1 | tee -a "${output_file}" > /dev/null
    collectLogs "${d}"
  done
  colorLog "SUCCESS" "采集应用详情信息成功"
}

collectConfigMaps() {
  colorLog "INFO" "开始采集应用配置文件"
  local cms
  cms=$(kubectl get cm -n "${NAMESPACE}" --no-headers | awk '{print $1}')
  for d in ${cms}; do
    [ "${d}" == "kube-root-ca.crt" ] && continue
    local output_file="./${output_dir}/configmaps/${d}.yaml"
    printBlock "${d} configmap" "${output_file}"
    kubectl get cm -n "${NAMESPACE}" "${d}" -oyaml 2>&1 | tee -a "${output_file}" > /dev/null
  done
  colorLog "SUCCESS" "采集应用配置文件成功"
}

collectClickhouse() {
  colorLog "INFO" "开始采集Clickhouse信息"
  local output_file="./${output_dir}/database/clickhouse.txt"
  printBlock "clickhouse describe" "${output_file}"
  kubectl describe pod -n "${NAMESPACE}" -l app=clickhouse 2>&1 | tee -a "${output_file}" > /dev/null
  local status
  status=$(kubectl get pod -n "${NAMESPACE}" "${clickhouse_pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [  "${status}" != "true" ] && { colorLog "ERROR" "无可用Clickhouse POD"; return; }
  printBlock "clickhouse memory usage top 100" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"SELECT event_time, client_hostname, query_duration_ms, formatReadableSize(memory_usage), read_rows, projections, query \
              FROM system.query_log WHERE 1=1 AND event_time >= (now() - toIntervalMinute(60)) AND type = 'QueryFinish' \
              ORDER BY memory_usage DESC, query_duration_ms DESC LIMIT ${clickhouse_limit}\"" \
    2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "clickhouse merges" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query 'SELECT database, table, elapsed, progress, num_parts, result_part_name, is_mutation, merge_type FROM system.merges'" \
    2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "clickhouse mutation" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query 'SELECT database, table, mutation_id, command, create_time, parts_to_do, is_done FROM system.mutations WHERE is_done = 0'" \
    2>&1 | tee -a "${output_file}" > /dev/null
  collectLogs "${clickhouse_pod}"
  colorLog "SUCCESS" "采集Clickhouse信息成功"
}

collectMongodb() {
  colorLog "INFO" "开始采集Mongodb信息"
  local output_file="./${output_dir}/database/mongodb.txt"
  printBlock "mongodb describe" "${output_file}"
  kubectl describe pod -n "${NAMESPACE}" -l app=mongodb 2>&1 | tee -a "${output_file}" > /dev/null
  local status
  status=$(kubectl get pod -n "${NAMESPACE}" "${mongodb_pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [  "${status}" != "true" ] && { colorLog "ERROR" "无可用Mongodb POD"; return; }
  printBlock "mongodb stats" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${mongodb_pod}" -c mongodb -- sh -c "mongo ${mongodb_auth} \
  --eval 'db.adminCommand({listDatabases:1}).databases.forEach(function(database) {
          if (database.name === \"system\" || database.name === \"admin\" ||
          database.name === \"config\" || database.name === \"local\") return;
          db = db.getSiblingDB(database.name);
          db.getCollectionNames().forEach(function(collection) {
            var stats = db[collection].stats();
            var count = db[collection].count();
            print(database.name + \".\" + collection +
                  \" - count: \" + count +
                  \" - data_size: \" + Math.round(stats.storageSize / 1024) + \"KB, \" +
                  \"index_size: \" + Math.round(stats.totalIndexSize / 1024) + \"KB\");
        });
    })'" 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "mongodb io" "${output_file}"
  (
    kubectl exec -n "${NAMESPACE}" "${mongodb_pod}" -c mongodb -- sh -c "mongotop ${mongodb_top_auth} 2"
  ) 2>&1 | tee -a "${output_file}" > /dev/null &
  local pipe_pid=$!
  sleep "${mongodb_io_interval}"
  kill "${pipe_pid}" 2>/dev/null
  wait "${pipe_pid}" 2>/dev/null
  collectLogs "${mongodb_pod}"
  colorLog "SUCCESS" "采集Mongodb信息成功"
}

collectRedis() {
  colorLog "INFO" "开始采集Redis信息"
  local output_file="./${output_dir}/database/redis.txt"
  printBlock "redis describe" "${output_file}"
  kubectl describe pod -n "${NAMESPACE}" -l app=redis 2>&1 | tee -a "${output_file}" > /dev/null
  local status
  status=$(kubectl get pod -n "${NAMESPACE}" "${redis_pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [  "${status}" != "true" ] && { colorLog "ERROR" "无可用Redis POD"; return; }
  printBlock "redis keyspace" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${redis_pod}" -c redis -- sh -c "${redis_cmd} INFO KEYSPACE" 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "redis memory" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${redis_pod}" -c redis -- sh -c "${redis_cmd} INFO MEMORY" 2>&1 | tee -a "${output_file}" > /dev/null
  printBlock "redis bigkeys" "${output_file}"
  kubectl exec -n "${NAMESPACE}" "${redis_pod}" -c redis -- sh -c "${redis_cmd} --bigkeys" 2>&1 | tee -a "${output_file}" > /dev/null
  collectLogs "${redis_pod}"
  colorLog "SUCCESS" "采集Redis信息成功"
}

collectNats() {
  colorLog "INFO" "开始采集Nats信息"
  local output_file="./${output_dir}/database/nats.txt"
  printBlock "nats describe" "${output_file}"
  kubectl describe pod -n "${NAMESPACE}" -l app=nats 2>&1 | tee -a "${output_file}" > /dev/null
  local pod_name="nats-0"
  status=$(kubectl get pod -n "${NAMESPACE}" "${pod_name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [  "${status}" != "true" ] && { colorLog "ERROR" "无可用Nats POD"; return; }
  collectLogs "${pod_name}"
  colorLog "SUCCESS" "采集Nats信息成功"
}

collectChartValues() {
  colorLog "INFO" "开始采集Chart Values"
  local output_file="./${output_dir}/values.yaml"
  helm get values -n "${NAMESPACE}" "${NAMESPACE}" --all  2>&1 | tee -a "${output_file}" > /dev/null
  sed -i '1d' "${output_file}"
  colorLog "SUCCESS" "采集Chart Values成功"
}

deleteClickhouseParts() {
  local table="${1}"
  local status parts
  status=$(kubectl get pod -n "${NAMESPACE}" "${clickhouse_pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [  "${status}" != "true" ] && { colorLog "ERROR" "无可用Clickhouse POD"; return; }
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"SELECT DISTINCT partition_id, partition FROM system.parts
                  WHERE database='default' AND table='${table}'
                  AND parseDateTimeBestEffort(replaceAll(splitByString(',', partition)[-1], ')', '')) <= toStartOfMonth(addMonths(today(), -${reserve})) ORDER BY partition;\"")
  if [ -z "${parts}" ]; then
    colorLog "WARNING" "表${table}无${reserve}个月前数据, 取消删除"
    local count
    count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${table};\"")
    colorLog "SUCCESS" "表${table}数据总量: ${count}"
    return
  fi
  colorLog "WARNING" "即将删除表${table}以下分区数据: ${parts}"
  confirm=$(readInput "$(printf '\e[31m请确认是否删除? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消删除表${table}数据"; return; }
  while IFS=$'\t' read -r col1 col2; do
    local col2=${col2//\\/}
    colorLog "INFO" "开始删除表${table}数据 partition_id: ${col1}, partition: ${col2}"
    kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
          --query \"ALTER TABLE ${table} DROP PARTITION ${col2}\""
    colorLog "SUCCESS" "成功删除表${table}数据 partition_id: ${col1}, partition: ${col2}"
  done <<< "${parts}"
  colorLog "SUCCESS" "成功删除表${table}数据"
  local count
  count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${table};\"")
  colorLog "SUCCESS" "表${table}数据总量: ${count}"
}

createTables() {
  colorLog "INFO" "开始创建client_process_resource_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"create table if not exists client_process_resource_new
            (
                client_id    String,
                collected_at Int64,
                cpu_used     Int64,
                created_at   Int64,
                desc         String,
                disk_read    Int64,
                disk_write   Int64,
                fds          Int64,
                id           String,
                memory_used  Int64,
                name         String,
                pid          String,
                product      String,
                running_desc String,
                started_at   Int64,
                state        Int64,
                tenant_id    String,
                updated_at   Int64,
                version      String
            )
                engine = MergeTree PARTITION BY (tenant_id, toYYYYMM(toDateTime(created_at)))
                    ORDER BY (tenant_id, created_at, client_id, updated_at, collected_at, started_at)
                    TTL toDateTime(created_at) + toIntervalYear(1) TO VOLUME 'cold'
                    SETTINGS storage_policy = 'ttl', index_granularity = 8192;\""

  colorLog "INFO" "开始创建sensitive_category_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"create table if not exists sensitive_category_level_new
              (
                  category       String,
                  client_id      String,
                  created_at     Int64,
                  file_id        String,
                  file_uuid      String,
                  id             String,
                  level          Int64,
                  platform       String,
                  policy         String,
                  policy_version Int64,
                  rule           String,
                  rule_tag       String,
                  tenant_id      String,
                  updated_at     Int64
              )
                  engine = MergeTree PARTITION BY (tenant_id, toYYYYMM(toDateTime(created_at)))
                      ORDER BY (tenant_id, created_at, client_id, file_id, id, category, level, rule, policy, platform, rule_tag, policy_version, file_uuid)
                      TTL toDateTime(created_at) + toIntervalYear(1) TO VOLUME 'cold'
                      SETTINGS storage_policy = 'ttl', index_granularity = 8192;\""

  colorLog "INFO" "开始创建sensitive_file_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"create table if not exists sensitive_file_new
              (
                  category       String,
                  client_id      String,
                  created_at     Int64,
                  discovery_time Int64,
                  file_path      String,
                  file_storage   String,
                  file_trace_id  String,
                  filename       String,
                  id             String,
                  level          Int64,
                  md5            String,
                  platform       String,
                  policy_version Int64,
                  rule           String,
                  rule_tag       String,
                  sha1           String,
                  size           Int64,
                  tenant_id      String,
                  update_type    String,
                  updated_at     Int64,
                  uuid           String
              )
                  engine = MergeTree PARTITION BY (tenant_id, toYYYYMM(toDateTime(created_at)))
                      ORDER BY (tenant_id, created_at, client_id, id, filename, md5, sha1, category, level, rule, update_type, platform, discovery_time, updated_at, size, rule_tag, file_storage, policy_version, uuid)
                      TTL toDateTime(created_at) + toIntervalYear(1) TO VOLUME 'cold'
                      SETTINGS storage_policy = 'ttl', index_granularity = 8192;\""

  colorLog "INFO" "开始创建sensitive_file_category_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"create table if not exists sensitive_file_category_new
              (
                  category       String,
                  client_id      String,
                  content        String,
                  created_at     Int64,
                  file_id        String,
                  file_uuid      String,
                  hit_count      Int64,
                  id             String,
                  platform       String,
                  policy         String,
                  policy_version Int64,
                  recognize_type String,
                  rule           String,
                  rule_tag       String,
                  similarity     Int64,
                  tenant_id      String,
                  trait          String,
                  updated_at     Int64,
                  uuid           String
              )
                  engine = MergeTree PARTITION BY (tenant_id, toYYYYMM(toDateTime(created_at)))
                      ORDER BY (tenant_id, created_at, client_id, file_id, id, uuid, content, trait, category, hit_count, similarity, recognize_type, rule, policy, platform, rule_tag, policy_version, file_uuid)
                      TTL toDateTime(created_at) + toIntervalYear(1) TO VOLUME 'cold'
                      SETTINGS storage_policy = 'ttl', index_granularity = 8192;\""

  colorLog "INFO" "开始创建sensitive_file_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
    --query \"create table if not exists sensitive_file_level_new
              (
                  client_id      String,
                  content        String,
                  created_at     Int64,
                  file_id        String,
                  file_uuid      String,
                  hit_count      Int64,
                  id             String,
                  level          Int64,
                  platform       String,
                  policy         String,
                  policy_version Int64,
                  recognize_type String,
                  rule           String,
                  rule_tag       String,
                  similarity     Int64,
                  tenant_id      String,
                  trait          String,
                  updated_at     Int64,
                  uuid           String
              )
                  engine = MergeTree PARTITION BY (tenant_id, toYYYYMM(toDateTime(created_at)))
                      ORDER BY (tenant_id, created_at, client_id, file_id, id, uuid, content, trait, level, hit_count, similarity, recognize_type, rule, policy, platform, rule_tag, policy_version, file_uuid)
                      TTL toDateTime(created_at) + toIntervalYear(1) TO VOLUME 'cold'
                      SETTINGS storage_policy = 'ttl', index_granularity = 8192;\""
}

migrateData() {
  local src_count=0 target_count=0 diff=0 diff_count=1000
  local parts part created_at
  local src_table="client_process_resource"
  local target_table="client_process_resource_new"
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT DISTINCT partition FROM system.parts WHERE database='default' AND table='${src_table}';\"")
  for part in ${parts};do
    colorLog "INFO" "开始迁移${src_table}到${target_table}, 分区: ${part}"
    for i in $(seq 1 31); do
      [[ "${part}" =~ ([0-9]{6})[^0-9]*$ ]] && created_at="${BASH_REMATCH[1]}"
      created_at="${created_at}$(printf "%02d" "${i}")"
      kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"INSERT INTO ${target_table} (client_id, collected_at, cpu_used, created_at, desc, disk_read, disk_write,
                    fds, id, memory_used, name, pid, product, running_desc, started_at, state, tenant_id, updated_at, version)
                  SELECT client_id, collected_at, cpu_used, created_at, desc, disk_read, disk_write,
                    fds, id, memory_used, name, pid, product, running_desc, started_at, state, tenant_id, updated_at, version
                  FROM ${src_table}
                  WHERE toYYYYMMDD(toDateTime(created_at)) = ${created_at};\""
    done
  done
  src_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${src_table};\"")
  target_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${target_table};\"")
  colorLog "INFO" "迁移完成, 源表${src_table}数据量: ${src_count}, 迁移后${target_table}数据量: ${target_count}"
  diff=$((src_count - target_count))
  [ "${diff}" -lt 0 ] && diff=$((-diff))
  if [ "${diff}" -gt "${diff_count}" ]; then
    colorLog "WARNING" "源表${src_table}数据量和迁移后${target_table}数据量相差超过${diff_count}, 请排查"
    ((error_count++))
  fi
  ##########
  local src_table="sensitive_category_level"
  local target_table="sensitive_category_level_new"
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT DISTINCT partition FROM system.parts WHERE database='default' AND table='${src_table}';\"")
  for part in ${parts};do
    colorLog "INFO" "开始迁移${src_table}到${target_table}, 分区: ${part}"
    for i in $(seq 1 31); do
      [[ "${part}" =~ ([0-9]{6})[^0-9]*$ ]] && created_at="${BASH_REMATCH[1]}"
      created_at="${created_at}$(printf "%02d" "${i}")"
      kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"INSERT INTO ${target_table} (category, client_id, created_at, file_id, file_uuid, id, level, platform,
                    policy, policy_version, rule, rule_tag, tenant_id, updated_at)
                  SELECT category, client_id, created_at, file_id, file_uuid, id, level, platform,
                    policy, 0, rule, rule_tag, tenant_id, updated_at
                  FROM ${src_table}
                  WHERE toYYYYMMDD(toDateTime(created_at)) = ${created_at};\""
    done
  done
  src_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${src_table};\"")
  target_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${target_table};\"")
  colorLog "INFO" "迁移完成, 源表${src_table}数据量: ${src_count}, 迁移后${target_table}数据量: ${target_count}"
  diff=$((src_count - target_count))
  [ "${diff}" -lt 0 ] && diff=$((-diff))
  if [ "${diff}" -gt "${diff_count}" ]; then
    colorLog "WARNING" "源表${src_table}数据量和迁移后${target_table}数据量相差超过${diff_count}, 请排查"
    ((error_count++))
  fi
  ##########
  local src_table="sensitive_file"
  local target_table="sensitive_file_new"
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT DISTINCT partition FROM system.parts WHERE database='default' AND table='${src_table}';\"")
  for part in ${parts};do
    colorLog "INFO" "开始迁移${src_table}到${target_table}, 分区: ${part}"
    for i in $(seq 1 31); do
      [[ "${part}" =~ ([0-9]{6})[^0-9]*$ ]] && created_at="${BASH_REMATCH[1]}"
      created_at="${created_at}$(printf "%02d" "${i}")"
      kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"INSERT INTO ${target_table} (category, client_id, created_at, discovery_time, file_path, file_storage, file_trace_id,
                    filename, id, level, md5, platform, policy_version, rule, rule_tag, sha1, size, tenant_id, update_type, updated_at, uuid)
                  SELECT category, client_id, created_at, discovery_time, file_path, file_storage, file_trace_id,
                    filename, id, level, md5, platform, 0, rule, rule_tag, sha1, size, tenant_id, update_type, updated_at, uuid
                  FROM ${src_table}
                  WHERE toYYYYMMDD(toDateTime(created_at)) = ${created_at};\""
    done
  done
  src_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${src_table};\"")
  target_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${target_table};\"")
  colorLog "INFO" "迁移完成, 源表${src_table}数据量: ${src_count}, 迁移后${target_table}数据量: ${target_count}"
  diff=$((src_count - target_count))
  [ "${diff}" -lt 0 ] && diff=$((-diff))
  if [ "${diff}" -gt "${diff_count}" ]; then
    colorLog "WARNING" "源表${src_table}数据量和迁移后${target_table}数据量相差超过${diff_count}, 请排查"
    ((error_count++))
  fi
  ##########
  local src_table="sensitive_file_category"
  local target_table="sensitive_file_category_new"
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT DISTINCT partition FROM system.parts WHERE database='default' AND table='${src_table}';\"")
  for part in ${parts};do
    colorLog "INFO" "开始迁移${src_table}到${target_table}, 分区: ${part}"
    for i in $(seq 1 31); do
      [[ "${part}" =~ ([0-9]{6})[^0-9]*$ ]] && created_at="${BASH_REMATCH[1]}"
      created_at="${created_at}$(printf "%02d" "${i}")"
      kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"INSERT INTO ${target_table} (category, client_id, content, created_at, file_id, file_uuid, hit_count, id,
                    platform, policy, policy_version, recognize_type, rule, rule_tag, similarity, tenant_id, trait, updated_at, uuid)
                  SELECT category, client_id, content, created_at, file_id, file_uuid, hit_count, id,
                    platform, policy, 0, recognize_type, rule, rule_tag, similarity, tenant_id, trait, updated_at, uuid
                  FROM ${src_table}
                  WHERE toYYYYMMDD(toDateTime(created_at)) = ${created_at};\""
    done
  done
  src_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${src_table};\"")
  target_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${target_table};\"")
  colorLog "INFO" "迁移完成, 源表${src_table}数据量: ${src_count}, 迁移后${target_table}数据量: ${target_count}"
  diff=$((src_count - target_count))
  [ "${diff}" -lt 0 ] && diff=$((-diff))
  if [ "${diff}" -gt "${diff_count}" ]; then
    colorLog "WARNING" "源表${src_table}数据量和迁移后${target_table}数据量相差超过${diff_count}, 请排查"
    ((error_count++))
  fi
  ##########
  local src_table="sensitive_file_level"
  local target_table="sensitive_file_level_new"
  parts=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT DISTINCT partition FROM system.parts WHERE database='default' AND table='${src_table}';\"")
  for part in ${parts};do
    colorLog "INFO" "开始迁移${src_table}到${target_table}, 分区: ${part}"
    for i in $(seq 1 31); do
      [[ "${part}" =~ ([0-9]{6})[^0-9]*$ ]] && created_at="${BASH_REMATCH[1]}"
      created_at="${created_at}$(printf "%02d" "${i}")"
      kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} \
        --query \"INSERT INTO ${target_table} (client_id, content, created_at, file_id, file_uuid, hit_count, id, level,
                    platform, policy, policy_version, recognize_type, rule, rule_tag, similarity, tenant_id, trait, updated_at, uuid)
                  SELECT client_id, content, created_at, file_id, file_uuid, hit_count, id, level,
                    platform, policy, 0, recognize_type, rule, rule_tag, similarity, tenant_id, trait, updated_at, uuid
                  FROM ${src_table}
                  WHERE toYYYYMMDD(toDateTime(created_at)) = ${created_at};\""
    done
  done
  src_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${src_table};\"")
  target_count=$(kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"SELECT count() FROM ${target_table};\"")
  colorLog "INFO" "迁移完成, 源表${src_table}数据量: ${src_count}, 迁移后${target_table}数据量: ${target_count}"
  diff=$((src_count - target_count))
  [ "${diff}" -lt 0 ] && diff=$((-diff))
  if [ "${diff}" -gt "${diff_count}" ]; then
    colorLog "WARNING" "源表${src_table}数据量和迁移后${target_table}数据量相差超过${diff_count}, 请排查"
    ((error_count++))
  fi
}

dropNewTables() {
  colorLog "INFO" "开始删除client_process_resource_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"DROP TABLE IF EXISTS client_process_resource_new;\""
  colorLog "INFO" "开始删除sensitive_category_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"DROP TABLE IF EXISTS sensitive_category_level_new;\""
  colorLog "INFO" "开始删除sensitive_file_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"DROP TABLE IF EXISTS sensitive_file_new;\""
  colorLog "INFO" "开始删除sensitive_file_category_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"DROP TABLE IF EXISTS sensitive_file_category_new;\""
  colorLog "INFO" "开始删除sensitive_file_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"DROP TABLE IF EXISTS sensitive_file_level_new;\""
}

renameTables() {
  local date
  date=$(date "+%Y%m%d%H%M")
  colorLog "INFO" "开始重命名client_process_resource_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"RENAME TABLE client_process_resource TO client_process_resource_${date}, client_process_resource_new TO client_process_resource;\""
  colorLog "INFO" "开始重命名sensitive_category_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"RENAME TABLE sensitive_category_level TO sensitive_category_level_${date}, sensitive_category_level_new TO sensitive_category_level;\""
  colorLog "INFO" "开始重命名sensitive_file_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"RENAME TABLE sensitive_file TO sensitive_file_${date}, sensitive_file_new TO sensitive_file;\""
  colorLog "INFO" "开始重命名sensitive_file_category_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"RENAME TABLE sensitive_file_category TO sensitive_file_category_${date}, sensitive_file_category_new TO sensitive_file_category;\""
  colorLog "INFO" "开始重命名sensitive_file_level_new"
  kubectl exec -n "${NAMESPACE}" "${clickhouse_pod}" -c clickhouse -- sh -c "${clickhouse_cmd} --query \"RENAME TABLE sensitive_file_level TO sensitive_file_level_${date}, sensitive_file_level_new TO sensitive_file_level;\""
}

stopAllDeploy() {
  colorLog "INFO" "开始停止应用"
  local available
  kubectl scale deploy -n "${NAMESPACE}" --all --replicas=0
  for deploy in $(kubectl get deploy -n "${NAMESPACE}" -o=jsonpath='{.items[*].metadata.name}'); do
    available=$(kubectl get deploy "${deploy}" -n "${NAMESPACE}" -o=jsonpath='{.status.availableReplicas}')
    { [ -z "${available}" ] || [ "${available}" -eq 0 ]; } && colorLog "INFO" "${deploy} 可用副本数为0"
  done
  colorLog "SUCCESS" "停止应用完成"
}

startAllDeploy() {
  colorLog "INFO" "开始启动应用"
  kubectl scale deploy -n "${NAMESPACE}" --all --replicas=1
  colorLog "INFO" "等待启动应用完成......"
  kubectl rollout status deploy -n "${NAMESPACE}"
  colorLog "SUCCESS" "启动应用完成"
}

runRedisCleaner() {
  local overrides="${1}"
  kubectl run redis-cleaner -n "${NAMESPACE}" --rm -i --restart=Never \
    --image="${busybox_image}" \
    --image-pull-policy=IfNotPresent \
    --overrides="${overrides}"
}

runMongodbRepair() {
  local overrides="${1}"
  kubectl run mongodb-repair -n "${NAMESPACE}" --rm -i --restart=Never \
    --image="${mongodb_image}" \
    --image-pull-policy=IfNotPresent \
    --overrides="${overrides}"
}

getDispatchableDeploy() {
  local -a services=(
    "agcbb"
    "agentserver"
    "aiop.agentsvc"
    "clickhouse"
    "freeradius"
    "goms"
    "logminer"
    "mongodb"
    "nats"
    "nginx.agent"
    "nginx.web"
    "ngtdcbbag"
    "paddleOcr"
    "radius-s"
    "redis"
    "roam"
  )
  local input

  echo "" >&2
  echo "请选择要调度的应用(已选择 ${change_count} 项, 输入 0 结束选择): " >&2
  local i
  for ((i = 0; i < ${#services[@]}; i++)); do
    printf "  [%2d] %s\n" $((i + 1)) "${services[i]}" >&2
  done
  printf "  [%2d] %s\n" 0 "结束选择并开始确认" >&2
  printf "请输入序号: " >&2
  read -r input

  if ! [[ "${input}" =~ ^[0-9]+$ ]]; then
    echo ""
    return
  fi

  if [ "${input}" -eq 0 ]; then
    echo "exit"
    return
  fi

  if [ "${input}" -lt 1 ] || [ "${input}" -gt "${#services[@]}" ]; then
    echo ""
    return
  fi

  echo "${services[$((input - 1))]}"
}

validatePort() {
  local port="${1}"
  if [ -z "${port}" ]; then
    colorLog "WARNING" "端口不能为空, 输入值: ${port}"
    return 1
  fi
  if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
    colorLog "WARNING" "端口必须为数字, 输入值: ${port}"
    return 1
  fi
  if [ "${port}" -lt 1 ] || [ "${port}" -gt 39999 ]; then
    colorLog "WARNING" "端口必须在 1-39999 范围内, 输入值: ${port}"
    return 1
  fi
  return 0
}

validateCpu() {
  local cpu="${1}"
  [ -z "${cpu}" ] && return 0
  if ! [[ "${cpu}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && ! [[ "${cpu}" =~ ^[0-9]+m$ ]]; then
    colorLog "WARNING" "CPU 格式无效, 应为数字(如 0.5, 2)或毫核(如 500m), 输入值: ${cpu}"
    return 1
  fi
  return 0
}

validateMemory() {
  local memory="${1}"
  [ -z "${memory}" ] && return 0
  if ! [[ "${memory}" =~ ^[0-9]+(\.[0-9]+)?(Ei|Pi|Ti|Gi|Mi|Ki|E|P|T|G|M|K)?$ ]]; then
    colorLog "WARNING" "Memory 格式无效, 应为数字加单位(如 512Mi, 1Gi, 2G), 输入值: ${memory}"
    return 1
  fi
  if [[ "${memory}" =~ Gi$ ]]; then
    return 0
  fi
  colorLog "WARNING" "Memory 未使用 Gi 单位, 当前输入: ${memory}, 建议 limits 使用 Gi 单位(如 1Gi, 2Gi)"
  return 2
}

buildYqPath() {
  local path="${1}"
  local suffix="${2}"
  local result=""
  local part
  IFS='.' read -ra parts <<< "${path}"
  for part in "${parts[@]}"; do
    result="${result}[\"${part}\"]"
  done
  echo ".${result}${suffix}"
}

getResourcesLimitsDeploy() {
  local -a services=(
    "nginx.agent"
    "nginx.web"
    "aiop"
    "aiop.agentsvc"
    "product"
    "bff"
    "agentserver"
    "goms"
    "logminer"
    "clickhouse"
    "mongodb"
    "redis"
    "nats"
    "paddleOcr"
    "roam"
    "radius-s"
    "agcbb"
    "ngtdcbbag"
    "freeradius"
  )
  local i input
  echo "" >&2
  echo "请选择要修改资源 limits 的应用(已选择 ${#selected_services[@]} 项, 输入 0 结束选择): " >&2
  for ((i = 0; i < ${#services[@]}; i++)); do
    printf "  [%2d] %s\n" $((i + 1)) "${services[i]}" >&2
  done
  printf "  [%2d] %s\n" 0 "结束选择并开始确认" >&2
  printf "请输入序号: " >&2
  read -r input

  if ! [[ "${input}" =~ ^[0-9]+$ ]]; then
    echo ""
    return
  fi
  if [ "${input}" -eq 0 ]; then
    echo "exit"
    return
  fi
  if [ "${input}" -lt 1 ] || [ "${input}" -gt "${#services[@]}" ]; then
    echo ""
    return
  fi
  echo "${services[$((input - 1))]}"
}

helmUpgrade() {
  colorLog "INFO" "更新 chart 中, 请稍后......"
  helm upgrade -n "${NAMESPACE}" "${NAMESPACE}" --timeout "${helm_timeout}" "${chart_path}" -f "${chart_custom_values_yaml}" || colorLog "ERROR" "更新 chart 失败"
  colorLog "INFO" "等待重启应用完成, 请稍后......"
  kubectl rollout status deploy,sts -n "${NAMESPACE}" --timeout "${helm_timeout}"
}

#===============================================================================
# Function implementation
#===============================================================================
switchNamespace() {
  local ns
  ns=$(getNamespace)
  [ -z "${ns}" ] && { colorLog "WARNING" "未选择命名空间"; return; }
  [ -n "${ns}" ] && { NAMESPACE="${ns}"; colorLog "SUCCESS" "已切换至命名空间: ${NAMESPACE}"; }
}

showNodes() {
  colorLog "INFO" "节点列表"
  kubectl get node -owide
}

showNodeResources() {
  colorLog "INFO" "节点资源使用率"
  kubectl top node 2>/dev/null || colorLog "WARNING" "未配置 metrics-server, 无法获取资源使用率"
}

showNodeDetail() {
  local node_name
  node_name=$(getNodeName)
  [ -z "${node_name}" ] && { colorLog "WARNING" "未选择节点"; return; }
  colorLog "INFO" "节点 ${node_name} 详情"
  kubectl describe node "${node_name}"
}

showPods() {
  local label_filter args=()
  label_filter=$(readInput "输入标签筛选条件(如 app=nginx, 直接回车查看全部)")
  colorLog "INFO" "Pod 列表"
  [ -n "${label_filter}" ] && args+=("-l ${label_filter}")
  kubectl get pod -n "${NAMESPACE}" -owide "${args[@]}"
}

showPodResources() {
  colorLog "INFO" "Pod 资源使用率"
  kubectl top pod -n "${NAMESPACE}" 2>/dev/null || colorLog "WARNING" "未配置 metrics-server, 无法获取资源使用率"
}

showPodDetail() {
  local pod_name
  pod_name=$(getPodName "")
  [ -z "${pod_name}" ] && { colorLog "WARNING" "未选择 Pod"; return; }
  colorLog "INFO" "Pod ${pod_name} 详情"
  kubectl describe pod -n "${NAMESPACE}" "${pod_name}"
}

showPodLogs() {
  local pod_name container_name follow_input since_input filter_input args=()
  pod_name=$(getPodName "")
  [ -z "${pod_name}" ] && { colorLog "WARNING" "未选择 Pod"; return; }
  container_name=$(getContainerName "${pod_name}")
  [ -z "${container_name}" ] && { colorLog "WARNING" "未选择容器"; return; }
  follow_input=$(readInput "是否实时跟踪日志 [y/n]")
  [ "${follow_input}" == "y" ] && args+=("-f")
  since_input=$(readInput "查看最近多长时间 [默认10m], 格式如 1m, 1h")
  [ -z "${since_input}" ] && since_input="10m"
  [ -n "${since_input}" ] && args+=("--since=${since_input}")
  filter_input=$(readInput "输入日志筛选条件 [默认空]")
  [ -n "${filter_input}" ] && args+=(" | ${filter_input}")
  colorLog "INFO" "Pod ${pod_name} 容器 ${container_name} 日志"
  eval "kubectl logs -n ${NAMESPACE} ${pod_name} -c ${container_name} ${args[*]}"
}

restartPod() {
  local workload
  workload=$(getAllWorkloadName "")
  [ -z "${workload}" ] || [ "${workload}" == "/" ] && { colorLog "WARNING" "未选择应用"; return; }
  local res_type res_name
  res_type=$(echo "${workload}" | cut -d'/' -f1)
  res_name=$(echo "${workload}" | cut -d'/' -f2)
  confirm=$(readInput "$(printf '\e[31m确认将 %s 重启?[y/n]\e[0m' "${res_type}/${res_name}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  colorLog "INFO" "重启 ${res_type}/${res_name}"
  kubectl rollout restart "${res_type}" "${res_name}" -n "${NAMESPACE}"
  colorLog "INFO" "等待滚动更新 ${res_type}/${res_name} 完成......"
  kubectl rollout status "${res_type}" "${res_name}" -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "重启完成 ${res_type}/${res_name}"
}

stopPod() {
  local workload
  workload=$(getAllWorkloadName "")
  [ -z "${workload}" ] || [ "${workload}" == "/" ] && { colorLog "WARNING" "未选择应用"; return; }
  local res_type res_name
  res_type=$(echo "${workload}" | cut -d'/' -f1)
  res_name=$(echo "${workload}" | cut -d'/' -f2)
  confirm=$(readInput "$(printf '\e[31m确认将 %s 停止?[y/n]\e[0m' "${res_type}/${res_name}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  colorLog "INFO" "停止 ${res_type}/${res_name}"
  if [ "${res_type}" == "ds" ]; then
    kubectl patch "${res_type}" "${res_name}" -n "${NAMESPACE}" --type='json' -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"non-existing": "true"}}]'
  else
    kubectl scale "${res_type}" "${res_name}" -n "${NAMESPACE}" --replicas=0
  fi
  colorLog "SUCCESS" "已停止 ${res_type}/${res_name}"
}

startPod() {
  local workload
  workload=$(getAllWorkloadName "")
  [ -z "${workload}" ] || [ "${workload}" == "/" ] && { colorLog "WARNING" "未选择应用"; return; }
  local res_type res_name
  res_type=$(echo "${workload}" | cut -d'/' -f1)
  res_name=$(echo "${workload}" | cut -d'/' -f2)
  confirm=$(readInput "$(printf '\e[31m确认将 %s 启动?[y/n]\e[0m' "${res_type}/${res_name}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  colorLog "INFO" "启动 ${res_type}/${res_name}"
  if [ "${res_type}" == "ds" ]; then
    kubectl patch "${res_type}" "${res_name}" -n "${NAMESPACE}" --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'
  else
    kubectl scale "${res_type}" "${res_name}" -n "${NAMESPACE}" --replicas=1
  fi
  kubectl rollout status "${res_type}" "${res_name}" -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "已启动 ${res_type}/${res_name}"
}

execIntoPod() {
  local pod_name container_name
  pod_name=$(getPodName "")
  [ -z "${pod_name}" ] && { colorLog "WARNING" "未选择 Pod"; return; }
  container_name=$(getContainerName "${pod_name}")
  [ -z "${container_name}" ] && { colorLog "WARNING" "未选择容器"; return; }
  colorLog "INFO" "进入 Pod ${pod_name} 容器 ${container_name}"
  case "${pod_name}" in
  [Cc]lick[Hh]ouse-*)
    confirm=$(readInput "$(printf '\e[31m是否进入 Clickhouse 数据库?[y/n]\e[0m')")
    if [ "${confirm}" == "y" ]; then
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- sh -c "${clickhouse_cmd}"
    else
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- /bin/bash
    fi
    ;;
  [Mm]ongo*)
    confirm=$(readInput "$(printf '\e[31m是否进入 Mongodb 数据库?[y/n]\e[0m')")
    if [ "${confirm}" == "y" ]; then
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- sh -c "mongosh ${mongodb_auth}"
    else
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- /bin/bash
    fi
    ;;
  [Rr]edis-*)
    confirm=$(readInput "$(printf '\e[31m是否进入 Redis 数据库?[y/n]\e[0m')")
    if [ "${confirm}" == "y" ]; then
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- sh -c "${redis_cmd}"
    else
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- /bin/bash
    fi
    ;;
  *)
    kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- /bin/bash ||
      kubectl exec -it -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- /bin/sh
    ;;
  esac
}

showConfigMaps() {
  colorLog "INFO" "ConfigMap 列表"
  kubectl get cm -n "${NAMESPACE}"
}

showConfigMapDetail() {
  local cm_name
  cm_name=$(getCmName)
  [ -z "${cm_name}" ] && { colorLog "WARNING" "未选择 ConfigMap"; return; }
  colorLog "INFO" "ConfigMap ${cm_name} 详情"
  kubectl get cm -n "${NAMESPACE}" "${cm_name}" -oyaml
}

editConfigMap() {
  local cm_name
  cm_name=$(getCmName)
  [ -z "${cm_name}" ] && { colorLog "WARNING" "未选择 ConfigMap"; return; }
  kubectl edit cm -n "${NAMESPACE}" "${cm_name}"
}

setPodEnv() {
  local workload env_key env_value
  workload=$(getAllWorkloadName "")
  [ -z "${workload}" ] || [ "${workload}" == "/" ] && { colorLog "WARNING" "未选择应用"; return; }
  env_key=$(readInput "请输入环境变量 KEY")
  [ -z "${env_key}" ] && { colorLog "WARNING" "环境变量 KEY 不能为空"; return; }
  env_value=$(readInput "请输入环境变量 VALUE")
  local res_type res_name
  res_type=$(echo "${workload}" | cut -d'/' -f1)
  res_name=$(echo "${workload}" | cut -d'/' -f2)
  colorLog "INFO" "设置 ${res_type}/${res_name} 环境变量: ${env_key}=${env_value}"
  kubectl set env "${res_type}" "${res_name}" -n "${NAMESPACE}" "${env_key}=${env_value}"
  colorLog "INFO" "等待滚动更新完成......"
  kubectl rollout status "${res_type}" "${res_name}" -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "环境变量设置成功"
}

restartAllPods() {
  confirm=$(readInput "$(printf '\e[31m确认将所有 Pod 重启?[y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  res_type="deploy,ds"
  confirm=$(readInput "$(printf '\e[31m是否需要重启数据库 Pod?[y/n]\e[0m')")
  [ "${confirm}" == "y" ] && res_type="${res_type},sts"
  kubectl rollout restart "${res_type}" -n "${NAMESPACE}"
  colorLog "INFO" "等待滚动更新完成......"
  kubectl rollout status "${res_type}" -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "重启所有 Pod 完成"
}

stopAllPods() {
  confirm=$(readInput "$(printf '\e[31m确认将所有应用停止?[y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  res_type="deploy"
  confirm=$(readInput "$(printf '\e[31m是否需要停止数据库应用?[y/n]\e[0m')")
  [ "${confirm}" == "y" ] && res_type="${res_type},sts"
  kubectl get ds -n "${NAMESPACE}" -o custom-columns=":metadata.name" | \
    xargs -I {} kubectl patch ds {} -n "${NAMESPACE}" --type='json' -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"non-existing": "true"}}]'
  kubectl scale "${res_type}" -n "${NAMESPACE}" --all --replicas=0
  colorLog "SUCCESS" "已停止所有应用"
}

startAllPods() {
  confirm=$(readInput "$(printf '\e[31m确认将所有应用启动?[y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  kubectl get ds -n "${NAMESPACE}" -o custom-columns=":metadata.name" | \
    xargs -I {} kubectl patch ds {} -n "${NAMESPACE}" --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'
  kubectl scale deploy,sts -n "${NAMESPACE}" --all --replicas=1
  colorLog "INFO" "等待启动完成......"
  kubectl rollout status deploy,sts -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "已启动所有应用"
}

collectRuntimeInfoAndLogs() {
  local output_dir
  output_dir="./$(date "+%Y%m%d%H%M")_kubecoll"
  mkdir -p "${output_dir}/"{logs,configmaps,database}
  collectClusterInfo
  collectPodOverview
  collectConfigMaps
  collectClickhouse
  collectMongodb
  collectRedis
  collectNats
  collectChartValues
  colorLog "INFO" "开始打包采集的运行信息和日志"
  tar -zcvf "${output_dir}.tar.gz" "${output_dir}"
  rm -rf "${output_dir}"
  colorLog "SUCCESS" "打包采集的运行信息和日志成功, 文件名: ${output_dir}.tar.gz"
}

collectPprof() {
  colorLog "INFO" "开始采集Pprof信息"
  local workload
  workload=$(getAllWorkloadName "component=backend")
  [ -z "${workload}" ] || [ "${workload}" == "/" ] && { colorLog "WARNING" "未选择应用"; return; }
  local res_type res_name
  res_type=$(echo "${workload}" | cut -d'/' -f1)
  res_name=$(echo "${workload}" | cut -d'/' -f2)
  kubectl set env "${res_type}" "${res_name}" -n "${NAMESPACE}" DEV_SERVER_ENABLE="true"
  if [ "${res_type}" != "ds" ]; then
    colorLog "INFO" "等待滚动更新完成......"
    kubectl rollout status "${res_type}" "${res_name}" -n "${NAMESPACE}" --timeout "${helm_timeout}"
    colorLog "SUCCESS" "环境变量设置成功, 请等待应用运行10s......"
  fi
  sleep 10s
  local pod_name container_name
  pod_name=$(getPodName "app=${res_name}")
  [ -z "${pod_name}" ] && { colorLog "WARNING" "未选择 Pod"; return; }
  container_name=$(getContainerName "${pod_name}")
  [ -z "${container_name}" ] && { colorLog "WARNING" "未选择容器"; return; }
  echo "" >&2
  echo "请选择Pprof类型: " >&2
  echo "  [1] heap(内存分配)" >&2
  echo "  [2] profile(CPU使用率)" >&2
  echo "  [3] goroutine(goroutines 堆栈跟踪)" >&2
  echo "  [0] 取消" >&2
  printf "请输入序号: " >&2
  read -r input
  [ -z "${input}" ] || [ "${input}" == "0" ] && { colorLog "WARNING" "未选择Pprof类型"; return; }
  local pprof_type url
  case "${input}" in
  1)
    pprof_type="heap"
    url="http://127.0.0.1:${pprof_port}/debug/pprof/heap"
    ;;
  2)
    pprof_type="profile"
    url="http://127.0.0.1:${pprof_port}/debug/pprof/profile?seconds=${profile_duration}"
    ;;
  3)
    pprof_type="goroutine"
    url="http://127.0.0.1:${pprof_port}/debug/pprof/goroutine"
    ;;
  *)
    colorLog "WARNING" "未选择Pprof类型"
    return
  esac
  colorLog "INFO" "开始Pprof采集, Pod: ${pod_name}, 容器: ${container_name}, 采集类型: ${pprof_type}......"
  local output_dir=
  output_dir="./$(date "+%Y%m%d%H%M")_${res_name}_${pprof_type}_pprofcoll"
  mkdir -p "${output_dir}"
  for ((i=1; i<="${max_collections}"; i++)); do
    colorLog "INFO" "开始第 ${i} 次采集..."
    local timestamp filename
    timestamp=$(date +%Y%m%d_%H%M%S)
    filename="${pod_name}_${pprof_type}_${timestamp}.out"
    kubectl exec -n "${NAMESPACE}" "${pod_name}" -c "${container_name}" -- wget -q -O - "${url}" > "${output_dir}/${filename}" || colorLog "ERROR" "采集失败"
    colorLog "SUCCESS" "采集成功: ${filename}"
    [ "${i}" -lt "${max_collections}" ] && sleep "${collect_interval}"
  done
  colorLog "SUCCESS" "完成所有Pprof采集"
  colorLog "INFO" "开始打包Pprof采集信息"
  tar -zcvf "${output_dir}.tar.gz" "${output_dir}"
  rm -rf "${output_dir}"
  colorLog "SUCCESS" "打包Pprof采集信息成功, 文件名: ${output_dir}.tar.gz"
}

changeDatabasePassword() {
  colorLog "INFO" "开始修改Clickhouse, Mongodb和Redis的密码"
  confirm=$(readInput "$(printf '\e[31m是否修改Clickhouse密码? [y/n]\e[0m')")
  if [ "${confirm}" == "y" ]; then
    colorLog "INFO" "开始修改Clickhouse密码"
    new_password=$(readInput "$(printf '\e[31m请输入Clickhouse新密码\e[0m')")
    [ -z "${new_password}" ] && colorLog "ERROR" "新密码不能为空"
    encoded_password=$(echo -n "${new_password}" | base64)
    yq -i "$(printf '.clickhouse.password = "%s"' "${encoded_password}")" "${chart_custom_values_yaml}"
    colorLog "INFO" "修改Clickhouse密码成功"
  fi
  confirm=$(readInput "$(printf '\e[31m是否修改Mongodb密码? [y/n]\e[0m')")
  if [ "${confirm}" == "y" ]; then
    colorLog "INFO" "开始修改Mongodb密码"
    new_password=$(readInput "$(printf '\e[31m请输入Mongodb新密码\e[0m')")
    [ -z "${new_password}" ] && colorLog "ERROR" "新密码不能为空"
    encoded_password=$(echo -n "${new_password}" | base64)
    kubectl exec -n "${NAMESPACE}" "${mongodb_pod}" -c mongodb -- sh -c "mongo admin ${mongodb_auth} \
        --eval 'db.changeUserPassword(\"root\",\"${new_password}\")'"
    yq -i "$(printf '.mongodb.rootPassword = "%s"' "${encoded_password}")" "${chart_custom_values_yaml}"
    colorLog "INFO" "修改Mongodb密码成功"
  fi
  confirm=$(readInput "$(printf '\e[31m是否修改redis密码? [y/n]\e[0m')")
  if [ "${confirm}" == "y" ]; then
    colorLog "INFO" "开始修改Redis密码"
    new_password=$(readInput "$(printf '\e[31m请输入Redis新密码\e[0m')")
    [ -z "${new_password}" ] && colorLog "ERROR" "新密码不能为空"
    encoded_password=$(echo -n "${new_password}" | base64)
    yq -i "$(printf '.redis.password = "%s"' "${encoded_password}")" "${chart_custom_values_yaml}"
    colorLog "INFO" "修改Redis密码成功"
  fi
  helmUpgrade
  colorLog "INFO" "重启应用中, 请稍后......"
  kubectl rollout restart deploy,sts -n "${NAMESPACE}"
  colorLog "INFO" "等待滚动更新完成......"
  kubectl rollout status deploy -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "修改数据库密码成功"
}

deleteClickhouseData() {
  echo "" >&2
  echo "请选择需要删除的类型: " >&2
  echo "  [1] 数据资产" >&2
  echo "  [2] 事件日志" >&2
  echo "  [3] 告警日志" >&2
  echo "  [0] 取消" >&2
  printf "请输入序号: " >&2
  read -r input
  [ -z "${input}" ] || [ "${input}" == "0" ] && { colorLog "WARNING" "未选择数据类型"; return; }
  reserve=$(readInput "$(printf '\e[31m请输入保留最近几个月的数据, 默认为6个月\e[0m')")
  [ -z "${reserve}" ] && { colorLog "WARNING" "默认将保留最近6个月数据"; reserve=6; }
  colorLog "INFO" "将保留最近${reserve}个月数据"
  case "${input}" in
  1)
    local tables=(sensitive_file sensitive_file_category sensitive_file_level sensitive_category_level)
    for table in "${tables[@]}"; do
      colorLog "INFO" "开始删除${table}表数据"
      deleteClickhouseParts "${table}"
    done
    ;;
  2)
    colorLog "INFO" "开始删除audited_log表数据"
    deleteClickhouseParts "audited_log"
    ;;
  3)
    local tables=(alarm_log alarm_system_log)
    for table in "${tables[@]}"; do
      colorLog "INFO" "开始删除${table}表数据"
      deleteClickhouseParts "${table}"
    done
    ;;
  esac
}

rebuildClickhouseIndex() {
  colorLog "INFO" "开始重建 Clickhouse 索引"
  colorLog "INFO" "即将重建表 client_process_resource, sensitive_category_level, sensitive_file, sensitive_file_category, sensitive_file_level 索引"
  confirm=$(readInput "$(printf '\e[31m是否重建 Clickhouse 索引? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  local error_count=0
  local status
  status=$(kubectl get pod -n "${NAMESPACE}" "${clickhouse_pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  status=$(echo "${status}" | tr '[:upper:]' '[:lower:]')
  [ "${status}" != "true" ] && { colorLog "ERROR" "无可用Clickhouse POD"; return; }
  dropNewTables
  createTables
  migrateData
  if [ "${error_count}" -eq 0 ]; then
    colorLog "SUCCESS" "重建 Clickhouse 索引成功"
    confirm=$(readInput "$(printf '\e[31m是重命名表名? [y/n]\e[0m')")
    [ "${confirm}" == "y" ] && { renameTables; colorLog "SUCCESS" "重命名表名成功"; }
  else
    colorLog "ERROR" "重建 Clickhouse 索引失败"
  fi
}

deleteClickhouseAbnormalFiles() {
  colorLog "INFO" "开始删除 Clickhouse 异常文件"
  colorLog "WARNING" "功能未实现"
}

repairMongodbData() {
  colorLog "INFO" "开始修复 Mongodb 数据"
  confirm=$(readInput "$(printf '\e[31m是否修复 Mongodb 数据? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  local node_name volume_info host_path pvc image_pull_secrets mongodb_image available
  node_name=$(kubectl get pod mongodb-0 -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
  mongodb_image=$(kubectl get sts mongodb -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[?(@.name=="mongodb")].image}')
  volume_info=$(kubectl get sts mongodb -n "${NAMESPACE}" -o jsonpath='{range .spec.template.spec.volumes[?(@.name=="data")]}{.hostPath.path}{"|"}{.persistentVolumeClaim.claimName}{end}')
  host_path=$(echo "${volume_info}" | cut -d'|' -f1)
  pvc=$(echo "${volume_info}" | cut -d'|' -f2)
  image_pull_secrets=$(kubectl get sts mongodb -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.imagePullSecrets}' 2>/dev/null || echo "[]")
  [ -z "${image_pull_secrets}" ] && { image_pull_secrets="[]"; }
  stopAllDeploy
  colorLog "INFO" "开始停止 Mongodb"
  kubectl scale sts -n "${NAMESPACE}" mongodb --replicas=0
  available=$(kubectl get sts mongodb -n "${NAMESPACE}" -o=jsonpath='{.status.availableReplicas}')
  { [ -z "${available}" ] || [ "${available}" -eq 0 ]; } && colorLog "INFO" "Mongodb 可用副本数为0"
  colorLog "INFO" "停止 Mongodb 完成"
  local overrides
  if [ -n "${host_path}" ]; then
    colorLog "INFO" "当前为 hostPath 模式, 节点路径: ${host_path}, 节点名: ${node_name}"
    if [ -z "${node_name}" ]; then
      colorLog "ERROR" "未找到 node_name, 请检查 Mongodb 是否存在"
      return
    fi
    overrides=$(cat <<-EOF
    {
      "spec": {
        "imagePullSecrets": ${image_pull_secrets},
        "nodeName": "${node_name}",
        "containers": [{
          "name": "mongodb-repair",
          "image": "${mongodb_image}",
          "command": ["/bin/bash", "/opt/bitnami/scripts/mongodb/custom/repair-mongodb.sh"],
          "volumeMounts": [
            {"name": "data", "mountPath": "/data/mongodb/data", "subPath": "mongodb/data"},
            {"name": "repair-mongodb", "mountPath": "/opt/bitnami/scripts/mongodb/custom/repair-mongodb.sh", "subPath": "repair-mongodb.sh"}
          ]
        }],
        "volumes": [
          {"name": "data", "hostPath": {"path": "${host_path}", "type": "Directory"}},
          {"name": "repair-mongodb", "configMap": {"name": "mongodb-config", "defaultMode": 511}}
        ]
      }
    }
EOF
)
  elif [ -n "${pvc}" ]; then
    colorLog "INFO" "当前为 PVC 模式, PVC 名称: ${pvc}"
    overrides=$(cat <<-EOF
    {
      "spec": {
        "imagePullSecrets": ${image_pull_secrets},
        "containers": [{
          "name": "mongodb-repair",
          "image": "${mongodb_image}",
          "command": ["/bin/bash", "/opt/bitnami/scripts/mongodb/custom/repair-mongodb.sh"],
          "volumeMounts": [
            {"name": "data", "mountPath": "/data/mongodb/data", "subPath": "mongodb/data"},
            {"name": "repair-mongodb", "mountPath": "/opt/bitnami/scripts/mongodb/custom/repair-mongodb.sh", "subPath": "repair-mongodb.sh"}
          ]
        }],
        "volumes": [
          {"name": "data", "persistentVolumeClaim": {"claimName": "${pvc}"}},
          {"name": "repair-mongodb", "configMap": {"name": "mongodb-config", "defaultMode": 511}}
        ]
      }
    }
EOF
)
  else
    colorLog "ERROR" "未找到 data 卷定义, 请检查 Mongodb 是否存在"
    return
  fi
  runMongodbRepair "${overrides}"
  colorLog "INFO" "开始启动 Mongodb"
  kubectl scale sts -n "${NAMESPACE}" mongodb --replicas=1
  colorLog "INFO" "等待启动 Mongodb 完成......"
  kubectl rollout status sts -n "${NAMESPACE}" mongodb
  startAllDeploy
  colorLog "SUCCESS" "修复 Mongodb 数据完成"
}

cleanRedisData() {
  colorLog "INFO" "开始清空 Redis 持久化数据"
  confirm=$(readInput "$(printf '\e[31m是否清空 Redis 持久化数据? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  local node_name volume_info host_path pvc image_pull_secrets available image_name
  node_name=$(kubectl get pod redis-0 -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
  image_name=$(kubectl get sts redis -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[?(@.name=="redis")].image}' | sed 's|.*/||; s|:.*||')
  volume_info=$(kubectl get sts redis -n "${NAMESPACE}" -o jsonpath='{range .spec.template.spec.volumes[?(@.name=="data")]}{.hostPath.path}{"|"}{.persistentVolumeClaim.claimName}{end}')
  host_path=$(echo "${volume_info}" | cut -d'|' -f1)
  pvc=$(echo "${volume_info}" | cut -d'|' -f2)
  image_pull_secrets=$(kubectl get sts redis -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.imagePullSecrets}' 2>/dev/null || echo "[]")
  [ -z "${image_pull_secrets}" ] && { image_pull_secrets="[]"; }
  stopAllDeploy
  colorLog "INFO" "开始停止 Redis"
  kubectl scale sts -n "${NAMESPACE}" redis --replicas=0
  available=$(kubectl get sts redis -n "${NAMESPACE}" -o=jsonpath='{.status.availableReplicas}')
  { [ -z "${available}" ] || [ "${available}" -eq 0 ]; } && colorLog "INFO" "Redis 可用副本数为0"
  colorLog "INFO" "停止 Redis完成"
  local busybox_image="yasin.com.cn:33500/docker-hub/busybox:1.36.1"
  if echo "${image_name}" | grep -q '^redis-'; then
    local arch="${image_name#redis-}"
    busybox_image="yasin.com.cn:33500/docker-hub/busybox-${arch}:1.36.1"
  fi
  local overrides
  if [ -n "${host_path}" ]; then
    colorLog "INFO" "当前为 hostPath 模式, 节点路径: ${host_path}, 节点名: ${node_name}"
    if [ -z "${node_name}" ]; then
      colorLog "ERROR" "未找到 node_name, 请检查 Redis 是否存在"
      return
    fi
    overrides=$(cat <<-EOF
    {
      "spec": {
        "imagePullSecrets": ${image_pull_secrets},
        "nodeName": "${node_name}",
        "containers": [{
          "name": "redis-cleaner",
          "image": "${busybox_image}",
          "command": ["sh", "-c", "rm -rf /data/redis/data/* && echo Cleaned && ls -la /data/redis/data/"],
          "volumeMounts": [{"name": "host", "mountPath": "/data"}],
          "securityContext": {"privileged": true}
        }],
        "volumes": [{"name": "host", "hostPath": {"path": "${host_path}", "type": "Directory"}}]
      }
    }
EOF
)
  elif [ -n "${pvc}" ]; then
    colorLog "INFO" "当前为 PVC 模式, PVC 名称: ${pvc}"
    overrides=$(cat <<-EOF
    {
      "spec": {
        "imagePullSecrets": ${image_pull_secrets},
        "containers": [{
          "name": "redis-cleaner",
          "image": "${busybox_image}",
          "command": ["sh", "-c", "rm -rf /data/redis/data/* && echo Cleaned && ls -la /data/redis/data/"],
          "volumeMounts": [{"name": "data", "mountPath": "/data"}]
        }],
        "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "${pvc}"}}]
      }
    }
EOF
)
  else
    colorLog "ERROR" "未找到 data 卷定义, 请检查 Redis 是否存在"
  fi
  runRedisCleaner "${overrides}"
  colorLog "INFO" "开始启动 Redis"
  kubectl scale sts -n "${NAMESPACE}" redis --replicas=1
  colorLog "INFO" "等待启动 Redis 完成......"
  kubectl rollout status sts -n "${NAMESPACE}" redis
  startAllDeploy
  colorLog "SUCCESS" "清空 Redis 持久化数据成功"
}

resetManagerUserPassword() {
  colorLog "INFO" "开始重置管理中心用户密码"
  username=$(readInput "请输入管理中心用户名")
  [ -z "${username}" ] && { colorLog "WARNING" "用户名不能为空"; return; }
  confirm=$(readInput "$(printf '\e[31m是否重置管理中心用户 %s 密码? [y/n]\e[0m' "${username}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  kubectl exec -it -n "${NAMESPACE}" deploy/systemsvc -- systemsvc -resetpwd -u "${username}"
  colorLog "SUCCESS" "重置管理中心用户 ${username} 密码成功"
}

clearLicenseUUID() {
  colorLog "INFO" "开始清空授权UUID"
  confirm=$(readInput "$(printf '\e[31m是否清空授权UUID? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  colorLog "INFO" "清空授权UUID中, 请稍后......"
  kubectl exec -it -n "${NAMESPACE}" deploy/licensesvc -- licensesvc -clean
  colorLog "INFO" "重启 licensesvc 中, 请稍后......"
  kubectl rollout restart deploy -n "${NAMESPACE}" licensesvc
  colorLog "INFO" "等待滚动更新 licensesvc 完成......"
  kubectl rollout status deploy licensesvc -n "${NAMESPACE}" --timeout "${helm_timeout}"
  colorLog "SUCCESS" "清空授权UUID成功"
}

cleanAbnormalPods() {
  colorLog "INFO" "开始删除状态异常的 Pod"
  confirm=$(readInput "$(printf '\e[31m是否删除状态异常的 Pod? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  kubectl get pod -n "${NAMESPACE}" --no-headers | grep -v Running | awk '{print $1}' | xargs kubectl delete pod -n "${NAMESPACE}"
  colorLog "SUCCESS" "删除状态异常的 Pod 成功"
}

modifySystemKernelParameters() {
  colorLog "INFO" "开始修改系统内核参数"
  confirm=$(readInput "$(printf '\e[31m是否修改系统内核参数? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  cat >> /etc/sysctl.conf <<EOF
fs.file-max = 100000
# 增大等待连接队列的大小(默认为 128,高并发不够)
net.core.somaxconn = 65535
# 加快TIME-WAIT状态的回收和重用(适用于客户端频繁建连的场景)
net.ipv4.tcp_tw_reuse = 1
# 启用TCP窗口缩放,支持高延迟高带宽链路
net.ipv4.tcp_window_scaling = 1
# 增大TCP读/写缓冲区的最小、默认、最大值
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536  16777216
# 增大最大内存缓冲区大小(重要!)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
# 增大半连接队列长度
net.ipv4.tcp_max_syn_backlog = 65536
# 调整 overcommit 内存策略(重要)
# 0: 启发式overcommit(默认)
# 1: 总是overcommit(允许分配所有虚拟内存)
# 2: 不允许承诺超过"交换空间+物理内存*overcommit_ratio"的内存
# 对于Redis等内存型应用,建议设置为1
vm.overcommit_memory = 1
EOF
  echo "* hard nofile 655350" >> /etc/security/limits.conf
  echo "* soft nofile 655350" >> /etc/security/limits.conf
  sysctl -p
  colorLog "SUCCESS" "修改系统内核参数成功"
}

cleanDataFiles() {
  colorLog "INFO" "开始清理数据文件, 包含外发截图和敏感文件原文件"
  local days
  days=$(readInput "请输入要删除多少天之前的的文件 [默认 30]")
  [ -z "${days}" ] && days=30
  confirm=$(readInput "$(printf '\e[31m确认是否要删除 %d 天之前的文件? [y/n]\e[0m' "${days}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  kubectl exec -it -n "${NAMESPACE}" deploy/systemsvc -- systemsvc -clean -day "${days}"
  colorLog "SUCCESS" "清理 ${days} 天之前的文件完成"
}

dispatchApplicationNode() {
  colorLog "INFO" "开始批量调度应用"
  local deploy_name node_name change_count=0
  while true; do
    deploy_name=$(getDispatchableDeploy)
    if [ -z "${deploy_name}" ]; then
      colorLog "WARNING" "输入无效, 请重新输入"
      continue
    fi
    [ "${deploy_name}" == "exit" ] && break
    node_name=$(readInput "$(printf '请输入需要调度 %s 至的节点名称' "${deploy_name}")")
    [ -z "${node_name}" ] && { colorLog "WARNING" "节点名称不能为空, 请重新选择"; continue; }
    confirm=$(readInput "$(printf '\e[31m是否将 %s 调度至 %s? [y/n]\e[0m' "${deploy_name}" "${node_name}")")
    [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消当前调度, 继续选择其他应用"; continue; }
    yq -i "$(printf '.["%s"].nodeName = "%s"' "${deploy_name}" "${node_name}")" "${chart_custom_values_yaml}"
    colorLog "SUCCESS" "已配置 ${deploy_name} -> ${node_name}"
    ((change_count++))
  done
  [ "${change_count}" -eq 0 ] && { colorLog "WARNING" "未配置任何调度, 取消操作"; return; }
  confirm=$(readInput "$(printf '\e[31m共配置 %d 项调度, 是否执行helm upgrade应用? [y/n]\e[0m' "${change_count}")")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "已写入配置但未执行升级"; return; }
  helmUpgrade
  colorLog "SUCCESS" "批量调度应用成功"
}

updateChartValues() {
  colorLog "INFO" "开始更新应用配置"
  confirm=$(readInput "$(printf '\e[31m是否更新应用配置? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }
  helmUpgrade
  colorLog "SUCCESS" "更新chart配置成功"
}

modifyPorts() {
  colorLog "INFO" "开始更新服务端口"
  local manager_port downloader_port agent_port
  local new_manager_port new_downloader_port new_agent_port

  manager_port=$(yq ".service.managerNodePort" "${chart_custom_values_yaml}")
  downloader_port=$(yq ".service.downloaderNodePort" "${chart_custom_values_yaml}")
  agent_port=$(yq ".service.agentNodePort" "${chart_custom_values_yaml}")

  while true; do
    new_manager_port=$(readInput "请输入新的管理中心端口(原端口: ${manager_port}), 直接回车保持不变")
    [ -z "${new_manager_port}" ] && break
    validatePort "${new_manager_port}" || continue
    if [ "${new_manager_port}" == "${manager_port}" ]; then
      colorLog "INFO" "新端口与原端口相同, 跳过"
      new_manager_port=""
    fi
    break
  done

  while true; do
    new_downloader_port=$(readInput "请输入新的下载器端口(原端口: ${downloader_port}), 直接回车保持不变")
    [ -z "${new_downloader_port}" ] && break
    validatePort "${new_downloader_port}" || continue
    if [ "${new_downloader_port}" == "${downloader_port}" ]; then
      colorLog "INFO" "新端口与原端口相同, 跳过"
      new_downloader_port=""
    fi
    break
  done

  while true; do
    new_agent_port=$(readInput "请输入新的代理端口(原端口: ${agent_port}), 直接回车保持不变")
    [ -z "${new_agent_port}" ] && break
    validatePort "${new_agent_port}" || continue
    if [ "${new_agent_port}" == "${agent_port}" ]; then
      colorLog "INFO" "新端口与原端口相同, 跳过"
      new_agent_port=""
    fi
    break
  done

  if [ -z "${new_manager_port}" ] && [ -z "${new_downloader_port}" ] && [ -z "${new_agent_port}" ]; then
    colorLog "WARNING" "未修改任何端口, 取消操作"
    return
  fi

  echo "" >&2
  echo "即将更新以下端口配置:" >&2
  echo "----------------------------------------" >&2
  [ -n "${new_manager_port}" ] && printf "  管理中心端口: %s -> %s\n" "${manager_port}" "${new_manager_port}" >&2
  [ -n "${new_downloader_port}" ] && printf "  下载器端口:   %s -> %s\n" "${downloader_port}" "${new_downloader_port}" >&2
  [ -n "${new_agent_port}" ] && printf "  代理端口:     %s -> %s\n" "${agent_port}" "${new_agent_port}" >&2
  echo "----------------------------------------" >&2
  echo "" >&2

  confirm=$(readInput "$(printf '\e[31m确认写入配置文件并更新应用? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "已写入配置但未执行升级"; return; }
  if [ -n "${new_manager_port}" ]; then
    yq -i "$(printf '.service.managerNodePort = %s' "${new_manager_port}")" "${chart_custom_values_yaml}"
  fi
  if [ -n "${new_downloader_port}" ]; then
    yq -i "$(printf '.service.downloaderNodePort = %s' "${new_downloader_port}")" "${chart_custom_values_yaml}"
  fi
  if [ -n "${new_agent_port}" ]; then
    yq -i "$(printf '.service.agentNodePort = %s' "${new_agent_port}")" "${chart_custom_values_yaml}"
  fi
  colorLog "SUCCESS" "端口配置已写入配置文件"
  confirm=$(readInput "$(printf '\e[31m是否执行 helm upgrade 应用配置? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "已写入配置但未执行升级"; return; }
  helmUpgrade
  colorLog "SUCCESS" "更新端口配置成功"
}

modifyResourcesLimits() {
  colorLog "INFO" "开始批量修改应用资源 limits"
  local -a selected_services=()
  local -a selected_cpu=()
  local -a selected_mem=()
  local service_name cpu_limit memory_limit

  while true; do
    service_name=$(getResourcesLimitsDeploy)
    if [ -z "${service_name}" ]; then
      colorLog "WARNING" "输入无效, 请重新输入"
      continue
    fi
    [ "${service_name}" == "exit" ] && break
    local found_idx=-1
    for ((i = 0; i < ${#selected_services[@]}; i++)); do
      if [ "${selected_services[i]}" == "${service_name}" ]; then
        found_idx=$i
        break
      fi
    done
    if [ "${found_idx}" -ge 0 ]; then
      colorLog "WARNING" "${service_name} 已选择过, 将覆盖之前的配置"
    fi

    while true; do
      cpu_limit=$(readInput "请输入 ${service_name} 的 CPU limits(如 0.5, 2, 直接回车保持不变)")
      validateCpu "${cpu_limit}" && break
    done

    while true; do
      memory_limit=$(readInput "请输入 ${service_name} 的 Memory limits(如 1Gi, 512Mi, 直接回车保持不变)")
      local ret=0
      validateMemory "${memory_limit}" || ret=$?
      if [ "${ret}" -eq 1 ]; then
        continue
      elif [ "${ret}" -eq 2 ]; then
        local confirm_unit
        confirm_unit=$(readInput "$(printf '\e[31mMemory 未使用 Gi 单位, 是否继续? [y/n]\e[0m')")
        [ "${confirm_unit}" != "y" ] && continue
      fi
      break
    done

    if [ -z "${cpu_limit}" ] && [ -z "${memory_limit}" ]; then
      colorLog "WARNING" "未修改 ${service_name} 的任何资源限制, 跳过"
      continue
    fi

    if [ "${found_idx}" -ge 0 ]; then
      selected_cpu[found_idx]="${cpu_limit}"
      selected_mem[found_idx]="${memory_limit}"
    else
      selected_services+=("${service_name}")
      selected_cpu+=("${cpu_limit}")
      selected_mem+=("${memory_limit}")
    fi
    colorLog "SUCCESS" "已缓存 ${service_name} 的资源 limits 配置"
  done

  if [ "${#selected_services[@]}" -eq 0 ]; then
    colorLog "WARNING" "未选择任何应用, 取消操作"
    return
  fi

  echo "" >&2
  echo "即将批量更新以下资源 limits 配置:" >&2
  echo "----------------------------------------" >&2
  local i
  for ((i = 0; i < ${#selected_services[@]}; i++)); do
    printf "  [%d] 应用: %s\n" $((i + 1)) "${selected_services[i]}" >&2
    [ -n "${selected_cpu[i]}" ] && printf "      CPU    limits: %s\n" "${selected_cpu[i]}" >&2
    [ -n "${selected_mem[i]}" ] && printf "      Memory limits: %s\n" "${selected_mem[i]}" >&2
  done
  echo "----------------------------------------" >&2
  echo "" >&2

  confirm=$(readInput "$(printf '\e[31m确认写入配置文件并更新应用? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "取消操作"; return; }

  for ((i = 0; i < ${#selected_services[@]}; i++)); do
    if [ -n "${selected_cpu[i]}" ]; then
      yq -i "$(printf '%s = "%s"' "$(buildYqPath "${selected_services[i]}" ".resources.limits.cpu")" "${selected_cpu[i]}")" "${chart_custom_values_yaml}" || colorLog "ERROR" "更新 ${selected_services[i]} 的 CPU limits 失败"
    fi
    if [ -n "${selected_mem[i]}" ]; then
      yq -i "$(printf '%s = "%s"' "$(buildYqPath "${selected_services[i]}" ".resources.limits.memory")" "${selected_mem[i]}")" "${chart_custom_values_yaml}" || colorLog "ERROR" "更新 ${selected_services[i]} 的 Memory limits 失败"
    fi
  done

  colorLog "SUCCESS" "资源 limits 配置已批量写入文件"

  confirm=$(readInput "$(printf '\e[31m是否执行 helm upgrade 应用配置? [y/n]\e[0m')")
  [ "${confirm}" != "y" ] && { colorLog "WARNING" "已写入配置但未执行升级"; return; }

  helmUpgrade
  colorLog "SUCCESS" "批量更新资源 limits 配置成功"
}

#===============================================================================
# Menu Definition
#===============================================================================
declare -a MENU_ITEMS=(
  "1:查看节点列表:showNodes"
  "2:查看节点资源使用率:showNodeResources"
  "3:查看节点详情:showNodeDetail"
  "4:查看 Pod 列表:showPods"
  "5:查看 Pod 资源使用率:showPodResources"
  "6:查看 Pod 详情:showPodDetail"
  "7:查看 Pod 日志:showPodLogs"
  "8:重启 Pod:restartPod"
  "9:停止 Pod:stopPod"
  "10:启动 Pod:startPod"
  "11:进入 Pod 容器终端:execIntoPod"
  "12:查看 ConfigMap 列表:showConfigMaps"
  "13:查看 ConfigMap 详情:showConfigMapDetail"
  "14:编辑 ConfigMap:editConfigMap"
  "15:修改应用环境变量:setPodEnv"
  "16:重启所有 Pod:restartAllPods"
  "17:停止所有 Pod:stopAllPods"
  "18:启动所有 Pod:startAllPods"
  "19:采集运行信息和日志:collectRuntimeInfoAndLogs"
  "20:采集Pprof信息:collectPprof"
  "21:修改数据库密码:changeDatabasePassword"
  "22:删除 Clickhouse 数据:deleteClickhouseData"
  "23:重建 Clickhouse 索引:rebuildClickhouseIndex"
  "24:删除 Clickhouse 异常文件:deleteClickhouseAbnormalFiles"
  "25:修复 Mongodb 数据:repairMongodbData"
  "26:删除 Redis 持久化数据:cleanRedisData"
  "27:重置管理中心用户密码:resetManagerUserPassword"
  "28:清空授权UUID:clearLicenseUUID"
  "29:删除状态异常 Pod:cleanAbnormalPods"
  "30:修改系统内核参数:modifySystemKernelParameters"
  "31:清理数据目录:cleanDataFiles"
  "32:调度应用节点:dispatchApplicationNode"
  "33:更新应用配置:updateChartValues"
  "34:更新应用端口:modifyPorts"
  "35:更新应用资源 limits:modifyResourcesLimits"
  "36:切换命名空间:switchNamespace"
)

showMenu() {
  echo ""
  local item id rest desc
  for item in "${MENU_ITEMS[@]}"; do
    id="${item%%:*}"
    rest="${item#*:}"
    desc="${rest%%:*}"
    printf "  [%2s] %s\n" "${id}" "${desc}"
  done
  printf "  [%2s] %s\n" "0" "退出"
  echo ""
  echo "============================================================"
}

executeMenu() {
  local choice="${1}"
  if [ "${choice}" == "0" ]; then
    colorLog "INFO" "退出运维工具"
    exit 0
  fi
  local item id func
  for item in "${MENU_ITEMS[@]}"; do
    id="${item%%:*}"
    func="${item##*:}"
    if [ "${id}" == "${choice}" ]; then
      ${func}
      return 0
    fi
  done
  colorLog "WARNING" "无效选项: ${choice}"
  return 1
}

main() {
  checkKubectl
  if [ -n "${1}" ]; then
    executeMenu "${1}" && exit 0
  fi

  while true; do
    printHeader
    showMenu
    choice=$(readInput "请选择操作 [0-${#MENU_ITEMS[@]}]")
    executeMenu "${choice}"
    echo ""
    read -r -p "按 Enter 键继续......"
  done
}

main "$@"