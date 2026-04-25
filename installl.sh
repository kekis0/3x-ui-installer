#!/bin/bash
set -e

echo "====================================="
echo "  3x-ui PRO Installer (Nginx + SSL)"
echo "====================================="

export DEBIAN_FRONTEND=noninteractive

# -------------------------
# SYSTEM UPDATE
# -------------------------
echo "[+] Updating system..."
apt update && apt full-upgrade -y
apt install -y curl nginx openssl ca-certificates ufw cron

apt autoremove -y
apt clean

# -------------------------
# INPUTS
# -------------------------
read -p "Enter your domain (example: site.com): " DOMAIN
read -p "Enter DNSExit API key: " APIKEY
read -p "Enter 3x-ui internal port (default 10000): " PORT

PORT=${PORT:-10000}

echo "[+] Domain: $DOMAIN"
echo "[+] Port: $PORT"

# -------------------------
# FOLDERS
# -------------------------
mkdir -p /etc/dnsexit
mkdir -p /etc/ssl/dnsexit
mkdir -p /opt/ssl

# -------------------------
# DNSExit API payloads
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
# SSL FETCH SCRIPT
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
# FULLCHAIN BUILD
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
# FIRST SSL RUN
# -------------------------
echo "[+] Generating SSL..."
/opt/ssl/fetch-cert.sh
/opt/ssl/build-fullchain.sh

# -------------------------
# NGINX CONFIG
# -------------------------
echo "[+] Configuring Nginx..."

cat > /etc/nginx/sites-available/xray <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/ssl/dnsexit/fullchain.crt;
    ssl_certificate_key /etc/ssl/dnsexit/key.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:$PORT;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/xray /etc/nginx/sites-enabled/xray

nginx -t && systemctl restart nginx

# -------------------------
# FIREWALL
# -------------------------
echo "[+] Configuring firewall..."

ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# -------------------------
# AUTO RENEW CRON
# -------------------------
(crontab -l 2>/dev/null; echo "0 4 1 * * /opt/ssl/fetch-cert.sh && /opt/ssl/build-fullchain.sh && systemctl reload nginx") | crontab -

# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# -------------------------
# DONE
# -------------------------
echo "====================================="
echo " INSTALL COMPLETE"
echo "====================================="
echo " Domain: https://$DOMAIN"
echo " Nginx proxy: 443 → 127.0.0.1:$PORT"
echo " SSL: /etc/ssl/dnsexit/fullchain.crt"
echo " Key: /etc/ssl/dnsexit/key.key"
echo "====================================="
