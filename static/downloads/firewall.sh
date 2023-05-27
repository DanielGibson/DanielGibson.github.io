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
