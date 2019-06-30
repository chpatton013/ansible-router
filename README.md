# ansible-router

Hand-rolled home router provisioning via Ansible.

## Capabilities

| Capability  | Package           | Description                               |
|-------------|-------------------|-------------------------------------------|
| `dhcp`      | `isc-dhcp-server` | Network configuration                     |
| `dns`       | `bind9`           | DNS caching, forwarding, and blacklisting |
| `gateway`   | `iptables`        | NAT, firewall, and port-forwarding        |
| `ntp`       | `ntp`             | Local time server                         |
| `vpn`       | Undecided         | Local network tunneling for roaming hosts |
| `webserver` | `nginx`           | Termination and internal service routing  |

## TODO

* Complete setup for missing roles:
  * `gateway`
  * `vpn`
  * `webserver`

* Move BIND config files to separate those that were generated
  * As opposed to those that were edited. The "fixed" set of rendered templates
    can stay where they are, but the files that were created because of config
    data should be isolated for easy cleanup.

* Move all specific data to `/var/local/router/{ROLE}/...`
  * `dhcp`: Entirety of `defaults/main.yaml`
  * `dns`: Entirety of `defaults/main.yaml`
  * `gateway`: INCOMPLETE
  * `network`: Entirety of `defaults/main.yaml`
  * `ntp`: None
  * `vpn`: INCOMPLETE
  * `webserver`: INCOMPLETE

* Render these specific data files with vars from a shared data file:
  * `/var/local/router/shared.yaml`
