 NanoWatchdog - README.md

 Summary
 =======
 
   1. NanoWatchdog
      1. What is it
      1. Differences against the standard Linux watchdog daemon
   1. The Arduino Nano board
      1. How it works
      1. Available commands
      1. Acknowledging the reset events
   1. The watchdog management daemon
      1. Running
      1. Available commands
      1. Reset reason codes
   1. The client
   1. References

-----------------------------------------------------------------------
 NanoWatchdog
 ============

 What is it
 ----------
 NanoWatchdog is an Arduino-based PC watchdog.
 It is connected to the monitored PC with which it communicates through
 USB serial bus. It expects to be periodically pinged. At the expiration
 of a configurable timeout, it resets the PC.
 Very simple.

 NanoWatchdog has the advantage of being fully independant of the PC
 hardware, and of a very low cost (hardware is less than 10€).

 As a (small) inconvenient, the 2015.1 version is a bit more rough than
 the watchdog [2] standard daemon (see below for the differences between
 them).

 NanoWatchdog is extended in order to provide most of watchdog features,
 so that the Arduino Nano-based board + its associated Perl programs may
 not only provide a full replacement for almost any watchdog device
 [2,5], but also hopefully add some new nice features... 

 As extended features, The NanoWatchdog package also provides:
 - explicit start and stop of the watchdog
 - current running status
 - an history of last 10 NanoWatchdog-activated resets.

 NanoWatchdog project is so built around:
 - an Arduino Nano board, which embeds the NanoWatchdog program,
 - a Perl daemon which checks for various conditions and periodically
   pings the board,
 - a Perl client which is able to communicate with the board and the
   daemon.

 Differences against the standard Linux watchdog daemon
 ------------------------------------------------------

 NanoWatchdog                        | Linux watchdog daemon
 ----------------------------------  | ----------------------------------
 May be started through serial USB transmitted command | Is started at up time
 May be stopped through serial USB transmitted command | No (simple) stop interface
 Hardware is fully PC independant    | Relies on the /dev/watchdog kernel device
 Reset the PC by activating the RESET motherboard pins | Soft reboot the PC by terminating the running processes, unmounting file systems, etc.
 Defines a small set of PC checks    | Has defined a full battery of configurable tests
 Is able to display its status       | No status
 Store the last reset events         | No history

-----------------------------------------------------------------------
 The Arduino Nano board
 ======================

 The Arduino Nano board communicates with the NanoWatchdog daemon
 through an USB port. It receives configuration parameters, along with
 periodic pings.
 If a ping has not been received after a configurable delay, the board
 activates the RESET motherboard feature, through an embedded micro-relay.

 Due to its conception, the NanoWatchdog board hardware costs less that
 10€, and this is less than 10 times the costs of the usual branded
 watchdog hardwares. It is totally independant of the running operating
 system, as long as this one is capable of running a Perl program.

 How it works
 ------------
 At power time, NanoWatchdog stays in a wait state until it receives a
 'START' command. Once started, NanoWatchdog expects to be 'PING'-ed
 before the set delay expires. At each loop, it compares the last ping
 time against the current time, and reset the PC if the difference is
 greater than the set delay.

 NanoWatchdog may be 'STOP'-ed at any time, going back to wait state.
 Each reset action is traced through an event written in the Arduino
 EEPROM.

 NanoWatchdog keeps trace of the ten last reset events.

 Available commands
 ------------------

 Commands are sent to the NanoWatchdog board from the provided
 nw-client.pl client. Answers are displayed on client standard output.

 NanoWatchdog command interpreter is very rough:
 - Commands are case-sensitive.
 - When a command is composed with several words, NanoWatchdog board
   expects words be separated by one single space.

 A minimal set of commands should be sent to the NanoWatchdog board at
 PC initialization:
 - in order to set running mode:     `SET TEST OFF`
 - in order to set the current date: `SET DATE <date>`
 - in order to start the watchdog:   `START`.
 The nw-daemon.pl management daemon takes care of that when connecting
 to the serial bus (see below).

 ### Miscellaneous commands:

 `HELP`                 display the list of available commands

 `NOOP`                 no-operation command

 `REINIT`               re-init the operation after a reset has been
                      initiated, stopping the watchdog and
                      re-initializing internal counters; this is rather
                      used while in development phase

 ### Watchdog management:

 `START`                start the watchdog

 `STOP`                 stop the watchdog

 `STATUS`               display the current watchdog status, along with
                      the last stored reset event

 `REBOOT <reason>`      a command to unconditionnally reset the PC;
                      the reason will be stored in the reset event;
                      externally provided reason codes must fit in the
                      [16..127] range.

 ### EEPROM management

 `EEPROM INIT`          initialize the EEPROM content, writing a first
                      initialization event on top of it. This must be
                      done only once, at NanoWatchdog first run

 `EEPROM DUMP`          dump the EEPROM content

 ### Configuration

 `SET TEST ON|OFF`      set test mode on of off.
                      In test mode (ON), the reset is not actually
                      activated nor an event is written in the EEPROM;
                      only the red LED is lighted on

 `SET DATE <time>`      set the current date as the count of seconds since
                      1970-01-01 (EPOCH time); this is needed in order
                      to display actual dates in STATUS output

 `SET DELAY <number>`   set the timeout delay before resetting the PC if
                      no ping has happened

 ### Reset events management

 `ACKNOWLEDGE <index>`  acknowledge the specified reset event
                      index starts at zero (the most recent event), and
                      is valid up to 9, as only the 10 last events are
                      stored in EEPROM.

 Acknowledging the reset events
 ------------------------------
 Each reset event holds an 'acknowledgment' bit. This bit is cleared
 when the reset event occurs, and can only be set via the `ACKNOWLEDGE`
 command.

 This acknowledgment bit has no effect on the NanoWatchdog behavior by
 itself. It is only present to make easier the history management of
 the reset events.

 Use case:

 It may be desirable for the administrator to receive a mail when the
 PC reboots, and it may also be desirable to know why it has rebooted.
 By querying the last reset event of the NanoWatchdog via the 'STATUS'
 command, the administrator may know if the last reset event has been
 acknowledged. If not, then this is most probably because the last
 reboot has been initiated by the NanoWatchdog and this particular
 event has not yet been acknowledged. After having got this information,
 it is now time for the administrator to acknowledge this last event,
 thus preparing the next reboot, and go on.

-----------------------------------------------------------------------
 The watchdog management daemon
 ==============================

 The NanoWatchdog daemon is derived from SerialCS [4], a client/server
 set of Perl programs :

 - the server get its commands from a client connected through a TCP
   socket; two ports are opened: one for commands targeting the
   NanoWatchdog board through the serial bus, and the other for commands
   targeting the management daemon itself

 - if the command has been read on the serial command port, then it is
   sent to the NanoWatchdog board through the serial bus; the board
   answer is received through the same way, and sent back to the client

 - if the command has been read on the daemon command port, then it is
   interpreted and executed; a small acknowledgment is sent back to the
   client.

 The NanoWatchdog watchdog daemon keeps the same main features from
 SerialCS, extending them (even if not all yet implemented) to those of
 the standard Linux watchdog daemon:
 - automatically ping the hardware daemon (here the Arduino Nano board)
   instead of the Linux kernel /dev/watchdog device
 - have a configuration file in order to run some user-defined other
   tests.

 The NanoWatchdog watchdog daemon is expected to be autonomous.
 As opposed to SerialCS server, the NanoWatchdog watchdog daemon doesn't
 block when reading from the client TCP socket. Instead, its main loop
 is entirely watchdog-centric, and getting serial or daemon commands
 from a client is only one of the executed tasks.

 For its pinging of NanoWatchdog Arduino board, NanoWatchdog watchdog
 daemon relies on a loop where all configured checks are done.
 So each ping actually occurs after the specified interval plus the
 total elapsed time spent to these checks. One should make sure that
 this total time keeps less than the reboot delay, or something weird
 may happens ;)

 Running
 -------
 The NanoWatchdog management daemon is a Perl program which should be
 run at PC startup.

 When run without any command-line options, the program only displays
 its help message, and gracefully exit. So at least one option (e.g.
 `--nohelp`) must be specified.

 The NanoWatchdog management daemon defaults to be configured through
 the `/etc/nanowatchdog.conf` configuration file.

 It is also able to interpret the `/etc/watchdog.conf` configuration file
 if asked for (see include directive).

 See doc/Parameters.ods sheet for a full detail of command-line options,
 known configuration parameters, and management daemon commands.

 See also the output of `nw-daemon.pl -help` command for a list of
 command-line options and their default values.

 Available commands
 ------------------
 The NanoWatchdog management daemon can be queried from a client
 through its dedicated port (see 'port-daemon' configuration parameter).

 It recognizes following commands:

 `DUMP OPTS`      dump on standard output the current value of all
                command-line options

 `DUMP PARMS`     dump on standard output the current value of all
                configuration parameters

 `GET <parm>`     display on standard output the value of the 'parm'
                configuration parameter or command-line option.
                e.g. GET admin

 `PING ON|OFF`    restore (ON) on inhibit (OFF) the periodic ping of the
                NanoWatchdog board

 `QUIT`           gracefully terminates the daemon

 Reset reason codes
 ------------------

 The NanoWatchdog management daemon makes use of following reason
 codes:

 reason code  | parameter
 -----------  | ---------------
          16  | max-load-1
          17  | max-load-5
          18  | max-load-15
          19  | min-memory
          20  | max-temperature
          21  | pidfile
          22  | ping
          23  | interface

-----------------------------------------------------------------------
 The client
 ==========

 The client is a simple command-line application which takes commands 
 from its input, send them to the server, and displays on its output
 all that is sent back by the server.
 This is more or less roughly the same client than those from SerialCS.
 
 This NanoWatchdog client command-line program is provided only as a
 convenience for the user. But it doesn't embed any particularity
 related to the watchdog, nor anything which would be tied to this
 particular TCP server.

 Instead, any TCP client able to send strings to a server, and get and
 display its answers should be fine here.

-----------------------------------------------------------------------
 References
 ==========

 [1] https://www.kernel.org/doc/Documentation/watchdog/watchdog-api.txt

 [2] http://linux.die.net/man/8/watchdog

 [3] http://linux.die.net/man/5/watchdog.conf

 [4] https://github.com/trychlos/serialcs

 [5] http://www.berkprod.com/Other_Pages/Price_Ordering.aspx

-----------------------------------------------------------------------
 P. Wieser - Created on 2015, may 24th
             Last updated on 2017, apr. 29th
