#!/bin/bash

set -e

echo "====================================="
echo " WEB LAYER INSTALL (NGINX + SSL)"
echo "====================================="

# -------------------------
# INPUTS
# -------------------------
read -p "Enter domain (example.com): " DOMAIN

read -p "Enter SSL cert path (fullchain.crt): " CERT
read -p "Enter SSL key path (key.key): " KEY

# -------------------------
# INSTALL NGINX
# -------------------------
apt update
apt install -y nginx

# -------------------------
# BASIC SITE
# -------------------------
mkdir -p /var/www/site
echo "<h1>OK - SERVER ONLINE</h1>" > /var/www/site/index.html

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

    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;

    # ---------------- SITE ----------------
    location / {
        root /var/www/site;
        index index.html;
    }

    # ---------------- 3X-UI PANEL ----------------
    location /panel {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # ---------------- XRAY / VLESS WS ----------------
    location /ray {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # ---------------- SUBSCRIPTION ----------------
    location /subbus {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

EOF

# -------------------------
# TEST & RESTART
# -------------------------
nginx -t
systemctl restart nginx

# -------------------------
# DONE
# -------------------------
echo "====================================="
echo " WEB LAYER READY"
echo "====================================="
echo "https://$DOMAIN"
echo "https://$DOMAIN/panel"
echo "https://$DOMAIN/subbus"
echo "====================================="
