# Easy WARP
this script installs and configurates Cloudflare WARP with Wireguard core on linux based devices

## Features

- Support for variety of cpu architectures
- Can add custom license key (WARP+ support)
- better and more efficent warp configuration compared to warp configuration via proxy (SOCKS5 port: 40000) 
- uses less resources and has more speed

## Install

**run the script as root**
1. run this command:
```bash
bash <(curl -Ls https://raw.githubusercontent.com/mikeesierrah/ez-warp/main/ez-warp.sh)
```
2. check if WARP interface is running properly via running 'wg' command
```bash
wg
```

## Custom license
script asks for your custom license key , you can use it to enable WARP+.
**if you deny the script automatically installs WARP free**

## Tip
if you are using xray you should add this configuration to your 'outband': 
```json
    {
      "tag": "warp",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "ForceIPv6v4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "interface": "warp"
        }
      }
    }
```
Add this to routing in rules section
```json
      {
          "domain": [
              "geosite:openai"
          ],
          "outboundTag": "warp"
      }
```
| domainStrategy | [test-ipv6.com](https://test-ipv6.com/) | [bgp.he.net](https://bgp.he.net/) | [chat.openai.com](https://chat.openai.com/cdn-cgi/trace) |
| :--- | :---: | :---: | :---: |
| ForceIPv6v4 | IPv6v4 Address | IPv6 Address | IPv6 Address |
| ForceIPv6 | Website Not Accessible | IPv6 Address | IPv6 Address |
| ForceIPv4v6 | IPv6v4 Address **2** | IPv4 Address | IPv4 Address |
| ForceIPv4 | IPv4 Address | IPv4 Address | IPv4 Address |
| ForceIP | IPv6v4 Address **3** | IPv6 Address | IPv6 Address |

## DONATION
if you want to appreciate me donate 5$ to a person in need
