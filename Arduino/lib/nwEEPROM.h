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

#include <Time.h>           			/* to get the time_t definition */
#include "nwEvent.h"

#ifndef __NWEEPROM_H__
#define __NWEEPROM_H__

/* The structure which is actually serialized to/from EEPROM when
 * reading/writing an nwEvent object.
 * ack_reason holds:
 * - the acknowledgment boolean in b7
 * - the reason code in b6..b0 which actually limits the reason codes
 *   to 127.
 */
struct nwEventStr {
    char   version[nwVersionSize];		/* 32 */
    time_t time;						/*  4 */
    byte   ack_reason;					/*  1 */
};

static const int nwEventStrSize = sizeof( nwEventStr );

/* EEPROM content:
 *
 * address  type          size  content
 * -------  ------------  ----  ---------------------------------------
 *       0  nwEvent         37  initialization of the EEPROM
 *      37  int              2  count of reset traces
 *      39  nwEvent x 10   370  ten last resets
 *     409  .. 1023             unused
 */
static const int nwInitEventAdr  = 0;
static const int nwResetCountAdr = nwInitEventAdr+nwEventStrSize;
static const int nwResetEventAdr = nwResetCountAdr+sizeof( int );

#define EEPROM_SIZE              1024
#define NW_MAX_RESET_EVENT       10

/* read/write the initialization event */
nwEvent nwEEPROMInitEventGet();
void    nwEEPROMInitEventSet( nwEvent &ev );

/* read the count of stored reset events */
int     nwEEPROMResetEventCountGet();

/* read/write a reset event */
nwEvent nwEEPROMResetEventGet   ( int index );
void    nwEEPROMResetEventSet   ( nwEvent &ev, int index=0 );
void    nwEEPROMResetEventSetNew( nwEvent &ev, int index=0 );

#endif /* __NWEEPROM_H__ */
