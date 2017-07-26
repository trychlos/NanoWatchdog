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

#ifndef __NANOWATCHDOG_H__
#define __NANOWATCHDOG_H__

#include <Arduino.h>
#include <avr/pgmspace.h>
#include <EEPROM.h>
#include <Time.h>

/* an helper macro to get access to strings stored in Flash memory */
#define FS(x) (( __FlashStringHelper * )( x ))

/* max size of the version string, including null terminator */
static const int nwVersionSize = 32;
/*                                             0        1         2         3  */
/*                                             1234567890123456789012345678901 */
static const PROGMEM char nwVersionString[] = "NanoWatchdog v11.2017";

#define LED_BLINK	300					/* elapsed milliseconds on/off for a led blink */

/* blink the specified LED */
void nwBlinkPin( int pin, int blink=LED_BLINK );

/* a command date formating function
 * display yyyy-mm-dd hh:mi:ss from a time_t value */
String nwDateTimeString( time_t time );

/* some helping functions for Serial.print */
void nwSerialPrintVersion();

#include "nwEEPROM.h"
#include "nwEvent.h"
#include "nwReason.h"

#endif /* __NANOWATCHDOG_H__ */
