#!/bin/bash
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

if [ ! -r configure.ac ]; then
	echo "[error] this script must be run from TOPDIR"
	exit 1
fi

my_topdir="`pwd`"
tmpdir="`mktemp -d /tmp/tmpXXXX`"
mkdir -p "${tmpdir}/_build"
(
 cd "${tmpdir}/_build" &&
 "${my_topdir}/configure" --prefix=/ &&
 make TMPDIR="${tmpdir}" install-txz
)
rm -fr "${tmpdir}"
