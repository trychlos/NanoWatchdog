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

#ifndef __NWEVENT_H__
#define __NWEVENT_H__

class nwEvent {
	public:
		nwEvent();
		nwEvent( int reason );
		void readFromEEPROM( int adr=0 );
		void writeToEEPROM( int adr=0 );
		void display( const char *prefix="" );
		void acknowledge( bool ack=true );
		bool isNull();
	private:
		/* the version string of the originating NanoWatchdog */
	    char   _version[nwVersionSize];
	    /* the time_t time when the event happened */
	    time_t _time;
	    /* the reason code of the event (see nwReason.h) */
	    int    _reason;
	    /* whether the event has been acknowledged */
	    bool   _ack;

	    /* private functions */
	    void setup();
};

#endif /* __NWEVENT_H__ */
