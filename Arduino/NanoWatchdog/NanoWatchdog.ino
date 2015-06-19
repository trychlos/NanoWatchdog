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

static const PROGMEM char strACKNOWLEDGE[]       = "ACKNOWLEDGE ";
static const PROGMEM char strAcknowledgeHelp[]   = "  ACKNOWLEDGE <index>  acknowledge a stored reset event (index counted from most recent=0)";
static const PROGMEM char strEEPROM[]            = "EEPROM ";
static const PROGMEM char strINIT[]              = "INIT";
static const PROGMEM char strEepromInitHelp[]    = "  EEPROM INIT          initialize the EEPROM (once, before NanoWatchdog first installation)";
static const PROGMEM char strDUMP[]              = "DUMP";
static const PROGMEM char strEepromDumpHelp[]    = "  EEPROM DUMP          dump the EEPROM content";
static const PROGMEM char strHELP[]              = "HELP";
static const PROGMEM char strHelpHelp[]          = "  HELP                 list available commands";
static const PROGMEM char strNOOP[]              = "NOOP";
static const PROGMEM char strNoopHelp[]          = "  NOOP                 no-operation (used during NanoWatchdog initialization)";
static const PROGMEM char strPING[]              = "PING";
static const PROGMEM char strPingHelp[]          = "  PING                 ping the watchdog, reinitializing the timeout delay";
static const PROGMEM char strREBOOT[]            = "REBOOT ";
static const PROGMEM char strRebootHelp[]        = "  REBOOT <reason>      reset the PC right now";
static const PROGMEM char strREINIT[]            = "REINIT";
static const PROGMEM char strReinitHelp[]        = "  REINIT               reinit the watchdog after a reset (development mode)";
static const PROGMEM char strSET[]               = "SET ";
static const PROGMEM char strDATE[]              = "DATE ";
static const PROGMEM char strSetDateHelp1[]      = "  SET DATE <date>      set current UTC date as a count of seconds since 1970-01-01 (EPOCH time)";
static const PROGMEM char strSetDateHelp2[]      = "                       (needed for storing actual reset date and time)";
static const PROGMEM char strDELAY[]             = "DELAY ";
static const PROGMEM char strSetDelayHelp1[]     = "  SET DELAY <delay>    set no-ping timeout before reset (min=1, max=65535 (~18h)) [";
static const PROGMEM char strSetDelayHelp2[]     = " sec.]";
static const PROGMEM char strTEST[]              = "TEST ";
static const PROGMEM char strSetTestHelp1[]      = "  SET TEST ON|OFF      set test mode [";
static const PROGMEM char strON[]                = "ON";
static const PROGMEM char strOFF[]               = "OFF";
static const PROGMEM char strSTART[]             = "START";
static const PROGMEM char strStartHelp[]         = "  START                start the watchdog";
static const PROGMEM char strSTATUS[]            = "STATUS";
static const PROGMEM char strStatusHelp[]        = "  STATUS               display the current watchdog status";
static const PROGMEM char strSTOP[]              = "STOP";
static const PROGMEM char strStopHelp[]          = "  STOP                 stop the watchdog";
static const PROGMEM char strInvalidCommand[]    = "Unknown or invalid command: ";
static const PROGMEM char strOk[]                = "OK: ";
static const PROGMEM char strCro[]               = "[";
static const PROGMEM char strCrf[]               = "] - ";
static const PROGMEM char strEepromDump[]        = "EEPROM dump:";
static const PROGMEM char strInitEvent[]         = "  Initialization event:";
static const PROGMEM char strSpace4[]            = "    ";
static const PROGMEM char strSpace6[]            = "      ";
static const PROGMEM char strResetLastTrace[]    = "  Reset last traces:";
static const PROGMEM char strCount[]             = "    count: ";
static const PROGMEM char strReset[]             = "    reset #";
static const PROGMEM char strAvailableCommands[] = "Available commands:";
static const PROGMEM char strCurrentStatus[]     = "Current status:";
static const PROGMEM char strResetDelay[]        = "  Reset delay:  ";
static const PROGMEM char strSec[]               = " sec.";
static const PROGMEM char strTestMode[]          = "  Test mode:    ";
static const PROGMEM char strTestModeOn[]        = "ON (test mode)";
static const PROGMEM char strTestModeOff[]       = "OFF (reset mode)";
static const PROGMEM char strDateSet[]           = "  Date set:     ";
static const PROGMEM char strYes[]               = "yes";
static const PROGMEM char strNo[]                = "no";
static const PROGMEM char strStatus[]            = "  Status:       ";
static const PROGMEM char strStatusReset[]       = "reset";
static const PROGMEM char strResetTime[]         = "  Reset time:   ";
static const PROGMEM char strStatusStarted[]     = "started";
static const PROGMEM char strStartTime[]         = "  Start time:   ";
static const PROGMEM char strLastPing[]          = "  Last ping:    ";
static const PROGMEM char strNowIs[]             = "  Now is:       ";
static const PROGMEM char strBeforeReset[]       = "  Before reset: ";
static const PROGMEM char strSecLeft[]           = " sec. left";
static const PROGMEM char strStatusStopped[]     = "stopped";
static const PROGMEM char strLastResetNone[]     = "  Last reset:   none";
static const PROGMEM char strLastReset[]         = "  Last reset:";

/* the pin on which the LED is connected */
#define LED_START        14                /* A0: i/o port for start led */
#define LED_PING         15                /* A1: i/o port for ping led */
#define LED_RESET        16                /* A2: i/o port for reset led */
#define EXEC_RESET       17                /* A3: i/o port for reset relay */
#define LED_BLINK        300               /* elapsed milliseconds on/off for the ping led */
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
        if( command.startsWith( strACKNOWLEDGE )){
            ok = cmdAcknowledge( command );
        } else if( command.startsWith( strEEPROM )){
            ok = cmdEeprom( command );
        } else if( command.equals( strHELP )){
            ok = cmdHelp();
        } else if( command.equals( strNOOP )){
            ok = true;
        } else if( command.equals( strPING )){
            ok = cmdPing();
        } else if( command.startsWith( strREBOOT )){
            ok = cmdReboot( command );
        } else if( command.equals( strREINIT )){
            ok = cmdReinit();
        } else if( command.startsWith( strSET )){
            ok = cmdSet( command );
        } else if( command.equals( strSTART )){
            ok = cmdStart();
        } else if( command.equals( strSTATUS )){
            ok = cmdStatus();
        } else if( command.equals( strSTOP )){
            ok = cmdStop();
        }
        if( ok ){
            okCommand( command );
        } else {
            errorCommand( command );
        }
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
 * okCommand:
 *
 * Acknowledge the command.
 */
void okCommand( String command )
{
    Serial.print( strOk );
    Serial.println( command.c_str());
}

/**
 * errorCommand:
 *
 * Display an error message.
 */
void errorCommand( String command )
{
    Serial.print( strInvalidCommand );
    Serial.println( command.c_str());
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
  
    if( command.startsWith( strINIT, 7 )){
        ok = cmdEepromInit( command );
    } else if( command.startsWith( strDUMP, 7 )){
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
    bool ok = false;

    if( command.length() == 11 ){
        /* first, init the EEPROM to zero */
        for( int i=0 ; i<EEPROM_SIZE ; ++i ){
            EEPROM[i] = '\0';
        }
        /* then write the initialization event */
        nwEvent ev( NW_REASON_INIT );
        ev.acknowledge();
        nwEEPROMInitEventSet( ev );
        ok = true;
    }
    return( ok );
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
    nwEvent ev;
    bool ok = false;

    if( command.length() == 11 ){
        Serial.print( strCro );                        // [
        Serial.print( nwVersionString );
        Serial.print( strCrf );                        // ] -
        Serial.println( strEepromDump );               // EEPROM dump:
        /* read initialization event */
        ev = nwEEPROMInitEventGet();
        Serial.println( strInitEvent );                // "  Initialization event:"
        ev.display( strSpace4 );

        /* read reset traces count */
        int count = nwEEPROMResetEventCountGet();
        Serial.println( strResetLastTrace );           // "  Reset last traces:"
        Serial.print( strCount );                      // "    count: "
        Serial.println( count );

        for( int i=0 ; i<count ; ++i ){
            ev = nwEEPROMResetEventGet( i );
            Serial.print( strReset );                  // "    reset #"
            Serial.println( i );
            ev.display( strSpace6 );
        }
        Serial.flush();
        ok = true;
    }
    return( ok );
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
    Serial.print( strCro );
    Serial.print( nwVersionString );
    Serial.println( strCrf );
    Serial.println( strAvailableCommands );
    Serial.println( strAcknowledgeHelp );
    Serial.println( strEepromInitHelp );
    Serial.println( strEepromDumpHelp );
    Serial.println( strHelpHelp );
    Serial.println( strNoopHelp );
    Serial.println( strPingHelp );
    Serial.println( strRebootHelp );
    Serial.println( strReinitHelp );
    Serial.println( strSetDateHelp1 );
    Serial.println( strSetDateHelp2 );
    Serial.print  ( strSetDelayHelp1 );
    Serial.print( DEF_DELAY );
    Serial.println( strSetDelayHelp2 );
    Serial.print  ( strSetTestHelp1 );
    if( DEF_TEST ){
        Serial.print( strON );
    } else {
        Serial.print( strOFF );
    }
    Serial.println( "]" );
    Serial.println( strStartHelp );
    Serial.println( strStatusHelp );
    Serial.println( strStopHelp );
    Serial.flush();
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
        digitalWrite( LED_PING, HIGH );
        delay( LED_BLINK );
        digitalWrite( LED_PING, LOW );
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
  
    if( command.startsWith( strDATE, 4 )){
        ok = cmdSetDate( command );
    } else if( command.startsWith( strDELAY, 4 )){
        ok = cmdSetDelay( command );
    } else if( command.startsWith( strTEST, 4 )){
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
        if( rest.equals( strON )){
            parmTest = true;
          return( true );
        }
        if( rest.equals( strOFF )){
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
    time_t tnow;
    Serial.print( strCro );
    Serial.print( nwVersionString );
    Serial.println( strCrf );
    Serial.println( strCurrentStatus );                      // Current status:
    Serial.print( strResetDelay );                           /* delay (sec.) */
    Serial.print( parmDelay );
    Serial.println( strSec );
    Serial.print( strTestMode );                             /* test mode */
    if( parmTest ){
        Serial.println( strTestModeOn );
    } else {
        Serial.println( strTestModeOff );
    }
    Serial.print( strDateSet );                              /* whether the date has been set */
    if( dateSet ){
        Serial.println( strYes );
    } else {
        Serial.println( strNo );
    }
    Serial.print( strStatus );                               /* current status */
    if( resetTime > 0 ){
        Serial.println( strStatusReset );
        Serial.print( strResetTime );                        /* reset time (if resetted) */
        Serial.println( nwDateTimeString( resetTime ));
    } else if( startTime > 0 ){
        Serial.println( strStatusStarted );
        Serial.print( strStartTime );                        /* start time (if started) */
        Serial.println( nwDateTimeString( startTime ));
        Serial.print( strLastPing );                         /* last ping (if started) */
        Serial.println( nwDateTimeString( lastPing ));
        tnow = now();
        Serial.print( strNowIs );                            /* current time (if started) */
        Serial.println( nwDateTimeString( tnow ));
        Serial.print( strBeforeReset );                      /* left before reset (if started) */
        Serial.print( parmDelay-(tnow-lastPing));
        Serial.println( strSecLeft );
    } else {
        Serial.println( strStatusStopped );
    }
    nwEvent ev = nwEEPROMResetEventGet( 0 );                 /* last actual reset (if any) */
    if( ev.isNull()){
        Serial.println( strLastResetNone );  
    } else {
        Serial.println( strLastReset );
        ev.display( strSpace4 );
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
            /* write the reset time into eeprom
             */
            nwEvent ev( reason );
            nwEEPROMResetEventSetNew( ev );
            /* last, reset the PC
             */
            digitalWrite( EXEC_RESET, HIGH );
            delay( EXEC_BLINK );
            digitalWrite( EXEC_RESET, LOW );  
        }
    }
    return( true );
}

