# HashiCorp Vault Production Setup on AWS EC2 (Using Public IP & Self-Signed TLS)

## Project Overview

This project demonstrates how to **deploy HashiCorp Vault on an AWS EC2 Ubuntu server with HTTPS enabled** using a **self-signed TLS certificate and public IP address (without a domain name)**.

The setup includes:

* Installing Vault from the official HashiCorp repository
* Configuring secure storage
* Enabling HTTPS using OpenSSL
* Running Vault as a **systemd service**
* Initializing and unsealing Vault
* Enabling the **KV secrets engine**
* Creating a **read-only policy for Jenkins**
* Storing and retrieving secrets from Vault

This setup simulates a **real DevOps production workflow** for secret management.

---

# Architecture

```
Developer / Jenkins
        │
        │ HTTPS (8200)
        ▼
AWS EC2 Instance
(HashiCorp Vault Server)
        │
        ▼
Encrypted Secrets Storage
```

---

# Prerequisites

Before starting, ensure you have:

* AWS Account
* EC2 Ubuntu Instance (22.04 recommended)
* Open port **8200** in the EC2 Security Group
* Basic knowledge of Linux commands

Example Security Group Rule:

| Type       | Port | Source    |
| ---------- | ---- | --------- |
| Custom TCP | 8200 | 0.0.0.0/0 |

---

# Step 1 — Update System & Install Dependencies

Update Ubuntu packages:

```bash
sudo apt update && sudo apt upgrade -y
```

Install required tools:

```bash
sudo apt install -y unzip curl jq gnupg
```

---

# Step 2 — Install HashiCorp Vault (Official Repository)

Add the HashiCorp GPG key:

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | \
sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

Add the official repository:

```bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list
```

Install Vault:

```bash
sudo apt update
sudo apt install vault -y
```

Verify installation:

```bash
vault -v
```

---

# Step 3 — Create Vault User & Required Directories

Create a dedicated Vault system user:

```bash
sudo useradd --system --home /etc/vault.d --shell /bin/false vault
```

Create required directories:

```bash
sudo mkdir -p /opt/vault/data
sudo mkdir -p /etc/vault.d
```

Set ownership:

```bash
sudo chown -R vault:vault /opt/vault
sudo chown -R vault:vault /etc/vault.d
```

---

# Step 4 — Generate Self-Signed TLS Certificate

Since no domain is used, we generate a **certificate using the EC2 public IP**.

Create OpenSSL configuration:

```bash
sudo nano /etc/vault.d/vault-openssl.cnf
```

Paste the following configuration (replace with your EC2 public IP):

```
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = US
ST = State
L = City
O = Vault
OU = DevOps
CN = <EC2_PUBLIC_IP>

[req_ext]
subjectAltName = @alt_names

[alt_names]
IP.1 = <EC2_PUBLIC_IP>
```

Generate TLS certificate:

```bash
sudo openssl req -x509 -nodes -days 365 \
-newkey rsa:2048 \
-keyout /etc/vault.d/vault.key \
-out /etc/vault.d/vault.crt \
-config /etc/vault.d/vault-openssl.cnf \
-extensions req_ext
```

---

# Step 5 — Set Correct Permissions

```bash
sudo chown vault:vault /etc/vault.d/vault.*
```

```bash
sudo chmod 640 /etc/vault.d/vault.key
sudo chmod 644 /etc/vault.d/vault.crt
```

---

# Step 6 — Configure Vault

Create configuration file:

```bash
sudo nano /etc/vault.d/vault.hcl
```

Paste the following:

```
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
```

---

# Step 7 — Create systemd Service for Vault

Create service file:

```bash
sudo nano /etc/systemd/system/vault.service
```

Paste:

```
[Unit]
Description=Vault Server
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
```

---

# Step 8 — Start Vault Service

Reload systemd:

```bash
sudo systemctl daemon-reexec
```

```bash
sudo systemctl daemon-reload
```

Enable Vault service:

```bash
sudo systemctl enable vault
```

Start Vault:

```bash
sudo systemctl start vault
```

Check status:

```bash
sudo systemctl status vault
```

---

# Step 9 — Configure Vault Address

Set Vault server address:

```bash
export VAULT_ADDR=https://<EC2_PUBLIC_IP>:8200
```

To make it permanent:

```bash
echo 'export VAULT_ADDR=https://<EC2_PUBLIC_IP>:8200' >> ~/.bashrc
source ~/.bashrc
```

---

# Step 10 — Initialize Vault

Initialize Vault:

```bash
vault operator init -key-shares=5 -key-threshold=3
```

This command generates:

* 5 Unseal Keys
* 1 Root Token

⚠️ Save these securely.

---

# Step 11 — Unseal Vault

Vault starts in a sealed state.

Unseal using **3 keys**:

```bash
vault operator unseal
```

Enter 3 keys one by one.

Check status:

```bash
vault status
```

---

# Step 12 — Login to Vault

```bash
vault login
```

Paste the **Initial Root Token**.

---

# Step 13 — Enable KV Secrets Engine

Enable KV version 2 secrets engine:

```bash
vault secrets enable -path=secret kv-v2
```

Store a secret:

```bash
vault kv put secret/myapp username=admin password=supersecure123
```

Retrieve the secret:

```bash
vault kv get secret/myapp
```

---

# Step 14 — Create Jenkins Read Policy

Create policy file:

```bash
nano jenkins-read-policy.hcl
```

Paste:

```
path "secret/data/jenkins/*" {
  capabilities = ["read"]
}
```

Apply the policy:

```bash
vault policy write jenkins-read jenkins-read-policy.hcl
```

---

# Step 15 — Create Jenkins Token

Generate token for Jenkins:

```bash
vault token create -policy=jenkins-read -ttl=24h
```

---

# Step 16 — Store Jenkins Secrets

Store Docker credentials:

```bash
vault kv put secret/jenkins/docker \
username=mydockeruser \
password=MyP@ssword123
```

---

# Step 17 — Access Vault Web UI

Open browser:

```
https://<EC2_PUBLIC_IP>:8200
```

Example:

```
https://13.61.176.244:8200
```

Since the certificate is self-signed, the browser will show a **security warning**.

Click:

```
Advanced → Proceed
```

Login using the **root token**.

---



# Author

**Hanzala Israr**

---
<img width="1860" height="1114" alt="image" src="https://github.com/user-attachments/assets/d35c91ea-5e8e-4d34-a0ce-951016ec87e9" />


