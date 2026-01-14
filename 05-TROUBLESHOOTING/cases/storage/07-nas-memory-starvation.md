━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #07: NAS VM MEMORY STARVATION & I/O STORM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Storage / Resource Allocation / Performance
Severity: CRITICAL
Environment: NAS VM (NFS Server)
Impact: Complete environment instability, kernel soft lockups

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: Complete Environment Instability with Kernel Soft Lockups

Configuration Changes That Triggered the Issue:
  ├── Reduced NAS VM RAM: 5GB → 4GB
  ├── Increased VM count: 6 VMs → 12 VMs
  ├── New VMs allocated minimal RAM: 1GB - 1.5GB each
  └── All VMs using NAS NFS storage for OS and data disks

Symptoms:
  Linux kernel soft lockup warnings showing CPUs stuck for 31-47 seconds:
    • CPU#1: Stuck for 47s in systemd-userwor (systemd user worker)
    • CPU#0: Stuck for 47s in systemd-logind
    • CPU#2: Stuck for 31s in sssd_be (SSSD backend)

Environment Impact:
  ├── All VMs experiencing severe I/O delays
  ├── Services failing to start or respond
  ├── SSH sessions hanging during file operations
  ├── Systemd services timing out
  └── Overall system unusable

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The Cascade Failure Chain:

1. NAS VM Memory Constraint
   ├── NAS VM reduced to 4GB RAM
   ├── Must serve NFS storage for 12 client VMs
   ├── Insufficient RAM for filesystem metadata caching
   └── Linux kernel can't cache inodes/dentries effectively

2. Low-Memory Client VMs
   ├── New VMs allocated only 1GB - 1.5GB RAM
   ├── Insufficient memory to run services + cache
   ├── Heavy reliance on disk I/O for virtual memory
   └── Constant NFS requests for swap and cache operations

3. NFS Cache Starvation
   ├── NFS server needs to cache:
   │     • Inode metadata for all 12 VMs
   │     • Directory entries (dentries)
   │     • File attribute cache
   │     • Read-ahead buffers
   ├── With only 4GB RAM:
   │     • Cache constantly evicted
   │     • Every request → disk fetch
   │     • No cache hits → maximum latency
   └── Result: Every NFS operation goes to physical disk

4. I/O Queue Saturation
   ├── 12 VMs simultaneously requesting I/O from NAS
   ├── NAS VM disk queue saturated
   ├── IOPS overwhelmed by metadata requests
   ├── Latency spikes from milliseconds → seconds
   └── Processes waiting on I/O hang for 30+ seconds

5. Kernel Soft Lockup
   ├── Critical system processes stuck waiting for I/O:
   │     • systemd-userwor (user session management)
   │     • systemd-logind (login management)
   │     • sssd_be (authentication backend)
   ├── CPU scheduler can't preempt (waiting on I/O completion)
   ├── Watchdog detects CPU stuck > 20 seconds
   └── Kernel reports soft lockup warning

Why This Is a Cascade Failure:
  ├── Low VM RAM → More NFS I/O requests
  ├── Low NAS RAM → No NFS cache → All requests to disk
  ├── High request volume + no cache → I/O saturation
  ├── I/O saturation → Process hangs → Kernel lockups
  └── Kernel lockups → System-wide instability

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TECHNICAL DEEP DIVE: NFS SERVER MEMORY REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NFS Server RAM Usage Breakdown:

1. Base NFS Server Process
   ├── nfsd daemon: ~200MB
   ├── rpc.mountd: ~50MB
   ├── rpc.statd: ~30MB
   └── Total: ~300MB

2. Filesystem Metadata Cache (The Critical Component)
   ├── Inode cache: Stores file metadata
   │     • Each VM: ~100-200MB for OS files
   │     • 12 VMs × 150MB average = 1.8GB
   ├── Dentry cache: Stores directory entries
   │     • Each VM: ~50-100MB for directory structure
   │     • 12 VMs × 75MB average = 900MB
   ├── Page cache: File content caching
   │     • Variable based on workload
   │     • Minimum 1-2GB for reasonable performance
   └── Total metadata cache needs: ~4GB minimum

3. Network Buffers
   ├── TCP buffers for NFS connections
   ├── 12 clients × multiple connections
   └── ~500MB required

4. Operating System Overhead
   ├── Kernel: ~500MB
   ├── System services: ~300MB
   └── Total: ~800MB

Minimum RAM Calculation:
  Base services:        300MB
  Metadata cache:     4,000MB
  Network buffers:      500MB
  OS overhead:          800MB
  Safety margin:      1,400MB
  ━━━━━━━━━━━━━━━━━━━━━━━━━
  TOTAL MINIMUM:      7,000MB (7GB)

  Recommended:        8,000MB (8GB)

Why 4GB Was Catastrophically Insufficient:
  ├── 4GB total RAM
  ├── - 800MB OS overhead
  ├── - 300MB NFS services
  ├── - 500MB network buffers
  └── = 2.4GB remaining for filesystem cache
        (Need 4GB minimum for 12 VMs)

  Result: Cache constantly thrashing, ~0% hit rate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESOLUTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Two-Part Solution:

Part 1: Increase NAS VM Memory
  Action: 4GB → 8GB RAM

  Impact:
    ├── Adequate filesystem cache for 12 VMs
    ├── Kernel can cache inode/dentry metadata
    ├── NFS cache hit ratio: 5% → 90%+
    ├── Disk I/O reduced by ~70%
    └── I/O latency: seconds → milliseconds

  Verification:
    ├── Monitor cache statistics:
    │     └── Command: cat /proc/meminfo | grep -E "Cached|Buffers"
    ├── Check NFS statistics:
    │     └── Command: nfsstat -s
    └── Verify no more soft lockups:
          └── Command: dmesg | grep "soft lockup"

Part 2: Establish Minimum VM RAM Standard
  Action: Set 2GB minimum RAM for all VMs

  Rationale:
    ├── 2GB allows essential services to run in memory
    ├── Reduces reliance on swap/disk cache
    ├── Prevents excessive NFS I/O from memory pressure
    └── Provides buffer for occasional spikes

  Applied To:
    ├── Vault VMs: 1GB → 2GB (3 VMs)
    ├── Grafana: 1.5GB → 2GB
    ├── Ansible: 1.5GB → 2GB
    └── All future VMs: 2GB minimum enforced

Result After Changes:
  ├── No more kernel soft lockup warnings
  ├── NFS I/O latency normalized (< 10ms average)
  ├── All services starting and running normally
  ├── SSH sessions responsive
  └── Environment stable under full workload

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Insights:

1. NFS Server Memory Is Primarily for Caching
   "NFS server RAM is NOT just for the NFS process - it's primarily for
   filesystem caching. When serving storage for multiple VMs, the NAS VM
   needs enough memory to cache metadata (inodes, dentries) for ALL client
   VMs. Starving the NFS server of RAM creates an I/O bottleneck that
   cascades to ALL VMs using that storage."

2. Infrastructure VMs Are Not Negotiable
   ✗ Don't reduce infrastructure VM resources to fit more workload VMs
   ✓ Infrastructure supports everything - must be adequately resourced
   ✓ NAS VM is single point of failure for storage - needs headroom
   ✓ Saving 1GB on NAS breaks 12 VMs worth 26GB total

3. Minimum VM RAM Standards Are Essential
   ✗ 1GB VMs create memory pressure → excessive I/O
   ✓ 2GB minimum allows services to run in memory
   ✓ Reduces NFS I/O pressure across entire environment
   ✓ Small investment with huge stability returns

4. Test Under Realistic Workload
   ✗ Don't assume resource reduction is safe without testing
   ✓ Boot all VMs simultaneously (realistic scenario)
   ✓ Run typical services on all VMs
   ✓ Monitor for kernel warnings and I/O latency
   ✓ Test for sustained period (hours, not minutes)

5. Monitor Infrastructure Health
   ✓ Set up alerts for kernel soft lockup warnings
   ✓ Monitor NFS cache hit ratios (should be >90%)
   ✓ Track I/O latency on NAS VM
   ✓ Alert on memory pressure indicators

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BEST PRACTICES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NFS Server Sizing Formula:
  Base RAM = 2GB (OS + NFS services)
  Per-Client RAM = 0.5GB (metadata cache per VM)

  Total RAM = Base + (Clients × Per-Client)

  Examples:
    • 6 VMs:  2GB + (6 × 0.5GB) = 5GB minimum
    • 12 VMs: 2GB + (12 × 0.5GB) = 8GB minimum
    • 20 VMs: 2GB + (20 × 0.5GB) = 12GB minimum

Minimum VM RAM Standards:
  ✓ All VMs: 2GB absolute minimum
  ✓ Database VMs: 4GB minimum
  ✓ Application servers: 3GB minimum
  ✓ Utility VMs (monitoring, etc.): 2GB minimum

Infrastructure VM Protection:
  ✓ Never reduce infrastructure VM resources to fit workload
  ✓ Infrastructure VMs get first priority on resources
  ✓ NAS, vCenter, PfSense: Non-negotiable resource allocations
  ✓ Test infrastructure changes in isolation first

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  ✓ Calculate NFS server RAM based on client VM count
  ✓ Use sizing formula: Base (2GB) + (0.5GB × clients)
  ✓ Establish and document minimum VM RAM standards
  ✓ Plan for growth: Add 20% buffer to calculations

Deployment:
  ✓ Enforce minimum VM RAM through templates/policies
  ✓ Document resource allocation decisions
  ✓ Test environment stability under full load
  ✓ Verify NFS cache hit ratio >90% before production

Monitoring:
  ✓ Monitor NFS server memory usage:
      └── Command: free -h && cat /proc/meminfo | grep -E "Cached|Buffers"

  ✓ Monitor NFS cache statistics:
      └── Command: nfsstat -m (on clients)

  ✓ Watch for kernel warnings:
      └── Command: dmesg -T | grep -E "lockup|hung_task"

  ✓ Track I/O latency:
      └── Command: iostat -x 1

  ✓ Set up alerts for:
      • Kernel soft lockup warnings
      • NFS cache hit ratio < 85%
      • I/O await time > 50ms
      • Memory usage > 90%

Operational:
  ✓ Test resource changes in staging first
  ✓ Monitor for 24 hours after resource changes
  ✓ Never reduce infrastructure VM resources without testing
  ✓ Keep infrastructure resource decisions documented
  ✓ Regular capacity planning reviews

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Symptom: Kernel Soft Lockup Warnings

Diagnostic Steps:

1. Check kernel messages:
   Command: dmesg -T | tail -100 | grep "lockup"
   Look for: "soft lockup - CPU#X stuck for XXs"

2. Check NFS server memory:
   Command: free -h
   Look for: Available memory < 1GB = problem

3. Check filesystem cache:
   Command: cat /proc/meminfo | grep -E "Cached|Buffers"
   Look for: Cached < 2GB with many clients = insufficient

4. Check NFS client count:
   Command: netstat -an | grep :2049 | grep ESTABLISHED | wc -l
   Compare: Client count vs RAM allocation

5. Check I/O latency:
   Command: iostat -x 1 5
   Look for: await > 50ms = I/O bottleneck

6. Check client VM memory pressure:
   Command (on client): free -h && vmstat 1 5
   Look for: High swap usage, si/so columns active

Resolution Path:
  ├── If NFS server memory < formula minimum → Increase NAS VM RAM
  ├── If client VMs < 2GB RAM → Increase client VM RAM
  ├── If I/O latency high → Check disk performance, consider SSD
  └── If cache thrashing → Reduce client count or increase NFS RAM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • NFS server performance tuning
  • Memory allocation for infrastructure VMs
  • ESXi memory ballooning behavior (Issue #06 - Resource Allocation)
  • Minimum viable VM resource standards

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
