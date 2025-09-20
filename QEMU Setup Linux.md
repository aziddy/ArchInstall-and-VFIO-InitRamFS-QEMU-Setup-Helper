Assuming Arch is installed
## 1) Install Virtualization Packages
```bash
# Install QEMU and related packages
sudo pacman -S qemu-full virt-manager libvirt edk2-ovmf bridge-utils dnsmasq vde2 openbsd-netcat iptables-nft

# Enable and start libvirt
sudo systemctl enable --now libvirtd
sudo usermod -a -G libvirt $USER

# Check virtualization support
lscpu | grep Virtualization
lsmod | grep kvm
```

---
## 2) Enable IOMMU for GPU Passthrough

We must edit your ***GRUB*** config to pass specific parameters to the ***Linux Kernel*** on boot to enable ***IOMMU*** Features 

```bash
# Edit GRUB configuration
sudo nano /etc/default/grub

# Modify GRUB_CMDLINE_LINUX_DEFAULT line:
# For Intel CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
# For AMD CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"

# Update GRUB config that GRUB Bootloader in EFI Parition reads from
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```


> [!example] Whats ***IOMMU***?
> ***Input-Output Memory Management Unit*** is a motherboard hardware feature that
> - Creates Isolation between devices and system memory
> 	- Prevents VM's from accessing memory it shouldn't
> - Allows Virtual Machines to have direct hardware access
> 	- Essential for **GPU Passthrough**

---
## 3) Create a Script to Check IOMMU Groups
We will create a script that will output each **IOMMU Group** and their **Devices**. So we can identify what **IOMMU Group** we will pass through to the VM

Create file `check_iommu.sh`
```bash
nano ~/check_iommu.sh
```

Enter in the contents
```bash
#!/bin/bash
shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
# OUTPUT LIKE THIS
# IOMMU Group 0:
# 	00:00.0 Host bridge [0600]: Intel Corporation 8th Gen Core Processor Host Bridge/DRAM Registers [8086:3e20] (rev 07)

# IOMMU Group 1:
# 	01:00.0 VGA compatible controller [0300]: NVIDIA Corporation RTX 4070 [10de:2783]
# 	01:00.1 Audio device [0403]: NVIDIA Corporation RTX 4070 Audio [10de:22bc]

# IOMMU Group 2:
# 	00:01.0 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th # Gen Core Processor PCIe Controller [8086:1901] (rev 07)
# 	01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce # RTX 4070] [10de:2783] (rev a1)
# 	01:00.1 Audio device [0403]: NVIDIA Corporation AD104 High Definition Audio Controller [10de:22bc] (rev a1)

# IOMMU Group 15:
# 	00:1f.3 Audio device [0403]: Intel Corporation Cannon Lake PCH cHDA Controller [8086:a348] (rev 10)
```

Make executable and run 
```bash
chmod +x ~/check_iommu.sh
./check_iommu.sh
```


> [!WARNING] Were looking for the **IOMMU Group** with your **GPU** in it!
> - Note the `[vendor:device]` ID's of your GPU (Eg `10de:2684`)
> 	- Your GPU will often have two devices
> 		- **Graphics** Processor
> 		- **Audio** Controller (for *HDMI*/*DisplayPort* audio)

---
## 4) Configure GPU for Passthrough

### 4.A) Configure `VFIO` 

> [!info] Whats ***VFIO***?
> **VFIO (Virtual Function I/O)** is a Linux kernel driver that:
> - Takes control of **PCI** devices (like a GPU)
> 	- Reserving it for a VM later, preventing the Host OS from taking ownership

```bash
# Identify your NVIDIA GPU
lspci -nnk | grep -i nvidia

# Note the vendor:device IDs (e.g., 10de:2684)
# Edit GRUB again to add VFIO binding
sudo nano /etc/default/grub

# Add your GPU IDs to GRUB_CMDLINE_LINUX_DEFAULT:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt vfio-pci.ids=10de:xxxx,10de:yyyy"
# Replace xxxx and yyyy with your actual GPU device IDs
```

Create **VFIO** configuration file that tells ***VFIO Driver*** what to do
```bash
sudo nano /etc/modprobe.d/vfio.conf
```

Add the following content to the `vfio.conf` file
```bash
options vfio-pci ids=10de:xxxx,10de:yyyy
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
```

> [!EXAMPLE] Boot Time Sequence Flow
> - Kernel starts with `IOMMU` enabled
> - `VFIO` driver loads and spots ids=`10de:2783`,`10de:22bc`
> - `VFIO` "claims" these devices before other drivers can
> - NVIDIA drivers start but find their devices already taken
> - Result: GPU is bound to VFIO, available for VM passthrough

> [!bug] Why we check the **IOMMU Groups** earlier?
> We have to pass `[vendor:device]` ID's of ***ALL*** devices in a **IOMMU Group** to the **VFIO Driver** for it to work 

### 4.B) Configure `initramfs` 
====

Edit `initramfs` configuration
```bash
sudo nano /etc/mkinitcpio.conf
# Default content of the file should look like this
	# MODULES=()
	# BINARIES=()
	# FILES=()
	# HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)
```

Modify `mkinitcpio.conf` content
```bash
# Modify these lines
MODULES=(vfio_pci vfio vfio_iommu_type1)
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)
```

Rebuild `initramfs`
```bash
sudo mkinitcpio -P
```

Update `GRUB` and reboot
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```


> [!info] Whats ***initramfs***?
>**initramfs (Initial RAM Filesystem)** is a **temporary mini-operating system** that runs before the main Linux System boots
> - Loads essential drivers needed to access your drive
> - Mounts your `root` file system
> - Setups hardware before main system starts

```bash
1. BIOS/UEFI → 2. GRUB → 3. Linux Kernel → 4. initramfs → 5. Main Linux System
                                          ↑
                                    We modify this part
```

> [!info] Whats ***mkinitcpio***?
>**mkinitcpio** is Arch Linux's tool for building `initramfs` images. The configuration file `/etc/mkinitcpio.conf` tells it:
> - Which kernel modules (drivers) to include
> - Which "*hooks*" (scripts/functions) to run
> - How to build `initramfs`


---

## 5) Prepare 2nd SSD
```bash
# Identify your second drive
lsblk

# Note the device name (e.g., /dev/nvme1n1 or /dev/sdb)
# Ensure it's unmounted
sudo umount /dev/sdY* 2>/dev/null || true

# Optionally, wipe the drive
sudo dd if=/dev/zero of=/dev/sdY bs=1M count=100
```

---
## 6) Get QEMU Manager GUI running - `virt-manager`
We will use `virt-manager` a graphical interface for managing QEMU VM's on Linux 
```bash
┌─────────────────┐
│   virt-manager  │  ← GUI (what you interact with)
├─────────────────┤
│     libvirt     │  ← Management layer (Consistent API for managing VMs)
├─────────────────┤
│   QEMU/KVM      │  ← Virtualization engine (runs VMs)
├─────────────────┤
│ Linux Kernel    │  ← Hardware interaction
└─────────────────┘
```

Launch `virt-manager` and make sure `libvirt` service is running and accessible 
```bash
# Verify libvirt is running first
sudo systemctl status libvirtd

# Add yourself to libvirt group if not done
sudo usermod -a -G libvirt $USER
# Then log out and back in

# Start virt-manager
virt-manager
```

## 7) Create Windows VM with `virt-manager`
1) **Create a new Virtual Machine**
2) **Local install media** → Browse to Windows ISO
3) **Set Memory & CPUs** (recommend 8GB+ RAM, 4+ cores)
4) **Storage Configuration:**
    - Uncheck "Enable storage for this virtual machine"
    - After creation, add hardware → Storage
    - Device type: "Select or create custom storage"
    - Browse to your second SSD device (e.g., `/dev/sdb`)
5) **Before finishing:** Check "Customize configuration before install"


- **Machine Type:** Usually fine as default (pc-q35 or similar)
- **Firmware:** Change from "BIOS" to "**UEFI**"
	- Select: `UEFI x86_64: /usr/share/edk2-ovmf/x64/OVMF_CODE.fd`
	- **Why:** Modern Windows expects UEFI, better GPU passthrough compatibility

**CPUs Tab**
- Topology:
	- ✅ Check "**Manually set CPU topology**"
	- **Example for 8-core CPU:**
		- Sockets: 1
		- Cores: 4 (or 6)
		- Threads: 2 (if your CPU has hyperthreading)
- CPU Model:
	- ✅ Check "**Copy host CPU configuration**"
		- *Ensures VM gets all CPU features for best performance*

**Memory Tab**
- Memory:
	- Set desired allocated RAM (ex `32000 MB`)

**Boot Options Tab**
- Boot Device Order:
	- Ensure your storage device is in boot order
	- `CDROM1` should be first for Windows installation

**Add Hardware - Storage**
- Click "Add Hardware" → Storage:
	- Storage Configuration:
		- **Device type:** "Select or create custom storage"
		- **Browse:** Navigate to your second SSD device
			- Example: `/dev/nvme1n1` or `/dev/sdb`
			- **NOT** a partition like `/dev/sdb1`
		- **Bus type:** `VirtIO` (for best performance)

> [!warning] Important Storage Notes:
> ```
> ✅ Use raw device: /dev/sdb
❌ Don't use partition: /dev/sdb1
✅ VirtIO bus for performance
❌ IDE bus is slower
> ```

**Add Hardware - PCI Host Devices (GPU Passthrough!)**
- Click "Add Hardware" → PCI Host Device:
	- Select your NVIDIA GPU:
		- Look for: "NVIDIA Corporation GeForce RTX xxxx"
			- Should show as available (if VFIO binding worked)
		- Add BOTH devices:
			1) **GPU:** "NVIDIA Corporation GeForce RTX 4070"
			2) **GPU Audio:** "NVIDIA Corporation RTX 4070 High Definition Audio"

Download/Install `VirtIO` Drivers
```bash
# Install from Arch repositories  
sudo pacman -S edk2-ovmf-guest qemu-guest-agent

# VirtIO ISO location after install:
ls /usr/share/edk2-guest-tools/
```

> [!info] Whats ***VirtIO***?
> **VirtIO** is a **virtualization standard** for high-performance virtual devices
> - 


**Load VirtIO storage drivers** during Windows installation:
- Click "Add Hardware" → Storage
	- Device type: `CDROM device`
	- Select your VirtIO drivers ISO
		- When prompted for disk location, click `Load driver`
		- Browse `VirtIO ISO` → `viostor` → `w11` → `amd64`

> [!WARNING] Windows doesn't come with VirtIO Drivers
> So we gotta install them in your Windows installation ASAP



## Console / Terminal Way
~~