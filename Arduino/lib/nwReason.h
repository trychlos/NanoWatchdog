/*
 * NanoWatchdog
 * An Arduino Nano based PC watchdog.
 *
 * Copyright (C) 2015,2016,2017 Pierre Wieser <pwieser@trychlos.org>
 *
 * NanoWatchdog is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * NanoWatchdog is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NanoWatchdog; see the file COPYING. If not, see
 * <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *   Pierre Wieser <pwieser@trychlos.org>
 */

#ifndef __NWREASON_H__
#define __NWREASON_H__

/**
 * ReasonCode:
 *
 * This is the reason code of an event.
 *
 * Because this reason code is serialized in b6..b0 bits of the
 * nwEventStr structure, it is actually limited to 127.
 */
enum {
	NW_REASON_INIT          = 0,
	NW_REASON_NOPING,								/* 1 */
	NW_REASON_DEFAULT       = NW_REASON_NOPING,		/* 1 */
	NW_REASON_COMMAND_START = 16,
	NW_REASON_MAX_LOAD_1    = 16,					/* NanoWatchdog management daemon */
	NW_REASON_MAX_LOAD_5,							/* NanoWatchdog management daemon */
	NW_REASON_MAX_LOAD_15,							/* NanoWatchdog management daemon */
	NW_REASON_MIN_MEMORY,							/* NanoWatchdog management daemon */
	NW_REASON_MAX_TEMPERATURE,						/* NanoWatchdog management daemon */
	NW_REASON_PIDFILE,								/* NanoWatchdog management daemon */
	NW_REASON_PING,									/* NanoWatchdog management daemon */
	NW_REASON_INTERFACE,							/* NanoWatchdog management daemon */
	NW_REASON_MAX           = 127
};

String nwReasonString( int code );

#endif /* __NWREASON_H__ */
