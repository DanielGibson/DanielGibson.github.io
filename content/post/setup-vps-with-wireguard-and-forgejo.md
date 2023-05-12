+++
date = "2023-05-11T20:20:20+02:00"
title = "How to set up a Linux server to host Forgejo (gitea-fork) behind a WireGuard VPN"
slug = "vps-with-wireguard-and-forgejo"
tags = [ "linux", "wireguard", "VPN", "git", "LFS", "gamedev", "server", "VPS" ]
draft = true
toc = true
# ghcommentid = 13
+++

# How to set up a Linux server to host Forgejo (gitea-fork) behind a WireGuard VPN

This HowTo explains how to set up a Linux server that runs SSH, WireGuard, Forgejo (a web-based
git forge, kinda like self-hosted Github) and a minimal DNS server so we can have an internal domain
for pretty URLs. I'll also set up automated backups and some basic self-monitoring.  
To follow it **you'll need (very) basic Linux commandline knowledge**, i.e. you should be able to navigate
the file system in a terminal, use SSH and edit textfiles with a terminal-based text editor (like nano,
joe or vim, whatever you prefer).  
It will assume that you're using **Ubuntu Server 22.04**, but it should be the same for other
(systemd-using) Debian-based Linux distributions, and reasonably similar when using other distributions.
You'll also need full **root privileges** on the system.

**Note:** This article often requires you to enter commands in the shell. I will the following convention:

`$ some_command --some argument`  
means: Enter "some_command --some argument" (without quotes) in a Linux terminal, _as **normal user**_.

`# some_command --some argument`  
means: Enter "some_command --some argument" (without quotes) in a Linux terminal, _as **root**_,
or maybe with `sudo` (you can use `$ sudo -i` to get a root-shell so you don't have to use sudo
for each command).

## Motivation

*You can skip this section if you're already convinced that this HowTo is relevant for you ;-)*

We needed a git server with a web frontend. It should be low-maintenance, because we're a small
company that doesn't have a dedicated admin who could regularly spend time on keeping the server
up-to-date, especially when running external software packages where updates might require more
steps than a `sudo apt update && sudo apt upgrade`.

To be honest, we *would* probably just pay a service like Github or Gitlab or whatever, if they had
offers that meet our requirements at a reasonable price - but we create games (and related products),
which means we don't only have code, but also *lots* of binary data (game assets like models and textures),
even relatively small projects can easily have checkout sizes (*without history!*) of dozens of GB,
bigger projects often use several hundreds of GB or more. Nowadays Git supports that reasonably well with
[Git Large File Storage (LFS)](https://git-lfs.com/), and while several Git hosters generally support LFS,
prices for data are a bit high: Github sells "data packs" that cost $5/month for 50GB of data and 50GB
of traffic, so if you have a 40GB repo you can only do one full clone per month or you need a second
data pack.. this doesn't scale that well. Gitlab's price is even more ridiculous: $60/month for packs
of 10GB of storage and 20GB of traffic...  
So self-hosting is a lot more attractive, as you can get a VPS (Virtual Private Server,
basically a VM running "in the cloud") with several hundreds of GB storage for < €20/month,
and S3-style "object storage" (that can be used for Git LFS data) for about €10 per 1TB per month[^hoster].

To **host Git** (and get a nice Github-ish frontend) we use [Forgejo](https://forgejo.org/), a fork
of [Gitea](https://gitea.io/). It's written in Go and is just a single executable with few external
dependencies (it needs a database, but supports [sqlite](https://sqlite.org/index.html), which
should be more than adequate for our needs). It can store the LFS data directly in the filesystem
on the servers disk, but also supports storing it in S3-compatible (external) object storage.

We work decentralized, most people in their own home, so the server needs to be accessible over the
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
   because only our team can access it at all, so if we forget to update Forgejo for a while, we'll still be safe.
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

If not you can create it by running `ssh-keygen` in a terminal. Confirm that you want to save
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

Save the file and restart the SSH server to make sure the changed config is loaded:  
`# systemctl restart sshd`

If that failed for some reason, `systemctl status sshd` should show some information on the cause.

## Setting up a WireGuard VPN server

### Install WireGuard

`# apt install wireguard-tools`  

If the Linux kernel you're using is older than 5.6 (check with `$ uname -r`), also install `wireguard-dkms`
to get the WireGuard kernel module (it's included in Linux 5.6 and newer).

### Basic setup of the server

You will need a private and corresponding public key for WireGuard for the server (and also 
for each client, we'll get to that later).  
Create a directory that only root can access to store them in:  
`# mkdir /root/wireguard && chmod 700 /root/wireguard`  
`# cd /root/wireguard && umask 077`

Now use WireGuards `wg` tool to generate private key (stored it in a file called `wg_privatekey.txt`):  
`# wg genkey > wg_privatekey.txt`  
and to generate the public key (stored in `wg_publickey.txt`) from the private key:  
`# cat wg_privatekey.txt | wg pubkey > wg_publickey.txt`

The easiest way to set up a WireGuard network device (here it's called `wg0`) is creating a config
for the `wg-quick` tool.  
As root create a textfile at `/etc/wireguard/wg0.conf` with the following content:

```ini
# configuration of this server (its IP in the VPN, what port to listen on etc)
[Interface]
# the IP the wireguard device will have in the VPN - you can use a different
# one of course, but make sure it's a private IP and subnet that are unused
# in the networks you're usually in
Address = 172.30.0.1/24
# the UDP port wireguard will listen on - this is WireGuards default port
ListenPort = 51820
# replace "YourPrivateKey" with the private key stored in wg_privatekey.txt
PrivateKey = YourPrivateKey
```

As mentioned in the comment, `Address` should have a
[private IPv4 address](https://en.wikipedia.org/wiki/Internet_Protocol_version_4#Private_networks)
that doesn't conflict with your LAN/WIFI at home, in the office or wherever this is going to be used.
`/24` at the end of the IP is the subnet mask of the network we're creating (equivalent to `255.255.255.0`),
meaning we can have up to 254 different IPs in the VPN (in this case 172.30.0.1 to 172.30.0.254;
172.30.0.0 and 172.30.0.255 are reserved); see [Wikipedia (Subnetwork)](https://en.wikipedia.org/wiki/Subnetwork)
for details. Of course you could choose a different IP and subnetwork, including one that's bigger
(like a /20), whatever suits your needs.

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

### Configure a client, on the client

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
# Replace "ThisClientsPrivateKey" with the private key you just
# generated *on this client* (in /root/wireguard/wg_privatekey.txt)
PrivateKey = ThisClientsPrivateKey
# the IP address this client will use in the private network
# must not be used by another client (or the server itself)
Address = 172.30.0.3/24
# configure a DNS server for a custom local domain
# only relevant on Linux, will be explained in another chapter below
#PostUp = resolvectl dns %i 172.30.0.1; resolvectl domain %i yourcompany.lan

# the server we're gonna connect to
[Peer]
# public key of the *server*
PublicKey = YourServersPublicKey
# AllowedIPs is used for routing (only) that network through the tunnel
AllowedIPs = 172.30.0.0/24
# public IP or domain of the server and the port it's listening on
Endpoint = yourserver.example.net:51820
```

* **PrivateKey** is the private key **of this client**. *(On Windows this line is generated automatically)*
* **Address** must be an unused address in the private network you configured as "Address" on the server.
  Note that it must have the same subnetmask, `/24` in my example.
* **PostUp**  a command that's executed when the connection is established. Commented out for now
  because it only makes sense after the DNS chapter below.
* **PublicKey** (under `[Peer]`) is the public key of the server, if you followed the instructions
  above it's saved in `/root/wireguard/wg_publickey.txt` **on the server**, so replace
  "YourServersPublicKey" with the contents of that file.
* **AllowedIPs** is the private network reachable through this tunnel, note that it uses `172.30.0.0`
  as IP (the first IP of the subnet), which has the special meaning of representing that subnet.
  Used by WireGuard to ensure that only IPs in that network are routed through the tunnel.
* **EndPoint** configures the public address and port of the WireGuard server that the client connects to.
  Replace "yourserver.example.net" (or "1.2.3.4") with the correct IP or domain.

Now the VPN connection is configured on the client, but won't work just yet, because the server
must be told about the new client first.

### Add new clients to the server configuration

On the **server**, open `/etc/wireguard/wg0.conf` as root in an editor again.

At the end of the file, add the following (this example adds two clients, if you only created one,
add only one `[Peers]` section):

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

Now you can tell WireGuard to reload the config:  
`# wg syncconf wg0 <(wg-quick strip wg0)`

.. and now the clients should be able to connect (on Windows by clicking `Activate` for the tunnel,
on Linux with `# wg-quick up wg0`).

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

<br><br><br><br>

## TODO

migrate LFS from local storage to S3-like object-storage:  
`$ sudo -u git forgejo migrate-storage -t lfs -c /etc/forgejo/app.ini -s minio --minio-endpoint endpoint-url.com --minio-access-key-id YOUR_ACCESS_KEY_ID --minio-secret-access-key YOUR_SECRET_ACCESS_KEY --minio-bucket gitea --minio-use-ssl -w /var/lib/forgejo/`

migrate from S3-like object-storage back to local:  
`$ sudo -u git forgejo migrate-storage -t lfs -c /etc/forgejo/app.ini -s local -p /var/lib/forgejo/data/lfs -w /var/lib/forgejo/`

<br><br><br>

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
    the overall quality of their service, and this HowTo should work with any Linux server (VPS or dedicated).
    FWIW, the performance of the VPS itself has been fine so far.  
    Some other low-cost hosters I have at least a little experience with include
    [Hetzner](https://www.hetzner.com/) (they offer dedicated servers for < €50/month)
    and [vultr](https://www.vultr.com/) (they also offer cheap S3-compatible Object Storage, but 
    I don't know if their performance is better than Contabos..).

