#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Azure Cloud Shell Bootstrap - SOCKS5 Proxy Tool
# Repo file: azure_proxy_bootstrap.sh
#
# Default:
# Resource Group: azure-proxy-rg
# Region: japanwest
# VM Prefix: proxy-jpw
# VM Size: Standard_B2ts_v2
# Proxy: japan:japn
# Port: 1080
# =========================================================

TOOL_DIR="$HOME/azure-proxy-tool"
mkdir -p "$TOOL_DIR"
cd "$TOOL_DIR"

# =========================================================
# 00_config.sh
# =========================================================
cat > 00_config.sh <<'EOF'
#!/usr/bin/env bash

RESOURCE_GROUP="azure-proxy-rg"
REGION="japanwest"
VM_PREFIX="proxy-jpw"
VM_SIZE="Standard_B2ts_v2"

PROXY_USER="japan"
PROXY_PASS="japn"
PROXY_PORT="1080"

ADMIN_USER="ubuntu"
IMAGE="Ubuntu2204"

EXPORT_FILE="proxies.txt"
CLOUD_INIT_FILE="cloud-init-proxy.yml"

SOURCE_IP="*"

RESOURCE_PROVIDERS=(
  "Microsoft.Compute"
  "Microsoft.Network"
  "Microsoft.Storage"
)
EOF

# =========================================================
# 01_register_providers.sh
# =========================================================
cat > 01_register_providers.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

echo "[+] Checking Azure login..."
az account show >/dev/null

echo "[+] Current subscription:"
az account show --query "{name:name, subscription:id, user:user.name}" -o table

echo "[+] Register required Azure Resource Providers..."

for ns in "${RESOURCE_PROVIDERS[@]}"; do
  echo
  echo "[+] Provider: $ns"

  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")"

  if [[ "$state" == "Registered" ]]; then
    echo "    Already Registered"
  else
    echo "    Current state: $state"
    echo "    Registering $ns..."
    az provider register --namespace "$ns" --wait
  fi

  final_state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
  echo "    Final state: $final_state"
done

echo
echo "[OK] Resource Provider registration completed."
EOF

# =========================================================
# 02_make_cloud_init.sh
# =========================================================
cat > 02_make_cloud_init.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

echo "[+] Generating cloud-init file: $CLOUD_INIT_FILE"

cat > "$CLOUD_INIT_FILE" <<CLOUDINIT
#cloud-config
package_update: true
package_upgrade: false

write_files:
  - path: /root/install_3proxy.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -eux

      PROXY_USER="${PROXY_USER}"
      PROXY_PASS="${PROXY_PASS}"
      PROXY_PORT="${PROXY_PORT}"

      export DEBIAN_FRONTEND=noninteractive

      apt-get update -y
      apt-get install -y curl ca-certificates ufw git build-essential make gcc libssl-dev

      systemctl stop 3proxy || true
      pkill 3proxy || true

      THREEPROXY_BIN=""

      if apt-cache show 3proxy >/dev/null 2>&1; then
        apt-get install -y 3proxy || true
        THREEPROXY_BIN="\$(command -v 3proxy || true)"
      fi

      if [ -z "\$THREEPROXY_BIN" ]; then
        cd /opt
        rm -rf 3proxy
        git clone https://github.com/3proxy/3proxy.git
        cd /opt/3proxy
        make -f Makefile.Linux
        install -m 755 /opt/3proxy/bin/3proxy /usr/local/bin/3proxy
        THREEPROXY_BIN="/usr/local/bin/3proxy"
      fi

      mkdir -p /etc/3proxy

      cat > /etc/3proxy/3proxy.cfg <<PROXYCONF
      daemon
      maxconn 1000
      nscache 65536
      timeouts 1 5 30 60 180 1800 15 60
      auth strong
      users \${PROXY_USER}:CL:\${PROXY_PASS}
      allow \${PROXY_USER}
      socks -p\${PROXY_PORT} -i0.0.0.0
      PROXYCONF

      cat > /etc/systemd/system/3proxy.service <<SERVICECONF
      [Unit]
      Description=3proxy SOCKS5 Proxy Server
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=forking
      ExecStart=\${THREEPROXY_BIN} /etc/3proxy/3proxy.cfg
      Restart=always
      RestartSec=5
      LimitNOFILE=65536

      [Install]
      WantedBy=multi-user.target
      SERVICECONF

      ufw allow 22/tcp || true
      ufw allow \${PROXY_PORT}/tcp || true
      ufw --force enable || true
      iptables -I INPUT -p tcp --dport \${PROXY_PORT} -j ACCEPT || true

      systemctl daemon-reload
      systemctl enable 3proxy
      systemctl restart 3proxy

      sleep 2

      systemctl status 3proxy --no-pager || true
      ss -lntp | grep ":\${PROXY_PORT}" || true

runcmd:
  - bash /root/install_3proxy.sh > /root/install_3proxy.log 2>&1
CLOUDINIT

echo "[OK] cloud-init generated."
EOF

# =========================================================
# 03_create_proxies.sh
# =========================================================
cat > 03_create_proxies.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

QUANTITY="${1:-}"

if [[ -z "$QUANTITY" ]]; then
  read -rp "Proxy Quantity: " QUANTITY
fi

if ! [[ "$QUANTITY" =~ ^[0-9]+$ ]] || [[ "$QUANTITY" -lt 1 ]]; then
  echo "[ERROR] Proxy Quantity must be a positive number."
  exit 1
fi

echo "[+] Creating/checking resource group: $RESOURCE_GROUP / $REGION"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$REGION" \
  -o table

if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
  bash ./02_make_cloud_init.sh
fi

touch "$EXPORT_FILE"

vm_exists() {
  local vm_name="$1"
  az vm show -g "$RESOURCE_GROUP" -n "$vm_name" >/dev/null 2>&1
}

next_vm_name() {
  local index=1

  while true; do
    local vm_name
    vm_name="$(printf "%s-%03d" "$VM_PREFIX" "$index")"

    if ! vm_exists "$vm_name"; then
      echo "$vm_name"
      return 0
    fi

    index=$((index + 1))
  done
}

get_public_ip() {
  local vm_name="$1"

  az vm show \
    -g "$RESOURCE_GROUP" \
    -n "$vm_name" \
    -d \
    --query publicIps \
    -o tsv
}

open_nsg_port() {
  local vm_name="$1"
  local nsg_name="${vm_name}NSG"

  echo "[+] Opening Azure NSG port ${PROXY_PORT} on $nsg_name"

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$nsg_name" \
    --name "Allow-SOCKS5-${PROXY_PORT}" \
    --priority 300 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$SOURCE_IP" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "$PROXY_PORT" \
    -o table || true
}

test_proxy() {
  local ip="$1"

  echo "[+] Testing SOCKS5 proxy: ${ip}:${PROXY_PORT}:${PROXY_USER}:${PROXY_PASS}"

  for i in {1..20}; do
    result="$(curl -sS \
      --connect-timeout 10 \
      --max-time 20 \
      --socks5-hostname "${PROXY_USER}:${PROXY_PASS}@${ip}:${PROXY_PORT}" \
      https://api.ipify.org || true)"

    if [[ "$result" == "$ip" ]]; then
      echo "[OK] Proxy live: ${ip}:${PROXY_PORT}:${PROXY_USER}:${PROXY_PASS}"
      return 0
    fi

    echo "    Waiting for cloud-init/3proxy... attempt $i/20"
    sleep 15
  done

  echo "[!] Proxy test failed for now."
  echo "    Check VM install log:"
  echo "    az vm run-command invoke -g $RESOURCE_GROUP -n <VM_NAME> --command-id RunShellScript --scripts 'cat /root/install_3proxy.log; systemctl status 3proxy --no-pager; ss -lntp | grep 1080'"
  return 1
}

create_one_proxy() {
  local vm_name
  vm_name="$(next_vm_name)"

  echo
  echo "=================================================="
  echo "[+] Creating VM: $vm_name"
  echo "    Resource Group: $RESOURCE_GROUP"
  echo "    Region: $REGION"
  echo "    Size: $VM_SIZE"
  echo "    Proxy: ${PROXY_USER}:${PROXY_PASS}"
  echo "    Port: $PROXY_PORT"
  echo "=================================================="

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$vm_name" \
    --location "$REGION" \
    --image "$IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --custom-data "$CLOUD_INIT_FILE" \
    --public-ip-sku Standard \
    --public-ip-address-allocation static \
    --nsg "${vm_name}NSG" \
    --tags created_by=azure_proxy_tool proxy_port="$PROXY_PORT" \
    -o table

  open_nsg_port "$vm_name"

  echo "[+] Getting Public IP..."
  ip=""

  for i in {1..10}; do
    ip="$(get_public_ip "$vm_name" || true)"

    if [[ -n "$ip" ]]; then
      break
    fi

    sleep 10
  done

  if [[ -z "$ip" ]]; then
    echo "[ERROR] Could not get Public IP for $vm_name"
    return 1
  fi

  proxy_line="${ip}:${PROXY_PORT}:${PROXY_USER}:${PROXY_PASS}"

  if ! grep -q "^${ip}:${PROXY_PORT}:" "$EXPORT_FILE" 2>/dev/null; then
    echo "$proxy_line" >> "$EXPORT_FILE"
  fi

  echo
  echo "[OK] CREATED:"
  echo "$proxy_line"
  echo

  test_proxy "$ip" || true
}

echo "[+] Start creating $QUANTITY proxy/proxies..."

for ((i=1; i<=QUANTITY; i++)); do
  echo
  echo "========== $i/$QUANTITY =========="
  create_one_proxy
done

echo
echo "=================================================="
echo "[DONE] Proxy list exported to: $EXPORT_FILE"
echo "=================================================="
cat "$EXPORT_FILE"
EOF

# =========================================================
# 04_test_proxies.sh
# =========================================================
cat > 04_test_proxies.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

FILE="${1:-$EXPORT_FILE}"

if [[ ! -f "$FILE" ]]; then
  echo "[ERROR] File not found: $FILE"
  exit 1
fi

echo "[+] Testing proxies from $FILE"
echo

while IFS=: read -r ip port user pass; do
  [[ -z "${ip:-}" ]] && continue

  echo -n "Test ${ip}:${port} ... "

  result="$(curl -sS \
    --connect-timeout 10 \
    --max-time 20 \
    --socks5-hostname "${user}:${pass}@${ip}:${port}" \
    https://api.ipify.org || true)"

  if [[ "$result" == "$ip" ]]; then
    echo "OK"
  else
    echo "FAIL result=$result"
  fi
done < "$FILE"
EOF

# =========================================================
# 05_fix_one_proxy.sh
# =========================================================
cat > 05_fix_one_proxy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

VM_NAME="${1:-}"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage:"
  echo "bash 05_fix_one_proxy.sh proxy-jpw-001"
  exit 1
fi

cat > /tmp/fix_3proxy_vm.sh <<FIXSCRIPT
set -eux

PROXY_USER="${PROXY_USER}"
PROXY_PASS="${PROXY_PASS}"
PROXY_PORT="${PROXY_PORT}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl ca-certificates ufw git build-essential make gcc libssl-dev

systemctl stop 3proxy || true
pkill 3proxy || true

cd /opt
rm -rf 3proxy
git clone https://github.com/3proxy/3proxy.git
cd /opt/3proxy
make -f Makefile.Linux
install -m 755 /opt/3proxy/bin/3proxy /usr/local/bin/3proxy

mkdir -p /etc/3proxy

cat > /etc/3proxy/3proxy.cfg <<PROXYCONF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth strong
users \${PROXY_USER}:CL:\${PROXY_PASS}
allow \${PROXY_USER}
socks -p\${PROXY_PORT} -i0.0.0.0
PROXYCONF

cat > /etc/systemd/system/3proxy.service <<SERVICECONF
[Unit]
Description=3proxy SOCKS5 Proxy Server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICECONF

ufw allow 22/tcp || true
ufw allow \${PROXY_PORT}/tcp || true
ufw --force enable || true
iptables -I INPUT -p tcp --dport \${PROXY_PORT} -j ACCEPT || true

systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

sleep 2

systemctl status 3proxy --no-pager || true
ss -lntp | grep ":\${PROXY_PORT}" || true
FIXSCRIPT

echo "[+] Fixing 3proxy on VM: $VM_NAME"

az vm run-command invoke \
  -g "$RESOURCE_GROUP" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "$(cat /tmp/fix_3proxy_vm.sh)"

echo "[OK] Fix command completed."
EOF

# =========================================================
# 06_delete_one_proxy.sh
# =========================================================
cat > 06_delete_one_proxy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

VM_NAME="${1:-}"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage:"
  echo "bash 06_delete_one_proxy.sh proxy-jpw-001"
  exit 1
fi

echo "[!] About to delete VM and related resources: $VM_NAME"
read -rp "Type DELETE to confirm: " confirm

if [[ "$confirm" != "DELETE" ]]; then
  echo "Cancelled."
  exit 0
fi

NIC_ID="$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "networkProfile.networkInterfaces[0].id" -o tsv 2>/dev/null || true)"
NIC_NAME="$(basename "$NIC_ID" 2>/dev/null || true)"

OS_DISK="$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "storageProfile.osDisk.name" -o tsv 2>/dev/null || true)"

PUBLIC_IP_NAME=""
NSG_NAME=""

if [[ -n "$NIC_NAME" && "$NIC_NAME" != "." ]]; then
  PUBLIC_IP_ID="$(az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME" --query "ipConfigurations[0].publicIPAddress.id" -o tsv 2>/dev/null || true)"
  PUBLIC_IP_NAME="$(basename "$PUBLIC_IP_ID" 2>/dev/null || true)"

  NSG_ID="$(az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME" --query "networkSecurityGroup.id" -o tsv 2>/dev/null || true)"
  NSG_NAME="$(basename "$NSG_ID" 2>/dev/null || true)"
fi

echo "[+] Delete VM: $VM_NAME"
az vm delete -g "$RESOURCE_GROUP" -n "$VM_NAME" --yes || true

if [[ -n "$NIC_NAME" && "$NIC_NAME" != "." ]]; then
  echo "[+] Delete NIC: $NIC_NAME"
  az network nic delete -g "$RESOURCE_GROUP" -n "$NIC_NAME" || true
fi

if [[ -n "$PUBLIC_IP_NAME" && "$PUBLIC_IP_NAME" != "." ]]; then
  echo "[+] Delete Public IP: $PUBLIC_IP_NAME"
  az network public-ip delete -g "$RESOURCE_GROUP" -n "$PUBLIC_IP_NAME" || true
fi

if [[ -n "$NSG_NAME" && "$NSG_NAME" != "." ]]; then
  echo "[+] Delete NSG: $NSG_NAME"
  az network nsg delete -g "$RESOURCE_GROUP" -n "$NSG_NAME" || true
fi

if [[ -n "$OS_DISK" ]]; then
  echo "[+] Delete OS Disk: $OS_DISK"
  az disk delete -g "$RESOURCE_GROUP" -n "$OS_DISK" --yes || true
fi

echo "[OK] Deleted: $VM_NAME"
EOF

# =========================================================
# 07_delete_all_proxy_rg.sh
# =========================================================
cat > 07_delete_all_proxy_rg.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

echo "[!] About to delete whole Resource Group: $RESOURCE_GROUP"
echo "This will delete all VM, Disk, NIC, NSG, Public IP inside this group."
read -rp "Type DELETE to confirm: " confirm

if [[ "$confirm" != "DELETE" ]]; then
  echo "Cancelled."
  exit 0
fi

az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

echo "[OK] Delete request sent for Resource Group: $RESOURCE_GROUP"
EOF

# =========================================================
# 08_debug_one_proxy.sh
# =========================================================
cat > 08_debug_one_proxy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source ./00_config.sh

VM_NAME="${1:-}"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage:"
  echo "bash 08_debug_one_proxy.sh proxy-jpw-001"
  exit 1
fi

az vm run-command invoke \
  -g "$RESOURCE_GROUP" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts '
echo "===== cloud-init status ====="
cloud-init status --long || true

echo "===== install log ====="
tail -n 200 /root/install_3proxy.log || true

echo "===== 3proxy status ====="
systemctl status 3proxy --no-pager || true

echo "===== listening ports ====="
ss -lntp || true

echo "===== firewall ====="
ufw status verbose || true

echo "===== config ====="
cat /etc/3proxy/3proxy.cfg || true
'
EOF

# =========================================================
# run.sh
# =========================================================
cat > run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " Azure SOCKS5 Proxy Tool - Cloud Shell"
echo "=================================================="
echo

bash ./01_register_providers.sh
bash ./02_make_cloud_init.sh
bash ./03_create_proxies.sh
EOF

chmod +x ./*.sh

echo
echo "=================================================="
echo "[OK] Tool created at: $TOOL_DIR"
echo "=================================================="
echo
echo "Running now..."
echo

bash ./run.sh
