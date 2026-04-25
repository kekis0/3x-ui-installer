#!/bin/bash

set -e

echo "====================================="
echo " SAFE INSTALL (ANTI-ERROR VERSION)"
echo "====================================="

# -------------------------
# WAIT APT LOCK
# -------------------------
echo "[+] Checking apt lock..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 2
done

export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y curl openssl ca-certificates nginx sqlite3 jq

# -------------------------
# INPUT
# -------------------------
read -p "DOMAIN: " DOMAIN
read -p "DNSExit API KEY: " APIKEY

# -------------------------
# FOLDERS
# -------------------------
mkdir -p /etc/dnsexit
mkdir -p /etc/ssl/dnsexit
mkdir -p /opt/ssl
mkdir -p /var/www/html

echo "OK" > /var/www/html/index.html

# -------------------------
# SSL REQUEST FILES
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
# SAFE FETCH CERT
# -------------------------
fetch_ssl() {
    echo "[+] Requesting SSL..."

    curl -s -H "Content-Type: application/json" \
    --data @/etc/dnsexit/cert.json \
    https://api.dnsexit.com/dns/lse.jsp > /etc/ssl/dnsexit/cert.crt

    curl -s -H "Content-Type: application/json" \
    --data @/etc/dnsexit/key.json \
    https://api.dnsexit.com/dns/lse.jsp > /etc/ssl/dnsexit/key.key

    # -------------------------
    # VALIDATE CERT
    # -------------------------
    if ! grep -q "BEGIN CERTIFICATE" /etc/ssl/dnsexit/cert.crt; then
        echo "❌ ERROR: Cert is not valid (API returned garbage)"
        cat /etc/ssl/dnsexit/cert.crt
        exit 1
    fi

    chmod 600 /etc/ssl/dnsexit/key.key
}

# -------------------------
# BUILD FULLCHAIN SAFE
# -------------------------
build_chain() {
    echo "[+] Building fullchain..."

    curl -s https://letsencrypt.org/certs/2024/r12.pem -o /etc/ssl/dnsexit/chain.pem

    cat /etc/ssl/dnsexit/cert.crt /etc/ssl/dnsexit/chain.pem > /etc/ssl/dnsexit/fullchain.crt

    # verify
    openssl x509 -in /etc/ssl/dnsexit/fullchain.crt -noout >/dev/null

    if [ $? -ne 0 ]; then
        echo "❌ FULLCHAIN INVALID"
        exit 1
    fi
}

fetch_ssl
build_chain

echo "[+] SSL OK"

# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# -------------------------
# FORCE SETTINGS
# -------------------------
echo "[+] Configuring x-ui..."

UUID=$(cat /proc/sys/kernel/random/uuid)

sqlite3 /etc/x-ui/x-ui.db <<EOF
DELETE FROM inbounds;
INSERT INTO inbounds (port, protocol, settings, stream_settings, remark, enable)
VALUES (
10000,
'vless',
'{"clients":[{"id":"$UUID"}],"decryption":"none"}',
'{"network":"ws","security":"none","wsSettings":{"path":"/ray"}}',
'auto',
1
);
EOF

systemctl restart x-ui

# -------------------------
# NGINX CONFIG
# -------------------------
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     /etc/ssl/dnsexit/fullchain.crt;
    ssl_certificate_key /etc/ssl/dnsexit/key.key;

    location / {
        root /var/www/html;
    }

    location /ray {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /panel {
        proxy_pass http://127.0.0.1:2053;
    }
}
EOF

nginx -t
systemctl restart nginx

# -------------------------
# OUTPUT
# -------------------------
echo "====================================="
echo " DONE SAFE INSTALL"
echo "====================================="
echo "SITE: https://$DOMAIN"
echo "PANEL: https://$DOMAIN/panel"
echo ""
echo "VLESS:"
echo "UUID: $UUID"
echo "PORT: 443"
echo "PATH: /ray"
echo "====================================="
