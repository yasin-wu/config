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