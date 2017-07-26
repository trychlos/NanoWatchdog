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
 * nwBlinkPin:
 * @pin: the PIN number of the LED.
 * @blink: the delay in milliseconds; defaults to LED_BLINK.
 */
void nwBlinkPin( int pin, int blink )
{
    digitalWrite( pin, HIGH );
    delay( blink );
    digitalWrite( pin, LOW );
}

/**
 * nwDateTimeString:
 * @t: a time_t value
 *
 * Returns: the corresponding 'yyyy-mm-dd hh:mi:ss' date and time as a
 * new String
 */
String nwDateTimeString( time_t t )
{
    TimeElements tm;
    breakTime( t, tm );
    String str = String( tmYearToCalendar( tm.Year ), DEC ) + "-";
    if( tm.Month < 10 ){
        str = str + "0";
    }
    str = str + String( tm.Month, DEC ) + "-";
    if( tm.Day < 10 ){
        str = str + "0";
    }
    str = str + String( tm.Day, DEC ) + " ";
    if( tm.Hour < 10 ){
        str = str + "0";
    }
    str = str + String( tm.Hour, DEC ) + ":";
    if( tm.Minute < 10 ){
        str = str + "0";
    }
    str = str + String( tm.Minute, DEC ) + ":";
    if( tm.Second < 10 ){
        str = str + "0";
    }
    str = str + String( tm.Second, DEC );
    str += " UTC";
   
    return( str );
}

/**
 * nwOutputTitle:
 * @title: the title to send to Serial.println
 */
void nwSerialPrintVersion()
{
	Serial.print( "[" );
	Serial.print( FS( nwVersionString ));
	Serial.print( "] - " );
}
