# @(#) NanoWatchdog
#
# Copyright (C) 2015 Pierre Wieser (see AUTHORS)
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
# use: "autoreconf" to generate configure.

AC_PREREQ(2.59)

AC_INIT([NanoWatchdog],[2015.3],[pwieser@trychlos.org],,[https://trychlos.github.io/NanoWatchdog])

AM_INIT_AUTOMAKE([-Wall -Werror])

AC_CONFIG_SRCDIR([src/daemon/nw-daemon.pl])

AC_CONFIG_FILES([
	Makefile
	Arduino/Makefile
	Arduino/lib/Makefile
	Arduino/NanoWatchdog/Makefile
	doc/Makefile
	etc/Makefile
	etc/systemd/Makefile
	etc/systemd/system/Makefile
	pcb/Makefile
	src/Makefile
	src/client/Makefile
	src/daemon/Makefile
])

AC_OUTPUT
