#!/bin/bash

IP_CERT=$(curl -s -4 ip.sb)
ZEROSSL_KEY=
GENERATED_DIR=./cert/$IP_CERT
HTTP_DIR=/var/www/html

apt install jq unzip -y

# 创建CSR和KEY
#RSA
#openssl req -new -newkey rsa:2048 -nodes -keyout $IP_CERT.key -out $IP_CERT.csr -subj "/C=CN/ST=Shanghai/L=Shanghai/CN=$IP_CERT"
#ECC
openssl ecparam -name prime256v1 -out "ecparam.pem"
openssl req -new -SHA256 -newkey ec:ecparam.pem -nodes -keyout $IP_CERT.key -out $IP_CERT.csr -subj "/C=CN/ST=Shanghai/L=Shanghai/CN=$IP_CERT"
mkdir -p $GENERATED_DIR

# ZeroSSL REST API
curl -s -X POST https://api.zerossl.com/certificates?access_key=$ZEROSSL_KEY --data-urlencode certificate_csr@$IP_CERT.csr -d certificate_domains=$IP_CERT -d certificate_validity_days=90 -o $IP_CERT.resp

mv ecparam.pem ${GENERATED_DIR}/ecparam.pem
mv $IP_CERT.csr ${GENERATED_DIR}/$IP_CERT.csr
mv $IP_CERT.key ${GENERATED_DIR}/$IP_CERT.key

echo "已创建证书请求"
mkdir -p $HTTP_DIR/.well-known/pki-validation
ID="$(cat $IP_CERT.resp | jq -r '.id')"
URL=$(cat $IP_CERT.resp | jq -r ".validation.other_methods.\"$IP_CERT\".file_validation_url_http")
FILE_NAME=$(basename $URL)
cat ./$IP_CERT.resp | jq -r ".validation.other_methods.\"$IP_CERT\".file_validation_content|join(\"\n\")" > $HTTP_DIR/.well-known/pki-validation/$FILE_NAME
#echo "等待10秒以确保生效"
#sleep 10
curl -s -X GET http://api.zerossl.com/certificates/${ID}?access_key=$ZEROSSL_KEY -o status.resp
CERT_STATUS=$(cat status.resp | jq -r '.status')

if [ "$CERT_STATUS" == "draft" ];
then
  echo "证书 $ID 还未准备好"
  #可选 HTTPS_CSR_HASH，大概吧
  curl -s -X POST https://api.zerossl.com/certificates/${ID}/challenges?access_key=$ZEROSSL_KEY -d validation_method=HTTP_CSR_HASH
  echo "等待10秒"
  sleep 10s
fi

curl -s -X GET http://api.zerossl.com/certificates/${ID}?access_key=$ZEROSSL_KEY -o status.resp
echo "验证证书状态"
CERT_STATUS=$(cat status.resp | jq -r '.status')

if [ "$CERT_STATUS" == "issued" ];
then
  echo "证书已颁发"
else
  echo "验证失败"
  exit 1
fi

echo "下载证书"
curl  https://api.zerossl.com/certificates/${ID}/download?access_key=$ZEROSSL_KEY --output $GENERATED_DIR/certificate.zip
echo "."
unzip -o -d $GENERATED_DIR $GENERATED_DIR/certificate.zip
cat $GENERATED_DIR/certificate.crt $GENERATED_DIR/ca_bundle.crt >$GENERATED_DIR/fullcert.pem
#rm -r ./$IP_CERT.resp ./status.resp
