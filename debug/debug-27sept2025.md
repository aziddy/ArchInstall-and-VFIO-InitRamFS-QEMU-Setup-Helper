
## 27 Sept 2025
```bash
PBO = 70 Level 5
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XML/EXPO Profile = Disabled
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
VM vCPU = 6
Motherboard Firmware = F4 # Gigabyte B850M
Hugepages = 0
CPU Governer = powersave
```

#### Findings
- Linux Host doesn't seem to crash, probably thanks to 'pcie_aspm=off' addition in GRUB
- Left computer for +2hrs, didnt crash
- Windows VM Playing Helldivers 2
    - Whole Host crashed after 15min of play 

---

## 28 Sept 2025
```bash
PBO = 70 Level 5
Eco Mode = Enabled - 105w
X3D Turbo = ON
SMT = OFF
DDR5 Auto Booster = Disabled
XML/EXPO Profile = Disabled
GRUB = "quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 pcie_aspm=off"
CPU Pinning GRUB = OFF
CPU Pinning VM XML = OFF
VM vCPU = 6
Motherboard Firmware = F4 # Gigabyte B850M
Hugepages = 14336 (28GB)
CPU Governer = performance
```

#### Findings
- Windows VM Playing Helldivers 2
    - TBD 