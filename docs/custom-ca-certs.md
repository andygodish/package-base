# Custom CA Certificate and CA Generation

This guide creates a local Certificate Authority (CA) and wildcard TLS certificate for a UDS development environment running under the domain `uds.local`.

---

## Setup Directories

```bash
mkdir -p ./certs/uds.local
cd ./certs/uds.local
```

## Create Local CA

```bash
openssl genrsa -out uds.local-ca.key 4096
openssl req -x509 -new -nodes -key uds.local-ca.key \
  -sha256 -days 3650 \
  -subj "/CN=UDS Local Dev CA" \
  -out uds.local-ca.crt
```

## Create server key and CSR config

```bash
openssl genrsa -out uds.local.key 2048

cat > uds.local.csr.cnf <<'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = uds.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = uds.local
DNS.2 = *.uds.local
DNS.3 = *.admin.uds.local
EOF
```

## Generate CSR

```bash
openssl req -new -key uds.local.key -out uds.local.csr -config uds.local.csr.cnf
```

## Create extensions file and sign certificate

```bash
cat > uds.local.v3.ext <<'EOF'
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = uds.local
DNS.2 = *.uds.local
DNS.3 = *.admin.uds.local
EOF

openssl x509 -req -in uds.local.csr \
  -CA uds.local-ca.crt -CAkey uds.local-ca.key -CAcreateserial \
  -out uds.local.crt -days 825 -sha256 -extfile uds.local.v3.ext
```

## Verify

```bash
openssl x509 -in uds.local.crt -text -noout | grep DNS

echo "✅ Certificate generation complete. Files created in ~/certs/uds.local:"
ls -1 ~/certs/uds.local
```

## Trust the CA Locally

### MAC OS

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/certs/uds.local/uds.local-ca.crt
```

### Linux

```bash
sudo cp ~/certs/uds.local/uds.local-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

## Encoding Cert and Key for use in UDS Config

```bash
# encode cert (no line wraps) and set ADMIN_TLS_CERT
export CERT="$(openssl base64 -A -in ./certs/uds.local/uds.local.crt)"
yq -i '.variables.core.ADMIN_TLS_CERT = env(CERT)' uds-config.yaml

# encode key and set ADMIN_TLS_KEY (if needed)
export KEY="$(openssl base64 -A -in ./certs/uds.local/uds.local.key)"
yq -i '.variables.core.ADMIN_TLS_KEY = env(KEY)' uds-config.yaml
```
