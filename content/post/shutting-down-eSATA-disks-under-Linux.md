+++
date = "2010-05-11T22:55:05+02:00"
title = "Shutting down (e)SATA disks under Linux"
tags = [ " disconnect disk", "disk", "eSATA", "hotplug", "Linux", "SATA", "shutdown", "spin down" ]
ghcommentid = 5
+++

I'm using a eSATA external harddrive and want to be able to safely unplug it without shutting down my PC. While just removing the drive after unmounting worked so far, I'm not sure if it's really safe - I'd really prefer to cleanly disconnect it and spinning it down before pulling the plug. 
I googled that and stumbled upon <a href="http://www.sakana.fr/blog/2009/05/04/linux-sata-hot-plug-unplug/">http://www.sakana.fr/blog/2009/05/04/linux-sata-hot-plug-unplug/</a> which seems to be a clean and safe way to do it, so I just wrote a script to do that.
<!--more-->
It also checks if any partition of that drive is still mounted (that check might result in false positives however or might just fail when the disk is mounted by UUID or via some mapper like dmcrypt) and tells you to unmount before disconnecting the drive - however you can bypass that test with the <code>-f</code> option.

You can copy the script by moving the mouse over the code, clicking that "view source" icon on the top right corner of the code listing and then just copy and paste the code from the popup-window.
Save the code to <code>/usr/local/sbin/disc_disk</code> (or some other directory in $PATH, but note that this script can only be successfully executed by the root-user - or via sudo - anyway) and make it executable (<code>chmod 755 /usr/local/sbin/disc_disk</code>).
Usage is quite easy: If you want to disconnect the disk represented by /dev/sdX just execute (as root or prefixed by <code>sudo</code>) <pre><code>$ disc_disk sdX</pre></code>

This should probably work with any hot-pluggable device managed by the Linux SCSI subsystem like USB memory sticks (tried that, worked for me) or real SCSI discs.


```bash
#!/bin/sh
# simple script to shutdown and disconnect SATA-discs
# (and probably other devices using Linux's SCSI-subsystem 
# like USB mass-storage devices)
# (C) 2010 caedes
# You may use and distribute this freely.

USG="Usage: disc_disk [-f] <device>\n
	-f forces disconnect even if device is mounted\n
	Example: disc_disk sda"

if [ "$1" = "-h" ]; then
	echo "Disconnects and shuts down disk."
	echo -e $USG
	exit 0
fi

FORCE=0

if [ -n "$2" ]; then
	if [ "$1" = "-f" ]; then
		FORCE=1
	else
		echo "Unknown Option $1"
		echo -e $USG
		exit 1
	fi
	DEV=$2
else
	DEV=$1
fi

if [ -z $DEV ]; then
	echo "Disconnects and shuts down disk."
	echo -e $USG
	exit 1
fi

DPATH="/sys/block/$DEV/device/delete"

if [ ! -e $DPATH ]; then
	echo "Invalid device!"
	echo -e $USG
	exit 1
fi

# really simple check, might fail (may be skipped  with -f)
# (e.g. on mount /dev/sdb /mnt/sda and disc_disk sda)
if [ $FORCE -eq 0 ]; then
	if [ $(mount | grep $DEV | wc -l) -gt 0 ]; then
		echo "Device still mounted! Unmount it before disconnecting or use -f option to enforce disconnect (dangerous!)."
		echo $(mount | grep $DEV)
		exit 1
	fi
fi

echo "Shutting down and disconnecting $DEV.."
echo 1 > $DPATH
echo "Done."
```
