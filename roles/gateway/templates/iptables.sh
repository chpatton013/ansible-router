################################################################################
# FILTER - CHAINS

iptables -t filter -N INPUT_CANDIDATE

################################################################################
# FILTER - INPUT

# Drop all incoming packets by default.
iptables -t filter -P INPUT DROP

# Accept packets that are associated to connections that have already been
# accepted.
iptables -t filter -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Accept packets from the loopback interface.
iptables -t filter -A INPUT -i {{gateway.loopback_interface}} -j ACCEPT

# Drop packets that have an invalid tracking state.
iptables -t filter -A INPUT -m conntrack --ctstate INVALID -j DROP

# Accept new incoming ICMP packets.
iptables -t filter -A INPUT -p icmp -m conntrack --ctstate NEW -j ACCEPT

# Pass new incoming UDP and TCP packets to their respective chains.
# Note that all new TCP packets must be SYN packets, else they are invalid.
iptables -t filter -A INPUT -p udp -m conntrack --ctstate NEW -j INPUT_CANDIDATE
iptables -t filter -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j INPUT_CANDIDATE

# Reject all packets that have not been explicitly accepted.
# Note that rejected UDP and TCP packets are tracked to prevent port scanning.
iptables -t filter -A INPUT -p udp -m recent --set --rsource --name {{gateway.udp_port_scan.list}} -j REJECT --reject-with icmp-port-unreachable
iptables -t filter -A INPUT -p tcp -m recent --set --rsource --name {{gateway.tcp_port_scan.list}} -j REJECT --reject-with tcp-reset
iptables -t filter -A INPUT -j REJECT --reject-with icmp-proto-unreachable

################################################################################
# FILTER - OUTPUT

# Accept all outgoing packets by default.
iptables -t filter -P OUTPUT ACCEPT

################################################################################
# FILTER - FORWARD

# Drop all forwarding packets by default.
iptables -t filter -P FORWARD DROP

# Accept packets that are associated to connections that have already been
# accepted.
iptables -t filter -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Accept packets from NAT'ing internal hosts.
iptables -t filter -A FORWARD -i {{gateway.lan_interface}} -j ACCEPT
{% if gateway.port_mapping is not undefined %}

# Accept packets that are being mapped to internal hosts.
{% for mapping in gateway.port_mapping %}
iptables -t filter -A FORWARD -p {{mapping.protocol}} -d {{mapping.destination_host}} --dport {{mapping.destination_port}} -j ACCEPT
{% endfor %}
{% endif %}

# Reject all packets that have not been explicitly accepted.
iptables -t filter -A FORWARD -j REJECT --reject-with icmp-host-unreachable

################################################################################
# FILTER - INPUT_CANDIDATE (custom chain)

# Reject all UDP packets from hosts that have previously been rejected within
# the past {{gateway.udp_port_scan.timeout}} seconds.
iptables -t filter -A INPUT_CANDIDATE -p udp -m recent --update --rsource --seconds {{gateway.udp_port_scan.timeout}} --name {{gateway.udp_port_scan.list}} -j REJECT --reject-with icmp-port-unreachable

# Reject all TCP packets from hosts that have previously been rejected within
# the past {{gateway.tcp_port_scan.timeout}} seconds.
iptables -t filter -A INPUT_CANDIDATE -p tcp -m recent --update --rsource --seconds {{gateway.tcp_port_scan.timeout}} --name {{gateway.tcp_port_scan.list}} -j REJECT --reject-with tcp-reset
{% if gateway.bruteforce is not undefined %}

# Drop packets that are part of a bruteforce attack by throttling connections to
# a specific number of hits per timeout period.
{% for bruteforce in gateway.bruteforce %}
iptables -t filter -A INPUT_CANDIDATE -p {{bruteforce.protocol}} --dport {{bruteforce.port}} -m recent --name BRUTEFORCE --rttl --rcheck --hitcount {{bruteforce.hitcount}} --seconds {{bruteforce.timeout}} -j DROP
{% endfor %}
{% endif %}
{% if gateway.firewall_openings is not undefined %}

# Accept packets on specific openings in the firewall.
{% for opening in gateway.firewall_openings %}
iptables -t filter -A INPUT_CANDIDATE -p {{opening.protocol}} --dport {{opening.port}} -j ACCEPT
{% endfor %}
{% endif %}

################################################################################
# NAT - POSTROUTING

# Perform NAT for internal hosts connecting to external addresses.
iptables -t nat -A POSTROUTING -o {{gateway.wan_interface}} -j MASQUERADE

################################################################################
# NAT - PREROUTING
{% if gateway.port_mapping is not undefined %}

# Map specific ports from router to internal hosts.
{% for mapping in gateway.port_mapping %}
iptables -t nat -A PREROUTING -i {{gateway.lan_interface}} -p {{mapping.protocol}} --dport {{mapping.source_port}} -j DNAT --to {{mapping.destination_host}}:{{mapping.destination_port}}
{% endfor %}
{% endif %}
