/*
 * NanoWatchdog
 * An Arduino Nano based PC watchdog.
 *
 * Copyright (C) 2015 Pierre Wieser <pwieser@trychlos.org>
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

#include "NanoWatchdog.h"

/**
 * nwReasonString:
 * @code: the reason code.
 *
 * Returns: the label corresponding to the specified reason code as a
 * new String
 */
String nwReasonString( int code )
{
    String str;

    if( code == NW_REASON_INIT ){
		str = "initialization";
    } else if( code == NW_REASON_NOPING ){
		str = "no ping";
    } else if( code >= NW_REASON_COMMAND_START ){
    	str = "external command";
    } else {
    	str = "unknown reason code";
    }

    return( str );
}
