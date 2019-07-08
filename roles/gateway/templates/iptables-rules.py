#!/usr/bin/env python

import subprocess


COMMANDS_FILE_PATH = "{{gateway.iptables_command_file}}"
RULES_FILE_PATH = "{{gateway.iptables_rules_file}}"


def main():
    rules = subprocess.check_output([
        "iptables-converter",
        "-s",
        COMMANDS_FILE_PATH,
    ])
    open(RULES_FILE_PATH, "w").write(rules)
    subprocess.check_call(["netfilter-persistent", "reload"])


if __name__ == "__main__":
    main()
