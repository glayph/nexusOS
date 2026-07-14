#!/bin/bash
# Nexus OS - Local Build Script
# Run as root on Ubuntu 22.04+
set -e

apt-get install -y debootstrap xorriso squashfs-tools \
  grub-pc-bin grub-efi-amd64-bin mtools dosfstools

debootstrap --arch=amd64 --variant=minbase noble rootfs \
  http://archive.ubuntu.com/ubuntu/

tee rootfs/etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu noble main restricted universe
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe
EOF

mount --bind /proc rootfs/proc && mount --bind /sys rootfs/sys && mount --bind /dev rootfs/dev

chroot rootfs /bin/bash -c "
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-generic initramfs-tools python3 python3-requests \
    bash coreutils systemd systemd-sysv util-linux procps \
    iproute2 vim nano curl wget ca-certificates
  echo root:nexus | chpasswd
"

umount rootfs/proc rootfs/sys rootfs/dev

cp nexus-agent.py rootfs/usr/local/bin/nexus-agent.py
chmod +x rootfs/usr/local/bin/nexus-agent.py
mkdir -p rootfs/etc/nexus
echo "nexus" > rootfs/etc/hostname

mkdir -p rootfs/etc/systemd/system/getty@tty1.service.d
cat > rootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF

echo 'if [ $(tty) = /dev/tty1 ]; then exec /usr/local/bin/nexus; fi' > rootfs/root/.bash_profile

cat > rootfs/usr/local/bin/nexus << LAUNCHER
#!/bin/bash
export TERM=linux
[ -f /etc/nexus/api.key ] && export ANTHROPIC_API_KEY=$(cat /etc/nexus/api.key)
exec /usr/local/bin/nexus-agent.py
LAUNCHER
chmod +x rootfs/usr/local/bin/nexus

mkdir -p iso/{boot/grub,EFI/boot,live}
KVER=$(ls rootfs/boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')
cp rootfs/boot/vmlinuz-$KVER iso/boot/vmlinuz
cp rootfs/boot/initrd.img-$KVER iso/boot/initrd.img
cp boot/grub/grub.cfg iso/boot/grub/grub.cfg

mksquashfs rootfs iso/live/filesystem.squashfs -comp zstd -e boot -noappend

grub-mkstandalone --format=x86_64-efi --output=iso/EFI/boot/bootx64.efi \
  --locales="" --fonts="" "boot/grub/grub.cfg=iso/boot/grub/grub.cfg"
grub-mkstandalone --format=i386-pc --output=core.img \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --fonts="" "boot/grub/grub.cfg=iso/boot/grub/grub.cfg"
cat /usr/lib/grub/i386-pc/cdboot.img core.img > bios.img
dd if=/dev/zero of=efiboot.img bs=1M count=4 status=none
mkfs.fat -F12 efiboot.img
mmd -i efiboot.img ::/EFI ::/EFI/boot
mcopy -i efiboot.img iso/EFI/boot/bootx64.efi ::/EFI/boot/
cp bios.img efiboot.img iso/

xorriso -as mkisofs -iso-level 3 -volid "NEXUS_OS_1_0" \
  -appid "Nexus OS 1.0 Agentic AI Linux" \
  -b bios.img -no-emul-boot -boot-load-size 4 -boot-info-table \
  --efi-boot efiboot.img -efi-boot-part --efi-boot-image \
  --protective-msdos-label -append_partition 2 0xef efiboot.img \
  -o nexus.iso iso

echo "nexus.iso ready: $(ls -lh nexus.iso | awk '{print $5}')"
