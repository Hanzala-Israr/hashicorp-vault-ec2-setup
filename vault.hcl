storage "file" {
path = "/opt/vault/data"
}

listener "tcp" {
address       = "0.0.0.0:8200"
tls_cert_file = "/etc/vault.d/vault.crt"
tls_key_file  = "/etc/vault.d/vault.key"
}

ui = true
disable_mlock = true

api_addr = "https://<EC2_PUBLIC_IP>:8200"
cluster_addr = "https://127.0.0.1:8201"
