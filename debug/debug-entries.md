
## 27 Sept 2025
```bash
PBO = 70 Level 5
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XMP/EXPO Profile = Disabled
dGPU Only Mode = Auto
SR-IOV Support = Disabled
GPU Host Translation Cache = Auto
Motherboard Firmware = F4 # Gigabyte B850M
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
Disk Bus Type = SATA
VM vCPU = 6
VM ivshMEM = 256 mb
Hugepages = 0
CPU Governer = powersave
```

#### Findings
- Linux Host doesn't seem to crash, probably thanks to 'pcie_aspm=off' addition in GRUB
- Left computer for +2hrs, didnt crash
- Windows VM Playing Helldivers 2
    - Whole Host crashed after 15min of play 

---

## 28 Sept 2025 - 1
```bash
PBO = 70 Level 5
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XMP/EXPO Profile = Disabled
dGPU Only Mode = Auto
SR-IOV Support = Disabled
GPU Host Translation Cache = Auto
Motherboard Firmware = F4 # Gigabyte B850M
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
Disk Bus Type = SATA
VM vCPU = 6
VM ivshMEM = 256 mb
Hugepages = 14336 (28GB)
CPU Governer = performance
```

#### Findings
- Windows VM Playing Helldivers 2
    - Whole Host crashed after 30min of play  

---

## 29 Sept 2025 - 1
```bash
PBO = 80 Level 2
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XMP/EXPO Profile = Disabled
dGPU Only Mode = Disabled
SR-IOV Support = Enabled
GPU Host Translation Cache = Disabled
Motherboard Firmware = F6b # Gigabyte B850M
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
Disk Bus Type = VirtIO
VM vCPU = 6
VM ivshMEM = 128 mb
Hugepages = 0
CPU Governer = performance # re-enable on boot
```

#### Findings
- Windows VM Playing Helldivers 2
    - Played on low settings for 1+ Hours, pretty good

---

## 30 Sept 2025 - 1
```bash
PBO = 80 Level 4 # Increased PBO Level 2->4
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XMP/EXPO Profile = Disabled
dGPU Only Mode = Disabled
SR-IOV Support = Enabled
GPU Host Translation Cache = Disabled
Motherboard Firmware = F6b # Gigabyte B850M
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
Disk Bus Type = VirtIO
VM vCPU = 6
VM ivshMEM = 128 mb
Hugepages = 0
CPU Governer = performance # re-enable on boot
```

#### Findings
- Windows VM Playing Helldivers 2
    - 30min Pretty no crashing
    - Playing game on low settings and still dip into 60fps range
        - Gotta figure out how to improve FPS, maybe try
            - X3DTurbo=OFF && SMT=ON
            - EcoMode=OFF
            - DDR5AutoBooster=ON
            - XMP/EXPO=ON


---

## 1 Oct 2025 - 1
```bash
PBO = 80 Level 4
Eco Mode = Disabled # Disabled Eco Mode
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XMP/EXPO Profile = Disabled
dGPU Only Mode = Disabled
SR-IOV Support = Enabled
GPU Host Translation Cache = Disabled
Motherboard Firmware = F6b # Gigabyte B850M
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
Disk Bus Type = VirtIO
VM vCPU = 6
VM ivshMEM = 128 mb
Hugepages = 0
CPU Governer = performance # re-enable on boot
```

#### Findings
- Windows VM Playing Helldivers 2 on Low Settings
    - 30 Min of play and no crash
    - Need to test longer