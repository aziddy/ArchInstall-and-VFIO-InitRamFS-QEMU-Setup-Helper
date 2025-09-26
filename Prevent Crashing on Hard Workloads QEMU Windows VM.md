
## **Most Likely Causes & Solutions**

### **1. NVIDIA Driver Crashes in VM (Most Common)**

Complete VM freezes during gaming often indicate GPU driver crashes. Here's how to fix:

**Switch to NVIDIA Studio Drivers:**
- Download **NVIDIA Studio Drivers** (not Game Ready) in Windows VM
- Studio drivers are more stable for virtualization environments
- Completely uninstall existing drivers with **DDU (Display Driver Uninstaller)** first

**Windows VM Registry Attempt Fix:**
```bash
Windows Registry Editor Version 5.00

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
# Blacklist NVIDIA drivers to prevent conflicts with VFIO passthrough
blacklist nvidia
blacklist nvidia_drm  
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nouveau
```

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



### 5. **Disable Memballoon**
[Looking Glass Link - Disable Memballon](https://looking-glass.io/docs/B7-rc1/install_libvirt/#memballoon)

VM's libvert XML
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


### **6. Power Management Issues**
Aggressive power management can cause instability:
```bash
# Disable power management features that cause crashes
sudo nano /etc/default/grub

# Add these parameters:
GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm=off processor.max_cstate=1 intel_idle.max_cstate=0"

sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### **7. MSI Interrupt Conflicts**
Fix interrupt handling issues:
```bash
# Create VFIO interrupt configuration
sudo nano /etc/modprobe.d/vfio.conf

# Add these lines to your existing vfio.conf:
options vfio-pci ids=10de:xxxx,10de:yyyy
options vfio enable_unsafe_noiommu_mode=1
options kvm ignore_msrs=1
```

### **8. CPU Governor & Scheduling**
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

### **9. Memory Allocation Strategy**
Reserve memory for your VM:
```bash
# Add hugepages for VM memory
echo 'vm.nr_hugepages = 8192' | sudo tee -a /etc/sysctl.conf  # 16GB worth
echo 'vm.hugetlb_shm_group = 78' | sudo tee -a /etc/sysctl.conf  # libvirt group ID

# Apply immediately
sudo sysctl -p
```

Configure VM to use hugepages:
```bash
sudo virt-xml <VM_NAME> --edit --memory hugepages=yes
```

### **10. Complete VM Configuration Review**
Export your current VM config and check for issues:
```bash
# Export current VM configuration
sudo virsh dumpxml <VM_NAME> > ~/vm-config.xml

# Check for potential issues
grep -E "model type|emulator|iothreads|vcpu" ~/vm-config.xml
```