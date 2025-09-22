
## Option 1) Via AUR Package
```bash
yay -S virtio-win
```

After installation, the VirtIO drivers ISO should be available at:
```bash
ls /usr/share/virtio-win/
```



## Option 2) Manual Download
```bash
# Download the latest virtio-win ISO
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

# Move to a convenient location
sudo mv virtio-win.iso /usr/share/virtio-win/
```