#!/bin/bash
set -e

#necessary functions 
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
    *) echo "error: The architecture is not supported."; return 1 ;;
  esac
  echo "$arch"
}

#check user status
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run it as root."
    exit 1
fi
# Check if Warp is already installed by testing for the existence of the config file
if [ -f /etc/wireguard/warp.conf ]; then
    echo "Warp is already installed."
    echo "Please select an option:"
    echo "1) Fully Uninstall Warp, Wireguard and related packages"
    echo "2) Exit"
    read -rp "Enter your choice (1 or 2): " choice
    case $choice in
      1)
        echo "Fully uninstalling Warp and associated packages..."
        # Stop and disable the Warp interface
        systemctl disable --now wg-quick@warp &> /dev/null || true
        # Remove configuration files and binaries
        rm -rf /etc/wireguard
        rm -rf wgcf-account.toml
        rm -f /usr/bin/wgcf

        # Fully remove Wireguard and related packages.
        # Note: Depending on your system, the package names might differ.
        ubuntu_major_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2 | cut -d'.' -f1)
        if [[ "$ubuntu_major_version" == "24" ]]; then
          apt-get purge -y wireguard openresolv net-tools iproute2 dnsutils
        else
          apt-get purge -y wireguard-tools openresolv net-tools iproute2 dnsutils
        fi
        apt-get autoremove -y

        echo "Uninstallation complete."
        exit 0
        ;;
      2)
        echo "Exiting..."
        exit 1
        ;;
      *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
    esac
fi
#installing necessary packages
apt --fix-broken install -y
apt update && apt upgrade -y
apt install -y openresolv
apt install -y net-tools iproute2 dnsutils
ubuntu_major_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2 | cut -d'.' -f1)
if [[ "$ubuntu_major_version" == "24" ]]; then
  sudo apt install -y wireguard
else
  apt install -y wireguard-tools
fi
systemctl enable systemd-resolved.service
systemctl start systemd-resolved.service

#checking packages
if ! command -v wg-quick &> /dev/null
then
    echo "something went wrong with wireguard package installation"
    exit 1
fi
if ! command -v resolvconf &> /dev/null
then
    echo "something went wrong with resolvconf package installation"
    exit 1
fi


# downloading assets dynamically using the GitHub API
arch=$(architecture)
echo "Detected architecture: $arch"

# Fetch the latest release JSON from GitHub
release_json=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest)

download_url=$(echo "$release_json" | grep "browser_download_url" | grep "wgcf_.*_linux_${arch}" | head -n 1 | cut -d '"' -f4)

if [ -z "$download_url" ]; then
    echo "Could not find download URL for architecture $arch"
    exit 1
fi

echo "Downloading wgcf from $download_url"
wget -O /usr/bin/wgcf "$download_url"
chmod +x /usr/bin/wgcf


# removing files that might cause problems

rm -rf wgcf-account.toml &> /dev/null || true
rm -rf /etc/wireguard/warp.conf &> /dev/null || true
# main dish
clear
yes | wgcf register
read -rp "Do you want to use your own key? (Y/n): " response
if [[ $response =~ ^[Yy]$ ]]; then
    read -rp "ENTER YOUR LICENSE: " LICENSE_KEY
    sed -i "s/license_key = '.*'/license_key = '$LICENSE_KEY'/" wgcf-account.toml
    wgcf update
fi

wgcf generate

CONFIG_FILE="./wgcf-profile.conf"
sed -i 's/^DNS = 1\.1\.1\.1/DNS = 8\.8\.8\.8,8\.8\.4\.4,1\.1\.1\.1,9\.9\.9\.10/g' ${CONFIG_FILE}
sed -i 's/^DNS = 2620:fe\:\:10,2001\:4860\:4860\:\:8888,2606\:4700\:4700\:\:1111/DNS = 8\.8\.8\.8,1\.1\.1\.1,9\.9\.9\.10/g' ${CONFIG_FILE}
sed -i '/\[Peer\]/i Table = off' "$CONFIG_FILE"
# Extract the IPv6 address from the config
ipv6_rout=$(awk -F '[ ,]+' '/Address/ {split($4, a, "/"); print a[1]}' "$CONFIG_FILE")
sed -i "6a \\
PostUp = ip -6 rule add from $ipv6_rout lookup 100\\
PostUp = ip -6 route add default dev warp table 100\\
PreDown = ip -6 rule del from $ipv6_rout lookup 100\\
PreDown = ip -6 route del default dev warp table 100" "$CONFIG_FILE"
mv "$CONFIG_FILE" /etc/wireguard/warp.conf
sed -i '/nameserver 2a00\:1098\:2b\:\:1/d' /etc/resolv.conf
sed -i '/nameserver 8\.8/d' /etc/resolv.conf
sed -i '/nameserver 9\.9/d' /etc/resolv.conf
sed -i '/nameserver 1\.1\.1\.1/d' /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 9.9.9.10" >> /etc/resolv.conf
systemctl disable --now wg-quick@warp &> /dev/null || true
systemctl enable --now wg-quick@warp

echo "Wireguard warp is up and running"
