#!/bin/bash

set -e

echo "====================================="
echo "        WEB LAYER (NGINX)"
echo "====================================="

export DEBIAN_FRONTEND=noninteractive

# -------------------------
# INPUT DOMAIN
# -------------------------
read -p "Enter your domain (example: site.com): " DOMAIN

read -p "Enter your panel path (example: $DOMAIN/...): " PANEL_PATH


# -------------------------
# INSTALL NGINX
# -------------------------
echo "[+] Installing nginx..."
apt update -y
apt install -y nginx

# -------------------------
# SSL PATHS (from your previous script)
# -------------------------
SSL_CERT="/etc/ssl/dnsexit/fullchain.crt"
SSL_KEY="/etc/ssl/dnsexit/key.key"

# safety check
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
  echo "❌ SSL files not found!"
  echo "Expected:"
  echo "$SSL_CERT"
  echo "$SSL_KEY"
  exit 1
fi

# -------------------------
# NGINX CONFIG
# -------------------------
echo "[+] Creating nginx config..."

cat > /etc/nginx/sites-available/xui.conf <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;

    # -------------------------
    # MAIN SITE (XRY)
    # -------------------------
    location / {
        proxy_pass http://127.0.0.1:1000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # -------------------------
    # FIXED PANEL PATH
    # -------------------------
    location /subbus {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # -------------------------
    # RANDOM PANEL PATH
    # -------------------------
    location /$PANEL_PATH {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # websocket support (important for x-ui)
    location /$PANEL_PATH/ws {
        proxy_pass http://127.0.0.1:2053/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /subbus/ws {
        proxy_pass http://127.0.0.1:2053/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# -------------------------
# ENABLE SITE
# -------------------------
ln -sf /etc/nginx/sites-available/xui.conf /etc/nginx/sites-enabled/xui.conf

# remove default site (IMPORTANT)
rm -f /etc/nginx/sites-enabled/default

# -------------------------
# TEST + RESTART
# -------------------------
nginx -t
systemctl restart nginx

# -------------------------
# FIREWALL (optional safe)
# -------------------------
ufw allow 80 || true
ufw allow 443 || true

# -------------------------
# RESULT
# -------------------------
echo "====================================="
echo "        DONE"
echo "====================================="
echo "MAIN SITE:"
echo "https://$DOMAIN/"
echo ""
echo "PANEL (fixed):"
echo "https://$DOMAIN/subbus"
echo ""
echo "PANEL (random):"
echo "https://$DOMAIN/$PANEL_PATH"
echo ""
echo "IMPORTANT:"
echo "- 3x-ui must be running on 127.0.0.1:2053"
echo "- Your site must be on 127.0.0.1:1000"
echo "====================================="
