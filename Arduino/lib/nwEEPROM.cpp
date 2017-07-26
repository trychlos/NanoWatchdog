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

#include "NanoWatchdog.h"

/**
 * nwEEPROMInitEventGet:
 *
 * Returns: the initialization event as a newly allocated nwEvent object.
 */
nwEvent nwEEPROMInitEventGet()
{
	nwEvent ev;

	ev.readFromEEPROM( nwInitEventAdr );

	return( ev );
}

/**
 * nwEEPROMInitEventSet:
 *
 * Writes the specified initialization event.
 */
void nwEEPROMInitEventSet( nwEvent &ev )
{
	ev.writeToEEPROM( nwInitEventAdr );
}

/**
 * nwEEPROMResetEventCountGet:
 *
 * Returns: count of stored reset events.
 */
int nwEEPROMResetEventCountGet()
{
    int count;

    EEPROM.get( nwResetCountAdr, count );

    return( count );
}

/**
 * nwEEPROMResetEventGet:
 * @index: the index of the desired reset event, counted from 0.
 *  0 is the most recent reset event.
 *  Upper limit is NW_MAX_RESET_EVENT-1, which is the oldest kept event.
 *
 * Returns: the desired reset event as a newly allocated nwEvent object.
 */
nwEvent nwEEPROMResetEventGet( int index )
{
	nwEvent ev;

	ev.readFromEEPROM( nwResetEventAdr + index*nwEventStrSize );

	return( ev );
}

/**
 * nwEEPROMResetEventSet:
 * @index: the index of the desired reset event, counted from 0.
 *
 * Updates the specified reset event at the given index.
 */
void nwEEPROMResetEventSet( nwEvent &ev, int index )
{
	ev.writeToEEPROM( nwResetEventAdr + index*nwEventStrSize );
}

/**
 * nwEEPROMResetEventSetNew:
 * @index: the index of the desired reset event, counted from 0.
 *  0 is the most recent reset event.
 *  Upper limit is NW_MAX_RESET_EVENT-1, which is the oldest kept event.
 *
 * Writes the specified reset event at the given index, shifted previous
 * events accordingly.
 *
 * The reset events are stored from most recent to least recent in the
 * limit of NW_MAX_RESET_EVENT events.
 * In order to rightly store the last event, we have to shift the
 * previous one, maybe losing the last one.
 */
void nwEEPROMResetEventSetNew( nwEvent &ev, int index )
{
	nwEvent ev_temp;
    int count = nwEEPROMResetEventCountGet();
    /* shift of one place to the bottom */
    if( count == NW_MAX_RESET_EVENT ){
        count -= 1;
    }
    for( int i=count ; i>0 ; --i ){
        ev_temp = nwEEPROMResetEventGet( i-1 );
        nwEEPROMResetEventSet( ev_temp, i );
    }
    /* write the most recent event */
    nwEEPROMResetEventSet( ev, 0 );
    /* update the counter */
    count += 1;
    EEPROM.put( nwResetCountAdr, count );
}
