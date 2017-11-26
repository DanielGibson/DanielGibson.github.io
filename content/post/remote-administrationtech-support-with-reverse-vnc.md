+++
date = "2010-01-08T02:55:18+02:00"
title = "Remote administration/tech-support with (reverse) VNC"
slug = "remote-administrationtech-support-with-reverse-vnc"
tags = [ "Linux", "reverse VNC", "TightVNC", "VNC", "Windows", "x11vnc" ]
ghcommentid = 3
+++

Like most computer-savvy people I am frequently asked to give tech support to my family etc. Because telling them on the telephone what to do is a major pain in the ass, <a title="Virtual Network Computing" href="http://en.wikipedia.org/wiki/VNC">VNC</a> is my weapon of choice, if SSH isn't sufficiant (got to show how something is done, SSH impossible/hard because the other side uses Windows or is behind a NAT, ...).

I'll describe how to set up a normal and reverse VNC-connections using <a title="home of x11vnc" href="http://www.karlrunge.com/x11vnc/">x11vnc</a> and <a title="TightVNC homepage" href="http://www.tightvnc.com/">TightVNC</a>.

<!--more-->

We have 2 computers: Your (the helpers) system - let's call it "the client" from now on- using a VNC Client, and the helpee's (does this word even exist?) system, running a VNC server - we'll call it "the server".

If the server runs Linux, i'd recommend installing <a title="home of x11vnc" href="http://www.karlrunge.com/x11vnc/">x11vnc</a>, if it runs Windows, tell the helpee to install <a title="TightVNC homepage" href="http://www.tightvnc.com/">TightVNC</a>.

You need to install a VNC-client on the client system, for example the TightVNC viewer (package "xtightvncviewer" on debian/Ubuntu).

<em>Please note:</em> This HOWTO describes simple <strong>unencrypted</strong> VNC sessions. If you want to encrypt the session you should use SSH tunneling or SSL - see your VNC softwares documentation on how to do this.

# First Case: Normal VNC

For normal VNC operation the server needs to be accessible via a public IP (or it needs to be in the same private subnet (LAN) as the client). This is normally the case, if the VNC server dials directly into the internet (-&gt; doesn't use a "router") or if the according port is forwarded by the router to the VNC server. You also sometimes get public IPs in university (W)LANs.

If the server doesn't have a public IP, configure the router that connects the LAN with the server to the internet to forward port 5900 TCP to the servers IP. Consult your routers manual on how to do this.

If you can't or don't want to configure the helpee's router, use reverse VNC (see below).

Tell the helpee to start the VNC server software. For x11vnc the appropriate command is
<pre><code>x11vnc -display :0 -passwd s0mep4ssword
</code></pre>
This will start x11vnc on display :0 (standard display) and on connection you'll be asked to enter a password, which is "s0mep4ssword" in this case. This not super secure, but should prevent basic automated attacks, especially if x11vnc only runs if needed.
Just tell the helpee to enter this into the terminal or create a clickable shortcut (on the desktop or in some menu...) that executes this command.

The TightVNC server on windows is started by clicking <strong>Start-&gt;Programs-&gt;TightVNC-&gt;Launch TightVNC Server</strong>. The helpee will be asked to set a password on the first TightVNC start. For further information see <a href="http://www.tightvnc.com/winst.php#start_serv">the official documentation</a>.

The helper (you) needs the helpee's public IP (or a <a title="DynDNS homepage" href="http://www.dyndns.org">dyndns</a>-address or something similar) to connect. Tell him to visit <a title="What's my IP" href="http://www.whatsmyip.org/">this</a> or <a title="heise My-IP service" href="http://www.heise.de/netze/tools/ip/">this</a> page and tell you the fat numbers ;-)

Connect with  
`vncviewer -compresslevel 9 123.45.67.89`  
(replace 123.45.67.89 with the correct IP). Enter the password ("s0mep4ssword" in my example) in the terminal when asked for it.
"-compresslevel 9" sets maximal compression for faster screen updates. It will look a bit crappy, but in my experience everything is still readable and usable.
If you're using Windows (boo!), click "<strong>Start-&gt;Programs-&gt;TightVNC-&gt;TightVNC     Viewer</strong>"; consult the <a href="http://www.tightvnc.com/winst.php#start_view">TightVNC documentation</a> for further information.

Now the helper should be able to see the helpee's desktop and do stuff. If the helper closes the vncviewer window, the connection is closed and the server (at least x11vnc) shuts down and needs to be restarted if the helper wants to connect again.

# Second Case: Reverse VNC

Technically,  in this case the helper is the server and the helpee is the client. So you got to make sure the helpee can connect to your Machine. If your PC doesn't have a public IP (and is not in the same LAN as the helpees PC), i.e. is not directly connected to the internet, configure the router that connects the LAN with your PC to the internet to forward port 5500 TCP to your IP. As you're probably tech-savvy, you'll know how to do this. If you don't, consult your routers documentation.
If you're in a LAN, but have no rights to change the routers configuration (for example in a university's (W)LAN), and you can't use normal VNC either, you're probably screwed. You could try some weird tunneling over a third PC/server with a public IP.. (ssh -L and ssh -R might be useful) but I'm not going to discuss this (hopefully rare) case now.

After making sure that your (the helpers) PC's port 5500 TCP is reachable from the internet, you have to start the vncviewer in listen mode:

<code>vncviewer -compresslevel 9 -listen</code>

If you're using Windows,  just start the TightVNC viewer (<strong>Start-&gt;Programs-&gt;TightVNC-&gt;TightVNC     Viewer)</strong> and click "<strong>Listening Mode</strong>".
Now the VNC viewer on your PC ist listening for incoming connections from a VNC-server (yes that sounds weird, but that's why it's called "reverse VNC").
The helpee now has to make his VNC server connect to your VNC viewer. If he's using x11vnc, it's as simple as:

<code>x11vnc -display :0 -connect foobar.dyndns.org</code>

foobar.dyndns.org should be your <a title="DynDNS homepage" href="http://www.dyndns.org/">dyndns</a> adress, pointing to your public IP. If you don't (want to) use dyndns, just replace "foobar.dyndns.org" with your public IP ("12.34.56.78" or whatever, you may look it up at <a title="What's my IP" href="http://www.whatsmyip.org/">this</a> or <a title="heise My-IP service" href="http://www.heise.de/netze/tools/ip/">this</a> page). If you're using dyndns (or something similar) you can also create a handy shortcut executing this line on potential helpees' desktops.

If the helpee is using Windows, tell him to start the TightVNC server, maybe set a password when asked to, right-click the TightVNC icon next to the clock, click "Add New Client" and enter your dyndns-adress or public IP. Consult the <a href="http://www.tightvnc.com/winst.php#start_view">TightVNC documentation</a> for further information.

Right after the helpee has sucessfully made his VNC server connect to your listening VNC viewer, you should get the familiar VNC window with his desktop on your screen.

Good luck.
