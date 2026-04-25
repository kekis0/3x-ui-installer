#!/bin/bash

set -e

echo "====================================="
echo "  3x-ui + SSL + Nginx Fallback Setup"
echo "====================================="

export DEBIAN_FRONTEND=noninteractive

# -------------------------
# UPDATE
# -------------------------
apt update
apt full-upgrade -y
apt install -y curl openssl ca-certificates nginx

apt autoremove -y
apt clean

# -------------------------
# INPUT
# -------------------------
read -p "Enter your domain (example.com): " DOMAIN
read -p "Enter DNSExit API key: " APIKEY

# -------------------------
# SSL DIRS
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
# FETCH SSL
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

chmod +x /opt/ssl/*.sh

# -------------------------
# GENERATE SSL
# -------------------------
echo "[+] Generating SSL..."
/opt/ssl/fetch-cert.sh
/opt/ssl/build-fullchain.sh

# -------------------------
# CRON
# -------------------------
(crontab -l 2>/dev/null; echo "0 4 1 * * /opt/ssl/fetch-cert.sh && /opt/ssl/build-fullchain.sh && systemctl restart xray") | crontab -

# -------------------------
# NGINX SETUP (FAKE SITE)
# -------------------------
echo "[+] Configuring Nginx..."

cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 127.0.0.1:8080;
    server_name $DOMAIN;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# -------------------------
# FAKE WEBSITE
# -------------------------
mkdir -p /var/www/html

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>$DOMAIN</title>
</head>
<body>
  <h1>Welcome</h1>
  <p>Website is under maintenance.</p>
</body>
</html>
EOF

systemctl restart nginx

# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "====================================="
echo " INSTALL COMPLETE"
echo "====================================="
echo ""
echo "SSL:"
echo "/etc/ssl/dnsexit/fullchain.crt"
echo "/etc/ssl/dnsexit/key.key"
echo ""
echo "Nginx fallback:"
echo "127.0.0.1:8080"
echo ""
echo "NEXT STEP: configure inbound in 3x-ui"
