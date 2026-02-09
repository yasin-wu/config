#!/bin/bash

colorLog() {
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local BLUE='\033[0;34m'
  local NC='\033[0m' # No Color
  local level=${1}
  local message=${2}
  case ${level} in
  "INFO") color=${BLUE} ;;
  "SUCCESS") color=${GREEN} ;;
  "WARNING") color=${YELLOW} ;;
  "ERROR") color=${RED} ;;
  *) color=${NC} ;;
  esac
  printf "${GREEN}[%s] [${color}%-7s${GREEN}] %s${NC}\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${level}" "${message}"
  if [ "${level}" == "ERROR" ]; then
    exit 1
  fi
}

## check global ipv6
checkGlobalIPv6Func() {
  colorLog "INFO" "开始检查系统网卡"
  local has_global_ipv6=false
  local interfaces ipv6_addrs
  interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
  for iface in ${interfaces}; do
    colorLog "INFO" "开始检查网卡: ${iface}"
    ipv6_addrs=$(ip -6 addr show dev "${iface}" scope global 2>/dev/null)
    if [ -n "${ipv6_addrs}" ]; then
      colorLog "SUCCESS" "网卡${iface}有以下Global IPv6地址: $(echo "${ipv6_addrs}" | awk '/inet6/{print $2}')"
      has_global_ipv6=true
      return
    else
      colorLog "WARNING" "网卡${iface}没有Global IPv6地址"
    fi
  done

  if [ "${has_global_ipv6}" == false ]; then
    colorLog "ERROR" "系统没有检测到任何网卡配置了Global IPv6地址,集群不支持IPv6"
  fi
}

## parse param
# shellcheck disable=SC2034
parseParamFunc() {
  while [[ $# -gt 1 ]]; do
    key="${2}"
    case ${key} in
      --name)
        name="${3}"
        shift 2
        ;;
      --mip)
        mip="${3}"
        shift 2
        ;;
      --token)
        token="${3}"
        shift 2
        ;;
      --type)
        type="${3}"
        shift 2
        ;;
      *)
        colorLog "ERROR" "未知参数: ${2}"
        ;;
    esac
  done
}

## load basic images
loadImageFunc() {
  colorLog "INFO" "开始加载集群基础镜像"
  local images_dir="/var/lib/rancher/k3s/agent/images/"
  if [ -n "${CLUSTER_DIR}" ]; then
    images_dir="${CLUSTER_DIR%/}/k3s/agent/images/"
  fi
  mkdir -p "${images_dir}" || {
    colorLog "ERROR" "创建集群基础镜像目录失败,请手动处理相关错误信息"
  }
  cp -rf ./package/k3s-images.tar.gz "${images_dir}" || {
    colorLog "ERROR" "加载集群基础镜像失败,请手动处理相关错误信息"
  }
  colorLog "SUCCESS" "加载集群基础镜像成功"
}

## set env
setEnvFunc() {
  loadImageFunc
  local k3s_cri="--kubelet-arg=container-log-max-size=100Mi --kubelet-arg=container-log-max-files=2"
  local k3s_disable="--disable traefik"
  local k3s_nodeport="--service-node-port-range=0-39999"
  local k3s_cidr="--cluster-cidr 10.42.0.0/16 --service-cidr 10.43.0.0/16"
  if [ "${IPV6}" == "enable" ]; then
    colorLog "INFO" "初始化IPv4和IPv6双栈集群"
    checkGlobalIPv6Func
    k3s_cidr="--cluster-cidr 10.42.0.0/16,2001:cafe:42:0::/56 --service-cidr 10.43.0.0/16,2001:cafe:42:1::/112"
  fi
  if [ -n "${CLUSTER_DIR}" ]; then
    mkdir -p "${CLUSTER_DIR%/}"/kubelet
    mkdir -p "${CLUSTER_DIR%/}"/k3s
    k3s_cri="${k3s_cri} --data-dir ${CLUSTER_DIR%/}/k3s --kubelet-arg=root-dir=${CLUSTER_DIR%/}/kubelet"
  fi
  export K3S_NODE_NAME=${name}
  export INSTALL_K3S_SKIP_DOWNLOAD=true
  export INSTALL_K3S_EXEC="server --cluster-init ${k3s_cri} ${k3s_disable} ${k3s_nodeport} ${k3s_cidr}"
  if [ -n "${mip}" ]; then
    export K3S_TOKEN=${token}
    export K3S_URL=https://${mip}:6443
    export INSTALL_K3S_EXEC="agent ${k3s_cri}"
    if [ "${type}" == "server" ]; then
      export INSTALL_K3S_EXEC="server ${k3s_cri} ${k3s_disable} ${k3s_nodeport} ${k3s_cidr}"
    fi
  fi
}

## disable swap firewalld selinux
disableSFSFunc() {
  ## disable swap
  local line
  line=$(sed -n '/swap/=' /etc/fstab)
  swapoff -a
  for d in ${line}; do
    if sed -n "${d}","${d}"p '/etc/fstab' | grep "#" > /dev/null; then
      colorLog "SUCCESS" "swap off"
    else
      sed -i "${d}"'s/^/#&/g' /etc/fstab
    fi
  done
  ## stop firewalld
  systemctl stop firewalld
  systemctl disable firewalld

  ## disable selinux
  setenforce 0
  sed -i "s|SELINUX=enforcing|SELINUX=disable|g" /etc/selinux/config
  sed -i "s|SELINUX=permissive|SELINUX=disable|g" /etc/selinux/config
}

## check cluster status
checkClusterStatusFunc() {
  colorLog "INFO" "开始检查集群状态"
  local nodes ready_nodes non_ready_nodes system_pods non_running_pods
  if ! command -v kubectl &> /dev/null; then
    colorLog "${1}" "未安装集群,请联系管理员或者初始化集群"
    return 1
  fi
  nodes=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name")
  if [ -z "${nodes}" ]; then
    colorLog "${1}" "集群无任何节点,请联系管理员或者初始化集群"
    return 1
  fi
  ready_nodes=$(kubectl get nodes --no-headers | awk '$2 == "Ready" {print $1}')
  if [ -z "${ready_nodes}" ]; then
    colorLog "${1}" "集群无任何Ready节点,请联系管理员或者初始化集群"
    return 1
  fi
  non_ready_nodes=$(kubectl get nodes --no-headers | awk '$2 != "Ready" {print $1}' | tr '\n' ' ')
  if [ -n "${non_ready_nodes}" ]; then
    colorLog "WARNING" "集群存在非Ready节点: ${non_ready_nodes},请手动恢复节点"
  fi
  system_pods=$(kubectl get pod -n kube-system --no-headers)
  if [ -z "${system_pods}" ]; then
    colorLog "${1}" "集群异常,无系统pod,请手动处理相关错误信息"
    return 1
  fi
  non_running_pods=$(kubectl get pod -n kube-system --no-headers | awk '$3!= "Running" && $3!= "Completed" {print $1}' | tr '\n' ' ')
  if [ -n "${non_running_pods}" ]; then
    colorLog "${1}" "集群系统pod状态异常,请手动处理相关错误信息"
    return 1
  fi
  colorLog "SUCCESS" "集群状态正常"
  return 0
}

## check cluster status with timeout
checkClusterStatusWithTimeout() {
  local timeout=${CHECK_CLUSTER_TIMEOUT}
  local interval=5
  local success=0
  local start_time end_time
  start_time=$(date +%s)
  end_time=$((start_time + timeout))
  while [[ $(date +%s) -lt "${end_time}" ]]; do
    if checkClusterStatusFunc "WARNING"; then
      success=1
      break
    fi
    colorLog "WARNING" "集群状态检查未通过,${interval}秒后重试..."
    sleep "${interval}"
  done
  if [ "${success}" -eq 0 ]; then
    colorLog "ERROR" "集群状态检查超时${timeout}秒,请手动检查集群状态并修复相关错误"
  fi
}

## install yq
installYQFunc() {
  if ! command -v yq >/dev/null 2>&1; then
    colorLog "INFO" "开始安装yq..."
    chmod +x ./scripts/yq
    cp -rf ./scripts/yq /usr/bin/ || {
      colorLog "ERROR" "安装yq失败,请手动处理相关错误信息"
    }
  fi
}

## init cluster
initClusterMain() {
  colorLog "INFO" "开始初始化集群"
  if command -v kubectl >/dev/null 2>&1; then
    colorLog "ERROR" "系统已安装集群,请勿重复安装"
  fi
  disableSFSFunc
  mv -f /etc/default/k3s /etc/default/k3s.bak >/dev/null 2>&1 || true
  echo "CATTLE_NEW_SIGNED_CERT_EXPIRATION_DAYS=3650" |tee -a /etc/default/k3s
  setEnvFunc "$@"
  chmod +x ./package/k3s
  cp -rf ./package/k3s /usr/local/bin/ || {
    colorLog "ERROR" "初始化集群失败,请手动处理相关错误信息"
  }
  sh ./scripts/install_k3s.sh
  local token_dir token
  token_dir="${CLUSTER_DIR-/var/lib/rancher}"
  token=$(cat "${token_dir%/}/k3s/server/node-token")
  colorLog "INFO" "检查集群节点健康状态: kubectl get nodes -o wide"
  colorLog "INFO" "检查系统pod健康状态: kubectl get pod -n kube-system"
  checkClusterStatusWithTimeout || {
    colorLog "ERROR" "初始化集群失败,请手动处理相关错误信息,查看日志: journalctl -u k3s -f"
  }
  colorLog "SUCCESS" "初始化集群成功,集群Token: ${token##*server:}"
}

## reset cluster
resetClusterMain() {
  colorLog "INFO" "开始重置集群"
  if [ ! -f /usr/local/bin/k3s-uninstall.sh ]; then
    colorLog "ERROR" "找不到集群卸载脚本,请初始化集群"
  fi
  sh /usr/local/bin/k3s-killall.sh >/dev/null 2>&1 || true
  sh /usr/local/bin/k3s-uninstall.sh
  initClusterMain "$@"
  colorLog "SUCCESS" "重置集群成功"
}

## join cluster
joinClusterMain() {
  colorLog "INFO" "开始加入集群"
  if command -v kubectl >/dev/null 2>&1; then
    colorLog "ERROR" "系统已加入集群,请勿重复加入"
  fi
  disableSFSFunc
  setEnvFunc "$@"
  chmod +x ./package/k3s
  cp -rf ./package/k3s /usr/local/bin/ || {
    colorLog "ERROR" "加入集群失败,请手动处理相关错误信息,查看日志: journalctl -u k3s-agent -f"
  }
  sh ./scripts/install_k3s.sh
  colorLog "SUCCESS" "加入主节点为${mip}的集群成功"
}

## rejoin cluster
rejoinClusterMain() {
  colorLog "INFO" "开始重新加入集群"
  if [ ! -f /usr/local/bin/k3s-agent-uninstall.sh ] && [ ! -f /usr/local/bin/k3s-uninstall.sh ]; then
    colorLog "ERROR" "找不到集群卸载脚本,请加入集群"
  fi
  sh /usr/local/bin/k3s-killall.sh >/dev/null 2>&1 || true
  if [  -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
    sh /usr/local/bin/k3s-agent-uninstall.sh
  fi
  if systemctl list-unit-files --type=service | grep -w 'k3s.service'; then
    colorLog "INFO" "开始清理节点残留信息"
    read -r -p $'\e[31m请确认是否已经将旧节点信息从集群中删除,确定继续计入?[y/n]\e[0m' select
    if [ "${select}" == "y" ]; then
      sh /usr/local/bin/k3s-uninstall.sh
    fi
  fi
  joinClusterMain "$@"
  colorLog "SUCCESS" "重新加入集群成功"
}

## main
main() {
  export CHECK_CLUSTER_TIMEOUT="300"
  if [ "${1}" == "help" ] || [ "${1}" == "-h" ] || [ -z "${1}" ]; then
    echo " "
    echo "Usage: ./install.sh command [options]"
    echo " "
    echo "Commands:
    init:      initialize the cluster master node
    join:      join a node to a cluster
    reset:     reinitialize the cluster master node
    rejoin:    rejoin a node to a cluster"
    echo " "
    echo "Options:
    --name:  set node name; for init, reset, join and rejoin command
    --mip:   set master ip; for join and rejoin command
    --token: set cluster token; for join and rejoin command
    --type:  set node type; server or agent(default: agent)"
    echo " "
    echo "Environment variable:
    IPV6:         set dual-stack(IPv4 + IPv6)(default: disable, IPV6=enable); for init, reset, install command
    CLUSTER_DIR:  set cluster data path(default: /var/lib); for init, reset, join and rejoin command"
    echo " "
    exit 0
  fi

  colorLog "INFO" "Environment variable:
  IPV6:        ${IPV6}
  CLUSTER_DIR: ${CLUSTER_DIR}"

  local name mip token type
  parseParamFunc "$@"
  if [ -z "${name}" ]; then
    colorLog "ERROR" "请输入节点名"
  fi
  if [ "${1}" == "join" ] || [ "${1}" == "rejoin" ]; then
    if [ -z "${mip}" ]; then
      colorLog "ERROR" "主节点IP为空!请使用参数--mip指定主节点IP"
    fi
    if [ -z "${token}" ]; then
      token_dir="${CLUSTER_DIR-/var/lib/rancher}"
      colorLog "ERROR" "token为空!请使用参数--token指定token"
      colorLog "ERROR" "token为空!请在master节点运行获取token: cut -d ':' -f 4 ${token_dir%/}/k3s/server/node-token"
    fi
  fi

  colorLog "INFO" "节点名: ${name}"
  if [ -n "${mip}" ]; then
    colorLog "INFO" "主节点IP: ${mip}"
    colorLog "INFO" "集群Token: ${token}"
    colorLog "INFO" "正在加入主节点为${mip}的集群"
  fi

  installYQFunc

  case ${1} in
  init)
    initClusterMain "$@"
    ;;
  reset)
    resetClusterMain "$@"
    ;;
  join)
    joinClusterMain "$@"
    ;;
  rejoin)
    rejoinClusterMain "$@"
    ;;
  *)
    colorLog "ERROR" "未知命令: ${1},请使用help命令查看帮助信息"
    ;;
  esac
}

main "$@"