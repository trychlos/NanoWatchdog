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
 * nwEvent::nwEvent:
 *
 * An empty constructor to initialize a new nwEvent with suitable
 * default values.
 */
nwEvent::nwEvent()
{
	this->setup();
}

/**
 * nwEvent::nwEvent:
 * @reason: the event reason code.
 *
 * A constructor which takes a specific reason code.
 */
nwEvent::nwEvent( int reason )
{
	this->setup();
    _reason = reason;
}

/*
 * nwEvent::setup:
 *
 * Initializes the object with suitable default values.
 */
void nwEvent::setup()
{
	/* set version to current version string */
    memset(( void * ) _version, '\0', sizeof( _version ));
    for( int i=0 ;; ++i ){
        _version[i] = pgm_read_byte_near( nwVersionString+i );
        if( _version[i] == '\0' ){
        	break;
        }
    }
    /* set event time to now */
    _time = now();
    /* set reason code to default (no ping) */
    _reason = NW_REASON_DEFAULT;
    /* set acknowledgement to false */
    _ack = false;
}

/**
 * nwEvent::readFromEEPROM:
 * @adr: the read address in the EEPROM (counted from zero)
 *
 * Deserialization: setup the current object with the data read from
 * EEPROM at specified address.
 */
void nwEvent::readFromEEPROM( int adr )
{
	nwEventStr ev;

    EEPROM.get( adr, ev );

    for( int i=0 ; i<nwVersionSize ; ++i ){
    	_version[i] = ev.version[i];
    }
    _time = ev.time;
    _reason = ev.ack_reason & B01111111;
    _ack = ev.ack_reason >> 7;
}

/**
 * nwEvent::writeToEEPROM:
 * @adr: the write address in the EEPROM (counted from zero)
 *
 * Serialization: write the current object at the specified address in
 * the EEPROM.
 */
void nwEvent::writeToEEPROM( int adr )
{
	nwEventStr ev;

	for( int i=0 ; i<nwVersionSize ; ++i ){
    	ev.version[i] = _version[i];
    }
    ev.time = _time;
    ev.ack_reason = _reason;
    ev.ack_reason |= ( _ack ? B10000000 : 0 );

    EEPROM.put( adr, ev );
}

/**
 * nwEvent::display:
 * @prefix: the prefix to be displayed on each line
 *
 * Display the content of the object.
 */
void nwEvent::display( const char *prefix )
{
    Serial.print( prefix );
    Serial.print( F( "version:      " ));
    Serial.println( _version );
    Serial.print( prefix );
    Serial.print( F( "date:         " ));
    Serial.println( nwDateTimeString( _time ));
    Serial.print( prefix );
    Serial.print( F( "reason:       " ));
    Serial.print( _reason );
    Serial.print( " (" );
    Serial.print( nwReasonString( _reason ));
    Serial.println( ")" );
    Serial.print( prefix );
    Serial.print( F( "acknowledged: " ));
    Serial.println( _ack ? "yes":"no" );
}

/**
 * nwEvent::acknowledge:
 * @ack: whether to acknowledge the event.
 *
 * Set the acknowledgment indicator.
 */
void nwEvent::acknowledge( bool ack )
{
	_ack = ack;
}

/**
 * nwEvent::isNull:
 *
 * Returns: true if the event is not set.
 */
bool nwEvent::isNull()
{
	return( _time == 0 );
}
