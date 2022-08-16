#!/bin/bash
set -e

webhook="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=210172d3-95a9-4a78-acf3-92cd657281f7"
file_name="golangci-lint.txt"
file_dir=${CI_PROJECT_DIR}

# shellcheck disable=SC2006
msg () {
key=$(echo "${webhook}" | awk -F = '{print $2}')
if test -s "${file_dir}"; then
    file_id=`curl -s -F media=@${file_name} "https://qyapi.weixin.qq.com/cgi-bin/webhook/upload_media?key=$key&type=file" |awk 'END{print}'|awk  -F '"'  '{print $14}'`
else
    echo "未检测到文件,脚本退出"
    exit 1
fi

curl "${webhook}" \
   -H 'Content-Type: application/json' \
   -d '
   {
        "msgtype": "file",
        "file": {
           "media_id": "'"$file_id"'"

        }
   }'

}

msg
