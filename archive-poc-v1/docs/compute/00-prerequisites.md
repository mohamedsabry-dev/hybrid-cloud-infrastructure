

# Prerequisites

Before starting the lab environment build, ensure you have the required hardware and software.

---

## Hardware Requirements

* **OS:** Windows 11/10 Pro (Home edition may have limitations)
* **RAM:** 32GB minimum (64GB recommended for running multiple VMs)
* **CPU:** Intel VT-x or AMD-V capable processor (8 cores/16 threads minimum)
* **Storage:** 500GB+ available (SSD strongly recommended - NVMe preferred for performance)
* **Network:** LAN/Wi-Fi with static IP capability (required for stable bridge networking)

---

## Required Software Downloads

* **Hypervisor:** [VMware Workstation Pro](https://knowledge.broadcom.com/external/article/344595/downloading-and-installing-vmware-workst.html)
* **ESXi ISO:** [VMware ESXi 8.0.3](https://knowledge.broadcom.com/external/article/399823/vmware-esxi-80-update-3e-now-available-a.html)
* **vCenter ISO:** [VMware vCenter 8.0.3](https://knowledge.broadcom.com/external/article/387785/download-vcenter-server-patches-and-isos.html)

> ** Planning Note:** Create a local Low-Level Design (LLD) file to track IPs, credentials, and resource assignments. **Never upload files containing passwords to this repository.**

> ** Why these versions?** ESXi 8.0.3 and vCenter 8.0.3 are tested stable versions that work well on VMware Workstation without licensing headaches. Avoid mixing versions between ESXi and vCenter.

---

## Host Resource Verification

Run the following PowerShell commands to verify physical resources meet requirements.

### Check RAM
```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object @{Name="TotalRAM_GB";Expression={[math]::round($_.TotalPhysicalMemory/1GB,2)}}
```

**Expected Output:**
```
TotalRAM_GB
-----------
63.84
```
> If you see less than 32GB, you'll struggle running ESXi + multiple VMs. Consider upgrading or reducing VM count.

### Check CPU
```powershell
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
```

**Expected Output:**
```
Name                                     NumberOfCores NumberOfLogicalProcessors
----                                     ------------- -------------------------
Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz             6                        12
```
> You need hardware virtualization support (VT-x/AMD-V). If `NumberOfLogicalProcessors` is less than 8, performance will suffer.

### Check Storage
```powershell
Get-PSDrive -PSProvider FileSystem | Select Name, Used, Free, @{Name="Free_GB";Expression={[math]::round($_.Free/1GB,2)}}
```

**Expected Output:**
```
Name     Used        Free Free_GB
----     ----        ---- -------
C    275166343168 512000000000  476.84
```
> Look for drives with 500GB+ free space. This is where you'll store VMDKs. SSD/NVMe makes a huge difference in VM performance.

---

## Next Steps

Once you've verified your hardware meets requirements and downloaded the necessary software:

**→ Continue to:** [02-windows-host-configuration.md](02-windows-host-configuration.md)
