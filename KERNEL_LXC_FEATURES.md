# Kernel LXC/Container Features for Pixel 6 (Raviole)

## Overview

This kernel includes comprehensive container support through two kernel fragments:
- `gentoo_lxc_powerhouse.fragment` - Core LXC features
- `lxc_enhanced.fragment` - Advanced networking and container features

## Features Enabled

### Core Container Infrastructure

| Feature | Config | Purpose |
|---------|--------|---------|
| Namespaces | `CONFIG_*_NS=y` | Process, network, user, IPC, UTS, time isolation |
| Cgroups v1/v2 | `CONFIG_CGROUPS=y` | Resource limits (CPU, memory, I/O) |
| Checkpoint/Restore | `CONFIG_CHECKPOINT_RESTORE=y` | Container migration, CRIU support |
| Seccomp | `CONFIG_SECCOMP_FILTER=y` | System call filtering |

### Container Networking

| Feature | Config | Purpose |
|---------|--------|---------|
| veth pairs | `CONFIG_VETH=y` | Container-to-host virtual ethernet |
| Bridge | `CONFIG_BRIDGE=y` | Container network bridge |
| TUN/TAP | `CONFIG_TUN=y` | VPN and tunnel support |
| MACVLAN | `CONFIG_MACVLAN=y` | Direct host network passthrough |
| IPVLAN | `CONFIG_IPVLAN=y` | L2/L3 container networking |
| VXLAN | `CONFIG_VXLAN=y` | Overlay networks (Docker Swarm, K8s) |
| Wireguard | `CONFIG_WIREGUARD=y` | Secure tunnel for containers |

### Netfilter / NAT

| Feature | Config | Purpose |
|---------|--------|---------|
| Bridge netfilter | `CONFIG_BRIDGE_NETFILTER=y` | iptables on bridge traffic |
| IPv4 NAT | `CONFIG_IP_NF_NAT=y` | Container IPv4 masquerading |
| IPv6 NAT | `CONFIG_IP6_NF_NAT=y` | Container IPv6 masquerading |
| MASQUERADE | `CONFIG_*_TARGET_MASQUERADE=y` | NAT for container egress |
| nftables | `CONFIG_NF_TABLES=y` | Modern firewall rules |

### Filesystems

| Feature | Config | Purpose |
|---------|--------|---------|
| OverlayFS | `CONFIG_OVERLAY_FS=y` | Layered container filesystems |
| SquashFS | `CONFIG_SQUASHFS=y` | Read-only container images |
| FUSE | `CONFIG_FUSE_FS=y` | User-space filesystems |
| tmpfs (extended) | `CONFIG_TMPFS_XATTR=y` | Extended attributes support |

### Device Management

| Feature | Config | Purpose |
|---------|--------|---------|
| devtmpfs | `CONFIG_DEVTMPFS=y` | Automatic /dev population |
| cgroup devices | `CONFIG_CGROUP_DEVICE=y` | Device access control |

## Network Modes Supported

### 1. NAT Mode (Default)
Container shares host IP via masquerading.
```
Host (wlan0) <--bridge--> Container (eth0)
              NAT/MASQUERADE
```

### 2. Bridge Mode
Containers get IPs from same network as host (requires bridge setup).
```
Host <--br0--> Container1
          +--> Container2
```

### 3. MACVLAN Mode (requires CONFIG_MACVLAN)
Container gets its own MAC address on host network.
```
wlan0 (host) <--macvlan--> eth0 (container, own MAC)
```

### 4. Host Mode
Container shares host network namespace directly.
```
lxc.net.0.type = none
```

## Usage

### Building the Kernel
```bash
cd /home/vince/android/android-gs-raviole-6.1-android16
./private/devices/google/raviole/build_raviole.sh
```

### Verifying Features
```bash
# On device
zcat /proc/config.gz | grep -E 'CONFIG_(BRIDGE|VETH|MACVLAN|NAMESPACES)'

# Check namespaces
ls -la /proc/self/ns/

# Check cgroups
cat /proc/cgroups
```

### Setting Up Bridge Networking (for container own-IP)
```bash
# Create bridge
ip link add br0 type bridge
ip link set br0 up

# Add WiFi to bridge (may require driver support)
ip link set wlan0 master br0

# In container config
# lxc.net.0.type = veth
# lxc.net.0.link = br0
# lxc.net.0.flags = up
```

## Known Limitations

1. **WiFi Bridging**: Android's wlan0 driver may not support bridging mode. MACVLAN or NAT are alternatives.

2. **SELinux**: May block some container operations. Use `setenforce 0` or configure policies.

3. **nosuid on /data**: Addressed by mounting container rootfs from a loop device with suid enabled.

## Files

| File | Description |
|------|-------------|
| `gentoo_lxc_powerhouse.fragment` | Core LXC kernel config |
| `lxc_enhanced.fragment` | Advanced networking features |
| `KERNEL_LXC_FEATURES.md` | This documentation |

## TEAM_001 Notes

Enhanced kernel fragment created to address gaps between the original LXC fragment and what was actually running. Key additions:
- `CONFIG_BRIDGE_NETFILTER=y` - Required for Docker/LXC networking
- `CONFIG_CHECKPOINT_RESTORE=y` - Enables CRIU for container migration
- `CONFIG_MACVLAN=y` / `CONFIG_IPVLAN=y` - Advanced networking modes
- `CONFIG_IP6_NF_NAT=y` - IPv6 NAT for dual-stack containers
- `CONFIG_DEVTMPFS=y` - Proper device management
- `CONFIG_SQUASHFS=y` - Read-only container images
