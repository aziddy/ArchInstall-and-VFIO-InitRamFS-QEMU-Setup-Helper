
## **Most Likely Causes & Solutions**

### **1. NVIDIA Driver Crashes in VM (Most Common)**

Complete VM freezes during gaming often indicate GPU driver crashes. Here's how to fix:

**Switch to NVIDIA Studio Drivers:**
- Download **NVIDIA Studio Drivers** (not Game Ready) in Windows VM
- Studio drivers are more stable for virtualization environments
- Completely uninstall existing drivers with **DDU (Display Driver Uninstaller)** first

**Windows VM Registry Attempt Fix:**
Windows Registry Editor Version 5.00

```bash
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers]
"TdrLevel"=dword:00000000
"TdrDelay"=dword:00000000
```
This disables Windows GPU timeout detection that can cause crashes

### **2. VFIO Reset Issues**
Your GPU might not be properly resetting between VM sessions:
```bash
# Add GPU reset quirks to GRUB
sudo nano /etc/default/grub

# Modify your GRUB line to include reset quirks:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt vfio-pci.ids=10de:xxxx,10de:yyyy vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1"

sudo grub-mkconfig -o /boot/grub/grub.cfg
```


> [!INFO] New GRUB Parameters
> - `vfio_iommu_type1.allow_unsafe_interrupts=1`'
> 	- Tells `VFIO` driver to handle interrupts in a "unsafe" way
> 	- Many GPUs don't fully support interrupt remapping
> 		- This param allows to be accessed directly without the proxy 
> 	- "Unsafe" meaning it could allow malicious programs in a VM to inject interrupts into the host
> 	- Intense video games generate many interrupts
> 	- When ***Not Enabled*** ❌
> 		1. Game loads textures → GPU sends interrupts → VFIO blocks them → GPU driver crashes
> 		2. Game tries to render frame → GPU is in confused state → Complete freeze
> - `kvm.ignore_msrs=1`
> 	- Tells KVM Hypervisor to ignore Model-Specific Registers (MSRs) that it doesn't recognize 
> 	- When ***Enabled*** ✅
> 		- Game accesses MSRs → KVM ignores unknown ones → Game continues normally
> 	- When ***Not*** ❌
> 		- Game starts → Accesses CPU performance MSRs → KVM blocks them → Game thinks CPU is broken

**Add vendor-reset module:**
```bash
# Install vendor-reset for better GPU resets
yay -S vendor-reset-dkms-git

# Add to initramfs
sudo nano /etc/mkinitcpio.conf
# Add vendor-reset to MODULES line:
MODULES=(vfio_pci vfio vfio_iommu_type1 vendor-reset)

sudo mkinitcpio -P
```

> [!INFO] ***Vendor-Reset*** Module Addition
> The vendor-reset module:
> - Hooks into the kernel's PCI reset mechanism using ftrace
> - Provides vendor-specific reset procedures for supported GPUs (mainly AMD GPUs like RX 470/480/570/580/590)
> - Ensures clean GPU state between VM sessions
> - Prevents GPU driver crashes in subsequent VM boots

### 3. \[AMD Only\] Enable `topoext`, `constant_tsc` & `nonstop_tsc
[Looking Glass Link - topoext AMD CPU Feature Flag](https://looking-glass.io/docs/B7-rc1/install_libvirt/#additional-tuning)

##### 3.A) Check if your AMD CPU has the Feature Flags
Run
```bash
lscpu | grep topoext
lscpu | grep constant_tsc
lscpu | grep nonstop_tsc
```
If you see the flags in the list, your CPU supports them

##### 3.B) Enable CPU Feature Flag on VM
VM's libvert XML
```xml
<cpu mode='host-passthrough'>
  <feature policy='require' name='topoext'/>
  <feature policy='require' name='constant_tsc'/>
  <feature policy='require' name='nonstop_tsc'/>
</cpu>
```

> [!INFO] Whats `topoext` Feature Flag?
> 
> - **CPU feature flag `topoext`**
> 	- This is an AMD-specific CPU flag called _Topology Extensions_. It lets the operating system inside the VM know how the CPU cores are arranged (which ones are real cores and which ones are hyper-threaded siblings)
> 	- Can hurt performance or scheduling efficiency if not enabled


> [!INFO] Whats `constant_tsc`& `nonstop_tsc` Feature Flags?
> ### nonstop_tsc
> Makes sure your **Time Stamp Counter** keeps running when your CPU is asleep
> 
> ### constant_tsc
> Regular TSC (Time Stamp Counter):
> ```bash
 > CPU @ 4.9GHz → TSC counts at 4.9 billion cycles/second
> CPU @ 3.8GHz → TSC counts at 3.8 billion cycles/second
> CPU @ 1.2GHz → TSC counts at 1.2 billion cycles/second
> ```
> Constant TSC:
> ```bash
> CPU @ 4.9GHz → TSC counts at FIXED 100MHz rate
> CPU @ 3.8GHz → TSC counts at FIXED 100MHz rate  
> CPU @ 1.2GHz → TSC counts at FIXED 100MHz rate
> ```
> Solution: TSC rate never changes = consistent timing always
> 
> **✅ With `constant_tsc` (You Have This!):**
> - **Thermal throttling happens** → Game timing stays perfect
> - **CPU drops from 4.9GHz to 2.0GHz** → TSC still ticks at same rate
> - **Game physics/networking** → No timing glitches during throttling
> - **VM stability** → Much less likely to crash from thermal events
> 
>  **❌ Without `constant_tsc`:**
> - **Thermal throttling happens** → TSC suddenly runs slower
> - **Game thinks time slowed down 2.5x** → Physics breaks, network timeouts
> - **VM crashes** → DirectX/Vulkan drivers get confused by time jumps

### 4. **Blacklist Nvidia Drivers from Running on Host**

If you run the command
```bash
sudo dmesg -w # wathc mode / continuous 
```
and see a lot of 
```bash
[ 3641.293448] nvidia-nvlink: Unregistered Nvlink Core, major device number 511
[ 3641.841143] nvidia-nvlink: Nvlink Core is being initialized, major device number 511
[ 3641.841149] NVRM: GPU 0000:01:00.0 is already bound to vfio-pci.
[ 3641.845221] NVRM: The NVIDIA probe routine was not called for 1 device(s).
[ 3641.845223] NVRM: This can occur when another driver was loaded and 
               NVRM: obtained ownership of the NVIDIA device(s).
[ 3641.845224] NVRM: Try unloading the conflicting kernel module (and/or
               NVRM: reconfigure your kernel without the conflicting
               NVRM: driver(s)), then try loading the NVIDIA kernel module
               NVRM: again.
[ 3641.845224] NVRM: No NVIDIA devices probed.
```

Your Linux Host **NVIDIA Drivers** are still trying to bind to the **dGPU**, but **VFIO-PCI** is already binded. 

But still the Linux Host **NVIDIA Drivers** making failed probe attempts to the **dGPU** to find if its binded, can cause errors like
- **Leave hardware registers in unexpected states**
- **Interfere with VFIO's device reset capabilities**
- **Create lingering power management conflicts**
- **Affect GPU's ability to handle VM resets properly**

##### 4.A) Create NVIDIA Blacklist Configuration

So we need to **blacklist** (stop from running) the **NVIDIA Drivers** on the **Linux Host** 
```bash
sudo nano /etc/modprobe.d/blacklist-nvidia.conf
```

Add the following content:
```bash
# Blacklist NVIDIA drivers
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm

# Blacklist nouveau driver
blacklist nouveau

# Prevent these modules from loading
install nvidia /bin/false
install nvidia_drm /bin/false
install nvidia_modeset /bin/false
install nouveau /bin/false
```


> [!INTO] Difference between `blacklist` & `install` lines in modprobe.d conf file 
> - **blacklist**
> 	- Basically saying to not automatically load in this module yourself
> 	- ⚠️ But other modules that did auto load in can call other modules to load in, bypassing this
> - **install \<MODULE\> /bin/false**
> 	- Hijacks module mechanism
> 	- Where `/bin/false` tells to immediate exit with no failure status
> 	- ✅ Other modules calling a module with this on it will not load now



##### 4.B) Update Your Existing VFIO Configuration

Edit your existing VFIO config:
```bash
sudo nano /etc/modprobe.d/vfio.conf
```

Ensure it looks like this (update with your actual GPU IDs):
```bash
# Bind the Nvidia GPU to VFIO driver
options vfio-pci ids=aaaa:xxxx,aaaa:yyyy

# Prevent loading of conflicting drivers
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset  
blacklist nvidia_uvm
blacklist nouveau

# Ensure VFIO loads before conflicting drivers
softdep nvidia pre: vfio-pci
softdep nvidia_drm pre: vfio-pci
softdep nouveau pre: vfio-pci
```
##### 4.C) Update initramfs and GRUB
```bash
# Rebuild initramfs with new configuration
sudo mkinitcpio -P

# Update GRUB configuration
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Reboot to apply changes
sudo reboot
```

##### 4.D) Verify After Reboot
```bash
# Should show NO nvidia modules loaded
lsmod | grep nvidia

# Should show GPU bound to vfio-pci  
lspci -nnk | grep -A3 -B1 NVIDIA

# Check for the error messages are gone
sudo dmesg | grep -i nvidia
```

### 5. **CPU Pinning**

##### Option 5.A) SMT/Hypertheading OFF for 7800X3D - 6 Cores Pinned
In `<VM-NAME>.xml`
```xml
  <!-- Total 6 vCPUs for the VM (cores 2-7) -->
<vcpu placement='static'>6</vcpu>
<cputune>
	<!-- Pin guest vCPUs to cores 2-7 -->
	<vcpupin vcpu='0' cpuset='2'/>
	<vcpupin vcpu='1' cpuset='3'/>
	<vcpupin vcpu='2' cpuset='4'/>
	<vcpupin vcpu='3' cpuset='5'/>
	<vcpupin vcpu='4' cpuset='6'/>
	<vcpupin vcpu='5' cpuset='7'/>
	
	<!-- Pin QEMU emulator threads to cores 0-1 -->
	<emulatorpin cpuset='0-1'/>
</cputune>
```

**Layout**
- Core 0: Host OS + QEMU emulator
- Core 1: Host OS + QEMU emulator
- Core 2: VM vCPU 0
- Core 3: VM vCPU 1
- Core 4: VM vCPU 2
- Core 5: VM vCPU 3
- Core 6: VM vCPU 4
- Core 7: VM vCPU 5

**GRUB** Changes/Additions:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="... isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7"
```

> [!INFO] What each CPU Pinning **GRUB** Parameter does?
> - `isolcpus=2-7`
> 	- **Removes** CPU cores `2-7` from the **Linux kernel scheduler's general pool**
> 	- Prevents random host processes from interrupting VM cores
> 	- Reduces CPU cache pollution on VM cores
> 	- **Linux Scheduler:** *"I only have 2 CPUs (0-1) to run processes on"* 
> 		- System processes ONLY run on cores 0-1
> 		- Cores 2-7 are "hidden" from general scheduling
> 		- Only explicitly pinned processes (your VM) can use cores 2-7
> - `nohz_full=2-7`
> 	- **Disables periodic timer ticks** on CPU cores `2-7` when they're running user tasks
> 	- Eliminates 1000 interruptions per second on VM cores
> 	- Critical for low-latency applications (gaming, real-time)
> 	- **Normal behavior:**
> 		- Every 1ms (1000Hz): TICK! 
> 			- → Kernel interrupts EVERY core for housekeeping
> 			- → Breaks VM execution for timer processing
> 			- → Causes jitter and performance loss
> 	- **With `nohz_full=2-7`:**
> 		- Cores 0-1: Still get timer ticks (host needs them)
> 		- Cores 2-7: NO periodic ticks when running VM
> 			- → VM can run uninterrupted for longer periods
> 			- → Much lower latency and jitter
> - `rcu_nocbs=2-7`
> 	- **Moves RCU (Read-Copy-Update) callback processing** OFF cores `2-7`
> 	- Eliminates 1000 interruptions per second on VM cores
> 	- Critical for low-latency applications (gaming, real-time)
> 	- **Normal behavior:**
> 		- RCU System: "Time to clean up old data structures!"
> 			- → Interrupts ALL cores including VM cores
> 			- → VM execution paused for RCU housekeeping
> 	- **With `rcu_nocbs=2-7`:**
> 		- RCU callbacks for cores `2-7` → Processed on cores `0-1`
> 			- → VM cores never interrupted for RCU work
> 			- → Host cores handle the cleanup burden

##### Option 5.B) SMT/Hypertheading ON for 7800X3D - 6 Cores + Threads Pinned

WARNING: 
- Check X3D Turbo is disabled & SMT is on Auto in UEFI/BIOS
- Check with linux commands that SMT/Hyperthreading is present before setting VM's XML and GRUB

In `<VM-NAME>.xml`
```xml
<!-- Total 12 vCPUs for the VM (6 physical cores × 2 threads) -->
<vcpu placement='static'>12</vcpu>

<cputune>
	<!-- Pin guest vCPUs to physical cores 2-7 (both threads of each core) -->
	<vcpupin vcpu='0' cpuset='2'/>   <!-- Core 2, Thread 1 -->
	<vcpupin vcpu='1' cpuset='10'/>  <!-- Core 2, Thread 2 -->
	<vcpupin vcpu='2' cpuset='3'/>   <!-- Core 3, Thread 1 -->
	<vcpupin vcpu='3' cpuset='11'/>  <!-- Core 3, Thread 2 -->
	<vcpupin vcpu='4' cpuset='4'/>   <!-- Core 4, Thread 1 -->
	<vcpupin vcpu='5' cpuset='12'/>  <!-- Core 4, Thread 2 -->
	<vcpupin vcpu='6' cpuset='5'/>   <!-- Core 5, Thread 1 -->
	<vcpupin vcpu='7' cpuset='13'/>  <!-- Core 5, Thread 2 -->
	<vcpupin vcpu='8' cpuset='6'/>   <!-- Core 6, Thread 1 -->
	<vcpupin vcpu='9' cpuset='14'/>  <!-- Core 6, Thread 2 -->
	<vcpupin vcpu='10' cpuset='7'/>  <!-- Core 7, Thread 1 -->
	<vcpupin vcpu='11' cpuset='15'/> <!-- Core 7, Thread 2 -->
	
	<!-- Pin QEMU emulator threads to physical cores 0-1 -->
	<emulatorpin cpuset='0-1,8-9'/>
</cputune>
```

**Layout**
- Physical Core 0: Threads 0,8   → Host OS + QEMU emulator
- Physical Core 1: Threads 1,9   → Host OS + QEMU emulator
- Physical Core 2: Threads 2,10  → VM vCPUs 0,1
- Physical Core 3: Threads 3,11  → VM vCPUs 2,3  
- Physical Core 4: Threads 4,12  → VM vCPUs 4,5
- Physical Core 5: Threads 5,13  → VM vCPUs 6,7
- Physical Core 6: Threads 6,14  → VM vCPUs 8,9
- Physical Core 7: Threads 7,15  → VM vCPUs 10,11

**GRUB** Changes/Additions:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="... isolcpus=2-7,10-15 nohz_full=2-7,10-15 rcu_nocbs=2-7,10-15"
```



### 6. **Disable Memballoon**
[Looking Glass Link - Disable Memballon](https://looking-glass.io/docs/B7-rc1/install_libvirt/#memballoon)

You can edit the VM's XML configuration:
```bash
# Edit your VM configuration
sudo virsh edit <VM_NAME>
```

Find the `<memballoon>` section and change it to:
```xml
<memballoon model="none"/>
```

> [!INFO] Whats `memballoon`?
> The VirtIO memballoon device enables the host to dynamically reclaim memory from your VM by growing the balloon inside the guest, reserving reclaimed memory. Libvirt adds this device to guests by default.
> 
> However, this device causes 
> - Major performance issues with **VFIO passthrough** setups
> 	- Like passing in a **dGPU**
> - Can cause crashing if **CPU** or **VFIO Passthrough Device** *(ex dGPU)* tries to access memory that `memballon` takes away from RAM


### **7. Power Management Issues**
Aggressive power management can cause instability:
```bash
# Disable power management features that cause crashes
sudo nano /etc/default/grub

# Add these parameters:
GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm=off processor.max_cstate=1 intel_idle.max_cstate=0"

sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### 8. **MSI Interrupt Conflicts**
Fix interrupt handling issues:
```bash
# Create or edit VFIO interrupt configuration
sudo nano /etc/modprobe.d/vfio.conf

# Add these lines to your existing vfio.conf:
options vfio-pci ids=10de:xxxx,10de:yyyy
options vfio enable_unsafe_noiommu_mode=1
options kvm ignore_msrs=1
```

### **9. CPU Governor & Scheduling**
Set performance governor during gaming:
```bash
# Create a script to set performance mode
sudo nano /usr/local/bin/vm-performance.sh
```

```bash
#!/bin/bash
echo "Setting CPU governor to performance"
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

echo "Setting VM CPU affinity"
# Replace with your VM process ID
VM_PID=$(pgrep -f "qemu.*win11")  # Replace win11 with your VM name
if [ ! -z "$VM_PID" ]; then
    taskset -cp 4-7 $VM_PID  # Pin to specific cores
fi
```

```bash
chmod +x /usr/local/bin/vm-performance.sh
```

### **10. Configure Hugh Pages**
Reserve memory for your VM:
```bash
# Reserve 8192 huge pages (16GB worth of 2MB pages)
# 8192*2MB = 16384MB or 16GB
# 14336*2MB = 28672MB or 28GB
echo 'vm.nr_hugepages = 8192' | sudo tee -a /etc/sysctl.conf

# Allow the libvirt group (ID 78) to access huge pages
# warning: libvirt group id might be different, check your system first
echo 'vm.hugetlb_shm_group = 78' | sudo tee -a /etc/sysctl.conf

# Apply the settings immediately
sudo sysctl -p

# Configure your VM to actually use these huge pages
sudo virt-xml <VM_NAME> --edit --memory hugepages=yes
```

Configure VM to use hugepages:
```bash
sudo virt-xml <VM_NAME> --edit --memory hugepages=yes
```

> [!WARNING] Hugh Pages are not Universally Accessible 
> - After reboot (or applying with `sudo sysctl -p`), your system will **set aside 16 GB of RAM** (in this example) for HugePages
> - That memory is no longer available for normal applications—it can only be used by processes that explicitly request HugePages


> [!INFO] What are ***Hugepages*** ?
> - **Standard**:
> 	- Linux typically uses 4KB memory pages by default
> 	- When an application needs large amounts of memory, it gets many small 4KB pages
> 	- This creates overhead because the CPU has to manage many page table entries
> - **Huge pages:**
> 	- Much larger memory pages (typically 2MB or 1GB instead of 4KB)
> 	- Significantly reduces the number of page table entries needed
> 	- Improves memory access performance and reduces CPU overhead
> 	- **Why it bigger pages are better**
> 		1. **Better Performance**: Your VM can access memory more efficiently
> 		2. **Reduced CPU Overhead:** Fewer page table lookups = less CPU time spent on memory management
> 		3. **Prevents Crashes:** More stable memory allocation under heavy workloads (like gaming)
> 		4. **Memory Dedication:** Reserves physical memory specifically for your VM, preventing host system from using it

### **11. Complete VM Configuration Review**
Export your current VM config and check for issues:
```bash
# Export current VM configuration
sudo virsh dumpxml <VM_NAME> > ~/vm-config.xml

# Check for potential issues
grep -E "model type|emulator|iothreads|vcpu" ~/vm-config.xml
```