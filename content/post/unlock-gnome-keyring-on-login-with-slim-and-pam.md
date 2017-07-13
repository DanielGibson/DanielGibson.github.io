+++
date = "2010-05-05T02:41:30+02:00"
title = "Unlock gnome-keyring on Login with SLiM and PAM"
tags = [ "gnome-keyring", "libpam-gnome-keyring", "Linux", "network manager", "PAM", "slim" ]
+++

My favorite desktop environment is <a href="http://www.xfce.org/">XFCE</a>, because it's fast, doesn't need much memory¹ and still is convenient (automounting of CDs and memory sticks, easy unmounting by clicking, a real desktop, etc).
I also use [SLiM](https://github.com/iwamatsu/slim) as a display manager because it is slim and looks much better than xdm.

On my Laptop I also use GNOME's <a href="http://projects.gnome.org/NetworkManager/">NetworkManager</a> because I haven't yet found a better and less bloated alternative for handling wireless networks and VPNs.
NetworkManager is able to store your passwords (WPA-keys etc) in the <a href="http://live.gnome.org/GnomeKeyring">GNOME Keyring</a> so you don't need to enter them each time your laptop connects to a wireless network. But you still have to enter the password to unlock the keyring.. <em><strong>unless</strong></em> you let <a href="http://en.wikipedia.org/wiki/Pluggable_Authentication_Modules">PAM</a> handle that on login.
<!--more-->
I'll describe how to make PAM unlock your GNOME-Keyring, when you log in with SLiM, so applications like the NetworkManager can access the keyring. I'll focus on how to do that with <a href="http://debian.org">Debian</a> "squeeze" (the current testing), but it should be directly applicable for Ubuntu (at least "Lucid", for older versions you'll have to build your own slim package with PAM support - or maybe use the one from debian) and quite similar in any other Linux distribution.

## What should be installed?

<ul>
	<li><strong>slim</strong> SLiM, with PAM-support (if you compile yourself: <code>make USE_PAM=1</code>)</li>
	<li><strong>gnome-keyring</strong> the GNOME keyring daemon</li>
	<li><strong>libpam-gnome-keyring</strong> PAM module to unlock the GNOME keyring upon login (if you compile it yourself: should be contained in gnome-keyring sources)</li>
	<li>probably some software using the GNOME keyring, like network-manager-gnome</li>
</ul>
If you haven't used slim before, you may configure it by editing <code>/etc/slim.conf</code>, at least for debian it contains helpful comments. Most interesting is the <strong>sessions</strong> option to set the sessions you want to use (I only use <code>startxfce4</code>).

## Configuration

You need to edit <code>/etc/pam.d/slim</code>. If that file doesn't exist (I hope it will be added to debians SLiM package soon), just paste it from <a href="http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=476248">the debian bugreport #476248</a>.
However, to unlock the keyring you need to add the following two lines to the end of the file:
<pre><code>auth    optional        pam_gnome_keyring.so
session    optional        pam_gnome_keyring.so  auto_start
</code></pre>
That should be all. Just log out, log back in and the keyring should be unlocked, so applications can access it without entering further passwords.
If it does not work and you've used GNOME keyring before, you may have to delete <code>~/.gnome2/keyrings/</code> to make it work correctly.
