Debian on ZFS Root installation script
======================================

The purpose of the script is to make the installation easy.

This is based on [ZFS on linux howto ](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Debian-GNU-Linux-to-a-Native-ZFS-Root-Filesystem).

ZFS root install procedure
==========================

The installation is only the 4 following steps :

* Boot on a Debian Live CDROM/Whatever (login: user, password: live)
* Download the installation script with wget and customize it

Command :

    $ wget http://raw.github.com/arcenik/debian-zfs-root/master/d8zroot.sh
    $ nano d8zroot.sh

* customize the installation script
 * Debian mirror
 * Disk and partitions scheme
 * ZFS volumes scheme
 * root password
 * user name/password/...

* run the script with root permission

Command :

    $ sudo bash d8zroot.sh

ZFS root on LUKS install procedure
==================================

The installation is only the 5 following steps :

* Boot on a Debian Live CDROM/Whatever (login: user, password: live)
* Download the installation script with wget and customize it

Command :

    $ wget http://raw.github.com/arcenik/debian-zfs-root/master/d8zroot.sh
    $ nano d8zroot.sh

* customize the installation script
 * Debian mirror
 * Disk, partitions scheme and LUKS formating
 * ZFS volumes scheme
 * root password
 * user name/password/...

* run the script with root permission

Command :

    $ sudo bash d8zroot.sh

* format and load the LUKS volume
** confirm the volume formating with YES (in capital)
** enter and confirm the password
** at this point you may need to swap to another console and generate some entropy by entering random things on the keyboard.
** enter the password again to load the LUKS volume

Serving files from a local server
=================================

If you prefer to customize your script on your computer with your favorite editor instead of changing it on the Debian Live systen, you can use python SimpleHTTPServer module to serve your files.

For example :

    $ cd some/path/
    $ python -m SimpleHTTPServer 8000

Then in the live Debian :

    $ wget http://192.168.1.2:8000/my-d8zroot.sh

Hack and patchs
===============

To make it working, some hack (and ugly patches) are required.

Initramfs hooks/cryptroot
-------------------------

The cryptroot hooks for initram fs is unable to detect the ZFS root in /etc/fstab, therefore it does not add the binaries and modules required in the initramfs.

To work arround this a copy of the script, with only the action function has been made

Initramfs script/local-top/cryptroot
------------------------------------

The cryptroot script that execute on boot fail to detect ZFS root properly.

The script use ROOT boot option and try to detect the filesystem type by using blkid. But as ROOT contains "ZFS=rpool/ROOT/debian-1" blkid fail to detect anything.

See : [Debian bug 820888](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=820888)

The workarround make the script to use only the lvm volume, which is properly detected.

Systemd dm-event.socket
-----------------------

The dm-event daemon is loaded too early, before /var being mounted. This cause the creation of files in the root filesystem preventing the proper mount of rpool/var due to /var being not empty.

See : [Debian bug 820883](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=820883)

To prevent this, the line is added to /lib/systemd/system/dm-event.socket

    After=systemd-remount-fs.service


Systemd zfs-mount.service (included in upstream)
------------------------------------------------

The zfs-mount.service is called too late and some files are created in the root instead of /var, preventing the proper mount of rpool/var.

See : [Github ZFS issue 4474](https://github.com/zfsonlinux/zfs/issues/4474)

To prevent this, the line is added to /lib/systemd/system/zfs-mount.service

    Before=systemd-remount-fs.service

This solution as some drowback for system with non ZFS root.

ZFS volumes should be mounted via /etc/fstab, either by specifying ZFS pool of ZFS volume individually.

Known problem
=============

keyboard-setup /tmp file
------------------------

The init script keyboard-setup creates a file in /tmp before the zfs mount -a preventing the proper mount of /tmp.
See : https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=819288



