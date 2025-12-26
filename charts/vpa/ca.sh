#!/bin/bash

cert_dir="./tmp"
namespace="vpa-system"
rm -rf "${cert_dir}"
mkdir -p "${cert_dir}"

# 创建证书配置文件
cat > "${cert_dir}/vpa-cert-config.cnf" <<'EOF'
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[ dn ]
CN = vpa-webhook.vpa-system.svc
O = Kubernetes
OU = VPA

[ req_ext ]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ alt_names ]
DNS.1 = vpa-webhook
DNS.2 = vpa-webhook.vpa-system
DNS.3 = vpa-webhook.vpa-system.svc
DNS.4 = vpa-webhook.vpa-system.svc.cluster.local
EOF

openssl genrsa -out "${cert_dir}/ca.key" 2048
openssl req -x509 -new -nodes -key "${cert_dir}/ca.key" -sha256 -days 3650 -out "${cert_dir}/ca.crt" -subj "/CN=VPA Admission Controller CA/O=Kubernetes/OU=VPA"

openssl genrsa -out "${cert_dir}/tls.key" 2048
openssl req -new -key "${cert_dir}/tls.key" -out "${cert_dir}/tls.csr" -config "${cert_dir}/vpa-cert-config.cnf"

openssl x509 -req -in "${cert_dir}/tls.csr" \
  -CA "${cert_dir}/ca.crt" \
  -CAkey "${cert_dir}/ca.key" \
  -CAcreateserial \
  -out "${cert_dir}/tls.crt" \
  -days 3650 \
  -extensions req_ext \
  -extfile "${cert_dir}/vpa-cert-config.cnf"

openssl x509 -in "${cert_dir}/tls.crt" -text -noout | grep -A3 "Subject Alternative Name"

kubectl create ns "${namespace}"
kubectl create secret generic vpa-tls-certs \
  --namespace="${namespace}" \
  --from-file=serverCert.pem="${cert_dir}/tls.crt" \
  --from-file=serverKey.pem="${cert_dir}/tls.key" \
  --from-file=caCert.pem="${cert_dir}/ca.crt"\
  --dry-run=client -o yaml | kubectl apply -f -