#!/bin/bash

colorLog() {
  RESET=$(tput sgr0)      # 重置所有样式
  RED=$(tput setaf 1)     # 设置前景色为红色
  GREEN=$(tput setaf 2)   # 设置前景色为绿色
  YELLOW=$(tput setaf 3)  # 设置前景色为黄色
  BLUE=$(tput setaf 4)    # 设置前景色为蓝色
  local level=${1}
  local message=${2}
  case ${level} in
  "INFO") color=${BLUE} ;;
  "SUCCESS") color=${GREEN} ;;
  "WARNING") color=${YELLOW} ;;
  "ERROR") color=${RED} ;;
  *) color=${NC} ;;
  esac
  printf '%b\n' "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")] [${color}${level}${GREEN}] ${message}${RESET}"
  if [ "${level}" == "ERROR" ]; then
    exit 1
  fi
}

image_file="./longhorn-images.txt"
images=()
while IFS= read -r image; do
  [ -z "${image}" ] && continue
  images+=("${image}")
  if docker image inspect "${image}" > /dev/null 2>&1; then
    continue
  fi
  while true; do
    colorLog "INFO" "Pulling ${image} ..."
    if docker pull --platform linux/amd64 "${image}" > /dev/null 2>&1; then
      colorLog "SUCCESS" "Successfully pulled ${image}"
      break
    else
      colorLog "WARNING" "Failed to pull ${image},try again after 1 second"
      sleep 1
    fi
  done
done < "${image_file}"
colorLog "SUCCESS" "Successfully pulled all images"

colorLog "INFO" "Packaging longhorn images"
mkdir -p "./tmp/"
docker save "${images[@]}" -o "./tmp/longhorn.tar" || {
  colorLog "ERROR" "Packaging longhorn images failed"
}
colorLog "SUCCESS" "Package images successfully"