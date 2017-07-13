+++
date = "2013-12-31T04:13:03+02:00"
title = "(Re)installing GRUB to the MBR"
tags = [ "debian", "grub", "grub2", "mbr", "squeeze", "wheezy" ]
+++

This is just a very short roundup of the relevant commands needed to reinstall grub,
e.g. when migrating a Linux installation to a new hard drive.

* boot live Linux system (from CD/DVD or USB key, I use
  [grml](http://grml.org), any other live Linux should do)
* mount root-fs of your installation (e.g. /dev/sda2) to /mnt/
* if they're in separate partitions, mount the /boot/, /usr/, ...
  partitions of your installation to /mnt/boot, /mnt/usr/, ...
* `mount --bind` /dev/ and /sys/ to /mnt/dev and /mnt/sys (maybe also /proc
  for older versions of grub?), grub will need those
* `chroot /mnt`
* execute `grub-install $device` (e.g. /dev/sda) to install grub to the MBR of $device
* `update-grub` to upgrade the grub menu entries
* If names of partitions changed, don't forget to adjust `/etc/fstab`
* reboot, remove live linux
* configure your BIOS/UEFI to boot from that harddisk

That's all - you should now be greeted by a fresh grub that lets you boot your Linux, BSD, Windows, .. installations
<!--more-->
