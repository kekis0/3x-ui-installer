#!/bin/bash

set -e

echo "====================================="
echo " FULL INSTALL (SSL → 3x-ui → NGINX)"
echo "====================================="

# -------------------------
# WAIT APT LOCK
# -------------------------
echo "[+] Waiting for apt lock..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 3
done

# -------------------------
# SYSTEM UPDATE
# -------------------------
export DEBIAN_FRONTEND=noninteractive

apt update
apt full-upgrade -y
apt install -y curl openssl ca-certificates nginx sqlite3

# -------------------------
# INPUT
# -------------------------
read -p "Enter domain: " DOMAIN
read -p "Enter DNSExit API key: " APIKEY

# -------------------------
# DIRS
# -------------------------
mkdir -p /etc/dnsexit
mkdir -p /etc/ssl/dnsexit
mkdir -p /opt/ssl
mkdir -p /var/www/site

echo "OK" > /var/www/site/index.html

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
# FETCH CERT
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
EOF

chmod +x /opt/ssl/*.sh

# -------------------------
# GENERATE SSL FIRST
# -------------------------
echo "[+] Generating SSL..."
/opt/ssl/fetch-cert.sh
/opt/ssl/build-fullchain.sh

echo "[+] SSL ready:"
echo "/etc/ssl/dnsexit/fullchain.crt"
echo "/etc/ssl/dnsexit/key.key"

# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# -------------------------
# AUTO INBOUND
# -------------------------
UUID=$(cat /proc/sys/kernel/random/uuid)

sqlite3 /etc/x-ui/x-ui.db <<EOF
INSERT INTO inbounds 
(port, protocol, settings, stream_settings, remark, enable)
VALUES 
(10000, 'vless',
'{"clients":[{"id":"$UUID"}],"decryption":"none"}',
'{"network":"ws","security":"none","wsSettings":{"path":"/ray"}}',
'auto', 1);
EOF

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

    root /var/www/site;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /ray {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /panel {
        proxy_pass http://127.0.0.1:2053;
    }

    location /subbus {
        proxy_pass http://127.0.0.1:2053;
    }
}
EOF

# -------------------------
# RESTART
# -------------------------
nginx -t
systemctl restart nginx
systemctl restart x-ui

# -------------------------
# CRON
# -------------------------
(crontab -l 2>/dev/null; echo "0 4 1 * * /opt/ssl/fetch-cert.sh && /opt/ssl/build-fullchain.sh && systemctl restart nginx") | crontab -

# -------------------------
# OUTPUT
# -------------------------
echo "====================================="
echo " DONE!"
echo "====================================="
echo "Site: https://$DOMAIN"
echo "Panel: https://$DOMAIN/panel"
echo "Subscription: https://$DOMAIN/subbus/..."
echo ""
echo "VLESS:"
echo "Address: $DOMAIN"
echo "Port: 443"
echo "UUID: $UUID"
echo "Path: /ray"
echo "TLS: ON"
echo "====================================="
