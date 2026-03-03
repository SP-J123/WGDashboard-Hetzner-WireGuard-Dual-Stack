<div align="center">

# 🌐 WGDashboard Hetzner Deployment: Ultimate Dual-Stack IPv6 WireGuard Setup 🌐

[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-success)](#)
[![IPv6 Native](https://img.shields.io/badge/IPv6-Native%20%2F120%20Routing-blue)](#)
[![BBR Optimized](https://img.shields.io/badge/Kernel-BBR%20Optimized-orange)](#)

*The definitive, SEO-optimized, production-ready bash script and cloud-init installer to deploy [WGDashboard](https://github.com/donaldzou/WGDashboard) (WireGuard Web UI) on Hetzner Cloud VPS infrastructure with true Native Dual-Stack (IPv4 & IPv6) routing, BBR optimization, and automatic HTTPS via Caddy.*

---

</div>

## ✨ Key Features

This deployment comes with two primary scripts: `install_wgdashboard.sh` and `cloud-config-interactive.yaml`. Both automatically apply the following enterprise-grade optimizations:

### 🚀 Network Performance & Kernel Tuning

> [!TIP]
> This script automatically forces maximum throughput by overriding the legacy default Linux network stack specifically for high-bandwidth VPS connections.

| Feature | Description |
| :--- | :--- |
| **BBR Congestion Control** | Automatically enables Google's BBR TCP congestion algorithm and `fq` queuing discipline to maximize throughput and minimize latency over long distances. |
| **Maximized Socket Buffers** | Increases the Kernel's read/write TCP window sizes (`rmem_max`/`wmem_max` to 67MB) to handle gigabit burst traffic without dropping packets. |
| **Aggressive Conntrack** | Expands the Netfilter connection tracking table (`nf_conntrack_max` to `2,000,000`) allowing the VPN to process millions of concurrent NAT connections flawlessly. |
| **MTU Optimization** | Intelligently drops the default WireGuard tunnel MTU to `1300`, preventing packet fragmentation across Hetzner's datacenters. |


### 🛡️ Native True Dual-Stack (IPv4 & IPv6)

> [!NOTE]
> Docker's default IPv6 implementation relies on experimental bridge networks and NAT masquerading, which frequently drops UDP packets. This deployment bypasses it entirely.

*   **Hetzner Subnet Carving:** Automatically mathematically detects your server's assigned physical `/64` IPv6 block and explicitly carves out an isolated `/120` subnet strictly for WireGuard clients.
*   **Zero-NAT IPv6 Forwarding:** Because of the `/120` allocation, Linux natively routes IPv6 traffic directly from the Hetzner gateway into your WireGuard tunnel without requiring any buggy `ip6tables` NAT masking.
*   **Host Networking (`network_mode: host`):** WGDashboard connects directly to your physical network adapters for bare-metal WireGuard performance.


### 🔒 Built-in Reverse Proxy & SSL Setup
*   **Interactive Wizard Setup:** Upon first execution, natively asks for your Domain Name and Email Address to configure your UI securely.
*   **Automated Caddy Deployment:** Installs Caddy, requests Free Let's Encrypt Wildcard Certificates, and securely reverse-proxies WGDashboard (Port `10086`) directly to `https://vpn.yourdomain.com`.

---

## 🛠️ Installation Methods

You have two options to deploy this application on a fresh Debian/Ubuntu VPS:

### Option A: Manual Bash Script

Great for standard Ubuntu/Debian servers that are already running.

1. SSH into your server as `root`.
2. Download or upload the `install_wgdashboard.sh` file to your server.
3. Make it executable: 
   ```bash
   chmod +x install_wgdashboard.sh
   ```
4. Run the installer to begin the wizard: 
   ```bash
   ./install_wgdashboard.sh
   ```
5. Follow the interactive wizard connecting your Domain!

### Option B: Hetzner Cloud-Init (Recommended)

You can build the entire server automatically during VPS creation.

1. Create a new Server in your Hetzner Cloud Console.
2. Scroll down to the **"Cloud config" / "User data"** section.
3. Paste the exact contents of `cloud-config-interactive.yaml` into the text box.
4. Deploy the server.
5. Once booted, simply SSH into your server (`ssh root@ip`). The Interactive Wizard will launch automatically, instantly completing the setup!

---

## 🚦 CRITICAL CONFIGURATION: Activating Client IPv6

> [!WARNING]  
> **Mandatory Setting for IPv6 Peer Routing!**  
> By default, WGDashboard creates peer configurations that route only IPv4 traffic over the tunnel. If you want a peer to truly utilize these IPv6 optimizations, you must manually update their `AllowedIPs` setting within the Web UI.

1. Log in to your deployed WGDashboard.
2. Go to **Peers** -> **Add Peer** (or Edit an existing one).
3. In the configuration popup, find the `AllowedIPs` box.
4. By default, it says `0.0.0.0/0`. 
5. You must change it to EXACTLY this: 

   ```ini
   0.0.0.0/0, ::/0
   ```

Changing this setting ensures that your laptop or mobile phone knows to send *both* the IPv4 Universe (`0.0.0.0/0`) AND the IPv6 Universe (`::/0`) deeply into the VPN tunnel. 

*(**Pro-Tip:** If you apply this formatting inside your WGDashboard **Global Settings**, all newly created peers will instantly support true Dual-Stack routing from that point onward!)*

---

## 🤝 Acknowledgements & Credits

*   ❤️ **[donaldzou/WGDashboard](https://github.com/donaldzou/WGDashboard)**: Endless thanks to Donald Zou for creating the underlying intuitive, powerful, and gorgeous WireGuard Web Interface that powers this logic.
*   ☁️ **[Hetzner Cloud](https://www.hetzner.com/)**: For their exceptional data-center design and providing massive default `/64` IPv6 blocks allowing us to perform this complex subnet carving.

