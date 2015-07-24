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
 * 
 * Commands: see cmdHelp() function.
 *
 * Note that command interpreter is very rough:
 * - commands are case sensitive
 * - multi words commands expect only one space between words and no extra chars
 * - commands are expected to be '\n' terminated
 *
 * The typical PC program may look like:
 *   nw-daemon.pl -nohelp
 *   nw-daemon.pl -config /etc/nanowatchdog.conf
 *   nw-daemon.pl -device /dev/ttyUSB0
 *
 * The NanoWatchdog takes care of waiting for ArnuinoNano initialization, before
 * set date, test mode off and start.
 *
 * See https://github.com/JChristensen/Timezone for a timezone library.
 *
 * See https://github.com/thijse/Arduino-Code-and-Libraries/blob/master/Libraries/Timezone/Examples/WorldClock/WorldClock.pde
 * for examples of Timezone usage.
 *
 * See http://www.timeanddate.com/worldclock/ for DST rule informations.
 */

#include <Arduino.h>
#include <EEPROM.h>
#include <Time.h>                              /* http://www.pjrc.com/teensy/td_libs_Time.html */
#include "NanoWatchdog.h"

static const char *strSpace3 = "   ";
static const char *strSpace4 = "    ";

/* the pin on which the LED is connected */
#define LED_START        14                /* A0: i/o port for start led */
#define LED_PING         15                /* A1: i/o port for ping led */
#define LED_RESET        16                /* A2: i/o port for reset led */
#define EXEC_RESET       17                /* A3: i/o port for reset relay */
#define EXEC_BLINK       300               /* maintain the relay closed */
#define DEF_DELAY        60                /* default reset delay without ping */
#define DEF_TEST         true              /* whether we are in test mode */

unsigned int parmDelay = DEF_DELAY;        /* config: delay */
bool parmTest = DEF_TEST;                  /* config: mode */
bool dateSet = false;                      /* whether the 'SET DATE <time>' command has been issued */

/* the start time
 * zero if the watchdog is stopped (doesn't count for pings and intervals)
 * is set to now() when the watchdog receives a 'START' command
 */
time_t startTime = 0;

/* the last ping time
 * zero if the watchdog is stopped (doesn't count for pings and intervals)
 * is set to now() when the watchdog receives a 'PING' command
 */
time_t lastPing = 0;

/* reset time
 * zero while the reset has not been activated, whether the watchdog is started
 * or not
 * is set to now() when the reset is activated, i.e. when the last ping is older
 * than the required interval)
 */
time_t resetTime = 0;

void setup() {
    Serial.begin( 19200 );
    pinMode( LED_START, OUTPUT );
    pinMode( LED_PING,  OUTPUT );
    pinMode( LED_RESET, OUTPUT );
    pinMode( EXEC_RESET, OUTPUT );
}

void loop() {
    /* is there a command to be executed ?
     */
    String command = getCommand();
    if( command.length() > 0 ){
        bool ok = false;
        if( command.startsWith( "ACKNOWLEDGE " )){
            ok = cmdAcknowledge( command );
        } else if( command.startsWith( "EEPROM " )){
            ok = cmdEeprom( command );
        } else if( command.equals( "HELP" )){
            ok = cmdHelp();
        } else if( command.equals( "NOOP" )){
            ok = true;
        } else if( command.equals( "PING" )){
            ok = cmdPing();
        } else if( command.startsWith( "REBOOT " )){
            ok = cmdReboot( command );
        } else if( command.equals( "REINIT" )){
            ok = cmdReinit();
        } else if( command.startsWith( "SET " )){
            ok = cmdSet( command );
        } else if( command.equals( "START" )){
            ok = cmdStart();
        } else if( command.equals( "STATUS" )){
            ok = cmdStatus();
        } else if( command.equals( "STOP" )){
            ok = cmdStop();
        }
        if( ok ){
            Serial.print( F( "OK: " ));
        } else {
            Serial.print( F( "Unknown or invalid command: " ));
        }
        Serial.println( command.c_str());
        Serial.flush();
    }
  
    /* a command may have been executed
     * see about the watchdog itself
     * if it has been started, and last ping is older than the delay
     */
    if( startTime > 0 && now() > lastPing + parmDelay ){
        execReset( NW_REASON_NOPING );
    }
}

/**
 * getCommand:
 *
 * Read a command from serial input until next newline '\n'
 * - we do not want block when reading the serial input
 *   so we increment the static variable when there is something to read
 * - and only return it when complete
 *
 * Returns: the command as a new String, or empty if there is no new
 *  command.
 */
String getCommand() 
{
    static String cmd = "";
    static bool is_complete = false;
  
    if( is_complete ){                            // reinit the input string
        is_complete = false;
        cmd = "";
    }
    while( Serial.available() > 0 ){
        char inChar = Serial.read();  
        if( inChar == '\n' ){
            is_complete = true;
            return( cmd );
        }
        cmd = cmd + inChar;
    }
    return( "" );
}

/**
 * cmdAcknowledge:
 * @command: the command to be executed.
 *
 * Acknowledge a stored reset event, whose index is specified from zero
 * where zero is the index of the most recent reset event.
 *
 * syntaxe: ACKNOWLEDGE <index>
 *
 * Returns: true if the command has been successfully executed, false else.
 */
bool cmdAcknowledge( String command )
{
    if( command.length() > 12 ){
        String rest = command.substring( 12 );
        int index = ( int ) rest.toInt();
        if( index >= 0 && index < NW_MAX_RESET_EVENT ){
            nwEvent ev = nwEEPROMResetEventGet( index );
            ev.acknowledge();
            nwEEPROMResetEventSet( ev, index );
            return( true );
        }
    }
    return( false );
}

/**
 * cmdEeprom:
 * @command: the command to be executed.
 *
 * EEPROM management:
 * - INIT : initialize the EEPROM content to zero
 * - READ: display the EEPROM content
 *
 * The content of the EEPROM is read with the STATUS command.
 */
bool cmdEeprom( String command )
{
    bool ok = false;
  
    if( command.startsWith( "INIT", 7 ) && command.length() == 11 ){
        ok = cmdEepromInit( command );
    } else if( command.startsWith( "DUMP", 7 ) && command.length() == 11 ){
        ok = cmdEepromDump( command );
    }
    return( ok );
}

/**
 * cmdEepromInit:
 * @command: the command to be executed.
 *
 * EEPROM management:
 * - INIT : initialize the EEPROM content to zero
 *
 * The 'SET DATE <time>' command should have been issued before initializing
 * the EEPROM in order to have a valid date.
 */
bool cmdEepromInit( String command )
{
    /* first, init the EEPROM to zero */
    for( int i=0 ; i<EEPROM_SIZE ; ++i ){
        EEPROM[i] = '\0';
    }
    /* write the initialization event */
    nwEvent ev( NW_REASON_INIT );
    ev.acknowledge();
    nwEEPROMInitEventSet( ev );
    /* last blink the START LED and returns */
    nwBlinkPin( LED_START );
    return( true );
}

/**
 * cmdEepromDump:
 * @command: the command to be executed.
 *
 * EEPROM management:
 * - DUMP: display the EEPROM content
 *
 * Read and display the EEPROM content.
 */
bool cmdEepromDump( String command )
{
    nwSerialPrintVersion();
    Serial.println( F( "EEPROM dump:" ));
    /* read initialization event */
    nwEvent ev = nwEEPROMInitEventGet();
    Serial.println( F( " Initialization event:" ));
    ev.display( strSpace3 );

    /* read reset traces count */
    int count = nwEEPROMResetEventCountGet();
    Serial.println( F( " Reset events count:" ));
    Serial.print( strSpace3 );
    Serial.print( F( "count=" ));
    Serial.println( count );

    for( int i=0 ; i<count ; ++i ){
        ev = nwEEPROMResetEventGet( i );
        Serial.print( F( " Reset event #" ));
        Serial.println( i );
        ev.display( strSpace3 );
    }
    return( true );
}

/**
 * cmdHelp:
 *
 * Display the available commands.
 *
 * Returns: true.
 */
bool cmdHelp()
{
    nwSerialPrintVersion();
    Serial.println( F( "Available commands:" ));
    Serial.println( F( " ACKNOWLEDGE <index>  acknowledge a stored reset event (index counted from most recent=0)" ));
    Serial.println( F( " EEPROM INIT          initialize the EEPROM (once, before NanoWatchdog first installation)" ));
    Serial.println( F( " EEPROM DUMP          dump the EEPROM content" ));
    Serial.println( F( " HELP                 list available commands" ));
    Serial.println( F( " NOOP                 no-operation (used at NanoWatchdog startup)" ));
    Serial.println( F( " PING                 ping the watchdog, reinitializing the timeout delay" ));
    Serial.println( F( " REBOOT <reason>      reset the PC right now" ));
    Serial.println( F( " REINIT               reinit watchdog after a reset (deprecated since 2015.2)" ));
    Serial.println( F( " SET DATE <date>      set current UTC date as a count of seconds since 1970-01-01 (EPOCH time)" ));
    Serial.println( F( "                      (needed for storing actual reset date and time)" ));
    Serial.print  ( F( " SET DELAY <delay>    set no-ping timeout before reset (min=1, max=65535 (~18h)) [" ));
    Serial.print( DEF_DELAY );
    Serial.println( F( " sec.]" ));
    Serial.print  ( F( " SET TEST ON|OFF      set test mode [" ));
    Serial.print( DEF_TEST ? "ON" : "OFF" );
    Serial.println( "]" );
    Serial.println( F( " START                start the watchdog" ));
    Serial.println( F( " STATUS               display the current watchdog status" ));
    Serial.println( F( " STOP                 stop the watchdog" ));
    return( true );
}

/**
 * cmdPing:
 *
 * Ping the watchdog, inhibiting the reset for the next interval
 * doesn't ping if the reset has been activated
 * no input args
 *
 * Returns: true.
 */
bool cmdPing()
{
    if( startTime > 0 && resetTime == 0 ){
        lastPing = now();
        nwBlinkPin( LED_PING );
      }
    return( true );
}

/**
 * cmdReboot:
 *
 * Reboot the PC right now.
 *
 * syntax: REBOOT <reason>
 *
 * Returns: true/false whether the command has been accepted.
 */
bool cmdReboot( String command )
{
    if( command.length() > 7 ){
        String rest = command.substring( 7 );
        int reason = ( int ) rest.toInt();
        if( reason >= NW_REASON_COMMAND_START && reason <= NW_REASON_MAX ){
            execReset( reason );
            return( true );
        }
    }
    return( false );
}

/**
 * cmdReinit:
 *
 * Reinit the watchdog.
 * This is only useful when in development mode
 *
 * Returns: true;
 */
bool cmdReinit()
{
    resetTime = 0;
    digitalWrite( LED_START, LOW );
    digitalWrite( LED_RESET, LOW );
    startTime = 0;
    return( true );
}

/**
 * cmdSet:
 * @command: the command to be executed.
 *
 * Set a configuration parameter
 * syntaxe: SET <parm> <value>
 * were parm is:
 * - DATE <date>
 *   the epoch time as a time_t
 *   default = 0
 * - INTERVAL <interval>
 *   the delay is seconds since the last ping at which the reset is launched
 *   value = 1..32767
 *   default = 60
 * - TEST ON|OFF
 *   whether a reset is really launched, or is just flagged as during tests
 *   value = ON (false, not a test) or OFF (true, is a test)
 *   default = ON
 *
 * Returns: true if the command has been successfully executed, false else.
 */
bool cmdSet( String command )
{
    bool ok = false;
  
    if( command.startsWith( "DATE ", 4 )){
        ok = cmdSetDate( command );
    } else if( command.startsWith( "DELAY ", 4 )){
        ok = cmdSetDelay( command );
    } else if( command.startsWith( "TEST ", 4 )){
        ok = cmdSetTest( command );
    }
    return( ok );
}

/**
 * cmdSetDate:
 * @command: the command to be executed.
 *
 * Set the current date
 * syntaxe: SET DATE <value>
 *   where value is an epoch time (count of seconds since 1970-01-01)
 * This is needed in order to be able actual reset time in EEPROM traces.
 *
 * Returns: true if the command has been successfully executed, false else.
 */
bool cmdSetDate( String command )
{
    if( command.length() > 9 ){
        String rest = command.substring( 9 );
        time_t epoch = rest.toInt();
        setTime( epoch );
        dateSet = true;
        return( true );
    }
    return( false );
}

/**
 * cmdSetDelay:
 * @command: the command to be executed.
 *
 * Set the reboot delay parameter
 * syntaxe: SET DELAY <value>
 *   the delay is seconds since the last ping at which the reset is launched
 *   value = 1..32767
 *   default = 60
 *
 * Returns: true if the command has been successfully executed, false else.
 */
bool cmdSetDelay( String command )
{
    if( command.length() > 10 ){
        String rest = command.substring( 10 );
        long long_delay = rest.toInt();
        if( long_delay >= 1 && long_delay <= 65535 ){
            parmDelay = int( long_delay );
            return( true );
        }
    }
    return( false );
}

/**
 * cmdSetTest:
 * @command: the command to be executed.
 *
 * Set the test parameter
 * syntaxe: SET TEST <value>
 *   whether a reset is really launched, or is just flagged during tests
 *   value = 0 (false, not a test) or 1 (true, is a test)
 *   default = 1
 *
 * Returns: true if the command has been successfully executed, false else.
 */
bool cmdSetTest( String command )
{
    if( command.length() > 9 ){
        String rest = command.substring( 9 );
        if( rest.equals( "ON" )){
            parmTest = true;
          return( true );
        }
        if( rest.equals( "OFF" )){
            parmTest = false;
            return( true );
        }
    }
    return( false );
}

/**
 * cmdStart:
 *
 * Start the watchdog
 * idempotent if already started
 * no input args
 *
 * Returns: true.
 */
bool cmdStart()
{
    if( startTime == 0 ){
        startTime = now();
        lastPing = startTime;
        digitalWrite( LED_START, HIGH );
    }
    return( true );
}

/**
 * cmdStatus:
 *
 * Display the current status of the watchdog
 * no input args
 * display:
 * - up date and time
 * - start date and time, or zero if not started
 * - current interval
 * - current test
 * - last ping date and time (may be zero)
 * - date and time of reboot, or zero if not started
 * - last reset time
 *
 * Returns: true:
 */
bool cmdStatus()
{
    nwSerialPrintVersion();
    Serial.println( F( "Current status:" ));
    Serial.print  ( F( " Reset delay:    " ));               /* reset delay */
    Serial.print  ( parmDelay );
    Serial.println( F( " sec." ));
    Serial.print  ( F( " Test mode:      " ));               /* test mode */
    Serial.println( parmTest ? F( "ON (test mode)" ) : F( "OFF (reset mode)" ));
    Serial.print  ( F( " Date set:       " ));               /* whether the date has been set */
    Serial.println( dateSet ? F( "yes" ) : F( "no" ));
    Serial.print  ( F( " Status:         " ));               /* current status */
    if( resetTime > 0 ){
        Serial.println( F( "reset" ));
        Serial.print  ( F( "   Reset time:   " ));           /* reset time (if resetted) */
        Serial.println( nwDateTimeString( resetTime ));
    } else if( startTime > 0 ){
        Serial.println( F( "started" ));
        Serial.print  ( F( "   Start time:   " ));           /* start time (if started) */
        Serial.println( nwDateTimeString( startTime ));
        Serial.print  ( F( "   Last ping:    " ));           /* last ping (if started) */
        Serial.println( nwDateTimeString( lastPing ));
        time_t tnow = now();
        Serial.print  ( F( "   Now is:       " ));           /* current time (if started) */
        Serial.println( nwDateTimeString( tnow ));
        Serial.print  ( F( "   Before reset: " ));           /* left before reset (if started) */
        Serial.print  ( parmDelay-(tnow-lastPing));
        Serial.println( F( " sec. left" ));
    } else {
        Serial.println( F( "stopped" ));
    }
    Serial.print  ( F( " Last reset:   " ));                 /* last reset event */
    nwEvent ev = nwEEPROMResetEventGet( 0 );
    if( ev.isNull()){
        Serial.println( F( "none" ));
    } else {
        Serial.println( "" );
        ev.display( strSpace3 );
    }
    Serial.flush();
    return( true );
}

/**
 * cmdStop:
 *
 * Stop the watchdog
 * idempotent if already stopped (or not yet started)
 * no input args
 *
 * Returns: true.
 */
bool cmdStop()
{
    cmdReinit();
    return( true );
}

/**
 * execReset
 * @reason: the reset reason code.
 *
 * If not in test mode, reset the PC and stores the event in EEPROM
 */
bool execReset( int reason )
{
    if( resetTime == 0 ){
        resetTime = now();
        digitalWrite( LED_RESET, HIGH );
        if( !parmTest ){
            /* write the reset time into eeprom */
            nwEvent ev( reason );
            nwEEPROMResetEventSetNew( ev );
            /* last, reset the PC */
            nwBlinkPin( EXEC_RESET, EXEC_BLINK );
        }
    }
    return( true );
}

