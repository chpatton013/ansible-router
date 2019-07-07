#!/usr/bin/env python

from __future__ import print_function

import argparse
import hashlib
import ipaddress
import os
import re
import subprocess
import sys

import requests
import yaml


DOMAIN_LISTS_FILE = "{{dns.domain_lists_file}}"
DOMAIN_LISTS_DIR = "{{dns.domain_lists_dir}}"
ZONES_DIR = "{{dns.var_forward_zones_dir}}"
FILE_CHUNK_SIZE = 1024


class DomainListSyncError(RuntimeError): pass


class DomainListSyncRequestError(DomainListSyncError):
    def __init__(self, url, request_exception):
        self.url = url
        self.request_exception = request_exception

    def __str__(self):
        as_str = "DomainListSyncRequestError: Failed to request from URL"
        as_str += "\n  URL: "
        as_str += self.url
        as_str += "\n  RequestException:"
        for line in str(self.request_exception).splitlines():
            as_str += "\n    "
            as_str += line
        return as_str


class DomainListSyncResponseError(DomainListSyncError):
    def __init__(self, url, response):
        self.url = url
        self.response = response

    def __str__(self):
        as_str = "DomainListSyncResponseError: Unsuccessful response from URL"
        as_str += "\n  URL: "
        as_str += self.url
        as_str += "\n  Response:"
        for line in str(self.response).splitlines():
            as_str += "\n    "
            as_str += line
        return as_str


def _parse_args():
    parser = argparse.ArgumentParser()

    reload_bind_group = parser.add_mutually_exclusive_group()
    reload_bind_group.add_argument(
        "--reload-bind",
        action="store_true",
        dest="reload_bind",
    )
    reload_bind_group.add_argument(
        "--no-reload-bind",
        action="store_false",
        dest="reload_bind",
    )

    parser.set_defaults(reload_bind=True)

    return parser.parse_args()


def _read_domain_list_zones_file(domain_list_zones_file_path):
    return yaml.load(
        open(domain_list_zones_file_path, "r"),
        Loader=yaml.SafeLoader,
    )


def _generate_lines(file_path):
    # Remove leading and trailing whitespace from the line, then strip line
    # comments denoted by the '#' character.
    for line in open(file_path, "r"):
        yield re.sub(r"#.*$", r"", line.strip())


def _is_domain_name(candidate):
    try:
        # IP addresses are not valid domain names.
        ipaddress.ip_address(unicode(candidate))
        return False
    except ValueError:
        pass

    # Valid domain names have at least two domain-parts separated by a `.`.
    domain_part, _, top_level_domain = candidate.rpartition(".")
    return domain_part and top_level_domain


def _generate_domains(file_path):
    # Extract "words" from `content`, and yield any that pass our domain filter.
    for line in _generate_lines(file_path):
        for match in re.finditer(r"(\S+)", line):
            for group in match.groups():
                domain_candidate = group.lower()
                if _is_domain_name(domain_candidate):
                    yield domain_candidate


def _reference_to_list_file_path(reference, lists_dir):
    sha1 = hashlib.sha1()
    sha1.update(reference)
    return os.path.join(lists_dir, "{}.list".format(sha1.hexdigest()))


def _sync_domain_list(url, file_path):
    try:
        response = requests.get(url, stream=True)
    except requests.exceptions.RequestException as exception:
        raise DomainListSyncRequestError(url, exception)

    if response.status_code != requests.codes.ok:
        raise DomainListSyncResponseError(url, response)

    with open(file_path, "w") as f:
        for chunk in response.iter_content(chunk_size=FILE_CHUNK_SIZE):
            if chunk:
                f.write(chunk)


def _sync_domain_list_zones(domain_list_zones, lists_dir):
    list_files = []
    successes = []
    failures = []
    for zone in domain_list_zones:
        for references_file in zone.get("references", []):
            for reference in _generate_domains(references_file):
                list_file_path = _reference_to_list_file_path(
                    reference,
                    lists_dir,
                )
                list_files.append(list_file_path)
                try:
                    _sync_domain_list(reference, list_file_path)
                    successes.append(reference)
                except DomainListSyncError as error:
                    failures.append(error)
    return list_files, successes, failures


def _generate_domain_list_files(lists_dir):
    for root, _dirnames, filenames in os.walk(lists_dir):
        for filename in filenames:
            yield os.path.join(root, filename)


def _delete_untracked_domain_lists(tracked_list_files, lists_dir):
    tracked = {f for f in tracked_list_files}
    present = {f for f in _generate_domain_list_files(lists_dir)}
    untracked = sorted(present - tracked)
    for file_path in untracked:
        os.unlink(file_path)
    return untracked


def _sync(domain_list_zones, lists_dir):
    list_files, successes, failures = _sync_domain_list_zones(
        domain_list_zones,
        lists_dir,
    )

    untracked = _delete_untracked_domain_lists(list_files, lists_dir)

    return successes, failures, untracked


def _zone_file_path(zone, zones_dir):
    return os.path.join(zones_dir, "{}.db.records".format(zone))


def _generate_zone_domains(zone, lists_dir):
    for domains_file in zone.get("domains", []):
        for domain in _generate_domains(domains_file):
            yield domain
    for references_file in zone.get("references", []):
        for reference in _generate_domains(references_file):
            list_file_path = _reference_to_list_file_path(
                reference,
                lists_dir,
            )
            for domain in _generate_domains(list_file_path):
                yield domain


def _domain_to_record(domain, record):
    return "{} {}\n".format(domain, record)


def _reload_bind():
    service_name = "bind9.service"
    try:
        subprocess.check_output(["systemctl", "status", service_name])
    except subprocess.CalledProcessError:
        return False
    else:
        subprocess.check_output(["systemctl", "reload", service_name])
        return True


def _transform(domain_list_zones, lists_dir, zones_dir, reload_bind):
    zone_files = []
    for zone in domain_list_zones:
        zone_file_path = _zone_file_path(zone["zone"], zones_dir)
        zone_files.append(zone_file_path)
        with open(zone_file_path, "w") as f:
            for domain in _generate_zone_domains(zone, lists_dir):
                f.write(_domain_to_record(domain, zone["record"]))

    if reload_bind:
        bind_reloaded = _reload_bind()
    else:
        bind_reloaded = False

    return zone_files, bind_reloaded


def main():
    args = _parse_args()

    domain_list_zones = _read_domain_list_zones_file(DOMAIN_LISTS_FILE)

    successes, failures, untracked = _sync(domain_list_zones, DOMAIN_LISTS_DIR)
    total_lists = len(successes) + len(failures)

    if successes:
        print("Synced {} of {} lists".format(len(successes), total_lists))
        for success in successes:
            print("  {}".format(success))

    if failures:
        print(
            "Failed to sync {} of {} lists".format(len(failures), total_lists),
            file=sys.stderr,
        )
        for failure in failures:
            print("  {}".format(failure), file=sys.stderr)

    if untracked:
        print("Deleted {} untracked lists".format(len(untracked)))
        for list_file in untracked:
            print("  {}".format(os.path.relpath(list_file, DOMAIN_LISTS_DIR)))

    zone_files, bind_reloaded = _transform(
        domain_list_zones,
        DOMAIN_LISTS_DIR,
        ZONES_DIR,
        args.reload_bind,
    )

    if zone_files:
        print("Generated {} zone files".format(len(zone_files)))
        for zone_file in zone_files:
            print("  {}".format(zone_file))

    if bind_reloaded:
        print("Reloaded BIND service")

    return 0


if __name__ == "__main__":
    sys.exit(main())
