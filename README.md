
The purpose of the script is to make the installation easy.

This is based on [ZFS on linux howto ](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Debian-GNU-Linux-to-a-Native-ZFS-Root-Filesystem).

Install Debian on ZFS Root
==========================

Here is the installation steps :

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

Serving files from a local server
=================================

If you prefer to customize your script on your computer with your favorite editor instead of changing it on the Debian Live systen, you can use python SimpleHTTPServer module to serve your files.

For example :

    $ cd some/path/
    $ python -m SimpleHTTPServer 8000

Then in the live Debian :

    $ wget http://192.168.1.2:8000/my-d8zroot.sh
