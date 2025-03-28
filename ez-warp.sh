#!/bin/bash
set -e

# UI Enhancements
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

show_header() {
    clear
    echo -e "${BLUE}${BOLD}=============================================${NC}"
    echo -e "${BLUE}${BOLD}       WireGuard WARP Installation Script      ${NC}"
    echo -e "${BLUE}${BOLD}=============================================${NC}\n"
}

show_progress() {
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$1${NC}"
}

show_success() {
    echo -e "${GREEN}${BOLD}✓ Success:${NC} $1\n"
}

show_warning() {
    echo -e "${YELLOW}${BOLD}! Warning:${NC} $1\n"
}

show_error() {
    echo -e "${RED}${BOLD}✗ Error:${NC} $1\n" >&2
}

# Necessary functions 
architecture() {
    case "$(uname -m)" in
        'i386' | 'i686') arch='386' ;;
        'x86_64') arch='amd64' ;;
        'armv5tel') arch='armv5' ;;
        'armv6l') arch='armv6' ;;
        'armv7' | 'armv7l') arch='armv7' ;;
        'aarch64') arch='arm64' ;;
        'mips64el') arch='mips64le_softfloat' ;;
        'mips64') arch='mips64_softfloat' ;;
        'mipsel') arch='mipsle_softfloat' ;;
        'mips') arch='mips_softfloat' ;;
        's390x') arch='s390x' ;;
        *) show_error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac
    echo "$arch"
}

# Initial checks
show_header
if [ "$(id -u)" -ne 0 ]; then
    show_error "This script requires root privileges. Please run using:${NC}\n\n  ${BOLD}sudo $0${NC}"
    exit 1
fi

# Check existing installation
if [ -f /etc/wireguard/warp.conf ]; then
    show_warning "WARP is already installed!"
    echo -e "${YELLOW}Please choose an option:${NC}"
    echo -e "  1) Fully uninstall WARP and related packages"
    echo -e "  2) Exit installation"
    
    while true; do
        read -rp $'\e[33mYour choice (1-2): \e[0m' choice
        case $choice in
            1)
                show_progress "Starting uninstallation process..."
                systemctl disable --now wg-quick@warp &> /dev/null || true
                rm -rf /etc/wireguard wgcf-account.toml /usr/bin/wgcf
                
                ubuntu_major_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2 | cut -d'.' -f1)
                if [[ "$ubuntu_major_version" == "24" ]]; then
                    apt-get purge -y wireguard openresolv net-tools iproute2 dnsutils
                else
                    apt-get purge -y wireguard-tools openresolv net-tools iproute2 dnsutils
                fi
                
                apt-get autoremove -y
                show_success "Uninstallation completed successfully!"
                exit 0
                ;;
            2)
                show_success "Exiting installation script"
                exit 0
                ;;
            *)
                show_error "Invalid option. Please enter 1 or 2."
                continue
                ;;
        esac
    done
fi

# Installation process
show_progress "Starting WARP installation..."
show_progress "Updating system packages..."
apt --fix-broken install -y
apt update && apt upgrade -y

show_progress "Installing required dependencies..."
apt install -y openresolv net-tools iproute2 dnsutils

ubuntu_major_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2 | cut -d'.' -f1)
if [[ "$ubuntu_major_version" == "24" ]]; then
    apt install -y wireguard
else
    apt install -y wireguard-tools
fi

systemctl enable --now systemd-resolved.service

# Verify installations
declare -A commands=(
    ["wg-quick"]="WireGuard"
    ["resolvconf"]="OpenResolv"
)

for cmd in "${!commands[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        show_error "Failed to install ${commands[$cmd]} components"
        exit 1
    fi
done

# Architecture detection
arch=$(architecture) || exit 1
show_success "Detected architecture: ${BOLD}$arch${NC}"

# Download wgcf
show_progress "Fetching latest WGCF release..."
release_json=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest)
download_url=$(echo "$release_json" | grep "browser_download_url" | grep "wgcf_.*_linux_${arch}" | head -n 1 | cut -d '"' -f4)

if [ -z "$download_url" ]; then
    show_error "Could not find compatible build for your architecture"
    exit 1
fi

show_progress "Downloading WGCF..."
wget -q --show-progress -O /usr/bin/wgcf "$download_url"
chmod +x /usr/bin/wgcf
show_success "WGCF downloaded successfully"

# Cleanup previous installations
rm -rf wgcf-account.toml /etc/wireguard/warp.conf &> /dev/null

# Account registration
clear
show_header
show_progress "Creating new WARP account..."
yes | wgcf register

# License key handling
read -rp $'\e[33mDo you want to use a custom license key? [y/N]: \e[0m' response
if [[ $response =~ ^[Yy]$ ]]; then
    read -rp $'\e[33mEnter your WARP license key: \e[0m' LICENSE_KEY
    show_progress "Applying license key..."
    sed -i "s/license_key = '.*'/license_key = '$LICENSE_KEY'/" wgcf-account.toml
    wgcf update
fi

# Profile generation
show_progress "Generating WireGuard configuration..."
wgcf generate

# Configuration adjustments
CONFIG_FILE="./wgcf-profile.conf"
show_progress "Optimizing network settings..."
sed -i 's/^DNS = 1\.1\.1\.1/DNS = 8\.8\.8\.8,8\.8\.4\.4,1\.1\.1\.1,9\.9\.9\.10/g' ${CONFIG_FILE}
sed -i 's/^DNS = 2620:fe\:\:10,2001\:4860\:4860\:\:8888,2606\:4700\:4700\:\:1111/DNS = 8\.8\.8\.8,1\.1\.1\.1,9\.9\.9\.10/g' ${CONFIG_FILE}
sed -i '/\[Peer\]/i Table = off' "$CONFIG_FILE"

ipv6_rout=$(awk -F '[ ,]+' '/Address/ {split($4, a, "/"); print a[1]}' "$CONFIG_FILE")
sed -i "6a \\
PostUp = ip -6 rule add from $ipv6_rout lookup 100\\
PostUp = ip -6 route add default dev warp table 100\\
PreDown = ip -6 rule del from $ipv6_rout lookup 100\\
PreDown = ip -6 route del default dev warp table 100" "$CONFIG_FILE"
sudo sed -i '/\[Peer\]/a PersistentKeepalive = 25' /etc/wireguard/warp.conf

# Final setup
mv "$CONFIG_FILE" /etc/wireguard/warp.conf

show_progress "Configuring DNS resolvers..."
sed -i '/nameserver 2a00\:1098\:2b\:\:1/d; /nameserver 8\.8/d; /nameserver 9\.9/d; /nameserver 1\.1\.1\.1/d' /etc/resolv.conf
{
    echo "nameserver 1.1.1.1"
    echo "nameserver 8.8.8.8"
} >> /etc/resolv.conf
echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
show_progress "Starting WARP service..."
systemctl disable --now wg-quick@warp &> /dev/null || true
systemctl enable --now wg-quick@warp

# Completion message
clear
show_header
echo -e "${GREEN}${BOLD}✔ Installation Completed Successfully!${NC}"
echo -e "\n${BOLD}Service Status:${NC}"
systemctl status wg-quick@warp --no-pager
echo -e "\n${YELLOW}Note:${NC} You can manage WARP using:"
echo -e "  ${BOLD}systemctl [start|stop|restart] wg-quick@warp${NC}"
echo -e "\n${GREEN}${BOLD}Enjoy secure browsing with WARP! 🚀${NC}\n"
