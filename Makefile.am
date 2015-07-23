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

AUTOMAKE_OPTIONS = dist-xz

SUBDIRS = \
	Arduino			\
	doc				\
	etc				\
	pcb				\
	src				\
	$(NULL)

docdir = $(datadir)/doc/@PACKAGE@-@VERSION@

dist_doc_DATA = \
	AUTHORS ChangeLog COPYING INSTALL NEWS README TODO

uninstall-local:
	rmdir $(DESTDIR)$(docdir)
