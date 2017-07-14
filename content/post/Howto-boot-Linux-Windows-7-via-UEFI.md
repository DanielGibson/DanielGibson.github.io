+++
date = "2014-01-02T02:05:41"
title = "How to boot Linux and Windows 7 via UEFI"
tags = [ "diskpart", "efi", "gdisk", "GPT", "grub", "grub-efi", "grub2", "Linux", "pain", "uefi", "Win7", "Windows" ]
+++

Don't.  
It's a fucking pain in the ass.  

***Note:*** *This refers to Windows 7 (and probably Vista and Server 2008
and older). Starting with Windows 8, the Windows installer should support
UEFI better and things should be easier.*

Buy a <= 2TB hard disk for Windows installations (additional Windows partitions
can be on larger HDDs using GPT, it's only painful for the system partitions).
However, if you want to use a hard drive with >2TB for your Windows installation,
you have to use GPT partitions (instead of the old MBR style which only
supports <= 2TB disks - there you can only use the space > 2TB with ugly
hacks and can't have a continuous partition from 2TB) - and Windows can only
boot from GPT partitions in UEFI mode.  
To make things more challenging, Windows doesn't offer creating a GPT partition table
and partitions in the graphical installer (at least for Win7), so one has to use cmd.exe.  
But don't worry, the Linux part also sucks :-)  
I'll describe how I got **Windows to install using GPT partitions** on a 3TB harddisk,
how to make an existing **Linux** (Debian Wheezy) installation **boot via EFI (using grub-efi)**
and how I got my Mainboard [ASUS Z87-A](http://www.asus.com/Motherboards/Z87A/)
to boot this and GRUB to chainload (UEFI) Windows.

<!--more-->

So my situation was like this: I bought a new PC with one 250GB SSD (Samsung SSD 840 Evo Series),
a 3TB hard disk and the aforementioned UEFI-capable Mainboard.  
I only use Windows for gaming, so I won't spend precious SSD space for it, so I installed Linux
(or rather copied an existing installation) to the SSD, using normal MBR partitions
(probably GPT would have been a better choice for multiple reasons) and afterwards
I wanted to install Windows 7 to the first 150GB of the HDD or so (with an additional
bigger partition for Windows games later, the rest of the harddisk will be data on Linux and swap).  
So, in short:
<ul>
	<li>Huge HDD: <code>/dev/<strong>sda</strong></code>, 3TB, planning Windows installation, Linux swap + data</li>
	<li>Small(ish) SSD: <code>/dev/<strong>sdb</strong></code>, 250GB, Linux-only, so far two partitions (about 50GB System, rest for /home)</li>
</ul>

<h3 id="prerequisites">Prerequisites</h3>

Enable UEFI boot in BIOS, but make sure to disable SecureBoot! To do that you may have to remove the keys first (if any).  
All that is done in the BIOS (On mine, press DEL on boot, in that flashy BIOS-like thingy press F7 to go to "Advanced Mode", there it's in the "Boot" section).

You'll need a 64bit Windows DVD to install Windows.  
For the Linux part you'll need a USB key or CD/DVD with a UEFI-capable live Linux system, I used <a href="http://grml.org/download/" title="Grml homepage">Grml full amd64</a> on a 512MB USB flash drive.

<h3 id="win7">Installing Windows 7 using GPT partitions</h3>
This describes how to install Windows 7 64bit onto a hard disk in UEFI mode. This <strong>only</strong> works with the <strong>64bit</strong> version of Windows!
Basically - follow this great guide: http://www.techpowerup.com/forums/threads/installing-windows-vista-7-on-a-guid-partition-table.167245/  
I'll list the relevant steps here and add a bit more explanation.  
<strong>Note</strong> that this will <strong>erase all contents on the selected disk!</strong>
<ul>
	<li>Boot from Windows Installation DVD <strong>in UEFI mode</strong>.
On my machine, I did that by pressing F8 during boot to get the Mainboard's boot menu and then selecting the <code>UEFI:$DVD_drive_name</code> entry (<code>not</code> the <code>$DVD_drive_name</code> entry without the <code>"UEFI:"</code> prefix).</li>
	<li>The Windows Installation DVD's should have booted to a menu letting you select language, keyboard layout etc. Do that and click to the next step</li>
	<li>... which lets you choose to "Upgrade" an installation or to do a fresh installation.</li>
	<li><strong>Choose neither</strong>, instead press the [Shift]+[F10] keys to get a Windows command prompt.
The next steps are in that command prompt:</li>
	<li>Execute <code>diskpart</code> to start Windows' <a title="Diskpart description on microsoft technet" href="http://technet.microsoft.com/en-us/library/cc770877.aspx">commandline partitioning tool</a></li>
	<li>Execute <code>list disk</code> to get a list of available hard drives/SSDs (within the diskpart tool, it has its own prompt and generally seems quite decent except for the lack of commandline completion).</li>
	<li>Execute <code>select disk 2</code> to select the second drive to partition (or another number for another drive, see the list from the last step).</li>
	<li>Execute <code>online disk</code> to make sure the disk is running (you can probably ignore if this fails)</li>
	<li>Execute <code>attributes disk clear readonly</code> to make sure the disk isn't set readonly (like the previous command this is just precautionary and may fail).</li>
	<li>Execute <code>clean</code> to remove any pre-existing partition tables from this disk (i.e. the one you selected 3 steps before)</li>
	<li>Execute <code>convert gpt</code> to use GPT partitions on this disk.</li>
	<li>Execute <code>create partition efi size=100</code> to create a 100MB <a title="Wikipedia on EFI System Partition" href="http://en.wikipedia.org/wiki/EFI_System_partition">EFI system partition</a>.</li>
	<li>Execute <code>create partition msr size=128</code> to create a 128MB <a title="Wikipedia on Microsoft Reserverd Partition" href="http://en.wikipedia.org/wiki/Microsoft_Reserved_Partition">Microsoft Reserved Partition</a></li>
	<li>Execute <code>create partition primary size=120000</code> to create a 120GB partition for the Windows installation. Change 120000 accordingly if you want another size (should not be below 50GB or so).
Note that usually the pagefile.sys needs as much space as your amount of RAM, same for hiberfil.sys, so the more RAM you have to bigger your C: drive needs to be.. These files are actually the reason I don't install Windows on the SSD - it just wastes too much space.</li>
	<li>Execute <code>format fs=ntfs label="Operating System"</code> to format that partition with NTFS (to install windows on later)</li>
	<li>Execute <code>assign letter=C</code> to make the last created partition the <code>C:</code> partition.
Maybe <em>C</em> was already assigned to some other device, in that case you can find out which one with <code>list volume</code> which one it is, and then use <code>select volume $id</code> to select it, <code>assign letter=X</code> to rename it to <code>X:</code>, <code>select disk 2</code> to go back to the disk you partitioned and formatted before (if it had the id 2...) and then <code>assign letter=C</code> to really assign the letter <code>C</code> this time, as the original <code>C:</code> has been renamed.</li>
	<li>Execute <code>exit</code> to leave diskpart (you're done there)</li>
	<li>Close the command prompt</li>
	<li>Click "Install Windows" (or similar) and install Windows to C:
<em>If something went wrong, in the Windows installer partitioning menu it'll show the free space after the last partition in two pieces: One up to 2TB, the other one after that.</em></li>
</ul>
After a few reboots you should have a working Windows installation on a GPT formatted hard disk, booting in UEFI mode.
If it <strong>doesn't</strong> boot from the hard disk, you may have to configure your BIOS to boot it in UEFI mode (see <a href="#prequisites">Prerequisites</a>)

<h3 id="grub">Making Linux boot in UEFI using grub2</h3>
This is for Debian Wheezy with grub2 1.99-27 - but it's probably the same for other distributions and newer versions of Grub.
Furthermore it describes what to do when Linux is already installed, I didn't try a fresh install, no idea if debian installer currently supports GPT or UEFI.

Why do I want to do this, my Linux boots and works just fine? - Because you can only load UEFI Windows from Grub in UEFI mode, so grub needs to be started in UEFI mode as well.

I tried using Windows' EFI System Partition on the HDD for grub as well (it would just another .efi image in there). While calling grub-install kinda succeeded (the files were where they're supposed to be and it even listed the entry in its list of EFI boot entries afterwards), I couldn't get it to work: When calling <code>efibootmgr</code> afterwards to show the EFI boot order list, the entry has vanished again.
So I'll describe how to use a seperate EFI partition for Linux, in my case on the SSD.

If you can still boot your Linux system, do so and install grub-efi, on debian wheezy the corresponding package is called <strong>grub-efi-amd64</strong>. Installing it will uninstall grub-pc (the PC/BIOS version).
Also a small partition (1MB is really enough for grub!), preferably at the beginning of the disk, is needed as EFI System Partition.
Because of alignment stuff I had some space there and used it.
It ended up being /dev/sdb3 though (because it was created after the others), so I reordered the partitions using <a href="http://linux.die.net/man/8/sfdisk">sfdisk</a>:
<ul>
	<li><code>sudo sfdisk -d /dev/sdb &gt; sdb.old</code> to save the partition table to an ASCII file</li>
	<li><code>cp sdb.old sdb.new</code>, then edit the sdb.new to change the partition order (rename them accordingly and reorder lines - not sure if the latter is necessary)</li>
	<li><code>sudo sfdisk /dev/sdb &lt; sdb.new</code> to read in the changed partition table</li>
	<li>Reordering done. That was easy :-)</li>
</ul>

Anyway, create a partition to be used as (Linux/Grub) EFI System Partition and format it as FAT (<code>mkfs.vfat /dev/sdb1</code>).
Then boot up the live Linux and install grub-efi:
<ul>
	<li>Boot Grml in UEFI Mode ([F8] on boot, "UEFI:Generic 500MB USB" or something like that if booting from USB key - it really needs to be UEFI mode!)</li>
	<li>mount root-fs of your installation (e.g. /dev/sdb2) to /mnt/</li>
	<li>if they're in separate partitions, mount the /boot/, /usr/, ... partitions of your installation to /mnt/boot, /mnt/usr/, ...</li>
	<li><code>mount --bind</code> /dev/ and /sys/ to /mnt/dev and /mnt/sys (maybe also /proc for older versions of grub?), grub will need those</li>
	<li>Create a directory <strong><code>/boot/efi/</code></strong>: <code>mkdir /boot/efi</code></li>
	<li>.. and mount your EFI System Partition there: <code>mount /dev/sdb1 /boot/efi</code></li>
	<li><code>chroot /mnt</code></li>
	<li>execute <code>grub-install /dev/sdb</code> (assuming your EFI system partition is on sdb) to install grub to the EFI System Partition
<em>If your EFI system partition isn't the first partition on that disk, you also have to add <code>-p 2</code> to that command (assuming it's the second partition..)</em></li>
	<li><code>update-grub</code> to upgrade the grub menu entries</li>
	<li>Create a <code>/boot/efi/EFI/BOOT/</code> directory: <code>mkdir /boot/efi/EFI/BOOT/</code></li>
	<li>Copy grub's .efi image into that directory, so the Mainboard can find it:
<code>cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI</code>
(yes, a symlink would be the sensible thing to use here, but FAT doesn't support it.)</li>
	<li>Add a line for <code>/boot/efi</code> to <code>/etc/fstab</code>,
e.g.: <code>/dev/sdb1       /boot/efi       vfat    defaults        0       0</code> </li>
	<li>If names of partitions changed, don't forget to adjust the <code>/etc/fstab</code> entries for them.</li>
	<li>Reboot, go into the BIOS, it should now have an EFI entry for your Linux disk, make sure it has highest boot priority</li>
	<li>Afterwards you should be able to boot to Grub, and to your Linux installation from there on.
</ul>

I didn't have to format the SSD as GPT, the Mainboard was able to do an UEFI boot from MBR partitions. This may not work with other Mainboards, in that case convert your MBR to GPT - <a href="http://www.rodsbooks.com/gdisk/" title="gdisk Homepage">gdisk</a> should be able to do that without destroying your data, see http://www.rodsbooks.com/gdisk/mbr2gpt.html

<h4 id="win-grub">Adding UEFI Windows to grub2</h4>
So what's missing? Oh right, the reason we suffered through all that pain with UEFI on Linux: Create a Grub entry for UEFI Windows!

For some reason, grub/os-prober didn't automatically detect the Windows installation (maybe that doesn't work for UEFI Windows installations, no idea, maybe it's fixed in newer versions of Grub..) so I did it manually:

Add the following to `/etc/grub.d/40_custom` (or, if your distro doesn't have /etc/grub.d/, add it to /etc/grub.conf or something like that):
```text
menuentry "Microsoft Windows 7 x86_64 UEFI-GPT" {
	insmod part_gpt
	insmod fat
	insmod search_fs_uuid
	insmod chain
	search --fs-uuid --set=root 03AF-7491
	chainloader (${root})/EFI/Microsoft/Boot/bootmgfw.efi
}
```
where 03AF-7491 was the output of
<code>sudo grub-probe --target=fs_uuid -d /dev/sda1</code>
(assuming your Windows EFI System Partition is /dev/sda1; the actual UUID will most probably be different for you).

Call <code>sudo update-grub</code> afterwards, so it gets added to <code>/boot/grub/grub.cfg</code>.

On next boot you should be able to select (and boot) Windows in Grub.

<h4 id="regrets">What I would have done differently in hindsight</h4>
Before copying over my Linux installation to my new SSD, I should have created
the partitions in GPT, using <a href="http://www.rodsbooks.com/gdisk/">gdisk or cgdisk</a>.
Except for the thing that I really should have had GPT partitions to boot
via UEFI and was just lucky that the Mainboard didn't care, gdisk makes alignment much easier.

The problem is, that my SSD (Samsung SSD 840 Evo <em>(not Pro)</em> Series)
ideally is aligned to its "erase block size" of 1536KB (**3072 sectors** of 512bytes),
which is unusual, normally it seems to be 1024 or 2048 sectors, so \(c\)fdisks
default alignment of 2048 sectors is suboptimal for me.  
Furthermore the SSD does not tell the operating system that it likes that alignment, so partitioning tools like GNU parted, cfdisk, .. really can't guess the right alignment automatically - unfortunately they don't allow to specify a manual alignment (at least I didn't find the corresponding option), so I specified aligned sectors by hand.. not fun and so 80ies.
Anyway, gdisk allows to specify the alignment in sectors, which would have been exactly what I needed.
Furthermore, I would have aligned to <strong>6144 sectors</strong> (2*3072), just to be sure - that would work for both 3072 and 2048 aligned drives.

And of course I shouldn't have wasted two days with trying to use Windows' EFI System Partition, but should have created for Linux/Grub on my SSD in the first place.

Questions, additions, .. are welcome :-)  
(Note that I'm far from being an expert on UEFI, I just somehow managed to get my shit to work)
