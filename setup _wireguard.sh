#!/bin/bash
# Fully automated WireGuard setup script with Pi-hole adblocker
# Ubuntu/Debian
# Features: 2 clients, QR codes, firewall, auto updates, IST timezone, adblocking

# Set timezone to IST
echo "Setting system timezone to IST..."
sudo timedatectl set-timezone Asia/Kolkata

# Ask for server IPv4
read -p "Enter your server's public IPv4: " SERVER_IPV4

# Update system and install packages
echo "Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y wireguard qrencode iptables curl unattended-upgrades curl sudo lsb-release

# Enable automatic security updates
echo "Configuring automatic security updates..."
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# Optimize network
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr

# Persist sysctl settings
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
EOF'
sudo sysctl -p

# Generate server and client keys
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

CLIENT1_PRIV=$(wg genkey)
CLIENT1_PUB=$(echo "$CLIENT1_PRIV" | wg pubkey)

CLIENT2_PRIV=$(wg genkey)
CLIENT2_PUB=$(echo "$CLIENT2_PRIV" | wg pubkey)

# Create server config
sudo bash -c "cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
PrivateKey = $SERVER_PRIV
Address = 10.0.0.1/24
ListenPort = 51820

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; \
         iptables -A FORWARD -o wg0 -j ACCEPT; \
         iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; \
         iptables -A INPUT -i wg0 -p udp --dport 53 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; \
           iptables -D INPUT -i wg0 -p udp --dport 53 -j ACCEPT

[Peer]
PublicKey = $CLIENT1_PUB
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25

[Peer]
PublicKey = $CLIENT2_PUB
AllowedIPs = 10.0.0.3/32
PersistentKeepalive = 25
EOL"

# Create client configs
mkdir -p ~/wireguard_clients

CLIENT1_CONF=~/wireguard_clients/client1.conf
cat > "$CLIENT1_CONF" <<EOL
[Interface]
PrivateKey = $CLIENT1_PRIV
Address = 10.0.0.2/32
DNS = 10.0.0.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IPV4:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL

CLIENT2_CONF=~/wireguard_clients/client2.conf
cat > "$CLIENT2_CONF" <<EOL
[Interface]
PrivateKey = $CLIENT2_PRIV
Address = 10.0.0.3/32
DNS = 10.0.0.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IPV4:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL

# Configure firewall
sudo bash -c 'cat > /etc/iptables.rules <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp --dport 51820 -j ACCEPT
-A FORWARD -i wg0 -j ACCEPT
-A FORWARD -o wg0 -j ACCEPT

COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth0 -j MASQUERADE
COMMIT
EOF'

sudo bash -c 'cat > /etc/network/if-pre-up.d/iptables <<EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF'
sudo chmod +x /etc/network/if-pre-up.d/iptables
sudo iptables-restore < /etc/iptables.rules

# Start WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Install Pi-hole for ad-blocking
echo "Installing Pi-hole for ad-blocking..."
curl -sSL https://install.pi-hole.net | bash

# Set Pi-hole DNS for WireGuard clients (already set to 10.0.0.1)

# Generate QR codes
echo "QR code for client1:"
qrencode -t ansiutf8 < "$CLIENT1_CONF"
echo "QR code for client2:"
qrencode -t ansiutf8 < "$CLIENT2_CONF"

# Setup unattended upgrades cron
if ! crontab -l | grep -q unattended-upgrades; then
  (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/apt update && /usr/bin/apt -y upgrade") | crontab -
fi

echo "Setup complete! WireGuard with 2 clients, firewall, Pi-hole adblocker, automatic updates, and IST timezone are all configured."
echo "Client configs saved at: $CLIENT1_CONF and $CLIENT2_CONF"
