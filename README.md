# ansible-router

Hand-rolled home router provisioning for Debian via Ansible.

## Installation

This project should be downloaded to the machine you want to configure as
router. You will want to retain this checkout so you can re-run the Ansible
roles to apply any configuration changes. A good place to store this project is
`/usr/src/router`.

After downloading this project, install it with:
```
sudo .../router/setup.sh
```

Note that in VirtualBox, a system restart is necessary after modifying network
interfaces because the external interface fails to acquire an IP address during
a restart of the `networking` service. You must fully restart the VM to acquire
an IP address, which is necessary for the rest of the roles in setup.

## Capabilities

| Capability  | Package           | Description                               |
|-------------|-------------------|-------------------------------------------|
| `dhcp`      | `isc-dhcp-server` | Network configuration                     |
| `dns`       | `bind9`           | DNS caching, forwarding, and blacklisting |
| `dyndns`    | `ddns`            | Dynamic DNS configuration                 |
| `gateway`   | `iptables`        | NAT, firewall, and port-forwarding        |
| `ntp`       | `ntp`             | Local time server                         |
| `vpn`       | Undecided         | Local network tunneling for roaming hosts |
| `webserver` | `nginx`           | Termination and internal service routing  |

Each capability is provided by a single Ansible role, however not all roles
provide capabilities. Some roles (such as `network` and `system-administration`)
do not provide a capability, but instead setup some prerequisite for other
capabilities.

## File locations

| Name          | Location                  | Purpose                          |
|---------------|---------------------------|----------------------------------|
| `router_root` | `/opt/router/`            | Cross-role parameter data        |
| `ROLE_root`   | `/opt/router/ROLE/`       | Role-specific parameter data     |
| `ROLE_bin`    | `/opt/router/ROLE/bin/`   | Role-specific executables        |
| `ROLE_share`  | `/opt/router/ROLE/share/` | Role-specific user data          |
| `router_etc`  | `/etc/opt/router/`        | Cross-role configuration data    |
| `ROLE_etc`    | `/etc/opt/router/ROLE/`   | Role-specific configuration data |
| `router_var`  | `/var/opt/router/`        | Cross-role variable data         |
| `ROLE_var`    | `/var/opt/router/ROLE/`   | Role-specific variable data      |
| `router_src`  | `/usr/src/router/`        | Expected source install location |

Disambiguating types of data:

* _Configuration data_: Files that are read directly by services. Usually some
  application-specific configuration file in a fixed location is altered to load
  these files explicitly, which provide additional configuration settings.
* _Parameter data_: Files that hold structured data (YAML) consumed by this
  project to generate configuration files. These files reflect the details of
  the user's system, and must conform to a specific schema per-role. Any
  modifications to these files will require a rerun of this project.
* _User data_: Files that the user populates with supplementary data to tweak
  the behavior of the system. These files hold data that is directly consumed by
  running services, or is transformed to directly-consumable data by cron.
  Modifications to these files will not require a rerun of this project; it
  will, however, most likely require a reload or restart of the service that
  consumes the data (which can be performed by cron).
* _Variable data_: Files that grow or shrink over time either by means of a
  running service or a cron job. These files' size or content may not be known
  at the time this project is run. Generally, these files are populated by
  network requests made from cron jobs.
* _Executables_: Tools that are invoked to generate more data periodically.
  These executables are invoked by later steps in the roles that generate them,
  periodically by cron, or manually by the user.

## TODO

* Load vars from 

* Complete setup for missing roles:
  * `gateway`
  * `vpn`
  * `webserver`

* Add `checksecurity` package to `system-administration` role
* Add `fail2ban` package to `gateway` role

* Move BIND config files to separate those that were generated
  * As opposed to those that were edited. The "fixed" set of rendered templates
    can stay where they are, but the files that were created because of config
    data should be isolated for easy cleanup.

* Combine BIND cron scripts into a single script

* Move DNS zone lists to `/var/opt/router/dns/{zone}/{list}`
