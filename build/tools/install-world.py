#!/usr/bin/env python3
#+
# Copyright 2015 iXsystems, Inc.
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
#####################################################################

import glob
import sys
import os
from utils import sh, sh_str, e, objdir, info, import_function


installworldlog = objdir('logs/dest-installworld')
distributionlog = objdir('logs/dest-distribution')
installkernellog = objdir('logs/dest-installkernel')
installkerneldebuglog = objdir('logs/dest-installkerneldebug')
installworld = import_function('build-os', 'installworld')
installkernel = import_function('build-os', 'installkernel')

# Base packages that must not be in our image. Sources and the compiler are
# not installed into a storage system (verified by comparing the files of the
# installed system against the contents of the packages), and the set-*
# metapackages pull exactly those in.
PKGBASE_EXCLUDE = (
    'FreeBSD-src', 'FreeBSD-src-sys',
    'FreeBSD-clang', 'FreeBSD-clang-dev', 'FreeBSD-lld', 'FreeBSD-lldb',
)


def register_base_packages(destdir):
    """Put the already laid out base under pkg accounting.

    installworld lays the world out as files and pkg knows nothing about it:
    such a base can only be updated by unpacking a whole image. Here the very
    same files are installed once more, but as packages, so the system gets a
    base tracked by pkg and is updated by deltas afterwards.

    The order matters: this has to happen BEFORE customize/conf-base.py, which
    copies /var into /conf/base. Otherwise the pkg database stays in /var, and
    /var in the installed system is a tmpfs poured from a template on every
    boot, so the package accounting would not survive the very first reboot.
    """
    repo = e('${PKGBASE_REPO}')
    # The directory inside the repository is named after the ABI
    # (FreeBSD:15:amd64), and that is determined by the tree rather than by our
    # configuration, so we search for it instead of guessing. latest is the
    # symlink that make packages points at the freshest build.
    candidates = sorted(glob.glob(os.path.join(repo, '*', 'latest')))
    if not candidates:
        info('No base package repository in {0}, skipping registration', repo)
        return
    latest = candidates[0]

    # The repository description is kept OUTSIDE the image: it belongs to the
    # build and has no business in the installed system. On top of that
    # install-ports lays out its own set of repositories anyway.
    repos_dir = objdir('pkgbase-repos.conf.d')
    sh('mkdir -p {0}'.format(repos_dir))
    with open(os.path.join(repos_dir, 'bsdnas-base.conf'), 'w') as fh:
        fh.write(
            'bsdnas-base: {\n'
            '  url: "file://%s",\n'
            '  enabled: yes,\n'
            '  signature_type: none\n'
            '}\n' % latest
        )

    pkg_env = 'env ASSUME_ALWAYS_YES=yes REPOS_DIR={0}'.format(repos_dir)
    sh('{0} pkg -r {1} update -f'.format(pkg_env, destdir),
       log=objdir('logs/dest-pkgbase-install'))

    info('Registering base packages from {0}', latest)
    packages = sh_str('{0} pkg -r {1} rquery %n'.format(pkg_env, destdir)).split()
    wanted = [p for p in packages
              if p not in PKGBASE_EXCLUDE
              and not p.endswith('-dbg')
              and not p.startswith('FreeBSD-set-')]
    if not wanted:
        raise RuntimeError(
            'Base repository {0} is empty or unavailable: the image would be '
            'left without the base tracked in pkg, which silently breaks '
            'updates'.format(latest))
    sh('{0} pkg -r {1} install -y {2}'.format(pkg_env, destdir, ' '.join(wanted)),
       log=objdir('logs/dest-pkgbase-install'), mode='a')
    info('Base registered: {0} packages', len(wanted))


if __name__ == '__main__':
    if e('${SKIP_INSTALL_WORLD}'):
        info('Skipping world installation, as instructed by setting SKIP_INSTALL_WORLD')
        sys.exit(0)

    if os.path.isdir(e('${WORLD_DESTDIR}')):
        sh('chflags -fR 0 ${WORLD_DESTDIR}')
        sh('rm -rf ${WORLD_DESTDIR}')

    sh('mkdir -p ${WORLD_DESTDIR}')
    installworld(e('${WORLD_DESTDIR}'), installworldlog, distributionlog, conf="run")
    installkernel(e('${KERNCONF}'), e('${WORLD_DESTDIR}'), installkernellog, conf="run")
    installkernel(
        e('${KERNCONF}-DEBUG'),
        e('${WORLD_DESTDIR}'),
        installkerneldebuglog,
        kodir="/boot/kernel-debug",
        conf="run"
    )
    if e('${SKIP_PKGBASE}'):
        info('Skipping base package registration as instructed by setting SKIP_PKGBASE')
    else:
        register_base_packages(e('${WORLD_DESTDIR}'))
