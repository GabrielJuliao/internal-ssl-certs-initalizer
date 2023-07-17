init_ca_dir() {
    mkdir certs crl csr newcerts private
    touch index.txt
    echo 1000 >serial
    echo 1000 >crlnumber
}

DIR=/certs # Change to your desired location, NOTE: this var have to be changed inside the files root_ca.cnf, and intermediate.cnf
KEYPASS=123456 # Pasword for your keys

if [ -d "$DIR" ];
then
    echo "$DIR directory exists, cleaning up."
    rm -r $DIR
fi

ROOT_CNF=$(pwd)/root_ca.cnf
INTERMEDIATE_CNF=$(pwd)/intermediate_ca.cnf

mkdir -p $DIR -m 644 && cd $DIR
mkdir -p ca server client common
echo $KEYPASS > common/keypass.txt && export KEYPASS_FILE=$(pwd)/common/keypass.txt
cd ca && mkdir root intermediate

cd root && init_ca_dir && export ROOT_CA_PATH=$(pwd) && cp $ROOT_CNF $ROOT_CA_PATH/ca.cnf && cd ..
cd intermediate && init_ca_dir && export INTERMEDIATE_CA_PATH=$(pwd) && cp $INTERMEDIATE_CNF $INTERMEDIATE_CA_PATH/ca.cnf && cd ../..

# creates root CA
openssl genrsa -aes256 -passout pass:123456 -out $ROOT_CA_PATH/private/ca.key 4096
openssl req -config $ROOT_CA_PATH/ca.cnf \
      -key $ROOT_CA_PATH/private/ca.key -passin file:$KEYPASS_FILE \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out $ROOT_CA_PATH/certs/ca.crt \
      -subj "/C=US/ST=California/L=San Francisco/O=Internal Certification Authority/OU=Root Certification Authority/CN=Root Certification Authority/CN=localhost"


# creates intermediate CA
openssl genrsa -aes256 -passout pass:123456 -out $INTERMEDIATE_CA_PATH/private/ca.key 4096
openssl req -config $INTERMEDIATE_CA_PATH/ca.cnf -new -sha256 \
      -key $INTERMEDIATE_CA_PATH/private/ca.key -passin file:$KEYPASS_FILE \
      -out $INTERMEDIATE_CA_PATH/csr/ca.csr\
      -subj "/C=US/ST=California/L=San Francisco/O=Internal Certification Authority/OU=Intermediate Certification Authority/CN=Intermediate Certification Authority/CN=localhost"

openssl ca -batch -config $ROOT_CA_PATH/ca.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in $INTERMEDIATE_CA_PATH/csr/ca.csr -passin file:$KEYPASS_FILE \
      -out $INTERMEDIATE_CA_PATH/certs/ca.crt

cat $INTERMEDIATE_CA_PATH/certs/ca.crt $ROOT_CA_PATH/certs/ca.crt > common/ca.bundle.pem


# creates server certificate
openssl genrsa -out server/server.key 2048
openssl req -config $INTERMEDIATE_CA_PATH/ca.cnf \
      -key server/server.key \
      -new -sha256 -out server/server.csr \
      -subj "/C=US/ST=California/L=San Francisco/O=Generic Application /OU=Generic SSL Server/CN=Generic SSL Server/CN=localhost"

openssl ca -batch -config $INTERMEDIATE_CA_PATH/ca.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in server/server.csr -passin file:$KEYPASS_FILE\
      -out server/server.crt

# creates client certificate
openssl genrsa -out client/client.key 2048
openssl req -config $INTERMEDIATE_CA_PATH/ca.cnf \
      -key client/client.key \
      -new -sha256 -out client/client.csr \
      -subj "/C=US/ST=California/L=San Francisco/O=Generic Application /OU=Generic SSL Client/CN=Generic SSL Client/CN=localhost"

openssl ca -batch -config $INTERMEDIATE_CA_PATH/ca.cnf \
      -extensions usr_cert -days 375 -notext -md sha256 \
      -in client/client.csr -passin file:$KEYPASS_FILE\
      -out client/client.crt

# echo Importing keystore/truststore

openssl pkcs12 -export -in server/server.crt -inkey server/server.key -name serverkeystore -out server/server.p12 -passout file:$KEYPASS_FILE
openssl pkcs12 -export -in client/client.crt -inkey client/client.key -name clientkeystore -out client/client.p12 -passout file:$KEYPASS_FILE


keytool -importkeystore -deststorepass:file $KEYPASS_FILE -destkeystore server/server.keystore -srckeystore server/server.p12 -srcstorepass:file $KEYPASS_FILE -srcstoretype PKCS12 -noprompt
keytool -importcert -trustcacerts -alias servertruststore -file common/ca.bundle.pem -keystore server/server.truststore -storepass:file $KEYPASS_FILE -noprompt


keytool -importkeystore -deststorepass:file $KEYPASS_FILE -destkeystore client/client.keystore -srckeystore client/client.p12 -srcstorepass:file $KEYPASS_FILE -srcstoretype PKCS12 -noprompt
keytool -importcert -trustcacerts -alias clienttruststore -file common/ca.bundle.pem -keystore client/client.truststore -storepass:file $KEYPASS_FILE -noprompt
