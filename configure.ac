# @(#) NanoWatchdog
#
# Copyright (C) 2015,2016,2017 Pierre Wieser (see AUTHORS)
#
# NanoWatchdog is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# NanoWatchdog is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NanoWatchdog; if not, see
# <http://www.gnu.org/licenses/>.
#
# use: "autoreconf && maintainer/make_install_txz.sh" to generate a
# nanowatchdog-x.yy.txz tarball installable via Ansible.

AC_PREREQ(2.59)

# when upgrading this version, do not omit to also upgrade the version
# in src/nw-client.pl / src/nw-daemon.pl
AC_INIT([NanoWatchdog],[11.2017],[pwieser@trychlos.org],,[https://trychlos.github.io/NanoWatchdog])

# unable to define something as 'no-dist-gz'
AM_INIT_AUTOMAKE([no-dist-gzip dist-xz])

AC_CONFIG_SRCDIR([src/nw-daemon.pl])

AC_CONFIG_FILES([
	Makefile
	Arduino/Makefile
	Arduino/lib/Makefile
	Arduino/NanoWatchdog/Makefile
	doc/Makefile
	etc/Makefile
	etc/init.d/Makefile
	etc/init.d/nanowatchdog
	etc/systemd/Makefile
	etc/systemd/nanowatchdog.service
	etc/udev/Makefile
	etc/udev/rules.d/Makefile
	maintainer/Makefile
	pcb/Makefile
	src/Makefile
])

AC_OUTPUT
