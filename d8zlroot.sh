###############################################################################
#
# Debian Jessie (version 8) installation script for ZFS root filesystem on 
# LUKS encrypted volume
#
# Copyright : Francois Scala @2016
# License   : GPL v3
#
#
# Disk schema :
# +-- DISK -------------------------------------------------------------------+
# | +-Part 3---+ +-Part 1--+ +-Part 2---------------------------------------+ |
# | | BIOS EFI | | Ext4    | | LUKS Encrypted vol.                          | |
# | |          | | /boot   | |+--VG_SYS-----------------------------------+ | |
# | |          | |         | || [LV_SWAP] [LV_ZROOT : ZFS Root          ] | | |
# | |          | |         | |+-------------------------------------------+ | |
# | +----------+ +---------+ +----------------------------------------------+ |
# +---------------------------------------------------------------------------+
#
###############################################################################

# Debian
DEBIANDIST=jessie
#DEBIANMIRROR="http://ftp.us.debian.org/debian"
DEBIANMIRROR="http://ftp.ch.debian.org/debian"

# ZFS
POOL=rpool
ZFSRELEASE=zfsonlinux_6_all.deb

# Default grub options
BOOT_OPTIONS="quiet vga=794"

###############################################################################
# customize your root password, user account here and other parameters
function do_user {

# Set root password
echo 'root:root' | chpasswd

# Create a user
adduser --gecos "Some User" --shell /bin/bash --disabled-password user
echo 'user:user' | chpasswd
#mkdir /home/user/.ssh
#cat > /home/user/.ssh/authorized_keys << _EOF
#ssh-rsa AAAAB3NzaC1yc2EAAAABJQA.....
#_EOF
#chown -R user.user /home/user/.ssh

# Locales
DEBIAN_FRONTEND=noninteractive apt-get install -y locales
locale-gen en_US.UTF-8
locale-gen C.UTF-8
export LANG=C.UTF-8

# Misc
DEBIAN_FRONTEND=noninteractive apt-get install -y tree htop ssh strace mc vim

# Automation (puppet, cfengine, ...)

}

###############################################################################
# customize your partition scheme here
function do_partitions {

LUKS_NAME="cryptroot"
LUKS_OPTIONS="--verbose --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random "

VG_NAME="vg_sys"
LV_ZROOT="lv_zroot"
LV_SWAP="lv_swap"

DISK=/dev/sda
BOOTPARAM=${DISK}

PARTBOOT=${DISK}1
PARTLUKS=${DISK}2
PARTLVM=/dev/mapper/${LUKS_NAME}
PARTZROOT=/dev/mapper/${VG_NAME}-${LV_ZROOT}
PARTSWAP=/dev/mapper/${VG_NAME}-${LV_SWAP}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y gdisk lvm2

sgdisk --clear  ${DISK}
sgdisk -n 1::+512M  -c 1:"BOOT"       -t 1:8300 ${DISK}
sgdisk -n 2::       -c 2:"${VG_NAME}" -t 2:8e00 ${DISK}
sgdisk -n 3:34:2047 -c 3:"BIOS"       -t 3:ef02 ${DISK}

mkfs.ext4 -L BOOT ${PARTBOOT}

DEBIAN_FRONTEND=noninteractive apt-get install -y gdisk cryptsetup

echo "==========================================================="
echo "==="
echo "=== LUKS setup"
echo "==="

res=1
while [ ${res} -gt 0 ]; do
echo "Luks format ${PARTLUKS}"
#echo XXX cryptsetup luksFormat ${LUKS_OPTIONS} ${PARTLUKS}
cryptsetup luksFormat ${LUKS_OPTIONS} ${PARTLUKS}
res=$?
echo "Luks format returned ${res}"
done

res=1
while [ ${res} -gt 0 ]; do
echo "Luks open ${PARTLUKS}"
cryptsetup luksOpen ${PARTLUKS} ${LUKS_NAME}
res=$?
echo "Luks open returned ${res}"
done

echo "==========================================================="
echo "==="
echo "=== LVM setup (for initramfs luks)"
echo "==="

pvcreate ${PARTLVM}
vgcreate ${VG_NAME} ${PARTLVM}
lvcreate -n ${LV_SWAP}  -L2G       ${VG_NAME}
lvcreate -n ${LV_ZROOT} -l100%FREE ${VG_NAME}

# Swap
mkswap -f -L SWAP ${PARTSWAP}
#swapon -va

}

###############################################################################
# customize your rpool setup
function do_rpool {

zpool create -o ashift=12 -o altroot=/mnt -m none              ${POOL} ${PARTZROOT}
zfs set atime=off                                              ${POOL}

zfs create -o mountpoint=none                                  ${POOL}/ROOT
zfs create -o mountpoint=/                                     ${POOL}/ROOT/debian-1

zpool set bootfs=${POOL}/ROOT/debian-1                         ${POOL}

zfs create -o mountpoint=/home                                 ${POOL}/home
#zfs create -o mountpoint=/usr                                  ${POOL}/usr # separated /usr unsupported by systemd
zfs create -o mountpoint=/var                                  ${POOL}/var
zfs create -o compression=lz4 -o atime=on                      ${POOL}/var/mail
zfs create -o compression=lz4 -o setuid=off -o exec=off        ${POOL}/var/log
zfs create -o compression=lz4 -o setuid=off -o exec=off        ${POOL}/var/tmp
zfs create -o mountpoint=/tmp -o compression=lz4 -o setuid=off ${POOL}/tmp

}

###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
# Nothing should be change after this line

echo "==========================================================="
echo "==="
echo "=== Partitioning"
echo "==="
do_partitions

###############################################################################
echo "==========================================================="
echo "==="
echo "=== Install ZFS On Linux on Live image"
echo "==="
if [ ! -f ${ZFSRELEASE} ]
then
	wget http://archive.zfsonlinux.org/debian/pool/main/z/zfsonlinux/${ZFSRELEASE}
fi
dpkg -i ${ZFSRELEASE}
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64 debian-zfs
modprobe zfs

###############################################################################
echo "==========================================================="
echo "==="
echo "=== Create ZFS Pool ${POOL}"
echo "==="
do_rpool

zpool export ${POOL}
zpool import -d /dev/disk/by-id -R /mnt ${POOL}

mkdir -p /mnt/etc/zfs/
zpool set cachefile=/mnt/etc/zfs/zpool.cache ${POOL}

mkdir -p /mnt/boot
mount /dev/disk/by-partlabel/BOOT /mnt/boot

###############################################################################
echo "==========================================================="
echo "==="
echo "=== Bootstrap Debian ${DEBIANDIST}"
echo "==="

DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap
debootstrap ${DEBIANDIST} /mnt ${DEBIANMIRROR}

cp /etc/hostname /mnt/etc/
cp /etc/hosts /mnt/etc/
cp ${ZFSRELEASE} /mnt/tmp/

echo "Generate fstab"
cat > /mnt/etc/fstab << _EOF
LABEL=BOOT	/boot	ext4	noatime	0	1
LABEL=SWAP	none	swap	defaults	0	0
_EOF

echo "Generatte empty crypttab"
cat > /mnt/etc/crypttab << _EOF
# no crypttab
_EOF

echo "Generate network/interfaces"
cat > /mnt/etc/network/interfaces << _EOF
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
_EOF

# Generate chroot script
declare -f do_user > /mnt/tmp/chroot.sh
cat >> /mnt/tmp/chroot.sh << _EOF

cd /tmp/

do_user

echo "==========================================================="
echo "==="
echo "=== Install ZFS and cryptsetup On Linux on target system"
echo "==="

DEBIAN_FRONTEND=noninteractive apt-get install -y lsb-release
dpkg -i /tmp/${ZFSRELEASE}
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64 debian-zfs cryptsetup lvm2

DEBIAN_FRONTEND=noninteractive apt-get install -y grub2-common grub-pc zfs-initramfs
grub-install --target=i386-pc --force ${BOOTPARAM}
mkdir -vp /boot/grub/
grub-mkconfig -o /boot/grub/grub.cfg

unset UCF_FORCE_CONFFOLD
export UCF_FORCE_CONFFNEW=YES
ucf --purge /boot/grub/menu.lst

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

###############################################################################
# patch grub
echo "Set grub default config"
cp /etc/default/grub /etc/default/grub.orig
echo "default/grub : GRUB_CMDLINE_LINUX_DEFAULT"
sed -i "s-GRUB_CMDLINE_LINUX_DEFAULT=\"quiet-GRUB_CMDLINE_LINUX_DEFAULT=\"${BOOT_OPTIONS}-" /etc/default/grub
echo "default/grub : GRUB_CMDLINE_LINUX"
sed -i "s-GRUB_CMDLINE_LINUX=\"-GRUB_CMDLINE_LINUX=\"cryptopts=source=${PARTLUKS},target=${LUKS_NAME},lvm=${VG_NAME}\-${LV_ZROOT} -" /etc/default/grub
echo "Update grub"
update-grub

###############################################################################
# patch initramfs cryptroot script
mkdir /root/backup
cd /usr/share/initramfs-tools/scripts/local-top/
cp cryptroot /root/backup/cryptroot.orig
patch -p0 --verbose << __EOP
--- cryptroot.orig
+++ cryptroot
@@ -330,7 +330,7 @@
 			if [ -f /conf/param.conf ] && grep -q "^ROOT=" /conf/param.conf; then
 				NEWROOT=\\\$(sed -n 's/^ROOT=//p' /conf/param.conf)
 			else
-				NEWROOT=\\\${cmdline_root:-/dev/mapper/\\\$cryptlvm}
+				NEWROOT=\\\${cmdline_root_notexist:-/dev/mapper/\\\$cryptlvm}
 				if [ "\\\$cryptrootdev" = "yes" ]; then
 					# required for lilo to find the root device
 					echo "ROOT=\\\$NEWROOT" >>/conf/param.conf
__EOP
# update-initramfs -u # updated below

###############################################################################
# config initramfs hooks
base64 -d << __EOF2 | gunzip -c > /etc/initramfs-tools/hooks/zfsroot
H4sICA6wDFcCA3pmc3Jvb3Quc2gAzVZta9swEP5s/Yqr40FTcNSUth8aUlhf2ArbCi3dC2MEWZZr
EUfyJDskTfPfd7KdNG0oKSyMJQTLp7vTPc+d7tLaoZFU1KakRVpwrvMp6ARoaQ3KmBFUKlkYNkps
WGidWZpqPbSUm2leGK2LyuyDUMKwQkDErDg+hCjTEZxUWwHcP8gcQg4PiXUGHZvC40LxdCmNjg+d
fvUln68v7j5d3vZ9YMICjzhgLAdHx+5x1D2ASWGBJQOW3QP+ZDJIGXqtl3bIZZ4KA/EorKIEnxCO
x0HQBalIboQRv22beIKnGnwfFxNZwD7xej0iLOOEtLb7IZ1NhIZJqXghtbLbP5zF8aAiQg9GOi4z
YXfbMCNepjnLAEWQyEwge0W11qWK4d4lVPLqhXgo7/tBF5mqBH3H2aqGExBPJvATwgfwA9T34VcP
ilQo4nlGFKVR0EVziXot+CYgZWMBVoyxbDLIdSFUIXFldWk4phxLsIkVdqUCbWJMKAoxeQmmT3HR
PkFPzhkAawPNZEQbCxp8vby5vbr+QofCKJFRZnhKg/c35x/rstXURRgGNhdcJpJ3hrp2FG1wtGI9
aPAvbfnbbZc28Qab2EgkyFKH1HFv6kwhIcFuIjFNftDclIurm2dofQgVG4k6F+EenujDwSmNxZiq
MsvaPYgxBq/OOeZ25hy3Wnt07j8T16t3aF9tjJgqWTZwFbVIjx/UOm67KYapsPgWayXeHnVDz1Pc
M/Q5X2H5n8f/osKfgXoq9VWl1Zr/K9ivwX0N7+uANyF+AbmCV9/SrUFcFPF/jXEN3Iue1bzuk/n2
+7Pj0XVeR+Os4W9es7HeusFdaFKXIcdhPRATwYFaN8MrTYuR5mtb8WhN7hrPkwVldpgz68aPa89K
iBjbc9yBS1m4YTqWDKLSTiM9wW4MzIItmIpZhpEAnsDMtEMqPv3g7O72x9n1dx/64CskFR4fUb4D
IY7gWbOJBTKnC4dL2lfCq/6UiJg4+pv5/AchcQYmqwgAAA==
__EOF2
chmod 755 /etc/initramfs-tools/hooks/zfsroot
update-initramfs -u

###############################################################################
# patch dm-event.socket
cd /lib/systemd/system
patch -p0 --verbose << __EOP
--- dm-event.socket.orig
+++ dm-event.socket
@@ -2,6 +2,7 @@
 Description=Device-mapper event daemon FIFOs
 Documentation=man:dmeventd(8)
 DefaultDependencies=no
+After=systemd-remount-fs.service
 
 [Socket]
 ListenFIFO=/var/run/dmeventd-server
__EOP

_EOF

###############################################################################
echo "==========================================================="
echo "==="
echo "=== Chroot installation step"
echo "==="

mount --bind /dev  /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys  /mnt/sys

chroot /mnt bash /tmp/chroot.sh 2>&1 | tee /mnt/root/install-chroot.log

# XXX Uncomment this to inspect/hack the system before the final unmount and reboot
#echo "XXXXXXXXXXXXXXXXXXXXXXX Confirm to unmount"
#read bla

umount /mnt/boot
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys
zfs umount -a
zpool export ${POOL}

echo "==========================================================="
echo "==========================================================="
echo "==========================================================="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "==="
echo "===     Installation completed."
echo "==="
echo "===     You can now remove the boot device and reboot to"
echo "===     your new installation"
echo "==="

###############################################################################
