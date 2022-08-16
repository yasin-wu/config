#!/bin/bash
set -e

dns="DNS:localhost"
ip="IP:127.0.0.1"
days=3650
dir="./tmp/"

# shellcheck disable=SC2206
# shellcheck disable=SC2068
while getopts ":d:i:" opt
do
    case ${opt} in
        d)
        array=(${OPTARG//,/ })
        for var in ${array[@]}
        do
          dns="${dns},DNS:${var}"
        done
        ;;
        i)
        array=(${OPTARG//,/ })
        for var in ${array[@]}
        do
          ip="${ip},IP:${var}"
        done
        ;;
        ?)
        echo "未知参数"
        exit 1;;
    esac
done

cat > ${dir}my-openssl.cnf << EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
x509_extensions = usr_cert
[ req ]
default_bits        = 2048
default_md          = sha256
default_keyfile     = privkey.pem
distinguished_name  = req_distinguished_name
attributes          = req_attributes
x509_extensions     = v3_ca
string_mask         = utf8only
[ req_distinguished_name ]
[ req_attributes ]
[ usr_cert ]
basicConstraints       = CA:FALSE
nsComment              = "OpenSSL Generated Certificate"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = CA:true
EOF

openssl genrsa -out ${dir}ca.key 2048

openssl req -x509 -new -nodes -key ${dir}ca.key -subj "/CN=yasin.com.cn" -days ${days} -out ${dir}ca.crt

openssl genrsa -out ${dir}server.key 2048

# shellcheck disable=SC2059
openssl req -new -sha256 -key ${dir}server.key \
    -subj "/C=CN/ST=SC/L=CD/O=Yasin/CN=yasin.com.cn" \
    -reqexts SAN \
    -config <(cat ${dir}my-openssl.cnf <(printf "\n[SAN]\nsubjectAltName=${dns},${ip}")) \
    -out ${dir}server.csr

# shellcheck disable=SC2059
openssl x509 -req -days ${days} \
    -in ${dir}server.csr -CA ${dir}ca.crt -CAkey ${dir}ca.key -CAcreateserial \
    -extfile <(printf "subjectAltName=${dns},${ip}") \
    -out ${dir}server.crt