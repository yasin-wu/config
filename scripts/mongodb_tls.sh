#!/bin/bash
set -e

# 默认值
DAYS=3650
SUBJ="/C=CN/ST=ChengDu/L=ChengDu/O=Yasin/OU=Yasin/CN=Yasin"
OUTPUT_DIR="./mongodb"
IPS=(127.0.0.1)
DOMAINS=(mongodb localhost)
CA_SUBJ="/CN=Yasin CA"

# 显示帮助
usage() {
  cat <<EOF
用法：$0 [选项]

可选参数：
  -d, --days DAYS       证书有效期（天数），默认 365
  -o, --output-dir DIR  输出目录，默认当前目录
  -I, --ip IP           添加 IP 地址到 SAN（可重复使用）
  -D, --domain DOMAIN   添加域名到 SAN（可重复使用）
  --ca-subj SUBJ        CA 证书的主题，默认 "/CN=Yasin CA"
  -h, --help            显示此帮助信息

描述：
  生成 CA 证书（ca.pem）和服务端证书包（mongodb.pem）。
  CA 证书为自签名，使用 --ca-subj 指定的主题。
  服务端证书由 CA 签名，使用 SUBJ 作为主题，
  并将提供的 IP 和域名添加为 SAN 扩展。

  生成的 mongodb.pem 包含服务端私钥和已签名的证书。

示例：
  $0 -s "/CN=mongodb.example.com" -D example.com -D mongo.local -I 192.168.1.100 -d 3650
EOF
  exit 0
}

validate_cert() {
  echo ""
  echo ">>> 开始校验 mongodb.pem ..."

  # 1. 检查文件是否存在且非空
  if [ ! -s "mongodb.pem" ]; then
    echo "❌ 错误：mongodb.pem 文件不存在或为空！" >&2
    return 1
  fi

  # 2. 检查私钥与证书的模数是否匹配（确保是一对）
  KEY_MOD=$(openssl rsa -noout -modulus -in mongodb.pem 2>/dev/null | openssl md5)
  CRT_MOD=$(openssl x509 -noout -modulus -in mongodb.pem 2>/dev/null | openssl md5)
  if [ -z "$KEY_MOD" ] || [ -z "$CRT_MOD" ]; then
    echo "❌ 错误：无法提取模数，mongodb.pem 内容可能损坏！" >&2
    return 1
  fi
  if [ "$KEY_MOD" != "$CRT_MOD" ]; then
    echo "❌ 错误：私钥和证书的模数不匹配（非一对）！" >&2
    return 1
  fi
  echo "✅ 校验通过：私钥与证书匹配"

  # 3. 验证证书是否由 ca.pem 正确签署
  VERIFY_OUT=$(openssl verify -CAfile ca.pem mongodb.pem 2>&1)
  if [[ "$VERIFY_OUT" != *"OK"* ]]; then
    echo "❌ 错误：证书未被 ca.pem 正确签署！详情：$VERIFY_OUT" >&2
    return 1
  fi
  echo "✅ 校验通过：证书由 CA 正确签署"

  # 4. 检查证书是否过期（检查当前时间是否在有效期内）
  if ! openssl x509 -checkend 0 -noout -in mongodb.pem 2>/dev/null; then
    echo "❌ 错误：证书已过期！" >&2
    return 1
  fi
  echo "✅ 校验通过：证书在有效期内"

  # 5. （可选）显示证书中的 SAN 与 CN，便于人工核对
  echo ""
  echo "📋 证书摘要信息："
  openssl x509 -in mongodb.pem -noout -subject -dates
  echo "SAN 扩展："
  openssl x509 -in mongodb.pem -noout -text | grep -A1 "Subject Alternative Name" || echo "  （未设置 SAN）"

  echo ""
  echo "✅✅✅ 全部校验通过，mongodb.pem 可安全使用！"
  return 0
}

# 解析参数
OPTS=$(getopt -o s:d:o:I:D:h -l subj:,days:,output-dir:,ip:,domain:,ca-subj:,help -n "${0}" -- "${@}")
if [ $? -ne 0 ]; then
  echo "错误：参数解析失败。" >&2
  exit 1
fi
eval set -- "${OPTS}"

while true; do
  case "${1}" in
    -d|--days)
      DAYS="${2}"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="${2}"
      shift 2
      ;;
    -I|--ip)
      IPS+=("${2}")
      shift 2
      ;;
    -D|--domain)
      DOMAINS+=("${2}")
      shift 2
      ;;
    --ca-subj)
      CA_SUBJ="${2}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "内部错误！" >&2
      exit 1
      ;;
  esac
done

# 检查 openssl
if ! command -v openssl &>/dev/null; then
  echo "错误：未找到 openssl，请先安装。" >&2
  exit 1
fi

# 检查 openssl 是否支持 -addext（需 1.1.1+）
SUPPORTS_ADDEXT=false
if openssl x509 -req -addext "" -in /dev/null -CA /dev/null -CAkey /dev/null -out /dev/null 2>/dev/null; then
  SUPPORTS_ADDEXT=true
fi
# 构建 SAN 字符串
SAN=""
for domain in "${DOMAINS[@]}"; do
  [ -n "${SAN}" ] && SAN="${SAN},"
  SAN="${SAN}DNS:${domain}"
done
for ip in "${IPS[@]}"; do
  [ -n "${SAN}" ] && SAN="${SAN},"
  SAN="${SAN}IP:${ip}"
done

# 创建输出目录
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

echo ">>> 正在生成 CA 密钥和证书..."
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days "${DAYS}" -key ca.key -out ca.pem -subj "${CA_SUBJ}"

echo ">>> 正在生成服务端密钥和证书签名请求（CSR）..."
openssl genrsa -out mongodb.key 4096
openssl req -new -key mongodb.key -out mongodb.csr -subj "${SUBJ}"

echo ">>> 正在使用 CA 签署服务端证书..."
if [ -n "${SAN}" ]; then
  if "${SUPPORTS_ADDEXT}"; then
    openssl x509 -req -days "${DAYS}" -in mongodb.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out mongodb.crt -addext "subjectAltName=${SAN}"
  else
    # 不支持 -addext，使用配置文件方式
    cat > san.cnf <<EOF
[v3_req]
subjectAltName = ${SAN}
EOF
    openssl x509 -req -days "${DAYS}" -in mongodb.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out mongodb.crt -extfile san.cnf -extensions v3_req
    rm -f san.cnf
  fi
else
  # 无 SAN，直接签名
  openssl x509 -req -days "${DAYS}" -in mongodb.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out mongodb.crt
fi

echo ">>> 正在合并私钥和证书到 mongodb.pem..."
cat mongodb.key mongodb.crt > mongodb.pem

# 清理临时文件（保留 ca.key）
rm -f mongodb.csr mongodb.crt ca.srl

if ! validate_cert; then
  echo "证书校验失败，请检查生成过程！" >&2
  exit 1
fi

echo "========================================"
echo "完成。文件已生成至：${OUTPUT_DIR}"
echo "  - ca.pem          ：CA 证书（用于 --tlsCAFile）"
echo "  - mongodb.pem     ：服务端私钥 + 证书（用于 --tlsCertificateKeyFile）"
echo "  - ca.key          ：CA 私钥（请妥善保管）"
if [ -n "${SAN}" ]; then
  echo "  - SAN 扩展        ：${SAN}"
else
  echo "  - 未添加 SAN，证书仅依赖于 CN。"
fi
echo "========================================"
echo "注意：SUBJ 中的 CN 以及 SAN（如有）必须与客户端连接时使用的主机名/IP 一致。"