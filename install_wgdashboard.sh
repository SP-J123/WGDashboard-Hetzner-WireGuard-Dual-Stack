#!/usr/bin/env bash
#
# ==============================================================================
# WGDashboard Comprehensive Interactive Installation Script
# Features:
# - Interactive Wizard for Domain & SSL Setup
# - True Dual-Stack IPv4 & IPv6 Support (Native Host Routing Hetzner-Style /120)
# - Automated Docker, Docker-Compose & Caddy Installation
# - VPS Kernel & Network Optimization (BBR, Buffers, Conntrack)
# - Custom Hetzner DNS Configuration
# - Auto-Injects Client IPv6 Support (::/0) & MTU tuning
# ==============================================================================

# Exit on any error, undefined variable, or pipe failure
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
  log_error "Please run this script as root or with sudo."
  exit 1
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}  Welcome to WGDashboard Interactive Setup!         ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""
echo "Please enter the Domain Name you pointed to this VPS:"
echo "(e.g., vpn.yourdomain.com - or leave blank to use your IP Address)"
read -p "Domain: " YOUR_DOMAIN

echo ""
echo "Please enter your Email Address for the FREE Let's Encrypt SSL Certificate:"
echo "(You can leave this blank if you did not enter a Domain)"
read -p "Email: " YOUR_EMAIL

if [ -n "$YOUR_DOMAIN" ] && [ -z "$YOUR_EMAIL" ]; then
    log_warn "You entered a domain but no email. SSL may not generate properly."
    echo ""
    read -p "Press enter to continue anyway, or Ctrl+C to cancel."
fi

echo -e "\n${GREEN}[+] Applying Configuration...${NC}"

# Define constants
INSTALL_DIR="/opt/wgdashboard"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
SYSCTL_CONF="/etc/sysctl.d/99-networking-tuning.conf"
DNS_STRING="185.12.64.1, 185.12.64.2, 2a01:4ff:ff00::add:1, 2a01:4ff:ff00::add:2"

# ==============================================================================
# STEP 1: VPS KERNEL & NETWORK OPTIMIZATION
# ==============================================================================
log_info "Applying high-performance kernel network optimizations..."

cat > "$SYSCTL_CONF" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.netdev_max_backlog=65535
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
net.netfilter.nf_conntrack_max=2000000
net.netfilter.nf_conntrack_tcp_timeout_established=86400
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.eth0.accept_ra=2
EOF

sysctl --system >/dev/null 2>&1
log_success "Kernel optimizations applied."

# ==============================================================================
# STEP 2: AUTO-DETECT IPs & CARVE SERVER IPV6 /120 SUBNET
# ==============================================================================
log_info "Detecting public IP addresses..."
PUBLIC_IPV4=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com || true)
if [ -z "$PUBLIC_IPV4" ]; then
    PUBLIC_IPV4=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}' | tr -d '\n' || true)
fi

IPV6_RAW=$(ip -6 addr show eth0 scope global | grep inet6 | head -n 1 | awk '{print $2}')
if [ -z "$IPV6_RAW" ]; then
  log_error "No global IPv6 address detected on eth0! Your VPS may not have IPv6 enabled."
  exit 1
fi

# Extract the base /64 prefix block (e.g., 2a01:4f8:1c19:73ff::/64)
IPV6_PREFIX=$(echo "$IPV6_RAW" | cut -d':' -f1-4)
# Hetzner Routing Magic: Carve a dedicated /120 subnet inside our block to prevent eth0 conflicts
# We append :ac1e: out of thin air, making it 2a01:4f8:1c19:73ff:ac1e::/120
WG_IPV6_BASE="${IPV6_PREFIX}:ac1e"
WG_IPV6_SERVER="${WG_IPV6_BASE}::1/120"
WG_IPV6_PEER="${WG_IPV6_BASE}::2/128"

log_success "Detected Public IPv4: ${PUBLIC_IPV4:-<None>}"
log_success "Calculated Isolated wg0 IPv6 Subnet: ${WG_IPV6_BASE}::/120"

ENDPOINT_IP="${YOUR_DOMAIN}"
if [ -z "$ENDPOINT_IP" ]; then
   ENDPOINT_IP="${PUBLIC_IPV4}"
fi

# ==============================================================================
# STEP 3: INSTALL DEPENDENCIES (Docker & Caddy)
# ==============================================================================
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
fi

if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
fi

if [ -n "$YOUR_DOMAIN" ]; then
    if ! command -v caddy &> /dev/null; then
        log_info "Installing Caddy for SSL..."
        apt-get update -qq
        apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update -qq && apt-get install -y -qq caddy
        systemctl enable caddy
    fi

    log_info "Configuring Caddy for ${YOUR_DOMAIN}..."
    cat > "/etc/caddy/Caddyfile" <<EOF
${YOUR_DOMAIN} {
    tls ${YOUR_EMAIL}
    reverse_proxy localhost:10086
}
EOF
    systemctl restart caddy
fi

# ==============================================================================
# STEP 4: GENERATE WGDASHBOARD DOCKER-COMPOSE (HOST NETWORKING)
# ==============================================================================
# We do not use ip6tables masquerading or proxying! Linux natively routes /120
mkdir -p "$INSTALL_DIR"

cat > "$COMPOSE_FILE" <<EOF
services:
  wgdashboard:
    image: 'donaldzou/wgdashboard:latest'
    restart: unless-stopped
    network_mode: host
    environment:
      - SERVICE_FQDN_WGDASHBOARD_10086
      - tz=Asia/Kolkata
      - "global_dns=$DNS_STRING"
      - "peer_global_dns=$DNS_STRING"
      - public_ip=$ENDPOINT_IP
      - 'wg0_post_up=iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -A FORWARD -o wg0 -j ACCEPT'
      - 'wg0_post_down=iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -D FORWARD -o wg0 -j ACCEPT'
    volumes:
      - 'wg-conf:/etc/wireguard'
      - 'wg-data:/opt/wireguarddashboard/src/db'
    cap_add:
      - NET_ADMIN
      - SYS_MODULE

volumes:
  wg-conf: null
  wg-data: null
EOF

# ==============================================================================
# STEP 5: DEPLOY CONTAINER AND FIX PEER IPs
# ==============================================================================
log_info "Starting WGDashboard Stack..."
cd "$INSTALL_DIR"

docker compose down 2>/dev/null || true
docker compose up -d

log_info "Waiting 10 seconds for initial wg0 config to generate..."
sleep 10

log_info "Injecting True IPv6 Routing & MTU Limitations..."
# We append MTU=1300 to match Hetzner's successful fragmentation avoidance
docker exec wgdashboard-wgdashboard-1 bash -c "
sed -i '/MTU/d' /etc/wireguard/wg0.conf
sed -i '/ListenPort/a MTU = 1300' /etc/wireguard/wg0.conf
sed -i 's|Address = 10.0.0.1/24|Address = 10.0.0.1/24, ${WG_IPV6_SERVER}|g' /etc/wireguard/wg0.conf
sed -i 's|AllowedIPs = 10.0.0.2/32|AllowedIPs = 10.0.0.2/32, ${WG_IPV6_PEER}, ::/0|g' /etc/wireguard/wg0.conf
sed -i 's/^DNS = .*/DNS = $DNS_STRING/g' /etc/wireguard/wg0.conf
"

docker restart wgdashboard-wgdashboard-1

echo -e "\n${CYAN}====================================================${NC}"
log_success " SETUP COMPLETE!"
if [ -n "$YOUR_DOMAIN" ]; then
    echo -e " Your dashboard is live at: https://${YOUR_DOMAIN}"
else
    echo -e " Your dashboard is live at: http://${PUBLIC_IPV4}:10086"
fi
echo -e " Your Wireguard Client Endpoint: ${ENDPOINT_IP}:51820"
echo -e " Your IPv4 IP: $PUBLIC_IPV4"
echo -e " Your True IPv6 Subnet: ${WG_IPV6_BASE}::/120"
echo -e "${CYAN}====================================================${NC}"
