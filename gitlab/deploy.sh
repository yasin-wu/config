#!/bin/bash
host=$1
user=$2
password=$3
dir=$4
# shellcheck disable=SC2236
if [ ! -n "$host" ] ;then
  echo "请输入主机地址!"
  exit
fi
# shellcheck disable=SC2236
if [ ! -n "$user" ] ;then
  echo "请输入用户名!"
  exit
fi
# shellcheck disable=SC2236
if [ ! -n "$password" ] ;then
  echo "请输入密码!"
  exit
fi
# shellcheck disable=SC2236
if [ ! -n "$dir" ] ;then
  echo "请输入目标文件夹!"
  exit
fi
echo "deploy start......"
sshpass -p "${password}" scp centos.tar centos-web.tar "${user}"@"${host}":"${dir}"
sshpass -p "${password}" ssh -Tq "${user}"@"${host}" <<remotessh
cd ${dir}
docker load -i centos.tar
docker load -i centos-web.tar
topcwpp up
exit
remotessh
echo "deploy end......"