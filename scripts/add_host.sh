#!/bin/bash

# 定义要添加的主机配置项
new_host="10.10.101.10 yasin-hub.com.cn"

# 检查配置项是否已存在
if ! grep -q "$new_host" /etc/hosts; then
    # 如果不存在，则添加到 /etc/hosts 文件末尾
    echo "$new_host" | sudo tee -a /etc/hosts > /dev/null
    echo "已添加主机配置项: $new_host"
else
    echo "主机配置项 $new_host 已存在。"
fi
