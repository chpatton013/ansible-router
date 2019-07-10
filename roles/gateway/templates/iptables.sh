# iptables commands
#
# There are three scenarios we are designing for with these rules:
#   NETWORK -> NETWORK
#   NETWORK -> ROUTER
#   ROUTER -> NETWORK
#
# After removing the uninteresting tables and chains from these scenarios, we
# can see the paths that any packet will take:
#   NETWORK -> nat.PREROUTING -> filter.FORWARD -> nat.POSTROUTING -> NETWORK
#   NETWORK -> nat.PREROUTING -> filter.INPUT -> ROUTER
#   ROUTER -> filter.OUTPUT -> nat.POSTROUTING -> NETWORK

################################################################################
# filter: custom chains

iptables -t filter -N FILTER_CTSTATE
iptables -t filter -N FILTER_INCOMING
iptables -t filter -N FILTER_VALID
iptables -t filter -N FILTER_ATTACKS
iptables -t filter -N FILTER_OPENINGS
iptables -t filter -N FILTER_REJECT

################################################################################
# filter.INPUT

# Drop all incoming packets by default.
iptables -t filter -P INPUT DROP

# Accept packets from known connections of drop invalid packets.
iptables -t filter -A INPUT -j FILTER_CTSTATE

# Accept all packets from the loopback interface.
iptables -t filter -A INPUT -i {{gateway.loopback_interface}} -j ACCEPT

# Pass all remaining packets to the FILTER_INCOMING chain.
iptables -t filter -A INPUT -j FILTER_INCOMING

################################################################################
# filter.OUTPUT

# Accept all outgoing packets by default.
iptables -t filter -P OUTPUT ACCEPT

################################################################################
# filter.FORWARD

# Drop all forwarding packets by default.
iptables -t filter -P FORWARD DROP

# Accept packets from known connections of drop invalid packets.
iptables -t filter -A FORWARD -j FILTER_CTSTATE

# Accept packets from the lan interface.
iptables -t filter -A FORWARD -i {{gateway.lan_interface}} -j ACCEPT

# Pass all remaining packets to the FILTER_INCOMING chain.
iptables -t filter -A FORWARD -j FILTER_INCOMING

################################################################################
# filter.FILTER_CTSTATE (custom chain)
#
# Accept or drop packets based on their conntrack state.
# Packets with a state of "NEW" will return from this chain without being
# assigned a final target.

# Accept packets that are associated to connections that have already been
# accepted.
iptables -t filter -A FILTER_CTSTATE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Drop packets that have an invalid tracking state.
iptables -t filter -A FILTER_CTSTATE -m conntrack --ctstate INVALID -j DROP

################################################################################
# filter.FILTER_INCOMING (custom chain)
#
# Pass valid TCP and UDP packets onto the FILTER_VALID chain, then pass any
# packets that reach the end onto the FILTER_REJECT chain.

# Accept all incoming ICMP packets.
iptables -t filter -A FILTER_INCOMING -p icmp -j ACCEPT

# Pass new valid UDP and TCP packets to the FILTER_VALID chain.
# Note that all new TCP packets must be SYN packets, else they are invalid.
iptables -t filter -A FILTER_INCOMING -p udp -m conntrack --ctstate NEW -j FILTER_VALID
iptables -t filter -A FILTER_INCOMING -p tcp --syn -m conntrack --ctstate NEW -j FILTER_VALID

# Reject all packets that have not been explicitly accepted.
iptables -t filter -A FILTER_INCOMING -j FILTER_REJECT

################################################################################
# filter.FILTER_VALID (custom chain)

iptables -t filter -A FILTER_VALID -j FILTER_ATTACKS
iptables -t filter -A FILTER_VALID -j FILTER_OPENINGS

################################################################################
# filter.FILTER_ATTACKS (custom chain)
#
# Reject packets that are deemed to be part of some attack. This includes TCP
# port-scanning, UDP port-scanning, and brute-force login attempts.
# Packets that are not classified as attacks will return from this chain without
# being assigned a final target.

# Reject all UDP packets from hosts that have previously been rejected within
# the past {{gateway.udp_port_scan.timeout}} seconds.
iptables -t filter -A FILTER_ATTACKS -p udp -m recent --update --rsource --seconds {{gateway.udp_port_scan.timeout}} --name {{gateway.udp_port_scan.list}} -j REJECT --reject-with icmp-port-unreachable

# Reject all TCP packets from hosts that have previously been rejected within
# the past {{gateway.tcp_port_scan.timeout}} seconds.
iptables -t filter -A FILTER_ATTACKS -p tcp -m recent --update --rsource --seconds {{gateway.tcp_port_scan.timeout}} --name {{gateway.tcp_port_scan.list}} -j REJECT --reject-with tcp-reset

{% if gateway.bruteforce is not undefined %}
# Drop packets that are part of a bruteforce attack by throttling connections to
# a specific number of hits per timeout period.
{% for bruteforce in gateway.bruteforce %}
iptables -t filter -A FILTER_ATTACKS -p {{bruteforce.protocol}} --dport {{bruteforce.port}} -m recent --name {{bruteforce.list}} --rttl --rcheck --hitcount {{bruteforce.hitcount}} --seconds {{bruteforce.timeout}} -j DROP
{% endfor %}
{% endif %}

################################################################################
# filter.FILTER_OPENINGS (custom chain)
#
# Accept packets that are bound for specifically opened protocol/port combos.
# Packets that are not bound for any openings will return from this chain
# without being assigned a final target.

{% if gateway.firewall_openings is not undefined %}
# Accept packets on specific openings in the firewall.
{% for opening in gateway.firewall_openings %}
iptables -t filter -A FILTER_OPENINGS -p {{opening.protocol}} --dport {{opening.port}} -j ACCEPT
{% endfor %}
{% endif %}

################################################################################
# filter.FILTER_REJECT (custom chain)
#
# Reject all packets that have entered this chain with their protocol-dependent
# RFC-compliant response. TCP and UDP packets are added to their respective
# port-scanning lists to mitigate potential attacks.

# Reject all packets that have not been explicitly accepted.
# Note that rejected UDP and TCP packets are tracked to prevent port scanning.
iptables -t filter -A FILTER_REJECT -p udp -m recent --set --rsource --name {{gateway.udp_port_scan.list}} -j REJECT --reject-with icmp-port-unreachable
iptables -t filter -A FILTER_REJECT -p tcp -m recent --set --rsource --name {{gateway.tcp_port_scan.list}} -j REJECT --reject-with tcp-reset
iptables -t filter -A FILTER_REJECT -j REJECT --reject-with icmp-host-unreachable

################################################################################
# NAT - POSTROUTING

# Perform NAT for internal hosts connecting to external addresses.
iptables -t nat -A POSTROUTING -o {{gateway.wan_interface}} -j MASQUERADE

################################################################################
# NAT - PREROUTING

{% if gateway.port_mapping is not undefined %}
# Map specific ports from router to internal hosts.
{% for mapping in gateway.port_mapping %}
iptables -t nat -A PREROUTING -i {{gateway.wan_interface}} -p {{mapping.protocol}} --dport {{mapping.source_port}} -j DNAT --to {{mapping.destination_host}}:{{mapping.destination_port}}
{% endfor %}
{% endif %}
