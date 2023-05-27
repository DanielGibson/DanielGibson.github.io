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
