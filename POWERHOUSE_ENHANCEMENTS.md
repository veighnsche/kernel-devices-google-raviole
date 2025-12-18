# Powerhouse Enhancements Documentation

**TEAM_038 Container-First Kernel Enhancements**

This document consolidates the rationale and usage documentation for kernel
configurations added to support container-first operation on the Pixel 6
Powerhouse build.

The actual kconfig options are in `powerhouse_enhancements.fragment`.

---

## Table of Contents

1. [LSM Stacking (Letter C)](#lsm-stacking-letter-c)
2. [Cgroup v2 Complete (Letter E)](#cgroup-v2-complete-letter-e)
3. [Memory Bias (Letter F)](#memory-bias-letter-f)
4. [FS Encryption + Integrity (Letter G)](#fs-encryption--integrity-letter-g)
5. [Audit + Forensics (Letter H)](#audit--forensics-letter-h)
6. [Network Fairness (Letter I)](#network-fairness-letter-i)

---

## LSM Stacking (Letter C)

### Purpose

Enable multiple LSMs to provide layered security:
- **SELinux**: Mandatory access control (Android + Gentoo policy)
- **Landlock**: Unprivileged process sandboxing (container-friendly)
- **Yama**: Ptrace restrictions (prevent container escape via ptrace)
- **BPF LSM**: Programmable security hooks (advanced use cases)

### LSM Order

```
landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf
```

- **Landlock first**: allows unprivileged sandboxing before other checks
- **SELinux near end**: acts as final MAC enforcement
- **BPF last**: allows programmatic policy on top of everything

### Configs Added

| Config | Purpose |
|--------|---------|
| `CONFIG_SECURITY_LANDLOCK=y` | Unprivileged process sandboxing |
| `CONFIG_SECURITY_PATH=y` | Required by Landlock |
| `CONFIG_SECURITY_YAMA=y` | Ptrace restrictions |
| `CONFIG_BPF_LSM=y` | Programmable security hooks |
| `CONFIG_SECURITY_LOCKDOWN_LSM=y` | Kernel lockdown |
| `CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y` | Early lockdown init |
| `CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y` | Default to no lockdown (configurable via boot param) |

### Usage

**Landlock** - Any process can sandbox itself:
```c
// See landlock(7) man page
struct landlock_ruleset_attr ruleset_attr = { .handled_access_fs = ... };
int ruleset_fd = landlock_create_ruleset(&ruleset_attr, sizeof(ruleset_attr), 0);
landlock_restrict_self(ruleset_fd, 0);
```

**Yama** - Ptrace scope levels:
- 0 = classic (any process can ptrace)
- 1 = restricted (only descendants)
- 2 = admin-only
- 3 = no-attach

Set via: `echo 1 > /proc/sys/kernel/yama/ptrace_scope`

---

## Cgroup v2 Complete (Letter E)

### Purpose

Make container resource limits enforceable:
- Tier-0 services keep resources under pressure
- Android can't accidentally bully container workloads
- Per-service CPU/memory/IO policies are possible

### Configs Added

| Config | Purpose |
|--------|---------|
| `CONFIG_CFS_BANDWIDTH=y` | cpu.max hard limits in cgroup v2 |
| `CONFIG_RT_GROUP_SCHED=y` | RT task scheduling per cgroup |
| `CONFIG_BLK_CGROUP_IOLATENCY=y` | io.latency QoS guarantees |
| `CONFIG_CGROUP_PERF=y` | Per-cgroup performance monitoring |
| `CONFIG_CGROUP_MISC=y` | Future-proofing for new resource types |

### Bias Wiring Structure

```
/sys/fs/cgroup/
├── system.slice/           (Android system services)
├── gentoo.slice/           (Gentoo LXC container)
│   ├── tier0.slice/        (Vault, Vaultwarden, Podman)
│   │   ├── cpu.weight = 200
│   │   ├── cpu.max = 80% (via CFS_BANDWIDTH)
│   │   ├── memory.min = 512M (protected)
│   │   └── io.latency = target=10ms
│   ├── tier1.slice/        (Forgejo, Registry)
│   │   ├── cpu.weight = 100
│   │   └── memory.min = 256M
│   └── tier2.slice/        (Ephemeral workloads)
│       ├── cpu.weight = 50
│       └── memory.max = 1G (hard limit)
└── user.slice/             (Android user apps)
```

*Numeric values are examples. Actual tuning happens at runtime.*

---

## Memory Bias (Letter F)

### Purpose

Make memory pressure behave like a server, not a phone:
- Tier-0 Gentoo services and container working sets stay resident
- Android churn gets reclaimed first
- Container bias is enforceable via memcg

### Configs Added

| Config | Purpose |
|--------|---------|
| `CONFIG_LRU_GEN_STATS=y` | MGLRU statistics for debugging reclaim |
| `CONFIG_DAMON_LRU_SORT=y` | Sort LRU lists based on access patterns |

### Already Enabled (in gentoo_lxc_powerhouse.fragment)

- `CONFIG_LRU_GEN=y` - MGLRU for efficient page aging
- `CONFIG_WORKING_SET_PROTECTION=y` - le9uo working set protection
- `CONFIG_DAMON_RECLAIM=y` - Proactive reclaim
- `CONFIG_MEMCG=y` - Per-cgroup memory accounting

### Tier-0 Survival Mechanisms

1. **memory.min** (cgroup v2): Hard reservation, cannot be reclaimed
   ```bash
   echo 512M > /sys/fs/cgroup/gentoo/tier0/memory.min
   ```

2. **memory.low** (cgroup v2): Soft protection, reclaim only when desperate
   ```bash
   echo 1G > /sys/fs/cgroup/gentoo/tier0/memory.low
   ```

3. **memory.oom.group**: Group OOM killing control
   ```bash
   echo 0 > /sys/fs/cgroup/gentoo/tier0/memory.oom.group
   ```

4. **le9uo working set protection**:
   - `vm.anon_min_ratio`: protect anonymous pages (default 20%)
   - `vm.clean_min_ratio`: protect clean file pages (default 20%)

5. **MGLRU generations**: Better page aging, reduces thrashing

6. **DAMON reclaim**: Proactive reclaim based on access patterns
   - Config: `/sys/kernel/mm/damon/admin/kdamonds/*/`

---

## FS Encryption + Integrity (Letter G)

### Purpose

Make "production" mean trustworthy at rest:
- Tier-0 service data can be encrypted independently of Android
- Immutable artifacts can be integrity-locked
- Containers can use encryption without special privilege hacks

### Configs Added

| Config | Purpose |
|--------|---------|
| `CONFIG_ENCRYPTED_KEYS=y` | Wrap keys with master key for secure storage |
| `CONFIG_PERSISTENT_KEYRINGS=y` | Keys survive process exit (needed for containers) |
| `CONFIG_BIG_KEYS=y` | Store large keys in tmpfs |
| `CONFIG_KEYS_REQUEST_CACHE=y` | Improve key lookup performance |
| `CONFIG_CRYPTO_ADIANTUM=y` | Low-power encryption for Tier-2 |

### Already Enabled

- `CONFIG_FS_ENCRYPTION=y` - Core fscrypt
- `CONFIG_FS_VERITY=y` - Core fs-verity

### Container fscrypt Usage

```bash
# Add key to user keyring
fscryptctl add_key /path/to/encrypted/dir

# Set encryption policy on directory
fscryptctl set_policy <key_identifier> /path/to/encrypted/dir

# Files created in directory are automatically encrypted
```

### Container fs-verity Usage

```bash
# Enable verity on a file (makes it immutable)
fsverity enable /path/to/file

# Measure file (get digest)
fsverity measure /path/to/file

# Any modification to the file will cause read errors (EIO)
```

### What This Enables for Tier-0

- Vault data directory: fscrypt-encrypted
- Vaultwarden database: fscrypt-encrypted
- Critical binaries: fs-verity protected
- Config files: fs-verity protected

---

## Audit + Forensics (Letter H)

### Purpose

Make the system explain itself under attack or failure:
- Policy denials (SELinux, seccomp)
- Privilege changes
- Sensitive syscalls
- Container boundary violations

**No additional kconfig needed** - all audit infrastructure already enabled.

### Already Enabled

- `CONFIG_AUDIT=y` - Audit infrastructure
- `CONFIG_AUDITSYSCALL=y` - Syscall auditing
- `CONFIG_TRACING=y` - Core tracing
- `CONFIG_FTRACE=y` - Function trace framework
- `CONFIG_KPROBES=y` / `CONFIG_UPROBES=y` - Kernel/user probes
- `CONFIG_TASKSTATS=y` - Task statistics

### Event Visibility Matrix

| Event Type | Source | Log Location |
|------------|--------|--------------|
| SELinux denial (AVC) | audit subsystem | dmesg, /var/log/audit/audit.log |
| Seccomp denial | audit subsystem | dmesg, /var/log/audit/audit.log |
| Process exec/exit | proc connector | netlink, auditd |
| Privilege change | audit subsystem | /var/log/audit/audit.log |
| Namespace creation | audit subsystem | /var/log/audit/audit.log |
| File access | audit rules | /var/log/audit/audit.log |

### Logging Options

**Option 1: auditd (recommended)**
```bash
emerge sys-process/audit
systemctl enable auditd
# Logs: /var/log/audit/audit.log
# Query: ausearch, aureport
```

**Option 2: dmesg/journald (minimal)**
```bash
dmesg | grep audit
journalctl -k | grep audit
```

**Option 3: BPF-based (advanced)**
- Use bpftrace or custom BPF programs

### Example Audit Rules

```bash
# Watch Tier-0 config files
auditctl -w /gentoo/etc/vault/ -p wa -k tier0_config

# Watch privilege escalation syscalls
auditctl -a always,exit -F arch=b64 -S setuid -S setgid -k priv_esc

# Watch namespace creation
auditctl -a always,exit -F arch=b64 -S clone -S unshare -S setns -k namespace

# Watch container runtime
auditctl -w /usr/bin/podman -p x -k container_runtime
auditctl -w /usr/bin/lxc-start -p x -k container_runtime
```

---

## Network Fairness (Letter I)

### Purpose

Ensure Tier-0 Gentoo services remain reachable and responsive:
- Network namespace isolation for containers
- Traffic scheduling fairness per workload class
- Protection from noisy neighbors

**No additional kconfig needed** - all network infrastructure already enabled.

### Already Enabled

**Network Namespaces:**
- `CONFIG_NET_NS=y`
- `CONFIG_NETFILTER=y`
- `CONFIG_NF_CONNTRACK=y`
- `CONFIG_NF_CONNTRACK_ZONES=y`

**Traffic Schedulers:**
- `CONFIG_NET_SCH_HTB=y` - Hierarchical Token Bucket
- `CONFIG_NET_SCH_FQ_CODEL=y` - Fair Queue + CoDel
- `CONFIG_NET_SCH_CAKE=y` - CAKE (advanced AQM)
- `CONFIG_NET_SCH_FQ=y` - Fair Queue

**Traffic Classifiers:**
- `CONFIG_NET_CLS_FW=y` - Firewall mark classifier
- `CONFIG_NET_CLS_BPF=y` - BPF classifier

**Cgroup Network Priority:**
- `CONFIG_CGROUP_NET_PRIO=y`

### Network Fairness Architecture

**Per-Namespace Isolation:**
- Each LXC/Podman container gets its own netns
- Conntrack is per-netns (no cross-contamination)
- nftables rules are per-netns

**Traffic Scheduling (qdisc):**
- FQ_CODEL: Fair queuing with controlled delay (default)
- CAKE: Common Applications Kept Enhanced (advanced)
- HTB: Hierarchical Token Bucket (bandwidth allocation)

### Example tc Setup for Tier-0 Priority

```bash
# Create HTB root qdisc
tc qdisc add dev eth0 root handle 1: htb default 30

# High priority class for Tier-0 (80% guaranteed, can burst to 100%)
tc class add dev eth0 parent 1: classid 1:10 htb rate 800mbit ceil 1000mbit prio 0

# Normal priority for Tier-1
tc class add dev eth0 parent 1: classid 1:20 htb rate 150mbit ceil 500mbit prio 1

# Best effort for Tier-2 and Android background
tc class add dev eth0 parent 1: classid 1:30 htb rate 50mbit ceil 200mbit prio 2

# Filter by cgroup classid
tc filter add dev eth0 parent 1: protocol ip prio 1 handle 10: cgroup
```

### Conntrack Tuning

```bash
# Recommended for server workload
sysctl -w net.netfilter.nf_conntrack_max=131072
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=3600

# Per-cgroup connection limits via nftables
nft add rule inet filter input ct count over 1000 reject
```

---

## History

- **TEAM_038**: Original implementation across 6 separate fragment files
- **TEAM_039**: Consolidated into single fragment + this documentation
