+++
date = "2011-01-05T16:55:41+02:00"
title = "Linux (Debian Squeeze) on Thinkpad T500"
tags = [ "Linux", "2055V1X", "debian", "debian squeeze", "shrink partition", "shrink windows", "special keys", "squeeze", "T500", "thinkpad", "ultranav", "xbindkeys" ]
+++

I recently got myself a Lenovo <a href="http://www.thinkwiki.org/wiki/Category:T500">Thinkpad T500</a> (2055V1X) . I chose this older model over the T510 and such, because I prefer a screen resolution of 1680x1050 over a crippled 1600x900 or worse. I write and read a lot of code so I need vertical space on the display and I'd definitely miss the 150pixels additional vertical space my old Laptop (Samsung X20 with a resolution of 1400x1050) has.

However, I shrunk the Windows 7 partition (I didn't want to dump Windows entirely) and installed Debian Squeeze (AMD64) in the resulting free space. I'm very pleased how painless everything was, almost all hardware ran out of the box, but I'll document some interesting stuff (how to shrink windows partition without breaking it, how to make special keys work and display information on Linux, how to make the touchpad and trackpoint behave the way I want, ...) anyway.

<!--more-->

### Shrinking Windows

There were three partitions: a small one (about 1,2GB) called SYSTEM_DRV, which seems to be a Win7 boot partition (since when does Windows have a seperate partition for that?), on the second one was the Windows installation (this is the one I shrunk) and the third one of about 9,8GB that contained Lenovo recovery stuff (double-clicking it lets you burn that stuff onto three DVDs - which may make sense because Lenovo doesn't ship any DVDs/CDs with the Thinkpad so if your harddrive fails you're fscked).
I defragmentated the system partition and then tried to shrink it with Windows onboard-tools (<a href="http://www.howtogeek.com/howto/windows-vista/resize-a-partition-for-free-in-windows-vista/">here is a description</a>), but it was not satisfactory: even though "only" 24GB were used by Windows and all that preinstalled crap, I could only shrink the partition to a size of 190GB, if I recall correctly. The reason was some unmovable system file or something like that.  
I wanted to shrink it to 100GB, so I used the Linux tool <a href="http://gparted.sourceforge.net/">GParted</a> from the <a href="http://grml.org/">grml Live-CD</a> to do the job, which it did without any problems: On the next boot Windows did a file system check or repair or something and kept on functioning without any complaints.

### Preparation

Before installing Debian I got the Squeeze Beta2 netinstall ISO from 
<del datetime="2011-02-06T19:09:59+00:00">http://cdimage.debian.org/cdimage/daily-builds/squeeze_d-i/amd64/iso-cd/</del> and burned it to a CDRW.  
<br>
<i>Update: Squeeze is now stable, use the netinstall ISO from <a href="http://debian.org/CD/netinst/">http://debian.org/CD/netinst/</a></i><br>


My T500 has got two display adapters: An Intel GMA X4500 and a AMD Mobility Radeon HD 3650. Only very recent versions of the Linux kernel (2.6.34 onwards as far as I know) support switching between them at runtime (but still X needs to be restarted) - Squeeze is still at 2.6.32, so that won't work without a custom kernel. See <a href="http://www.thinkwiki.org/wiki/Switchable_Graphics">the ThinkWiki</a> for further information.  
One can still switch the adapters in the BIOS (press F1 after powering on the Thinkpad). Because I don't need much 3D power at the moment and prefer longer battery life, a better driver and a cooler laptop I chose to use the Intel Chip ("Discrete Graphics"). Because of that I won't describe how to make the Radeon work, but it shouldn't be too painful (either use the default free driver or install the proprietary fglrx). 
My settings in the BIOS (Config -&gt; Display) look like this:

```text
Default Primary Video Device  [Internal]
Boot Display Device           [Thinkpad LCD]
Graphics Device               [Integrated Display]
OS Detection for Switchable Graphics 
                              [Disabled]
```

To install Debian you want to have Ethernet (wired LAN) ready for Internet-access, because the wireless chip in the T500 (at least in mine) needs proprietary firmware from Intel that Debian doesn't include by default.
However, if you've only got wireless Internet you can supply the firmware from a USB-stick, the Debian installer will prompt for that. 
<i><b>Update:</b></i> See <a href="http://wiki.debian.org/Firmware">the debian Wiki</a> for more information, including links to netinstall-ISOs that include firmware.

### Installing Debian

Just insert the CD, boot, follow the instructions (I won't describe that in detail, because that's not the point of this article). 
Some notes:
<ul>
	<li>Make sure to use manual partitioning and use the free space (after the second NTFS partition) for your linux partitions.</li>
	<li>If you want to use hibernate (suspend-to-disc), you'll need a big enough swap partition - it should be at least as big as your main memory. My T500 has 4GB of RAM, my swap partition is 6GB.</li>
	<li>Yes, you want to install grub to the MBR</li>
</ul>
Because I like my debian installation to be slim I always disallow apt to install the recommended packages of packages I install, by creating a file <strong>/etc/apt/apt.conf.d/06-norecommends</strong> with the following content:
```text
APT
{
        Install-Recommends "false";
        Install-Suggests "false";
};
```
But of course this is optional and has nothing to do with making Debian work on a Thinkpad ;-)

#### Getting WiFi firmware

After installing the basic stuff and rebooting to my new debian installation, I installed the WiFi firmware.
First I modified <b>/etc/apt/sources.list</b> to also use the <i>contrib</i> and <i>non-free</i> repositories, so the entries looked like this:
```text
deb http://ftp.de.debian.org/debian/ squeeze main contrib non-free
deb-src http://ftp.de.debian.org/debian/ squeeze main contrib non-free

deb http://security.debian.org/ squeeze/updates main contrib non-free
deb-src http://security.debian.org/ squeeze/updates main contrib non-free
```
 (Yours may look slightly different, depending on the mirror you selected).
After an <code>apt-get update</code> I installed the packages <b>firmware-linux</b> (not sure if this is really needed, maybe for the radeon) and <b>firmware-iwlwifi</b> (this one is definitely needed for wireless LAN, at least if you've got a "Intel Wifi Link 5100" or 5300 like me).

For using wireless LAN network-manager-gnome and the gnome-keyring (to store network keys) may come in handy. See <a href="http://caedesnotes.wordpress.com/2010/05/05/unlock-gnome-keyring-on-login-with-slim-pam/">my post on how to unlock the gnome-keyring on login when using the SLiM display manager</a> for more on that.

#### Protecting you hard disk drive with HDAPS

Thinkpads have a cool feature to protect the HDD from falling damage: The <a href="http://www.thinkwiki.org/wiki/Active_Protection_System">IBM Active Protection System</a>. On Linux this is supported by the HDAPS kernel driver and the hdapsd userspace daemon. To get a recent version of the kernel driver you have to install the tp-smapi driver package. It's available in apt in both the <strong>tp-smapi-source</strong> package and the <strong>tp-smapi-dkms</strong> package (I installed the latter).
The hdaps daemon is also available via apt, the package is called <strong>hdapsd</strong>. It should just work out of the box.

#### Hibernate support

Hibernate works out of the box. But there's a keyboard-shortcut to start hibernation, that doesn't: <strong>Fn-F12</strong>. It sends a ACPI button/suspend message and by default there is no ACPI handler for that event. This can be easily fixed, though: Just create a file <strong>/etc/acpi/events/hibernatebtn</strong> with the following content and after a reboot the button should work:
```bash
# /etc/acpi/events/hibernatebtn
# Called when the user presses the hibernate button

event=button[ /]suspend
action=/etc/acpi/hibernatebtn.sh
```

#### Disabling the PC speaker

To get rid of that annoying beep on several occasions (tab-completion, end of file in less, ...), add the following to the <strong>/etc/modprobe.d/blacklist.conf</strong> file:
```bash
# no beeps, plz
blacklist pcspkr
blacklist snd_pcsp
```

Note that this doesn't deactivate all beeps: The Thinkpad seems to beep independently of the OS e.g. on resume (after hibernate/standby) or when the power chord is plugged in or removed. 

### X.org/Desktop specific stuff

The following stuff concerns X.org. It's independent from a specific desktop environment (like XFCE, GNOME, KDE, ...) - but it may well be that some of this can also be done with tools from the desktop environment.

#### Make the "UltraNav" (Touchpad/Trackpoint) behave the way I want

Both the Touchpad and the Trackpoint work out of the box. They can be further configured with a tool like <strong>gpointing-device-settings</strong> or similar tools from your desktop environment.
However, two things could not be configured with gpointing-device-settings:
<ol>
<li>I want to be able to perform a <strong>click by tapping the touchpad</strong>. This should be configurable with gpointing-device-settings, but it didn't work anyway, so I had to do it at X.org configuration level.  
I created the directory <strong>/etc/X11/xorg.conf.d/</strong> and within that directory a file called <strong>10-synaptics.conf</strong> with the following content:
```text
# adapted from https://wiki.archlinux.org/index.php/Touchpad_Synaptics
Section "InputClass"
    Identifier "touchpad catchall"
    Driver "synaptics"
    MatchIsTouchpad "on"
    # this enables clicking by tapping:
    Option "TapButton1" "1" 
EndSection
```
</li>
<li>I want to be able to <strong>scroll with the Trackpoint</strong> by holding down the middle mouse button and moving the nipple. Also I want to emulate the third mouse button by pressing the other two - this is just out of habit, it's not needed, because the middle mouse button works as well.  
So I created a file name <strong>20-trackpoint.conf</strong> in the directory <strong>/etc/X11/xorg.conf.d/</strong> (see above), with the following content:
```text
# adapted from http://www.thinkwiki.org/wiki/How_to_configure_the_TrackPoint#xorg.conf.d
Section "InputClass"
        Identifier      "Trackpoint Wheel Emulation"
        MatchProduct    "TPPS/2 IBM TrackPoint"
        MatchDevicePath "/dev/input/event*"
        Option          "EmulateWheel"          "true"
        Option          "EmulateWheelButton"    "2"
        Option          "Emulate3Buttons"       "true"
        Option          "XAxisMapping"          "6 7"
        Option          "YAxisMapping"          "4 5"
EndSection
```
</li>
</ol>

#### Special Keys

The Thinkpad has a lot of special keys (or key-combinations), e.g. to configure the brightness, the volume, ...  
Some of them (e.g. brightness) already work, but it'd be nice to have some additional on-screen information, other don't do anything without further configuration.
(A special case is the hibernate button that I've mentioned earlier, because it is configured via ACPI handlers and not in X)  
I used the desktop-independent <strong>xbindkeys</strong> tool (from the identically named debian package) to support those keys. The <strong>xbindkeys-config</strong> utility is really handy to modify xbindkey's configuration file, <em>~/.xbindkeysrc</em>. However, for xbindkeys-config to work you need a <em>~/.xbindkeysrc</em> file (it may even be empty) or it'll crash, so just execute <pre><code>$ touch ~/.xbindkeysrc</code></pre> before doing anything else.
After installing xbindkeys you should make sure it's started when you log into X. One way to do so is to just add the following line to the <strong>~/.profile</strong> file: 
```bash
# ...
# start xbindkeys
xbindkeys &
```
Also most of the scripts for the special keys use the <em>osd_cat</em> tool from the <strong>xosd-bin</strong> package to display information on the screen, so you should install it.

##### Brightness Control

The keys to control the display's brightness (Fn-Home/Pos1 and Fn-End) already work out the box. But it would be nice if the current brightness level (there are 16: 0-15) was displayed on the screen along with a nice bar.. the following script (save it to some dir in you $PATH, e.g. <strong>/usr/local/bin/</strong> and make it executable (<code>chmod 755 /usr/local/bin/brightness.sh</code>) does that:
```bash
#!/bin/bash

if [ -n "$XAUTHORITY" ]; then
        # kill other osd_cat processes to prevent overlapping
        if [ $(ps -A | grep osd_cat | wc -l) -gt 0 ]; then
                killall osd_cat
        fi
        i=$(cat /sys/class/backlight/acpi_video0/brightness)    
        let i_perc=(100*$i)/15
        osd_cat -d 1 -A center -p bottom -o 50 -c yellow -s 1 \
        -f -adobe-courier-bold-r-normal--*-240-*-*-m-*-iso8859-1 \
        -b percentage -P $i_perc -T "Brightness: $i / 15"
fi
```
Make sure the path (<em>/sys/class/backlight/acpi_video0/brightness</em>) is correct for you or change it accordingly.  
Now either use <strong>xbindkeys-config</strong> to make sure this script is called if either Fn-Home or Fn-End is pressed or add the following to the <strong>~/.xbindkeysrc</strong> file (At the end I'll paste my complete ~/.xbindkeysrc file.):
```text
#brightness up
"brightness.sh"
    m:0x0 + c:233
    XF86MonBrightnessUp 

#brightness down
"brightness.sh"
    m:0x0 + c:232
    XF86MonBrightnessDown 
```

##### Switch Touchpad on/off

Fn-F8 is meant to toggle between touchpad, Trackpoint and both.. I see no point in disabling the Trackpoint so I just use it to disable/enable the touchpad.
So by pressing Fn-F8 you'll get a nice OSD info saying "Touchpad OFF" or "Touchpad ON" and the touchpad will be switched off/on.  
Save the following code as <em>toggletouchpad.sh</em> somewhere in your $PATH and make it executable:
```bash
#!/bin/bash
# adapted from http://forums.gentoo.org/viewtopic-p-6241953.html?sid=815e3e5f2bb9ccfbef0c8ff6cb37914b#6241953

if synclient -l | grep -q TouchpadOff[^[:alnum:]]*0 ; then     
   synclient TouchpadOff=1                                     
   status="TouchPad OFF"                                       
else
   synclient TouchpadOff=0
   status="TouchPad ON"
fi

# kill other osd_cat processes to prevent overlapping
if [ $(ps -A | grep osd_cat | wc -l) -gt 0 ]; then
    killall osd_cat
fi
if [ -n "$XAUTHORITY" ]; then
    echo $status | osd_cat -d 3 -p bottom -A center -o -50 -s 1 -c green \
    -f -adobe-courier-bold-r-normal--*-240-*-*-m-*-iso8859-1 
fi
```
Add the following to your <strong>~/.xbindkeysrc</strong> (or use xbindkeys-config to map the key yourself):
```text
#toggle touchpad
"toggletouchpad.sh"
    m:0x0 + c:199
    NoSymbol 
```

##### Configure display

Fn-F7 is meant to configure display output (to the internal LVDS display or the external VGA and DisplayPort ports).  
With Linux/X.org these configurations can be done with <a href="http://en.wikipedia.org/wiki/Randr">RandR</a>. A nice GUI for randr is <strong>arandr</strong> (available via apt), so I just start arandr whenever Fn-F7 is pressed.
<strong><em>Note:</em></strong> Fn-F7 is identified as the XF86Display key. XFCE has a default mapping for that (it executes <code>xrandr --auto</code> which is supposed to do something useful, but..) so you may need to disable that default mapping. In XFCE that is done in the keyboard settings.

Add the following to your <strong>~/.xbindkeysrc</strong> (or use xbindkeys-config to map the key yourself):
```text
#configure display
"arandr"
    m:0x0 + c:235
    XF86Display 
```

##### Volume Keys

There are three keys to control the volume: One for mute, one to increase the volume and one to decrease it.
The script uses amixer (from the <strong>alsa-utils</strong> package) to change the volume and also outputs the current volume/status.
Save it as <strong>volume.sh</strong> and make it executable:

```bash
#!/usr/bin/env bash
# adapted from http://ztatlock.blogspot.com/2009/01/volume-control-with-amixer-and-osdcat.html

CHANNEL=Master

if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
  p=$(basename $0)
  cat <<HERE

  Usage: $p <channel> <option>
  where option is in {+, -, m, u} or is a percent
  e.g. $p 50       # sets $CHANNEL to 50%
           $p Front m  # toggles the mute of the channel Front

HERE
  exit 0
fi

if [ $# -eq 2 ] ; then
  CHANNEL=$1
  shift
fi

function vol_level {
  amixer get $CHANNEL |\
  grep 'Front Left:'  |\
  cut -d " " -f 7     |\
  sed 's/[^0-9]//g'
}


function osd {
  killall osd_cat &> /dev/null
  echo $* |\
  osd_cat -d 2 -l 1 -p bottom -c green -s 1 -A center -o 50 \
    -f '-adobe-courier-bold-r-normal--*-240-*-*-m-*-iso8859-1' &
}

function mute_osd {
        if [ $(amixer get $CHANNEL | grep Playback | grep "\[on\]" | wc -l) -gt 0 ]
        then
                osd $CHANNEL Unmuted
        else
                osd $CHANNEL Muted
        fi
}

function vol_osd {
  killall osd_cat &> /dev/null
  osd_cat -d 2 -l 2 -p bottom -c green -s 1 -A center -o 50 \
    -f '-adobe-courier-bold-r-normal--*-240-*-*-m-*-iso8859-1' \
        -T "Volume ($CHANNEL) : $(vol_level) %" -b percentage -P $(vol_level) &
}

case "$1" in
  "+")
        amixer -q set $CHANNEL 5%+
        vol_osd
        ;;
  "-")
        amixer -q set $CHANNEL 5%-
        vol_osd
        ;;
  "m")
        amixer -q set $CHANNEL toggle
        mute_osd
        ;;
  *)
        amixer -q set $CHANNEL $1%
        ;;
esac
```
<del datetime="2011-12-28T14:51:40+00:00"><strong><em>Note:</strong></em> Due to a bug, probably in the sound driver or hardware, muting doesn't really work with this script (because muting master has no effect). Maybe I'll fix the script to use a workaround later.</del>
<i><b>Update:</b> Muting Master does work now (it actually has been working for months), probably due to an updated Kernel in Debian Squeeze.</i> 

Add the following to your <strong>~/.xbindkeysrc</strong> (or use xbindkeys-config to map the key yourself):
```text
#Volume Up
"volume.sh +"
    m:0x0 + c:123
    XF86AudioRaiseVolume 

#Volume Down
"volume.sh -"
    m:0x0 + c:122
    XF86AudioLowerVolume 

#Volume (Un)Mute
"volume.sh m"
    m:0x0 + c:121
    XF86AudioMute
```

##### Lock Screen

Fn-F2 is used to lock the screen. If you're using <b>xscreensaver</b> you can just call <code>xscreensaver-command -lock</code> to lock the screen.
To do that add the following to your <strong>~/.xbindkeysrc</strong> (or use xbindkeys-config to map the key yourself):
```text
#Lock Screen
"xscreensaver-command -lock"
    m:0x0 + c:160
    XF86ScreenSaver 
```

##### Battery Status

Fn-F3 has a battery symbol. I'm not sure what it's supposed to do, but just displaying the current battery status (percentage and if it's charging, discharging or whatever) may be nice.
The following script (save it as <strong>batteryinfo.sh</strong> to you $PATH and make it executable) does exactly that:
```bash
#!/bin/bash
# path to your battery. make sure it's correct
BAT_PATH="/sys/class/power_supply/BAT0"

if [ -n "$XAUTHORITY" ]; then
        # kill other osd_cat processes to prevent overlapping
        if [ $(ps -A | grep osd_cat | wc -l) -gt 0 ]; then
                killall osd_cat
        fi
        BAT_FULL=$(cat $BAT_PATH/energy_full)
        BAT_NOW=$(cat $BAT_PATH/energy_now)
        STATUS=$(cat $BAT_PATH/status)
        let perc=(100*$BAT_NOW)/$BAT_FULL

        osd_cat -d 2 -A center -p bottom -o 50 -c yellow -s 1 \
         -f -adobe-courier-bold-r-normal--*-240-*-*-m-*-iso8859-1 \
         -b percentage -P $perc -T "Battery $perc % loaded, $STATUS"
fi
```

Add the following to your <strong>~/.xbindkeysrc</strong> to make it work:
```text
#Battery Status
"batteryinfo.sh"
    m:0x0 + c:244
    XF86Battery 
```

I haven't mapped the remaining special keys (like play, pause, ...) yet, but as you may already have guessed, this could easily be done with xbindkeys. Use either xbindkeys-config to do that or create the entries for the <em>~/.xbindkeysrc</em> yourself - you can get the keycodes with <code>xbindkeys -k</code>.

My complete <strong>~/.xbindkeysrc</strong>:
```bash
###########################
# xbindkeys configuration #
###########################
#
# Version: 0.1.3
#
# If you edit this, do not forget to uncomment any lines that you change.
# The pound(#) symbol may be used anywhere for comments.
#
# A list of keys is in /usr/include/X11/keysym.h and in
# /usr/include/X11/keysymdef.h 
# The XK_ is not needed. 
#
# List of modifier (on my keyboard): 
#   Control, Shift, Mod1 (Alt), Mod2 (NumLock), 
#   Mod3 (CapsLock), Mod4, Mod5 (Scroll). 
#
# Another way to specifie a key is to use 'xev' and set the 
# keycode with c:nnn or the modifier with m:nnn where nnn is 
# the keycode or the state returned by xev 
#
# This file is created by xbindkey_config 
# The structure is : 
# # Remark 
# "command" 
# m:xxx + c:xxx 
# Shift+... 

#keystate_numlock = enable
#keystate_scrolllock = enable
#keystate_capslock = enable

#toggle touchpad
"toggletouchpad.sh"
    m:0x0 + c:199
    NoSymbol 

#configure display
"arandr"
    m:0x0 + c:235
    XF86Display 

#brightness up
"brightness.sh"
    m:0x0 + c:233
    XF86MonBrightnessUp 

#brightness down
"brightness.sh"
    m:0x0 + c:232
    XF86MonBrightnessDown 

#Volume Up
"volume.sh +"
    m:0x0 + c:123
    XF86AudioRaiseVolume 

#Volume Down
"volume.sh -"
    m:0x0 + c:122
    XF86AudioLowerVolume 

#Volume (Un)Mute
"volume.sh m"
    m:0x0 + c:121
    XF86AudioMute 

#Lock Screen
"xscreensaver-command -lock"
    m:0x0 + c:160
    XF86ScreenSaver 

#Battery Status
"batteryinfo.sh"
    m:0x0 + c:244
    XF86Battery 

#
# End of xbindkeys configuration
```

### What also works (tested)

<ul>
	<li>the webcam (tested with guvcview, vlc, google talk)</li>
	<li>the card reader (tested with SDHC card)</li>
	<li>Bluetooth (tested with Wiimote)</li>
	<li>sound card</li>
	<li>LAN, WLAN</li>
	<li>Hibernate (suspend to disk) and Standby (suspend to RAM)</li>
	<li>VGA out (Displayport only works with the Radeon - also on Windows - so I haven't really tested it on Linux. I guess you'd need the fglrx driver for that to work.)</li>
	<li>Several hardware sensors (fan speed, temperatures). About half of the temperature sensors don't work, though.. but who needs 16 temperature sensors anyway?
<strong><em>Has anyone got a clue where those sensors (temp1 ... temp16) are?</em></strong>
</ul>

### What doesn't work

<ul>
	<li>Switching the graphics adapter. With a newer kernel this should be possible - but not without restarting X. See <a href="http://www.thinkwiki.org/wiki/Switchable_Graphics">this article at the ThinkWiki</a></li>
	<li>Intels TurboMemory. This is supposed to speed up Windows boot, but basically is flash memory plucked into a PCI-Express port. Could be useful for Linux as well, but is not supported.</li>
	<li>The fingerprint reader (Authentec 2810) is unsupported according to <a href="http://www.thinkwiki.org/wiki/Integrated_Fingerprint_Reader">the ThinkWiki</a>. I don't care because most fingerprint readers can be fooled easily. Also I don't like the idea of a robber not only stealing my laptop, but also cutting off my fingers.</li>
</ul>

### Untested

<ul>
	<li>WAN (UMTS) (<a href="http://www.thinkwiki.org/wiki/Ericsson_F3507g_Mobile_Broadband_Module">should work</a>)</li>
	<li>Thinkpad 56k Modem (<a href="http://www.thinkwiki.org/wiki/ThinkPad_Modem_%28MDC-3.0,_56kbps_HDA%29">should work</a>) </li>
	<li>Firewire (should work)</li>
	<li>TPM (don't care)</li>
</ul>

### *Update:* Output of lspci and lsusb

I figured it may be a good idea to paste the output of lspci and lsusb. Note that the radeon is disabled via BIOS, so it isn't listed. I highlighted the lines listing non-working hardware.

{{< highlight text"hl_lines=27 42" >}}
caedes@Cyberdemon:~$ lspci 
00:00.0 Host bridge: Intel Corporation Mobile 4 Series Chipset Memory Controller Hub (rev 07)
00:02.0 VGA compatible controller: Intel Corporation Mobile 4 Series Chipset Integrated Graphics Controller (rev 07)
00:02.1 Display controller: Intel Corporation Mobile 4 Series Chipset Integrated Graphics Controller (rev 07)
00:03.0 Communication controller: Intel Corporation Mobile 4 Series Chipset MEI Controller (rev 07)
00:03.3 Serial controller: Intel Corporation Mobile 4 Series Chipset AMT SOL Redirection (rev 07)
00:19.0 Ethernet controller: Intel Corporation 82567LM Gigabit Network Connection (rev 03)
00:1a.0 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #4 (rev 03)
00:1a.1 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #5 (rev 03)
00:1a.2 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #6 (rev 03)
00:1a.7 USB Controller: Intel Corporation 82801I (ICH9 Family) USB2 EHCI Controller #2 (rev 03)
00:1b.0 Audio device: Intel Corporation 82801I (ICH9 Family) HD Audio Controller (rev 03)
00:1c.0 PCI bridge: Intel Corporation 82801I (ICH9 Family) PCI Express Port 1 (rev 03)
00:1c.1 PCI bridge: Intel Corporation 82801I (ICH9 Family) PCI Express Port 2 (rev 03)
00:1c.2 PCI bridge: Intel Corporation 82801I (ICH9 Family) PCI Express Port 3 (rev 03)
00:1c.3 PCI bridge: Intel Corporation 82801I (ICH9 Family) PCI Express Port 4 (rev 03)
00:1c.4 PCI bridge: Intel Corporation 82801I (ICH9 Family) PCI Express Port 5 (rev 03)
00:1d.0 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #1 (rev 03)
00:1d.1 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #2 (rev 03)
00:1d.2 USB Controller: Intel Corporation 82801I (ICH9 Family) USB UHCI Controller #3 (rev 03)
00:1d.7 USB Controller: Intel Corporation 82801I (ICH9 Family) USB2 EHCI Controller #1 (rev 03)
00:1e.0 PCI bridge: Intel Corporation 82801 Mobile PCI Bridge (rev 93)
00:1f.0 ISA bridge: Intel Corporation ICH9M-E LPC Interface Controller (rev 03)
00:1f.2 SATA controller: Intel Corporation ICH9M/M-E SATA AHCI Controller (rev 03)
00:1f.3 SMBus: Intel Corporation 82801I (ICH9 Family) SMBus Controller (rev 03)
03:00.0 Network controller: Intel Corporation Ultimate N WiFi Link 5300
04:00.0 Memory controller: Intel Corporation Turbo Memory Controller (rev 11) ## doesn't work
15:00.0 CardBus bridge: Ricoh Co Ltd RL5c476 II (rev ba)
15:00.1 FireWire (IEEE 1394): Ricoh Co Ltd R5C832 IEEE 1394 Controller (rev 04)
15:00.2 SD Host controller: Ricoh Co Ltd R5C822 SD/SDIO/MMC/MS/MSPro Host Adapter (rev 21)
15:00.3 System peripheral: Ricoh Co Ltd R5C843 MMC Host Controller (rev ff)
15:00.4 System peripheral: Ricoh Co Ltd R5C592 Memory Stick Bus Host Adapter (rev 11)
15:00.5 System peripheral: Ricoh Co Ltd xD-Picture Card Controller (rev 11)

caedes@Cyberdemon:~$ lsusb 
Bus 008 Device 002: ID 17ef:1003 Lenovo Integrated Smart Card Reader
Bus 008 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 007 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 006 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 005 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 004 Device 004: ID 0a5c:2145 Broadcom Corp. Bluetooth with Enhanced Data Rate II
Bus 004 Device 002: ID 08ff:2810 AuthenTec, Inc. AES2810 ## doesn't work
Bus 004 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 003 Device 002: ID 0bdb:1900 Ericsson Business Mobile Networks BV F3507g Mobile Broadband Module
Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 001 Device 004: ID 17ef:4807 Lenovo UVC Camera
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
{{< /highlight >}}
