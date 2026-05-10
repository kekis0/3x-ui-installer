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

# OPEN PORT 80
ufw allow 80/tcp

curl -s -H "Content-Type: application/json" \
--data @/etc/dnsexit/cert.json \
$API > /etc/ssl/dnsexit/cert.crt

curl -s -H "Content-Type: application/json" \
--data @/etc/dnsexit/key.json \
$API > /etc/ssl/dnsexit/key.key

chmod 600 /etc/ssl/dnsexit/key.key

# CLOSE PORT 80
ufw delete allow 80/tcp
EOF


# -------------------------
# BUILD FULLCHAIN
# -------------------------
cat > /opt/ssl/build-fullchain.sh <<'EOF'
#!/bin/bash

CERT="/etc/ssl/dnsexit/cert.crt"
CHAIN="/etc/ssl/dnsexit/chain.pem"
FULLCHAIN="/etc/ssl/dnsexit/fullchain.crt"
TEMP="/tmp/cert-clean.pem"

# DOWNLOAD CHAIN
curl -s https://letsencrypt.org/certs/2024/r12.pem -o $CHAIN

# CLEAN CERTIFICATE
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' $CERT > $TEMP

# REBUILD cert.crt WITH CHAIN
cat $TEMP $CHAIN > $CERT

# CREATE FULLCHAIN
cp $CERT $FULLCHAIN

chmod 644 $CERT
chmod 644 $FULLCHAIN

rm -f $TEMP
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
echo " SSL READY"
echo "====================================="
echo " Input certificate path (keywords: .crt / fullchain): /etc/ssl/dnsexit/fullchain.crt
"
echo " Input private key path (keywords: .key / privatekey): /etc/ssl/dnsexit/key.key"
# -------------------------
# INSTALL 3X-UI
# -------------------------
echo "[+] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)


read -p "Enter 3x-ui panel port: " PANEL_PORT


# -------------------------
# UFW FIREWALL
# -------------------------
echo "[+] Configuring firewall..."
ufw allow OpenSSH
ufw allow 443/tcp
ufw allow 2096/tcp
ufw allow ${PANEL_PORT}/tcp

ufw --force enable

# -------------------------
# UFW BEFORE.RULES
# -------------------------
echo "[+] Configuring before.rules..."

cat > /etc/ufw/before.rules <<'EOF'
#
# rules.before
#
# Rules that should be run before the ufw command line added rules. Custom
# rules should be added to one of these chains:
#   ufw-before-input
#   ufw-before-output
#   ufw-before-forward
#

# Don't delete these required lines, otherwise there will be errors
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]
# End required lines


# allow all on loopback
-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-output -o lo -j ACCEPT

# quickly process packets for which we already have a connection
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# drop INVALID packets (logs these in loglevel medium and higher)
-A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# ok icmp codes for INPUT
-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP
-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP
-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP
-A ufw-before-input -p icmp --icmp-type source-quench -j DROP

# ok icmp code for FORWARD
-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP
-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP
-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP
-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP

# allow dhcp client to work
-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT

#
# ufw-not-local
#
-A ufw-before-input -j ufw-not-local

# if LOCAL, RETURN
-A ufw-not-local -m addrtype --dst-type LOCAL -j RETURN

# if MULTICAST, RETURN
-A ufw-not-local -m addrtype --dst-type MULTICAST -j RETURN

# if BROADCAST, RETURN
-A ufw-not-local -m addrtype --dst-type BROADCAST -j RETURN

# all other non-local packets are dropped
-A ufw-not-local -m limit --limit 3/min --limit-burst 10 -j ufw-logging-deny
-A ufw-not-local -j DROP

# allow MULTICAST mDNS for service discovery (be sure the MULTICAST line above
# is uncommented)
-A ufw-before-input -p udp -d 224.0.0.251 --dport 5353 -j ACCEPT

# allow MULTICAST UPnP for service discovery (be sure the MULTICAST line above
# is uncommented)
-A ufw-before-input -p udp -d 239.255.255.250 --dport 1900 -j ACCEPT

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT

EOF

echo "[+] before.rules updated"

ufw disable
ufw enable 


echo "[+] Firewall configured"

# -------------------------
# DAILY REBOOT
# -------------------------
echo "[+] Adding daily reboot..."

(crontab -l 2>/dev/null; echo "0 5 * * * /sbin/reboot") | crontab -

echo "[+] Daily reboot scheduled"
