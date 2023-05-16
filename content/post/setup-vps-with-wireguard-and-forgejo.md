+++
date = "2023-05-16T20:20:20+02:00"
title = "How to set up a Linux server to host git with LFS behind a VPN"
slug = "vps-with-wireguard-and-forgejo"
tags = [ "linux", "wireguard", "VPN", "git", "LFS", "gamedev", "server", "VPS" ]
draft = true
toc = true
# ghcommentid = 13
+++

# How to set up a Linux server to host git with LFS behind a VPN

This Howto explains how to set up a Linux server that runs [SSH](https://www.openssh.com/),
[WireGuard VPN](https://www.wireguard.com/), [Forgejo](https://forgejo.org/) (a fork of
[Gitea](https://gitea.io), a web-based git forge, kinda like self-hosted Github) and a minimal
[DNS server](https://thekelleys.org.uk/dnsmasq/doc.html) so we can have an internal domain for pretty URLs.
We'll also set up automated backups and some basic self-monitoring.  
To follow it **you'll need (very) basic Linux commandline knowledge**, i.e. you should be able to navigate
the file system in a terminal, use SSH and edit textfiles with a terminal-based text editor (like nano,
joe or vim, whatever you prefer).  
It will assume that you're using **Ubuntu Server 22.04**, but it should be the same for other
(systemd-using) Debian-based Linux distributions, and reasonably similar when using other distributions.
You'll also need full **root privileges** on the system.

**Note:** You'll often need to enter commands in the shell. The following convention will be used:

`$ some_command --some argument`  
means: Enter "some_command --some argument" (without quotes) in a Linux terminal, _as **normal user**_.

`# some_command --some argument`  
means: Enter "some_command --some argument" (without quotes) in a Linux terminal, _as **root**_,
or maybe with `sudo` (you can use `$ sudo -i` to get a root-shell so you don't have to use sudo
for each command).

## Motivation

*You can skip this section if you're already convinced that this Howto is relevant for you ;-)*

[We](https://www.masterbrainbytes.com/) needed a git server with a web frontend.
It should be low-maintenance, because we're a small company that doesn't have a dedicated admin who
could regularly spend time on keeping the server up-to-date, especially when running external
software packages where updates might require more steps than a `sudo apt update && sudo apt upgrade`.

To be honest, we *would* probably just pay a service like Github or Gitlab or whatever, if they had
offers that meet our requirements at a reasonable price - but we create games (and related products),
which means we don't only have code, but also *lots* of binary data (game assets like models and textures),
even relatively small projects can easily have checkout sizes (*without history!*) of dozens of GB,
bigger projects often use several hundreds of GB or more. Nowadays Git supports that reasonably well with
[Git Large File Storage (LFS)](https://git-lfs.com/), and while several Git hosters generally support LFS,
prices for data are a bit high: Gitlab's takes $60/month for packs of 10GB of storage and 20GB
of traffic.. Githubs prices are a bit less ridiculous with "data packs" that cost $5/month
for 50GB of data and 50GB of traffic, but if you have a 40GB repo you'll already need a second
data pack if you do more than one full clone per month.. this doesn't scale that well.  
So self-hosting is a lot more attractive, as you can get a VPS (Virtual Private Server,
basically a VM running "in the cloud") with several hundreds of GB storage for < €20/month,
and S3-style "object storage" (that can be used for Git LFS data) for about €10 per 1TB per month[^hoster].

To **host Git** (and get a nice Github-ish frontend) we use [Forgejo](https://forgejo.org/), a fork
of [Gitea](https://gitea.io/). It's written in Go and is just a single executable with few external
dependencies (it needs a database, but supports [sqlite](https://sqlite.org/index.html), which
should be more than adequate for our needs). It can store the LFS data directly in the filesystem
on the servers disk, but also supports storing it in S3-compatible (external) object storage.

We work decentralized, most people at home, so the server needs to be accessible over the
internet.  
However, to keep **maintenance** low (while maintaining reasonable security), we "hide" Forgejo
behind a [Wireguard](https://www.wireguard.com/) VPN, so:  
1. The only network ports open to the internet are those of Wireguard and SSH, which both are installed
   from the standard distro packages (and thus can be easily updated) and are known to have good security
   *(arguably I could also hide SSH behind Wireguard, but I'd like to be able to get on the server
    with SSH directly even if Wireguard should fail for some reason. I'll make SSH public-key-auth-only,
    so I don't have to worry about bruteforcing attacks on the user passwords)*.
2. => We don't have to worry that Forgejo might have a vulnerability that allows unauthenticated users
   to run code (Gitlab [had such an issue a few years back](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2021-22205)),
   because only our team can access it at all, so if we forget to update Forgejo for a while,
   we'll still be safe[^security].
3. We can use plain HTTP (instead of HTTPS), because all connections to Forgejo go through the
   encrypted Wireguard tunnel, so we don't have to mess around with SSL certificates.

And of course, if we need other web-based services (like maybe a fancier bugtracker) those can be
run and protected in the same way.

## Configuring SSH for public key authentication

If you rent a (virtual private) server with Linux, you'll most probably get SSH access, likely with
a password.  
It's more secure (and possibly more comfortable) to use SSH public key authentication (which is also
what's usually used with Git). For this a cryptographic key-pair, consisting of a private and a public key,
is generated on clients (like the computer you're using) that should be able to connect to the server
with SSH

Here you've got two options: Using your default SSH key, or creating one specifically for this server.

### 1. Use your default SSH key

Check if you already have a default SSH public key, it's in `$HOME/.ssh/id_rsa.pub` (on Windows
`C:\Users\YourUserName\.ssh\id_rsa.pub`, on Linux something like `/home/yourusername/.ssh/id_rsa.pub`).

If not, you can create it by running  
`$ ssh-keygen`  
in a terminal. Confirm that you want to save
it in the default place (which should be the one mentioned above) and enter a password that will
be used to *locally* decrypt the key, for extra security.

When connecting to a SSH service that has public key authentication enabled, it will be used by default.
You might be asked for the password *of your SSH key* then, which is the one you set in `ssh-keygen`.

### 2. Creating one for this server

You can create an SSH key pair just for this server, possibly with a different password than the one
you're using for your default SSH key.

To do this, just run:  
`$ ssh-keygen -f /path/to/keyfile`  
This will create `/path/to/keyfile` (private key) and `/path/to/keyfile.pub` (public key).

You'll have to tell the SSH client to use this keyfile with `ssh -i /path/to/keyfile example-host.com`  
... **or** you create an entry in `$HOME/.ssh/config` for the host:
```sh
# my VPS for hosting git
Host example-host.com
    # or whatever user you're using for logging in
    User root
    HostName example-host.com
    IdentityFile /path/to/keyfile
```

then `$ ssh example-host.com` will automatically set the username and the keyfile

### Enabling your public SSH key on the server

Of course you need to tell the server your SSH public key so it can use it to authenticate your
connections. To do this, **on the server** edit the file `$HOME/.ssh/authorized_keys` (create it if
it doesn't exist) and add a line with the contents or the public key file from your local machine
(`$HOME/.ssh/id_rsa.pub` or `/path/to/keyfile.pub`).

Verify that this works by logging out of the server and logging in again (if you're using an SSH
key specific to this server, remember to pass the `-i /path/to/key` option to SSH).
It should ask for a password **for the key file**, like `Enter password for key '/path/to/keyfile':`,
*not* for the host (that prompt would look like `username@host password:`). Enter the password you
chose when creating the key file and you should be on the server.

If this didn't work as expected, you'll have to debug and fix that problem.

Once it works go on with the next step:

### Disable SSH login with password

Now that you can log into the server with public key authentication, logging in with a password
can be disabled, to prevent attackers from bruteforcing the password.

> **NOTE:** *If your server hoster supports creating **snapshots** of the server, now would be
> a good time to take one, so you can just restore it in case anything goes wrong here and you can't
> log in anymore (shouldn't happen if this is done correctly and you verified that logging in with
> public key authentication works, but better safe than sorry).*

As root (or with `sudo`) edit `/etc/ssh/sshd_config` and search for a line that contains
"PasswordAuthentication" and change it to `PasswordAuthentication no` - make sure to remove any `#`
characters from the start of the line as they comment it out!  
If there is no line with "PasswordAuthentication" yet, just add the `PasswordAuthentication no` line
somewhere in the middle of the config, *before* any lines that start with "Match", like "Match user asfd".  
Do the same to ensure that a `ChallengeResponseAuthentication no` line exists.

Save the file and restart the SSH server to make sure the changed config is loaded:  
`# systemctl restart sshd`

If that failed for some reason, `systemctl status sshd` should show some information on the cause.

## Setting up a WireGuard VPN server

### Install WireGuard

`# apt install wireguard-tools`  

If the Linux kernel you're using is older than 5.6 (check with `$ uname -r`), also install `wireguard-dkms`
to get the WireGuard kernel module (it's included in Linux 5.6 and newer).

### Basic setup of the server

> **NOTE:** This is a quite basic configuration of WireGuard, suitable for this particular usecase.
> It fully supports IPv6 (but here having IPv4 addresses in the VPN is sufficient) and
> can be configured in other ways than the classic "one VPN server with several clients" scenario
> used here.  
> If you've already got a wireguard connection `wg0` configured, just give it another name
> like `wg1`, so whenever this Howto mentions `wg0`, use `wg1` instead.

Wireguard requires a private and corresponding public key for the server (and also 
for each client, we'll get to that later).  
Create a directory that only root can access to store them in:  
`# mkdir /root/wireguard && chmod 700 /root/wireguard`  
`# cd /root/wireguard && umask 077`

Now use WireGuards `wg` tool with the `genkey` command to generate a new private key
(stored it in a file called `wg_privatekey.txt`):  
`# wg genkey > wg_privatekey.txt`  
and the `pubkey` command to generate the public key (`wg_publickey.txt`) from the private key:  
`# cat wg_privatekey.txt | wg pubkey > wg_publickey.txt`

The easiest way to set up a WireGuard network device (here it's called `wg0`) is creating a config
for the `wg-quick` tool.  
As root create a textfile at `/etc/wireguard/wg0.conf` with the following content:

```ini
# configuration of this server (its IP in the VPN, what port to listen on etc)
[Interface]
# the private IP the server will have in the VPN and its subnet (e.g. /24)
Address = 172.30.0.1/24
# the UDP port wireguard will listen on - 51820 is WireGuards default port
ListenPort = 51820
# the servers private key
# replace "YourPrivateKey" with the private key stored in wg_privatekey.txt
PrivateKey = YourPrivateKey
```

> **NOTE:** In WireGuard configurations (and lots of other kinds of config files and scripts),
> lines starting with `#` are comments. They're ignored by WireGuard and are meant to provide
> information to humans reading those files. In this case that's you, or other people who might
> want to modify your WireGuard configs later.

Make sure it's only readable by root (it contains your private key, after all!):  
`# chmod 600 /etc/wireguard/wg0.conf`

**`Address`** should be a
[private IPv4 address](https://en.wikipedia.org/wiki/Internet_Protocol_version_4#Private_networks)
that doesn't conflict with your LAN/WIFI at home, in the office or wherever this is going to be used.
`/24` at the end of the IP is the subnet mask of the network we're creating (equivalent to
`255.255.255.0`), meaning we can have up to 254 different IPs in the VPN (in this case 172.30.0.1
to 172.30.0.254; the first and last IPs - 172.30.0.0 and 172.30.0.255 in this example - have special
meanings); see [Wikipedia (Subnetwork)](https://en.wikipedia.org/wiki/Subnetwork) for details.
Of course you could choose a different IP and subnetwork, including one that's bigger (like a /20),
whatever suits your needs.

This is enough to get the wireguard network interface up:  
`# wg-quick up wg0`  
creates a WireGuard interface **wg0** based on the settings in /etc/wireguard/**wg0**.conf.  
You can verify that it worked with:  
`# ip address show wg0`  
the output should look like:  

```text
3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none 
    inet 172.30.0.1/24 scope global wg0
       valid_lft forever preferred_lft forever
```

That's a good start, but so far no one will be able to connect to this server, as no clients have
been configured yet.

### Configure a new client, on the client

This must be done on the client machine that's supposed to connect to the server!

This is similar to the server configuration. First you'll need to install wireguard, of course,
see [the WireGuard Installation page](https://www.wireguard.com/install/) for installers for several
operating systems including Windows.

#### ... on Windows

Start the WireGuard application, or right-click the wireguard icon next to the clock of your taskbar
and select "Manage tunnels..."

Then add an empty VPN tunnel:  
![Add empty tunnel](/images/wireguard_emptytunnel.png)

And configure it:  
![Configure tunnel](/images/wireguard_tunnelconf.png)

A new PrivateKey is automatically generated and set (and the PublicKey is set from it),
but you'll have to add the other settings shown on the screenshot (of course adjusted to your needs).
For **Name**, just pick a sensible name. Or a nonsensical one, I don't care :-p  
See the Linux section below for more explanation of the other settings.


Note that you'll need the **Public Key** later, so you can already copy it somewhere.
  
Click `Save`. You can't activate the connection yet though, this new client must first be added
to the server configuration, see below.

#### ... on Linux and similar (using wg-quick)

Like on the server, create a `/root/wireguard/` directory, make sure only root can access it and
create a private and a public WireGuard key:  
`# mkdir /root/wireguard && chmod 700 /root/wireguard`  
`# cd /root/wireguard && umask 077`  
`# wg genkey > wg_privatekey.txt`  
`# cat wg_privatekey.txt | wg pubkey > wg_publickey.txt`

Create `/etc/wireguard/wg0.conf` on the client with the following contents:

```ini
# settings for this interface 
[Interface]
# this client's private key
PrivateKey = ThisClientsPrivateKey
# the IP address this client will use in the private network
# must not be used by another client (or the server itself)
Address = 172.30.0.3/24
# configure a DNS server for a custom local domain
# only relevant on Linux, will be set in a later chapter
#PostUp = TODO

# the server we're gonna connect to
[Peer]
# public key of the *server*
PublicKey = YourServersPublicKey
# AllowedIPs is used for routing (only) that network through the tunnel
AllowedIPs = 172.30.0.0/24
# public IP or domain of the server and the port it's listening on
Endpoint = yourserver.example.net:51820
```
* The **`[Interface]`** section configures the WireGuard network interface of this client.
  It has the following settings:
    - **PrivateKey** is the private key **of this client**. On Windows this line is generated
      automatically, on Linux use the private key you just generated (in 
      `/root/wireguard/wg_privatekey.txt` on the client).
    - **Address** must be an unused address in the private network you configured as "Address"
      on the server.
      **Note** that it must have the **same subnetmask**, `/24` in my example.
    - **PostUp**  lets you set a command that's executed when the connection is established.
      Not available on Windows (unless explicitly allowing it in the registry).  
      Commented out for now because it only makes sense after the DNS chapter below.
* The **`[Peer]`** section configures the server this client will connect to:
    - **PublicKey** is the public key of the server, if you followed the instructions
      above it's saved in `/root/wireguard/wg_publickey.txt` **on the server**, so replace
      "YourServersPublicKey" with the contents of that file.
    - **AllowedIPs** is the private network reachable through this tunnel, note that it uses
      `172.30.0.0` as IP (the first IP of the subnet), which has the special meaning of representing
      that subnet. Used by WireGuard to ensure that only IPs in that network are routed through
      the tunnel.
    - **EndPoint** configures the public address and port of the WireGuard server that the client
      connects to. Replace "yourserver.example.net" (or "1.2.3.4") with the correct IP or domain.

Now the VPN connection is configured on the client, but won't work just yet, because the server
must be told about the new client first.

> **NOTE:** As the administrator of the WireGuard server, it make sense to have a copy of a 
> client configuration in a local text file, **without the PrivateKey**, as a template for future
> clients - the only things that must be adjusted per client are the **PrivateKey** and the **Address**
> (I also replace the last part of the  **Address** IP with `TODO` to make sure I don't forget to
>  set a new IP when copy&pasting it to a new client configuration).

#### ... on macOS

No idea, I don't have a mac :-p

There seems to be a WireGuard App in the [App Store](https://apps.apple.com/de/app/wireguard/id1451685025?mt=12)
and looking at [this tutorial](https://docs.oakhost.net/tutorials/wireguard-macos-server-vpn/#configuring-the-client)
I found it seems to be pretty similar to the Windows one, so you should be able to get it to work :-)

### Add new clients to the server configuration

On the **server**, open `/etc/wireguard/wg0.conf` in a text editor (as root).

At the end of the file, add the following (this example adds two clients, if you only created one,
add only one `[Peer]` section):

```ini

### List of clients that can connect to the VPN ###

# Heinrichs Windows PC
[Peer]
# replace with the real public key of the client
# (copied from the clients tunnel configuration)
PublicKey = bsiSrU3tPnu2j5qbtc+00nemvHAqClxBbyaam8=
# the IP the client gets, must be the same as in the "Address"
# in the clients config !! but with /32 at the end !!
AllowedIPs = 172.30.0.2/32
# make sure the connection stays alive, esp. if NAT routers are involved
PersistentKeepalive = 21


# Daniels Linux Laptop
[Peer]
# replace "DanielsPublicKey" with the public key of the client
# (from the clients wg_publickey.txt)
PublicKey = DanielsPublicKey
# the IP the client gets, must be the same as in the "Address"
# in the clients config !! but with /32 at the end !!
AllowedIPs = 172.30.0.3/32
# make sure the connection stays alive, esp. if NAT routers are involved
PersistentKeepalive = 21

# TODO: add more clients in the future, make sure they all use different IPs
#       and that everyone has their own [Peer] section

```

**Note** that, unlike *on* the client, **AllowedIPs** must have **`/32`** as subnet mask
(meaning all bits are masked, i.e. it only refers to this one IP), because only
traffic for that IP should be routed to that particular client[^clientsubnet].

Now you can tell WireGuard to reload the config:  
`# wg syncconf wg0 <(wg-quick strip wg0)`

.. and now the clients should be able to connect (on Windows by clicking `Activate` for the tunnel,
on Linux with `# wg-quick up wg0`).

**Note** that clients can only communicate with the server, not with each other, at least without
setting up ip forwarding on the server (which isn't done here).

`PersistentKeepalive = 21` makes sure that a (possibly empty) network packet is sent at least every
21 seconds to make sure that routers and firewalls between the client and the server don't assume
the WireGuard connection is closed when there's no real traffic, see also
[this more elaborate explanation](https://www.wireguard.com/quickstart/#nat-and-firewall-traversal-persistence).

> **NOTE:** If you're wondering why the client and the server need to know **each others public keys**,
> that's for security. When a WireGuard client connects to a WireGuard server, the server uses
> its copies of the clients public keys to identify the client (make sure the client is allowed to
> connect at all, and set client-specific options like their IP). The client on the other hand
> uses its copy of the servers public key to make sure that the WireGuard server it's connecting to
> really is the one it wants and not just an attacker who somehow redirected traffic meant for your
> WireGuard server to a server controlled by the attacker. For the general concept, see also
> [Wikipedia on Public-key cryptography](https://en.wikipedia.org/wiki/Public-key_cryptography)

### Configure the server to automatically start the connection

While you should have a working WireGuard VPN tunnel now, it won't work anymore if the server
is rebooted. So let's tell the server to automatically start the wireguard server.
Luckily the wireguard-tools Ubuntu package provides a systemd service that works with WireGuard
devices configured with a wg-quick config, so we don't have to do much.

To be sure there's no conflicts, first take the interface down:  
`# wg-quick down wg0`

Then enable the systemd service and start it:  
`# systemctl enable wg-quick@wg0.service`  
`# systemctl start wg-quick@wg0.service`

Check its state with:  
`# systemctl status wg-quick@wg0.service`

If you modify wg0.conf, instead of calling `# wg syncconf wg0 <(wg-quick strip wg0)` as shown above,
you can now also run:  
`# systemctl reload wg-quick@wg0.service`

> **NOTE:** You could do the same on Linux **clients** of course, if you want to start the `wg0` 
> connection to the server automatically at boot.

It might be a good idea to **reboot the server** and to make sure everything still works as expected
after the boot.

## A simple firewall with iptables and SSHGuard

Before setting up any more services, let's create some simple firewall rules that block all
connection attempts from the internet, except for ones to SSH and WireGuard.  
Furthermore [SSHGuard](https://www.sshguard.net/) is used to block hosts that are attacking our
SSH server.

Install SSHGuard:  
`# apt install sshguard`

Edit `/etc/sshguard/sshguard.conf` (as root) and replace the `BACKEND=...` line near the top of
the file with `BACKEND="/usr/libexec/sshguard/sshg-fw-ipset"` so SSHGuard stores the IPs that
should be blocked in an [ipset](https://linux.die.net/man/8/ipset) that can be used in iptables rules.
Save the file, then restart SSHGuard so it applies the changed config:  
`# systemctl restart sshguard.service`

> **NOTE:** *If your server hoster supports creating **snapshots** of the server, now would be
> a good time to take one, so you can just restore it in case something goes wrong with the
> firewall rules we're about to create and you lock yourself out*

By default, Ubuntu ships the [UFW](https://help.ubuntu.com/community/UFW) firewall.
This Howto uses plain [ip(6)tables](https://en.wikipedia.org/wiki/Iptables), so disable ufw[^why_iptables]:  
`# systemctl stop ufw.service`  
`# systemctl disable ufw.service`  

I suggest putting the firewall scripts into `/root/scripts/`, so create that directory.

Create one script called `firewall-flush.sh` in that directory that removes all firewall rules
and allows all connections:

```bash
#!/bin/sh

# This script resets ip(6)tables so all connections are allowed again

echo "Flushing firewall (iptables) rules"

# flush (remove) all existing rules
iptables -F
iptables -t nat -F
iptables -t filter -F
iptables -t mangle -F

# set INPUT policy to ACCEPT again
# (otherwise it'd remain at DROP and no connection would be possible)
iptables -P INPUT ACCEPT

echo ".. same for IPv6 (ip6tables) .."

# flush all existing rules
ip6tables -F
ip6tables -t nat -F
ip6tables -t filter -F
ip6tables -t mangle -F

# reset ip6tables INPUT policy to ACCEPT
ip6tables -P INPUT ACCEPT
```

Then create a second script `firewall.sh` with the actual firewall rules
(see the comments in the scripts for a little explanation of what it does).  
**Note** that you might have to modify the `WAN` network device name. It's the network device
connected to the internet - it might be called `eth0`, but names like `enp5s0` or similar
are also common. Just adjust the `WAN="eth0"` line accordingly[^devname].  
`firewall.sh`:

```bash
#!/bin/sh

# Daniels little firewall script
# Makes sure that we only accept SSH and wireguard connections
# from the internet. All other services (like http for the git tool etc)
# are only allowed via wireguard VPN (dev wg0)

# the network device connected to the internet
WAN="eth0"
# the VPN device (for connections to services not publicly exposed)
VPN="wg0"

echo "Creating IPv4 (iptables) firewall rules.."

# flush all existing rules
iptables -F
iptables -t nat -F
iptables -t filter -F
iptables -t mangle -F

# by default (as policy) allow all output, but block all input
# (further down we add exceptions that allow some kinds of connections)
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT

# Now some rules for incoming connections are added, each with iptables -A,
# so they'll be evaluated in this exact order

# allow all connections on the loopback device lo (localhost, 127.x.x.x)
iptables -A INPUT -i lo -j ACCEPT
# if for some broken reason we get packets for the localhost net that are
# are *not* from lo, drop them
# (if they're from lo, the previous rule already accepted them)
iptables -A INPUT -d 127.0.0.0/8 -j DROP

# for now, allow all incoming connections from VPN (wireguard) peers
# (*could* be limited to the ones actually needed: UDP 53 for dnsmasq,
#  TCP 22 for ssh/git, TCP 80 for http)
iptables -A INPUT -i $VPN -j ACCEPT

# SSHGuard detects SSH bruteforce attacks and adds their source IPs 
# to the sshguard4 (or sshguard6 for IPv6) ipsets. 
# So block connections from IPs in the set:
iptables -A INPUT -i $WAN -m set --match-set sshguard4 src -j DROP

# generally allow traffic for established connections
# (this includes replies to outgoing connections )
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# accept SSH connections on port 22 (unless sshguard has dropped them first)
iptables -A INPUT -i $WAN -p tcp --dport 22 -j ACCEPT
# also accept connections to the wireguard server
iptables -A INPUT -i $WAN -p udp --dport 51820 -j ACCEPT

# some useful ICMP messages that we should probably allow:
iptables -A INPUT -p icmp --icmp-type fragmentation-needed -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT # ping

echo ".. now doing (basically) the same for IPv6 (ip6tables)"

# flush all existing rules
ip6tables -F
ip6tables -t nat -F
ip6tables -t filter -F
ip6tables -t mangle -F

# by default (as policy) allow all output, but block all input
# (further down we add exceptions that allow some kinds of connections)
ip6tables -P INPUT DROP
ip6tables -P OUTPUT ACCEPT

# allow all connections on localhost (::1)
ip6tables -A INPUT -i lo -j ACCEPT
# .. but no connections that have a localhost address but are not on lo
ip6tables -A INPUT -d ::1/128 -j DROP

# Note: not creating any ip6tables rules for wireguard-internal traffic
# (on wg0), as we only use IPv4 for that private internal network

# drop all packets from IPv6 addresses that sshguard detected as attackers
ip6tables -A INPUT -i $WAN -m set --match-set sshguard6 src -j DROP

# generally allow traffic for established connections
# (this includes replies to outgoing connections )
ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# accept SSH connections on port 22 (unless sshguard has dropped them first)
ip6tables -A INPUT -i $WAN -p tcp --dport 22 -j ACCEPT
# also accept connections to the wireguard server
ip6tables -A INPUT -i $WAN -p udp --dport 51820 -j ACCEPT

# allow the ICMPv6 types required for IPv6
# (and ping, it's always useful if you can ping your server)
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT # dest unreachable
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT # packet too big
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT # time exceeded
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT # parameter problem
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT # echo request (ping)
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 133 -j ACCEPT # router solicitation
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 134 -j ACCEPT # router advertisement
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 135 -j ACCEPT # neighbor solicitation
ip6tables -A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 136 -j ACCEPT # neighbor advertisement
```

Make both scripts executable:  
`# chmod 755 /root/scripts/firewall*`

The safest way to test the firewall script is like this (executed in `/root/scripts/`):  
`# ./firewall.sh ; sleep 60 ; ./firewall-flush.sh`  
It will apply the firewall rules, then wait for 60 seconds, and then remove them again.
So you have one minute to test the rules, and if something went wrong and the rules lock
you out, you only have to wait for a minute and you can connect to the server again.

You could test if you can:
* ping the server - on your local machine run: `$ ping yourserver.example.com`  
  (replace "yourserver.example.com" with your servers domain or IP)
* create new SSH connections: `$ ssh -S none user@yourserver.example.com `  
  (replace "user" with the username you're using to normally log in to that server)  
  `-S none` makes sure that a new connection is established by disabling SSH connection sharing.
* connect with WireGuard - if a connection is currently active disable it, then enable it again
  (on Linux with `# wg-quick down wg0` and `# wg-quick up wg0`), then try to ping your server
  through wireguard (`$ ping 172.30.0.1`)

(make sure the rules are still active and haven't been flushed yet; you could of course sleep for
longer than a minute, e.g. `sleep 300` for five minutes)

You show display the current iptables rules for IPv4 by entering:  
`# iptables-save`  
and for IPv6:  
`# ip6tables-save`

(you could also use `iptables -L -v` or `ip6tables -L -v` if you find that output more readable)

If this all works, create a systemd service to ensure that the firewall script is automatically
run on boot.

Create a file `/etc/systemd/system/firewall.service` with the following contents:  

```systemd
## Systemd service file for Daniels little firewall script
## makes sure that the firewall (iptables) rules are set on boot
[Unit]
Description=Firewall
Requires=network.target
After=network.target
 
[Service]
User=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/scripts/firewall.sh
ExecStop=/root/scripts/firewall-flush.sh
 
[Install]
WantedBy=multi-user.target
```

Enable and start the firewall service:  
`# systemctl enable firewall.service`  
`# systemctl start firewall.service` 

Check with `# iptables-save` if the iptables rules have been created, reboot, make sure you still get
on the server (and the iptables rules are still/again there).

*By the way:* If it takes a while after boot until WireGuard is started, the systemd `network-online.target`
might be hanging (the wg-quick service waits for that). You can check this by executing  
`# systemctl status systemd-networkd-wait-online.service`  
If the output says something about a timeout (instead of "Finished Wait for Network to be Configured."),
execute  
`# networkctl`  
If the state of a device is "configur*ing*" instead of "configur*ed*" or "unmanaged", that explains
why `systemd-networkd-wait-online.service` didn't succeed (and then gave up after a timeout so
services that wait for it at least start *eventually*).  
At least on our server the problem was that for some reason systemd's *networkd* doesn't properly
finish configuring a device if **IPv6 is disabled**, as it is the default on a Contabo VPS. 
Contabo provides a command that can be executed to enable IPv6 *(but this is Contabo-specific, if
other hosters also disable IPv6 by default and you run into the same problem, refer to their documentation!):*  
`# enable_ipv6`

## Setting up dnsmasq as DNS server for a local domain

This step will set up [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) for the local
`example.lan` domain, so Forgejo will be reachable (in the VPN) under `http://git.example.lan`.

This isn't *strictly* needed, at least if you only host one http service on the server (or use different
ports for different services) - then you could access them with `http://172.30.0.1` or
`http://172.30.0.1:3000` - but it's definitely nice to have.

Of course you can use a different domain, like yourcompany.lan, but I think that using the nonexistant
.lan top-level-domain is a good idea for this purpose[^dotlan]. Alternatively you could use a subdomain of
a real domain you have, like vpn.yourcompany.com (and then maybe git.vpn.yourcompany.com), but to
be honest I'm not completely sure how that would be set up properly.

We'll install  and configure it to only listen
on wg0 and to answer queries for `*.example.lan`.

Install the dnsmasq package:  
`# apt install dnsmasq`

Stop its systemd service, as its standard configuration clashes with systemd-resolved (and is not
what we need anyway):  
`# systemctl stop dnsmasq.service`  

> **NOTE:** If you're already using dnsmasq on your server, or want to use it for something else
> as well, you can create alternative instance configurations as described in the
> [systemd howto](https://thekelleys.org.uk/gitweb/?p=dnsmasq.git;a=blob;f=debian/systemd_howto;hb=HEAD)
> included in the dnsmasq debian/Ubuntu package (which relies on the dnsmasq systemd service as
> defined in that package) to run multiple instances of dnsmasq at once.
> For the sake of simplicity, this Howto assumes that's not needed and uses the standard config.

As root, edit `/etc/default/dnsmasq`  
* Add the line `DOMAIN_SUFFIX="example.lan"` (or "yourcompany.lan" or whatever you want to use);
  make sure it's the only not commented-out line that sets DOMAIN_SUFFIX
* Uncomment the `IGNORE_RESOLVCONF=yes` line (so it's in there **without** a `#` before it)  
* Uncomment (or add) the `DNSMASQ_EXCEPT="lo"` line to ensure that dnsmasq will not be used as the
  systems default resolver.

Save the file and now edit `/etc/dnsmasq.conf` - in its initial states, all lines should be commented
out (begin with `#`).

The following lines should end up in dnsmasq.conf:

```cfg
# don't use resolv.conf to get upstream DNS servers
# in our case, don't use any upstream DNS servers,
# only handle example.lan and fail for everything else
# (VPN clients shouldn't get resolve their normal/global domains here)
noresolv
# answer requests to *.example.lan from /etc/hosts
local=/example.lan/
# only listen on the wireguard interface
interface=wg0
# only provide DNS, no DHCP
no-dhcp-interface=wg0
# This option (only available on Linux AFAIK) will make sure that:
# 1. like with bind-interfaces, dnsmasq only binds to wg0 (instead of
#    binding to the wildcard address on all devices and then only
#    replying to requests on the requested device)
# 2. this works even with interfaces that might dynamically appear
#    and disappear, like VPN devices
bind-dynamic
# this (and the next option) expands simple hosts like "horst"
# from /etc/hosts to "horst.example.lan"
expand-hosts
domain=example.lan
```

*(You could also delete or rename `/etc/wireguard.conf`and create a fresh one that only contains
the lines shown above)*

Next edit `/etc/hosts`. dnsmasq uses hosts configured in that file to answer DNS requests.
Add the lines

```text 
172.30.0.1      www.example.lan example.lan
172.30.0.1      git.example.lan
```

(if you want to use other aliases for other services add them as well, for example   
`172.30.0.1 openproject.example.lan`)

Now start dnsmasq again:  
`# systemctl start dnsmasq.service`

### Configure clients to use the DNS server

The VPN clients must be told to use the DNS server you just set up.

#### Linux and other Unix-likes

On **Linux** distros that use **systemd-resolved** (are there other Unix-likes that use systemd?),
replace the `#PostUp = TODO` line line in the client's `/etc/wireguard/wg0.conf` with:  
`PostUp = resolvectl dns %i 172.30.0.1; resolvectl domain %i ~example.lan; resolvectl default-route %i false`
(yes, that must all go in one line to work!).  
* `resolvectl dns %i 172.30.0.1` sets 172.30.0.1 as the network-interface-specific DNS server
  (Note that `%i` will be replaced with the interface name by `wg-quick`)
* `resolvectl domain %i ~example.lan` sets `example.lan` as the default domain for that interface,
  and the `~` prefix makes it a "routing (-only) domain", which means that all requests to that
  domain (and its subdomains), in this case `*.example.lan`, should go to the DNS server(s) configured
  for this interface.
* `resolvectl default-route %i false` means that this interfaces DNS server should *not* be used
  as the default DNS server for DNS requests for domains not explicitly configured as "routing domains".
  This ensures that the dnsmasq running on `172.30.0.1` will *only* be used to resolve `example.lan`,
  `git.example.lan`, `www.example.lan` etc, not any other domains like `blog.gibson.sh`
  or `raspi.myhome.lan` or `xkcd.com`.
* See [man resolvectl](https://www.freedesktop.org/software/systemd/man/resolvectl.html),
  [man systemd.network](https://www.freedesktop.org/software/systemd/man/systemd.network.html)
  and [this article](https://systemd.io/RESOLVED-VPNS/) for more information.

For this setting to take effect, you'll have to disconnect and reconnect the wireguard connection
on the client (`# wg-quick down wg0 && wg-quick up wg0`)

On *other distributions or operating systems* (that **don't use systemd-resolved**),
this might be a bit harder, and depend on *what* they're using *exactly*, anyway.
Some of them use the `resolvconf` package/tool to manage `/etc/resolv.conf`, but as far as I know
and according to [this serverfault.com answer](https://serverfault.com/questions/872109/resolv-conf-multiple-dns-servers-with-specific-domains), it only supports setting *global* DNS servers
(that are used for all domains), and a suggested workaround is to install dnsmasq or similar on the
client and configure dnsmasq to use `172.30.0.1` for `example.lan` (and another DNS server for 
all other requests).  
A simple workaround if you don't want to set up your own local caching DNS server (like dnsmasq):
Edit `/etc/hosts` *on the client* and add the hosts you need, like  
`172.30.0.1 git.example.lan www.example.lan whateverelse.example.lan`  
Of course it means that if another subdomain is added on the server, you also need to add it locally,
but depending on your usecase this might be the path of least resistance...

> **NOTE:** wg-quick allows setting a `DNS = 1.2.3.4` option under `[Interface]`.  
> Even with a default search domain, like `DNS = 172.30.0.1, example.lan`.  
> DO NOT USE THAT!  
> It sets the global DNS server, meaning, it will be used for *all* your DNS requests,
> not just the ones for `example.lan` - that's most probably not what you want, and when
> dnsmasq is configured like described here it won't even work (as it won't know how to resolve
> other domains like `gibson.sh` or `google.com`)!  
> Furthermore, it only works with resolvconf, not systemd-resolved or Windows (AFAIK).

#### Windows

On Windows, WireGuard doesn't support PostUp scripts (unless explicitly enabled in the registry),
because apparently there are bigger security implications than on Linux.

So instead of setting the DNS server when connecting and removing it when disconnecting, just
configure it once and leave it configured, by entering the following command in an
**Administrator** PowerShell:  
`Add-DnsClientNrptRule -Namespace 'example.lan','.example.lan' -NameServers '172.30.0.1'` 

As this explicitly sets the DNS server only for `*.example.lan`, it shouldn't hurt much 
that the server isn't reachable when the WireGuard connection is down - it just means that the DNS
request will timeout and fail in that case. .

> **NOTE:** If you want to remove the rule again, entering  
> `Get-DnsClientNrptRule` in an (Administrator) PowerShell will list rules
> including their "Name" identifiers, and  
> `Remove-DnsClientNrptRule -Name "{6E6B2697-2922-49CF-B080-6884A4E396DE}"`
> deletes the rule with that identifier.

#### macOS

Again, I can't test this myself because I don't have a Mac, but I found
[a blog post](https://stanislas.blog/2020/02/different-nameservers-domains-macos/)
that looks relevant.

The gist of it (in case it disappears in the future):
Create a textfile `/etc/resolver/example.lan` that contains the line 
`nameserver 172.30.0.1`

Apparently this doesn't work for all tools though (not for `dig`, for example), but according to
the blog post,
`$ scutils --dns` can be used to check if the setting was applied, and `ping` should also work. 
The blog posts suggests trying a reboot in case it doesn't work at all.  

I hope that it works with `git`, `git-lfs` and your web browser - if you try it,
please let me know how it went in a comment! :-)

#### Testing the DNS server

Now on the client you should be able to ping the new domains (if the WireGuard connection is active):  
`$ ping example.lan`  
`$ ping git.example.lan`

## Setting up nginx as a reverse http proxy

[nginx](https://nginx.org/) will be used as a webserver/reverse proxy, that makes
`http://www.example.lan` and `http://git.example.lan` and possibly other domains available,
redirecting them to other services based on the subdomain used (for example, the real git server, Forgejo, 
will listen at port 3000/tcp, instead of the standard http port 80/tcp, and [OpenProject](https://www.openproject.org/), that nginx could provide at `http://openproject.example.lan`, listens on port 6000/tcp).

Install it with:  
`# apt install nginx-light`  
(at least for the purposes documented in this tutorial, you won't need the additional features
provided by the full nginx package)

The Debian/Ubuntu configuration of nginx (maybe other distros do the same) splits up the site-specific
nginx-configuration into one little config per site; they're configured in `/etc/nginx/sizes-available/*.conf`,
to actually enable a site, its config is symlinked to `/etc/nginx/sites-enabled/`.  

By default, only `/etc/nginx/sites-available/default` exists (and is enabled), it shows the
static page from `/var/www/html/index.nginx-debian.html` (or index.htm or index.html in the same directory).
I'd suggest keeping it like this; you could edit that default index.html to provide links to the pages
with content, like `http://git.example.lan` (once they exist..).

You should however make one little change to `/etc/nginx/sites-available/default`:
Replace the `listen 80 default_server;` line with `listen 172.30.0.1:80 default_server;` to make
sure that nginx only listens on the WireGuard IP and not on all IPs.

As we'll soon install Forgejo, we can already configure the site for it in nginx by creating
`/etc/nginx/sites-available/git` with the following content:

```nginx
server {
    # should be reachable on port 80, only on WireGuard IP
    listen 172.30.0.1:80;
    # the domain that's used (=> will be available at http://git.example.lan)
    server_name git.example.lan;
    # nginx defaults to a 1MB size limit for uploads, which
    # *definitely* isn't enough for Git LFS.
    # 'client_max_body_size 300m;' would set a limit of 300MB
    # setting it to 0 means "no limit"
    client_max_body_size 0;

    location / {
        # Forgejo will listen on port 3000, on localhost
        proxy_pass http://127.0.0.1:3000;
        # http proxy header settings that are required 
        # according to the Forgejo/Gitea documentation:
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then create a symlink in `/etc/nginx/sites-enabled/`:  
`# ln -s /etc/nginx/sites-available/git /etc/nginx/sites-enabled/git`

and restart the nginx service:  
`# systemctl restart nginx.service`

Now if you open a browser on a desktop PC connected to the server with WireGuard (that
has the DNS server configured as described in the previous chapter), you should be able to open
http://example.lan and http://git.example.lan (though the latter will show an error page because
Forgejo isn't installed yet).  
**Note** that you might have to actually type the whole URL including `http://` in the browser,
because nowadays browsers only open URLs without protocol (http://) for known top level domains,
otherwise they'll open a web search using "git.example.lan" or whatever you typed in as search query...

As mentioned before, this uses plain HTTP, no HTTPS encryption, because:
1. That would be a PITA to set up for a custom/local domain (you'd have to create your own pseudo-CA
   and import that at every client)
2. The connection to the server is already encrypted with WireGuard, so it already is secure
   (even if your webbrowser may claim otherwise because it doesn't know that detail)
3. Not only is additional HTTPS encryption unnecessary, it'd also be additional overhead, both
   on the server and client CPUs that have to encrypt/decrypt the traffic twice and on the network
   bandwidth, as both WireGuard and SSL/TLS (used by HTTPS) add their own metadata to each packet,
   *in addition* to the http message you actually want to send/receive.

## Setting up dma as sendmail implementation

It's useful for a server to be able to send E-Mails.  
That can be used to tell you that an error happened, that updates are available, or it can just
be notifications from Forgejo or other software about new (comments on) bug reports, merge requests etc.

The standard way to do this on Unix-like systems is the /usr/sbin/sendmail tool; originally part of
a [fully fledged mailserver](https://en.wikipedia.org/wiki/Sendmail), but nowadays several different
programs implement that functionality, including minimal ones that don't implement SMTP themselves
but just send a mail through a configured external SMTP server.

This shows how to set up such a simple sendmail replacement, specifically
[dma](https://github.com/corecode/dma), as running a full mailserver isn't exactly straightforward
and also is against the idea of exposing as few possibly vulnerable services on this server
to the internet as possible.

So the idea is that you already have some E-Mail account that provides SMTP access (a freemailer,
your company mailserver, whatever), ideally with a special noreply-address just for this server.

Of course the first step is to install dma:  
`# apt install dma`

On Debian and Ubuntu, after the installation, you'll automatically be asked to configure dma
(with your mailservers login data etc), just follow the steps.  
Users of other distros (or Debian/Ubuntu users running into problems) will probably find the
[dma article in the ArchWiki](https://wiki.archlinux.org/title/Dma) helpful.

**TODO:** hints for apt configuration steps?

> **NOTE:** In case the E-Mail account you want to use is from **GMail** (or ~~Google Apps~~
>  ~~G Suite~~ Google Workspace), setting this up is a bit more painful, as by default Google
> doesn't support standard SMTP login anymore, but only OAuth2 based login (which is not supported
> by dma or other similar tools that I know of). It requires setting up an "App Password", see
> [the Google documentation for that](https://support.google.com/accounts/answer/185833?hl=en)
> or [this tutorial from Mailreach](https://help.mailreach.co/en/article/how-to-connect-a-gmail-google-workspace-account-to-mailreach-with-an-app-password-ulwj00/)
> (though note that Google UI has changed slightly since it was created, to get to the 
>  screen to create an App Password you currently need to click *Manage your Google Account
> -> Security -> How you sign in to Google -> 2-Step Verification* and select "App Passwords" there).  
> Also potentially useful: 
> [This article](https://pawait.africa/blog/googleworkspace/how-to-set-up-a-no-reply-email-with-a-custom-rejection-message-in-google-workspace/)
> on turning a Google-hosted E-Mail address into a No-Reply address that rejects mails sent to it.
> (Note that it might take 15 minutes or so until that rejection rule is in effect)

### Testing the sendmail command

Sending a mail on the commandline or a script with sendmail is easy:
It the receiver addresses are commandline arguments and the mail subject and text is read from stdin.

So create a textfile like this:
```text
Subject: This is a testmail!

This is the body of the test mail.
It's plain text.
You can probably somehow send HTML mails, but
1. I don't know how
2. Those suck anyway

Kind regards,
Your Server.
```

and then send the mail with:  
`# sendmail name@example.com othername@example.com < textfile_with_mail.txt`

The log files `/var/log/mail.err` and `/var/log/mail.log` help debugging mail issues.

## TODO: Setting up Forgejo for git hosting

TODO: install basically following https://docs.gitea.io/en-us/installation/install-from-binary/
(adapted for forgejo), adjust its config (app.ini) (higher timeouts to allow bigger uploads and migrations,
only listen on VPN IP, tell it to use sendmail, etc)

### Local storage vs. object storage for LFS

migrate LFS from local storage to S3-like object-storage:  
`$ sudo -u git forgejo migrate-storage -t lfs -c /etc/forgejo/app.ini -s minio --minio-endpoint endpoint-url.com --minio-access-key-id YOUR_ACCESS_KEY_ID --minio-secret-access-key YOUR_SECRET_ACCESS_KEY --minio-bucket gitea --minio-use-ssl -w /var/lib/forgejo/`

migrate from S3-like object-storage back to local:  
`$ sudo -u git forgejo migrate-storage -t lfs -c /etc/forgejo/app.ini -s local -p /var/lib/forgejo/data/lfs -w /var/lib/forgejo/`

## TODO: Backups with restic

TODO: setting up restic, link to docs for setting up rclone (for google drive),
pg_basebackup? (maybe only if I also describe OpenProject here?)

Suggested backup script (TODO: make lines fit in blog):

```bash
#!/bin/bash

export RESTIC_REPOSITORY="TODO_YOUR_RESTIC_REPO"
export RESTIC_PASSWORD_FILE=/root/backup/.restic-pw.txt

# who will get an e-mail if some part of the backup has an error?
# uses the "sendmail" command
WARN_MAIL_RECP=("foo@bar.example" "fu@fara.example")
# NOTE: if you don't want any emails sent, use an empty list, like in the next line
#WARN_MAIL_RECP=()

NUM_ERRORS=0

mytime() {
	date +'%R:%S'
}

checklastcommand() {
	if [ $? != 0 ]; then
		NUM_ERRORS=$(($NUM_ERRORS+1))
		echo "$*"
	fi
}

backupallthethings() {
	echo -e "Running Backup at $(date +'%F %R:%S')\n"
	
	echo "$(mytime) Backing up /root/ and /etc/"

	# let's backup all of /etc/, it's just a few MB and may generally come in handy
	# (also all of /root/)
	restic backup --exclude /root/.cache/ /root/ /etc/
	checklastcommand "ERROR: restic failed backing up /root/ and /etc"


	##### Forgejo #####

	echo "$(mytime) Backing up Forgejo"

	# TODO: somehow check if someone is currently pushing before stopping the service?

	# flush forgejos queues
	su -l git -c "forgejo -c /etc/forgejo/app.ini -w /var/lib/forgejo manager flush-queues"
	checklastcommand "ERROR: Flushing forgejo queues failed!"

	# stop the service, so we backup a consistent state
	systemctl stop forgejo
	checklastcommand "ERROR: Stopping forgejo service failed!"

	# Note: we're using forgejo with sqlite, so this also backs up the database
	restic backup /var/lib/forgejo/
	checklastcommand "ERROR: backing up /var/lib/forgejo failed!"

	# we're done backing up forgejo, start the service again
	systemctl start forgejo
	checklastcommand "ERROR: Starting forgejo service failed!"


	##### OpenProject #####

	# based on: https://www.openproject.org/docs/installation-and-operations/operation/backing-up/
	# and:      https://www.openproject.org/docs/installation-and-operations/operation/restoring/
	# (meaning, the restore instructions should work with this data, except you'll copy the directories 
	#  from the backup instead of extracting them from a tar.gz)

	echo "$(mytime) Backing up OpenProject"

	systemctl stop openproject
	checklastcommand "ERROR: Stopping OpenProject service failed!"

	[ -e /tmp/postgres-backup/ ] && rm -r /tmp/postgres-backup/
	mkdir /tmp/postgres-backup
	chown postgres:postgres /tmp/postgres-backup
	
	echo "$(mytime) .. dumping PostgreSQL database for OpenProject backup"
	
	# this line is like described in the openproject docs
	su -l postgres -c "pg_dump -U postgres -d openproject -x -O > /tmp/postgres-backup/openproject.sql"
	checklastcommand "ERROR: pg_dump for openproject.sql failed!"
	
	# this is just to be double-sure, so we have a backup of all postgres tables, not just openproject
	# (mostly redundant with openproject.sql, but whatever, it's not that big..)
	su -l postgres -c "pg_dumpall > /tmp/postgres-backup/all.sql"
	checklastcommand "ERROR: pg_dump for all.sql failed!"

	echo "$(mytime) .. backing up OpenProject files"

	restic backup /var/db/openproject/files/ /tmp/postgres-backup/
	checklastcommand "ERROR: backing up OpenProject"

	# Note: we don't manage git/svn repos with openproject, so those steps are missing
	# also: /etc/openproject/ is backed up as part of /etc/ above

	service openproject start
	checklastcommand "ERROR: Starting OpenProject service failed!"


	# TODO: rotate backups by forgetting old ones, with restic forget --keep-within 1y ?
	# TODO: remove unreferenced data with restic prune ?
	# TODO: maybe only do that occasionally, on sundays?

	echo -e "$(mytime) Backup done!\n"
}

[ -e /root/backup/backuplog.txt ] && mv /root/backup/backuplog.txt /root/backup/backuplog-old.txt
backupallthethings 2>&1 | tee /root/backup/backuplog.txt

if [ $NUM_ERRORS != 0 ]; then
	echo "$NUM_ERRORS errors during backup!"

	# if the list of mail recipients isn't emtpy, send them a mail about the error
	if [ ${#WARN_MAIL_RECP[@]} != 0 ]; then
		echo -e "Subject: WARNING: $NUM_ERRORS errors happened when trying to backup $(hostname)!\n" > /tmp/backuperrmail.txt
		echo -e "Please see log below for details\n" >> /tmp/backuperrmail.txt
		cat /root/backuplog.txt >> /tmp/backuperrmail.txt
		sendmail ${WARN_MAIL_RECP[@]} < /tmp/backuperrmail.txt
	fi
fi

```

TODO: cronjob to run backup every night

## Thanks

Thank you for reading this, I hope you found it helpful!

Thanks to [my employer](https://www.masterbrainbytes.com/) for letting me turn the documentation
for setting up our server into a proper blog post!

Thanks to [Yamagi](https://www.yamagi.org//) for proofreading this and answering my stupid questions
about server administration :-)

<!-- Below: Footnotes -->

[^hoster]: As a **server** we chose the [Contabo](https://contabo.com/) "Cloud VPS M" for €10.49/month,
    which has more CPU power and RAM than we need, a 400GB SSD, and supports snapshots (their "Storage VPS"
    line, that has even more storage but less CPU power and RAM, doesn't), which seems pretty useful to
    easily restore the system if an update goes wrong or similar. They also allow upgrading to a bigger
    VPS (with more CPU, RAM and storage) later without having to reinstall (unless you switch between
    normal VPS and "Storage VPS").  
    Furthermore, they offer S3-compatible Object Storage with unlimited traffic for €2.49 per 250GB per month,
    which is *very* cheap. Unfortunately we found the performance of the Contabo Object Storage unsatisfying,
    especially uploading was a bit slow: Usually between 2.5 and 4.5 MByte/s, but sometimes below 1 MB/s,
    for the whole upload duration of ~1GB file.. I hope this improves in the future, for now the "SSD"
    storage of the VPS is big enough for our usecase, so we use that - only if we end up needing
    more than 3TB storage their available VPSs stop scaling and we'll have to look more seriously at
    their Object Storage offerings..  
    Either way this is *not* an endorsement for Contabo, we haven't used them for long enough to judge
    the overall quality of their service, and this Howto should work with any Linux server (VPS or dedicated).
    FWIW, the performance of the VPS itself has been fine so far.  
    Some other low-cost hosters I have at least a little (positive) experience with include
    [Hetzner](https://www.hetzner.com/) (they offer dedicated servers for < €50/month)
    and [vultr](https://www.vultr.com/) (they also offer cheap S3-compatible Object Storage, but 
    I don't know if their performance is better than Contabos..).  
    I can absolutely **not** recommend OVH, as their customers had to learn 
    [the hard way](https://blocksandfiles.com/2023/03/23/ovh-cloud-must-pay-damages-for-lost-backup-data/)
    that OVH data centers are built out of wood and backups are stored in the same building as the
    backed up servers, so if a fire breaks out, it burns well and both the servers and the backups
    get destroyed.

[^security]: At least "reasonably safe". There is no total security. It's possible that OpenSSH, WireGuard
    or the Linux kernels network stack have unknown security vulnerabilities that an attacker could
    exploit to get onto your server. It's also possible that your hosters infrastructure gets
    compromised and attackers get access to the servers (via hypervisor for VPS, or remote consoles
    for dedicated servers, or even physically by breaking in).  
    And of course it's possible (I'd even say more likely than the scenarios mentioned before) that
    someone hacks *your* PC and gets access to the server and/or your git repos that way.  
    Anyway, if you follow this guide (and hopefully keep at least the Linux kernel, WireGuard and
    OpenSSH up to date), your data will be *a lot* safer than it would be if you exposed webservices
    (instead of just WireGuard) to the internet.  

[^clientsubnet]: I've never done this, but it might be possible to give a client some more
    IPs with a different subnet mask, but that's not useful for this usecase and you'd still have to
    make sure that there's no overlaps with IPs assigned to other clients.

[^why_iptables]: If you're wondering why I'm using iptables and not UFW or
    [nftables](https://netfilter.org/projects/nftables/), the answer is simple and boring:
    I'm not familiar with UFW or nftables, but I'm familiar with iptables, so using iptables
    was easiest for me `¯\_(ツ)_/¯`. If you're more familiar with an alternative, feel free to
    use that to create equivalent rules.

[^devname]: If you're not sure what the network device on your server is called, run `$ ip address`
    in the terminal. It will list all network devices (including loopback `lo` and your WireGuard
    device `wg0` if it's currently up). The device with the public internet IP that you're also
    using to connect to the server via SSH/WireGuard is the one you need.

[^dotlan]: Sometimes using a custom top level domain (TLD) is discouraged, because (unlike a few years back)
    nowadays, with enough money, one can register arbitrary TLDs that don't exist yet.  
    However, .lan is relatively widely used for this purpose, for example by OpenWRT, and
    <https://icannwiki.org/Name_Collision> shows that ICANN is aware that letting someone register
    .lan would be a bad idea. Furthermore, there even is an RFC that *almost* recommends using .lan,
    so I think it should be safe ("almost" as in [*"We do not recommend use of unregistered top-level
    at all, but should network operators decide to do this, the following top-level domains have been
    used on private internal networks (...) for this purpose: .intranet, .internal, .private, .corp,
    .home, **.lan**"*](https://www.rfc-editor.org/rfc/rfc6762.html#appendix-G)).  
    Do **not** use **.local**, it's [reserved for multicast DNS / zeroconf (avahi, bonjour)](https://en.wikipedia.org/wiki/.local)
    and using it as a TLD for normal DNS just causes headaches (will need explicit configuration on
    many clients to work, because by default they assume that it's mDNS-only).
