#!/bin/bash

for image in $(docker images |grep -w yasin-hub.com.cn | awk '{print $1 ":" $2}'); do
  # shellcheck disable=SC2001
  dst_image=$(echo "${image}" | sed 's/yasin-hub.com.cn/yasin-hub.com.cn:30500/g')
  echo "${image}"
  echo "${dst_image}"
  docker tag "${image}" "${dst_image}"
  docker push "${dst_image}"
done