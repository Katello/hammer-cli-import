#!/usr/bin/python
# -*- coding: UTF-8 -*-

import os
import re
import stat
import subprocess
import sys
from optparse import Option, OptionParser

try:
    from spacewalk.common.rhnLog import initLOG, log_debug
    from spacewalk.common.rhnConfig import CFG, initCFG
    from spacewalk.server import rhnSQL
except:
    _LIBPATH = "/usr/share/rhn"
    # add to the path if need be
    if _LIBPATH not in sys.path:
        sys.path.append(_LIBPATH)
    from common import CFG, initCFG, initLOG, log_debug
    from server import rhnSQL

LOG_FILE='/var/log/rhn/stargate-channel-export.log'


def db_init():
    initCFG()
    rhnSQL.initDB()

_query_packages = rhnSQL.Statement("""
select p.id, p.org_id, p.package_size, p.path, c.checksum, c.checksum_type, n.name, evr.epoch, evr.version, evr.release, a.label as arch
from rhnPackage p join rhnChecksumView c on p.checksum_id = c.id
join rhnPackageName n on p.name_id = n.id
join rhnPackageEVR evr on p.evr_id = evr.id
join rhnPackageArch a on p.package_arch_id = a.id
join rhnChannelPackage cp on cp.package_id = p.id
where cp.channel_id = :channel_id
order by n.name
""")

_query_organizations = rhnSQL.Statement("""
select id, name from web_customer
""")

_query_channels = rhnSQL.Statement("""
select id, label from rhnChannel where org_id = :org_id order by label
""")

_query_repos = rhnSQL.Statement("""
select cs.id, cs.label, cs.source_url from rhnContentSource cs join rhnChannelContentSource ccs on ccs.source_id = cs.id where ccs.channel_id = :channel_id
order by cs.label
""")


def export_packages(options):

    log(1, "Output directory: %s" % options.directory)

    h = rhnSQL.prepare(_query_organizations)
    h.execute()
    orgs = h.fetchall_dict()

    for org in orgs:
        log(1, "Processing organization: %s" % org["name"])
        h = rhnSQL.prepare(_query_channels)
        h.execute(org_id=org["id"])
        channels = h.fetchall_dict() or []

        for channel in channels:
            log(1, " * channel: %s" % channel["label"])
            h = rhnSQL.prepare(_query_repos)
            h.execute(channel_id=channel["id"])
            repos = h.fetchall_dict() or []
            if not repos:
                log(2, "  - no repos associated")
                continue
            repo_packages = {}
            in_repo = 0
            missing = 0
            for repo in repos:
                if repo['source_url'].startswith('file://'):
                    log(2, "  - local repo: %s. Skipping." % repo['label'])
                    continue
                repo_packages[repo['label']] = list_repo_packages(repo['label'], repo['source_url'])
                log(2, "  - repo %s with: %s packages." % (repo['label'], str(len(repo_packages[repo['label']]))))

            channel_dir = os.path.join(options.directory, str(org["id"]), str(channel["id"]))
            if not os.path.exists(channel_dir):
                os.makedirs(channel_dir)

            h = rhnSQL.prepare(_query_packages)
            h.execute(channel_id=channel["id"])

            while 1:
                pkg = h.fetchone_dict()
                if not pkg:
                    break
                if pkg['path']:
                    abs_path = os.path.join(CFG.MOUNT_POINT, pkg['path'])
                    log(3, abs_path)
                    pkg['nevra'] = pkg_nevra(pkg)
                    if pkgs_available_in_repos(pkg, repo_packages) != None:
                        in_repo += 1
                    else:
                        missing += 1
                        cp_to_export_dir(abs_path, channel_dir, options)
                        check_disk_size(abs_path, pkg['package_size'])
                        check_disk_nevrao(abs_path, pkg.copy())
            log(2, "  - exporting: %d" % missing)
            log(2, "  - available: %d" % in_repo)
            create_repository(channel_dir, options)


def exists_on_fs(abs_path):
    return os.path.isfile(abs_path)

def pkg_nevra(pkg):
    # this NEVRA has to match
    # satellite_tools.reposync.ContentPackage.getNEVRA
    epoch = pkg['epoch'] if pkg['epoch'] is not None else '0'
    return pkg['name'] + '-' + epoch + ':' + pkg['version'] + '-' + pkg['release'] + '.' + pkg['arch']


def cp_to_export_dir(pkg_path, dir, options):
    if not exists_on_fs(pkg_path):
        log(0, "File missing: %s" % abs_path)
        return
    target = os.path.join(dir, os.path.basename(pkg_path))
    if exists_on_fs(target):
        if options.force:
            os.remove(target)
            os.link(pkg_path, target)
    else:
        os.link(pkg_path, target)

def create_repository(repo_dir, options):
    subprocess.call(["createrepo", "--no-database", repo_dir])

def pkgs_available_in_repos(pkg, repo_packages):
    for label, packages in repo_packages.iteritems():
        if pkg['nevra'] in packages:
            return label
    return None

def list_repo_packages(label, source_url):
    name = "yum_src"
    mod = __import__('spacewalk.satellite_tools.repo_plugins', globals(), locals(), [name])
    submod = getattr(mod, name)
    plugin = getattr(submod, "ContentSource")
    try:
        repo_plugin = plugin(source_url, label)
    except ValueError:
        log(2, "Invalid repo source_url ... %s" % source_url)
        return set([])
    packages = map(lambda p:p.getNEVRA(), plugin.list_packages(repo_plugin, []))
    return set(packages)

def check_disk_size(abs_path, size):
    file_size = os.stat(abs_path)[stat.ST_SIZE]
    ret = 0
    if file_size != size:
        log(0, "File size mismatch: %s (%s vs. %s)" % (abs_path, size, file_size))
        ret = 1
    return ret

def check_disk_nevrao(abs_path, row, restore=None):
    file = {};
    (_redhat_,
      file['org_id'],
      file['checksum_prefix'],
      file['name'],
      file['evr'],
      file['arch'],
      file['checksum'],
      file['basename']) = row['path'].split('/')
    if not row['org_id']:
        row['org_id'] = 'NULL'
    else:
        row['org_id'] = str(row['org_id'])
    row['checksum_prefix'] = row['checksum'][:3]
    if row['epoch']:
        row['evr'] = row['epoch'] + ':'
    else:
        row['evr'] = ''
    row['evr'] += row['version'] + '-' + row['release']
    row['basename'] = "%s-%s-%s.%s.%s" % (
                row['name'], row['version'], row['release'],
                row['arch'], row['path'][-3:])
    ret = 0
    for key in ('org_id', 'checksum_prefix', 'name', 'evr', 'arch', 'checksum',
            'basename'):
        if file[key] != row[key]:
            log(0, "File path mismatch: %s (%s: %s vs. %s)" % (abs_path, key, row[key],
                                                               file[key]))
            ret = 1
    return ret

def log(level, *args):
    log_debug(level, *args)
    verbose = options.verbose
    if not verbose:
        verbose = 0
    if verbose >= level:
        print (', '.join(map(lambda i: str(i), args)))

if __name__ == '__main__':

    options_table = [
        Option("-v", "--verbose",       action="count",
            help="Increase verbosity"),
        Option("-d", "--dir",       action="store", dest="directory",
            help="Export directory"),
        Option("-f", "--force",       action="store", dest="force",
            help="Overwrite export, if already present"),
        Option("-S", "--no-size",       action="store_false", dest="size", default=True,
            help="Don't check package size")]
    parser = OptionParser(option_list=options_table)
    (options, args) = parser.parse_args()

    initLOG(LOG_FILE, options.verbose or 0)

    db_init()

    export_packages(options)

    sys.exit(0)
