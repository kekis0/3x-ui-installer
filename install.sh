#!/bin/bash

set -e

echo "====================================="
echo "  3x-ui + SSL (DNSExit) Installer"
echo "====================================="

# -------------------------
# SYSTEM UPDATE (SAFE)
# -------------------------
echo "[+] Updating system..."

export DEBIAN_FRONTEND=noninteractive

apt update
apt full-upgrade -y
apt install -y curl openssl ca-certificates

apt autoremove -y
apt clean

echo "[+] System updated"

# -------------------------
# INPUTS
# -------------------------
read -p "Enter your domain (example: site.com): " DOMAIN
read -p "Enter DNSExit API key: " APIKEY

echo "[+] Domain: $DOMAIN"
echo "[+] API key saved"

# -------------------------
# PACKAGES
# -------------------------
apt update && apt install curl openssl -y

# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

systemctl enable x-ui
systemctl restart x-ui

# -------------------------
# FOLDERS
# -------------------------
mkdir -p /etc/dnsexit
mkdir -p /etc/ssl/dnsexit
mkdir -p /opt/ssl

# -------------------------
# API FILES
# -------------------------
cat > /etc/dnsexit/cert.json <<EOF
{
  "apikey": "$APIKEY",
  "domain": "$DOMAIN",
  "action": "download",
  "file": "cert"
}
EOF

cat > /etc/dnsexit/key.json <<EOF
{
  "apikey": "$APIKEY",
  "domain": "$DOMAIN",
  "action": "download",
  "file": "privatekey"
}
EOF

# -------------------------
# FETCH SCRIPT
# -------------------------
cat > /opt/ssl/fetch-cert.sh <<'EOF'
#!/bin/bash

API="https://api.dnsexit.com/dns/lse.jsp"

curl -s -H "Content-Type: application/json" \
--data @/etc/dnsexit/cert.json \
$API > /etc/ssl/dnsexit/cert.crt

curl -s -H "Content-Type: application/json" \
--data @/etc/dnsexit/key.json \
$API > /etc/ssl/dnsexit/key.key

chmod 600 /etc/ssl/dnsexit/key.key
EOF

# -------------------------
# BUILD FULLCHAIN
# -------------------------
cat > /opt/ssl/build-fullchain.sh <<'EOF'
#!/bin/bash

CERT="/etc/ssl/dnsexit/cert.crt"
CHAIN="/etc/ssl/dnsexit/chain.pem"
FULLCHAIN="/etc/ssl/dnsexit/fullchain.crt"

curl -s https://letsencrypt.org/certs/2024/r12.pem -o $CHAIN

cat $CERT $CHAIN > $FULLCHAIN

chmod 644 $FULLCHAIN
EOF

chmod +x /opt/ssl/fetch-cert.sh
chmod +x /opt/ssl/build-fullchain.sh

# -------------------------
# FIRST RUN
# -------------------------
echo "[+] Generating SSL..."
/opt/ssl/fetch-cert.sh
/opt/ssl/build-fullchain.sh

# -------------------------
# CRON AUTO RENEW
# -------------------------
(crontab -l 2>/dev/null; echo "0 4 1 * * /opt/ssl/fetch-cert.sh && /opt/ssl/build-fullchain.sh") | crontab -

# -------------------------
# DONE
# -------------------------
echo "====================================="
echo " INSTALL COMPLETE"
echo " DOMAIN: $DOMAIN"
echo " 3x-ui: http://SERVER_IP:2053"
echo " SSL READY"
echo "====================================="
