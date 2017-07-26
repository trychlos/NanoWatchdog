#!/usr/bin/perl -w
# @(#) NanoWatchdog
#
# Copyright (C) 2015 Pierre Wieser (see AUTHORS)
#
# NanoWatchdog is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# NanoWatchdog is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NanoWatchdog; if not, see
# <http://www.gnu.org/licenses/>.
#
# This work is based on SerialCS, from the same author.
#
# All configuration parameters are stored in $parms global hash, whether
# they are hardcoded default, come from the configuration file(s), or
# have been set as command-line options.

use strict;
use Device::SerialPort;
use File::Basename;
use File::Find;
use Getopt::Long;
use IO::Socket::INET;
use MIME::Lite;
use POSIX;
use Proc::Daemon;
use Sys::Hostname;
use Sys::Syslog qw(:standard :macros);

use constant { true => 1, false => 0 };

my $me = basename( $0 );				# program base name
my $my_version = "11.2017";
my $errs = 0;							# exit code
my $nbopts = $#ARGV;					# command-line args count

# auto-flush on socket
$| = 1;

sub config_read_file;
sub max_load_5_def;
sub max_load_15_def;
sub msg;
sub msg_format;
sub msg_version;
sub parse_verbose;
sub send_from_def;
sub send_serial;
sub start_watchdog;

# Configuration parameters
# ========================
# There is one and only one rationale: gather in one single place all
# elements that participate to the configuration, in order to make the
# maintenance easier.
#
# A configuration parameter has a canonical name, a type and a default
# value.
# It may also have:
# - a counterpart in the NanoWatchdog (resp. watchdog) configuration file
#   which supersedes the default value;
# - a counterpart as a command-line option, which itself supersedes the
#   configuration file.
#
# Following keys are managed:
#   key       rule     when    comment
#   --------  -------  ------  -------------------------------------------------------
#   type      defined  must    the type of the expected value
#   category  defined  must    the category of the parameter
#   def       defined  must    the default value
#   min       defined  may     minimal allowed value if apply
#   max       defined  may     maximal allowed value if apply
#   parms     defined  may     the parameters to be passed to a computation function
#   config    defined  may     the name of the corresponding key in configuration file
#   value     dynamic  must    the current value
#   origin    dynamic  must    the origin of the current value
#   undef     defined  may     a value which means undef
#
# Handling the configuration parameters doesn't rely of specification
# ordering here. Instead handling takes care of:
#  1/ first set fixed default values
#  2/ then handle parameters which are overriden in the command-line
#  3/ then handle parameters which are specified in the configuration
#     file
#  4/ only last compute default values for parameters which are not
#     specified anywhere and have a computed default values.
#
# The configuration parameters are stored in a (unordered) hash.

use constant {
	PARM_CATEGORY_RUN      => 1,
	PARM_CATEGORY_CONFIG   => 2,
	PARM_CATEGORY_LISTENER => 3,
	PARM_CATEGORY_BOARD    => 4,
	PARM_CATEGORY_WATCHDOG => 5,
};

use constant {
	PARM_TYPE_BOOL         => 1,
	PARM_TYPE_INT          => 2,
	PARM_TYPE_STRING       => 3,
};

use constant {
	PARM_ORIGIN_DEFAULT    => 1,
	PARM_ORIGIN_CONFIG     => 2,
	PARM_ORIGIN_CMDLINE    => 3,
	PARM_ORIGIN_RUN        => 4,
};

my $parms = {
	# whether we set the board in test mode
	'action'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> true },
	# board serial bus baud rate (bps)
	'baudrate'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_BOARD,
						 'def'			=> 19200,
						 'config'		=> "baudrate" },
	# port number of the listener communication proxy to the board
	'boardport'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_LISTENER,
						 'def'			=> 7777,
						 'config'		=> "port-serial" },
	# nanowatchdog configuration file
	'config'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> "/etc/nanowatchdog.conf" },
	# whether to daemonize at startup
	'daemon'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> true },
	# port number of the daemon command interface
	'daemonport'	=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_LISTENER,
						 'def'			=> 7778,
						 'config'		=> "port-daemon" },
	# delay (secs.) without ping before reset condition
	'delay'			=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> 60,
						 'min'			=> 10,
						 'max'			=> 3600,
						 'config'		=> "delay" },
	# device filename
	'device'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_BOARD,
						 'def'			=> "/dev/ttyUSB0",
						 'config'		=> "device" },
	# force out-of-limits parameters
	'force'			=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> false },
	# whether to display help and gracefully exit
	'help'			=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> false },
	# include another configuration file (e.g. /etc/watchdog.conf)
	'include'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> "",
						 'config'		=> "include" },
	# check the interface
	'interface'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> [],
						 'config'		=> "interface" },
	# interval between pings of the board
	'interval'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> 10,
						 'min'			=> 5,
						 'max'			=> 60,
						 'config'		=> "interval" },
	# ipv4 of the management daemon listener
	'listener'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_LISTENER,
						 'def'			=> "127.0.0.1",
						 'config'		=> "ip" },
	# loop messages are displayed every 'logtick' loops
	'logtick'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> 1,
						 'config'		=> "logtick" },
	# as max-load-5 and max-load-15 rely on max-load-1 value, take care
	# of having a max-load-1 suitable default
	'maxload1'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> 0,
						 'min'			=> 2,
						 'max'			=> 100,
						 'undef'		=> 0,
						 'config'		=> "max-load-1" },
	'maxload5'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> \&max_load_5_def,
						 'parms'		=> [ qw/max-load-1/ ],
						 'min'			=> 2,
						 'max'			=> 100,
						 'config'		=> "max-load-5" },
	'maxload15'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> \&max_load_15_def,
						 'parms'		=> [ qw/max-load-1/ ],
						 'min'			=> 2,
						 'max'			=> 100,
						 'config'		=> "max-load-15" },
	# the minimum available memory (%)
	'memory'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> 0,
						 'config'		=> "max-temperature",
						 'undef'		=> 0 },
	# where to store the management daemon pid
	'nwpid'			=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> "",
						 'config'		=> "pid-file" },
	# whether to ping the board
	'nwping'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> true },
	# where to store the board status
	'nwstatus'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> "",
						 'config'		=> "status-file" },
	# timeout when initializing the connection to the board
	'opentimeout'	=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_BOARD,
						 'def'			=> 10,
						 'config'		=> "open-timeout" },
	# list of PID filenames to check
	'pidfile'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> [],
						 'config'		=> "pidfile" },
	# list of ipv4 to check
	'ping'			=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> [],
						 'config'		=> "ping" },
	# timeout when reading from the board
	'readtimeout'	=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_BOARD,
						 'def'			=> 5,
						 'config'		=> "read-timeout" },
	# the emitter of the mail
	'sendfrom'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> \&send_from_def,
						 'config'		=> "send-from" },
	# whether to send a mail at boot
	'sendmail'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> "never",
						 'config'		=> "send-mail" },
	# mail destinataire
	'sendto'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_CONFIG,
						 'def'			=> "root\@localhost",
						 'config'		=> "admin" },
	# whether to (try to) manage the board
	'serial'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_BOARD,
						 'def'			=> true },
	# whether to soft boot (ignored)
	'softboot'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> false },
	# sync the filesystem (ignored)
	'sync'			=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> false },
	# the maximum admitted temperature (°C)
	'temperature'	=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> 90,
						 'config'		=> "max-temperature" },
	# test directory
	'testdir'		=> { 'type'			=> PARM_TYPE_STRING,
						 'category'		=> PARM_CATEGORY_WATCHDOG,
						 'def'			=> "/etc/watchdog.d",
						 'config'		=> "test-directory" },
	# whether to run verbosely
	'verbose'		=> { 'type'			=> PARM_TYPE_INT,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> 34 },
	# whether to display the version and gracefully exit
	'version'		=> { 'type'			=> PARM_TYPE_BOOL,
						 'category'		=> PARM_CATEGORY_RUN,
						 'def'			=> false },
};

my $opt_force = \$parms->{'force'}{'value'};
my $opt_verbose = \$parms->{'verbose'}{'value'};

# Command-line options definitions
# ================================
# Rationale: gather in one (ordered) place the command-line options.
#
# Following keys are managed:
#   key       rule     when    comment
#   --------  -------  ------  -------------------------------------------------------
#   help      defined  may     the help message
#   parm      defined  always  the parameter canonical name
#   template  defined  may     an example of the value to be entered
#   spec      defined  may     a specification when cannot be infered from parameter
#   parse     defined  may     a ref to a parse function
#
# The command-line interpretation stops as soon as an error is detected.
# The result goes to the 'parms' global configuration hash, with the
# 'command' origin.

my $options = [
	# standard command-line options
	{ 'help'		=> { 'help'		=> "print this message, and gracefully exit",
						 'parm'		=> "help" }},
	{ 'version'		=> { 'help'		=> "print the program version, and gracefully exit",
						 'parm'		=> "version" }},
	{ 'verbose'		=> { 'help'		=> "specify the verbosity level",
						 'parm'		=> "verbose",
						 'spec'		=> "=s",
						 'parse'	=> \&parse_verbose }},
	# run behavior
	{ 'config'		=> { 'template'	=> "=/path/to/filename",
						 'help'		=> "configuration filename",
						 'parm'		=> "config" }},
	{ 'daemon'		=> { 'help'		=> "fork in the background and run as a daemon",
						 'parm'		=> "daemon" }},
	# board
	{ 'serial'		=> { 'help'		=> "try to talk with a serial device",
						 'parm'		=> "serial" }},
	{ 'device'		=> { 'template'	=> '=/path/to/device',
						 'help'		=> "the serial bus to talk with",
						 'parm'		=> "device" }},
	# TCP listener
	{ 'ip'			=> { 'template'	=> '=1.2.3.4',
						 'help'		=> "IP address the TCP server must listen to for commands",
						 'parm'		=> "listener" }},
	{ 'port-daemon'	=> { 'template'	=> '=number',
						 'help'		=> "port number the TCP server must listen to for daemon commands",
						 'parm'		=> "daemonport" }},
	{ 'port-board'	=> { 'template'	=> '=number',
						 'help'		=> "port number the TCP server must listen to for board commands",
						 'parm'		=> "boardport" }},
	# watchdog actions
	{ 'delay'		=> { 'template'	=> '=number',
						 'help'		=> "delay (secs.) to reboot without ping",
						 'parm'		=> "delay" }},
	{ 'interval'	=> { 'template'	=> '=number',
						 'help'		=> "interval between pings",
						 'parm'		=> "interval" }},
	{ 'ping'		=> { 'help'		=> "whether to ping the NanoWatchdog on wake",
						 'parm'		=> "nwping" }},
	# watchdog specific options
	# not all watchdog configuration parameters may be specified as a
	# command-line option - see man watchdog for more information
	{ 'action'		=> { 'help'		=> "not in test mode, actually reboot the machine",
						 'parm'		=> "action" }},
	{ 'sync'		=> { 'help'		=> "synchronize the filesystem during the check loop",
						 'parm'		=> "sync" }},
	{ 'softboot'	=> { 'help'		=> "soft-boot the system if an error occurs during the check loop",
						 'parm'		=> "softboot" }},
	{ 'force'		=> { 'help'		=> "force the usage of watchdog parameters outside of limits",
						 'parm'		=> "force" }},
];

my $option_help_post = " Daemon command interface:
    DUMP PARMS                 dump the configuration parameters values
    GET <parm>                 returns the value of (case-sensitive) parameter
    HELP                       print this list of commands
    PING ON|OFF                reactive or inhibit the periodic ping
    QUIT                       terminates the daemon
    SET VERBOSE <n>            set the verbosity level
 Daemon signals:
    HUP                        reloads the configuration file
    TERM                       terminates the daemon
    USR1                       restart the NanoWatchdog
 Daemon cumulative verbosity levels:
 This may also be entered as '0x<hexa' or '0b<binary>' strings.
        1      0x1  1<< 0      dump configuration on hup signal
        2      0x2  1<< 1      when terminating the daemon (default)
        4      0x4  1<< 2      dump configuration on startup
        8      0x8  1<< 3      dump command-line options on startup (obsolete)
       16     0x10  1<< 4      when sending the startup mail
       32     0x20  1<< 5      when starting the daemon and the board (default)
       64     0x40  1<< 6      startup debug
      128     0x80  1<< 7      configuration debug level 1
      256    0x100  1<< 8      configuration debug level 2
      512    0x200  1<< 9      client informations
     1024    0x400  1<<10      client debug level 1
     2048    0x800  1<<11      client debug level 2
     4096   0x1000  1<<12      board informations
     8192   0x2000  1<<13      board debug level 1
    16384   0x4000  1<<14      board debug level 2
    32768   0x8000  1<<15      loop debug level 1
    65536  0x10000  1<<16      loop debug level 2.";

# verbosity levels
use constant {
	LOG_CONFIG_HUP    => 1 << 0,			#     1: dump configuration on hup signal
	LOG_INFO_QUIT     => 1 << 1,			#     2: when terminating the daemon (default)
	LOG_CONFIG_START  => 1 << 2,			#     4: dump configuration on startup
	LOG_CMDLINE_START => 1 << 3,			#     8: dump command-line options on startup
	LOG_MAIL_START    => 1 << 4,			#    16: when sending the startup mail
	LOG_INFO_START    => 1 << 5,			#    32: when starting the daemon and the board (default)
	LOG_DEBUG_START   => 1 << 6,			#    64: startup debug
	LOG_CONFIG_DEBUG1 => 1 << 7,			#   128: configuration debug level 1
	LOG_CONFIG_DEBUG2 => 1 << 8,			#   256: configuration debug level 2
	LOG_CLIENT_INFO   => 1 << 9,			#   512: client informations
	LOG_CLIENT_DEBUG1 => 1 << 10,			#  1024: client debug level 1
	LOG_CLIENT_DEBUG2 => 1 << 11,			#  2048: client debug level 2
	LOG_BOARD_INFO    => 1 << 12,			#  4096: board informations
	LOG_BOARD_DEBUG1  => 1 << 13,			#  8192: board debug level 1
	LOG_BOARD_DEBUG2  => 1 << 14,			# 16384: board debug level 2
	LOG_LOOP_DEBUG1   => 1 << 15,			# 32768: loop debug level 1
	LOG_LOOP_DEBUG2   => 1 << 16,			# 65536: loop debug level 2
};

my $daemon_socket = undef;
my $board_socket = undef;
my $serial = undef;
my $background = false;
my $have_to_quit = false;
my $reason_code = 0;
my $board_status = undef;

# ---------------------------------------------------------------------
# handle HUP signal
sub catch_hup(){
	msg "HUP signal handler: reloading the configuration file ".$parms->{'config'}{'value'};
	if( config_read( $parms, $parms->{'config'}{'value'} )){
		config_dump( $parms ) if $$opt_verbose & LOG_CONFIG_HUP;
	}
}

# ---------------------------------------------------------------------
# handle Ctrl-C
sub catch_int(){
	msg( "exiting on Ctrl-C" ) if $$opt_verbose & LOG_INFO_QUIT;
	$errs = 1;
	catch_term();
}

# ---------------------------------------------------------------------
# program termination
sub catch_term(){
	if( defined( $serial )){
		send_serial( "STOP" );
		$serial->close();
	}
	$board_socket->close() if defined( $board_socket );
	$daemon_socket->close() if defined( $daemon_socket );
	msg( "NanoWatchdog terminating..." ) if ( $$opt_verbose & LOG_INFO_QUIT ) || $background;
	exit;
}

# ---------------------------------------------------------------------
# handle USR1 signal
sub catch_usr1(){
	msg "USR1 signal handler: restart the NanoWatchdog";
	if( defined( $serial )){
		send_serial( "STOP" );
		sleep( 1 );
		start_watchdog();
	}
}

# ---------------------------------------------------------------------
# deals with cmdline options
# get options specifications as an array of hash refs:
# - parm:     the parameter canonical name
# - help:     help message (single line)
# - template: example of option value
# return true if the command-line has been parsed without error
# handle --help and --version options which both gracefully exits
sub cmdline_get_options( $$ ){
	my $local_parms = shift;				# a ref to the parameters definition hash
	my $local_opts = shift;					# a ref to the options definition array
	# temporary hash to hold the options values
	my %temp_opts = ();
	# temporary array to hold the options specs
	my @temp_specs = ();
	# build the specification array for GetOptions()
	# simultaneously initializing resulting options hash
	foreach( @$local_opts ){
		# $key is the command-line option
		# there is only one $key per array element
		foreach my $key ( keys %$_ ){
			if( defined( $_->{$key}{'parm'} )){
				my $parm_def = $local_parms->{$_->{$key}{'parm'}};
				if( defined( $parm_def )){
					my $spec = $key;
					my $tmp_spec = cmdline_get_option_spec( $_->{$key}, $parm_def );
					if( defined( $tmp_spec )){
						$spec .= $tmp_spec;
						push @temp_specs, $spec;
					}
				}
			} else {
				msg( "no configuration parameter defined for 'key' command-line option" );
			}
		}
	}
	if( !GetOptions( \%temp_opts, @temp_specs )){
		msg "try '${0} --help' to get full usage syntax";
		$errs = 1;
		return( false );
	}
	# write the read value to the global configuration parameters hash
	# $key is the command-line option
	foreach my $key ( keys %temp_opts ){
		my $opt_def = cmdline_get_option_def( $local_opts, $key );
		if( defined ( $opt_def ) && defined( $opt_def->{'parm'} )){
			my $parm_def = $local_parms->{$opt_def->{'parm'}};
			if( defined( $parm_def )){
				if( defined( $opt_def->{'parse'} )){
					$parm_def->{'value'} = $opt_def->{'parse'}->( $temp_opts{$key} );
				} else {
					$parm_def->{'value'} = $temp_opts{$key};
				}
				$parm_def->{'origin'} = PARM_ORIGIN_CMDLINE;
			}
		}
	}
	# handle --help option
	$local_parms->{'help'}{'value'} = true if $nbopts < 0;
	if( $local_parms->{'help'}{'value'} ){
		cmdline_help( $local_parms, $local_opts );
		return( false );
	}
	# handle --version option
	if( $local_parms->{'version'}{'value'} ){
		msg_version();
		exit;
	}
	return( true );
}

# ---------------------------------------------------------------------
# Returns the command-line definition hash for this option
sub cmdline_get_option_def( $$ ){
	my $local_opts = shift;				# a ref to the options definition array
	my $local_key = shift;				# the name of the option
	foreach( @$local_opts ){
		foreach my $key ( keys %$_ ){
			if( $key eq $local_key ){
				return( $_->{$key} );
			}
		}
	}
	msg( "no option definition found for '$local_key' command-line option" );
	return( undef );
}

# ---------------------------------------------------------------------
# Returns the spec suitable for this command-line option
sub cmdline_get_option_spec( $$ ){
	my $local_opt = shift;				# a ref to this command-line option definition
	my $local_def = shift;				# a ref to this configuration parameter definition
	my $spec = undef;
	if( defined( $local_opt->{'spec'} )){
		$spec = $local_opt->{'spec'};
	} elsif( $local_def->{'type'} == PARM_TYPE_BOOL ){
		$spec = "!";
	} elsif( $local_def->{'type'} == PARM_TYPE_INT ){
		$spec = "=i";
	} elsif( $local_def->{'type'} == PARM_TYPE_STRING ){
		$spec = "=s";
	} else {
		msg( $local_def->{'type'}.": unmanaged type for '".$local_opt->{'parm'}."' configuration parameter" );
	}
	return( $spec );
}

# ---------------------------------------------------------------------
# Display the command-line options help message
sub cmdline_help( $$ ){
	my $local_parms = shift;			# a ref to the global configuration parameters hash
	my $local_opts = shift;				# a ref to the command-line options array
	# help preambule
	msg_version();
	print " Usage: $0 [options]\n";
	# display help messages
	# compute max length
	my $local_max = 0;
	my $l;
	foreach( @$local_opts ){
		foreach my $key ( keys %$_ ){
			$l = length( $key );
			$l += 4 if cmdline_opt_is_bool( $local_parms, $_->{$key} );
			$l += length( $_->{$key}{'template'} ) if defined( $_->{$key}{'template'} );
			if( $l > $local_max ){
				$local_max = $l;
			}
		}
	}
	# display help line for each option
	foreach( @$local_opts ){
		foreach my $key ( keys %$_ ){
			print "  --";
			if( cmdline_opt_is_bool( $local_parms, $_->{$key} )){
				print "[no]";
			}
			print "$key";
			$l = length( $key );
			$l += 4 if cmdline_opt_is_bool( $local_parms, $_->{$key} );
			if( defined( $_->{$key}{'template'} )){
				print $_->{$key}{'template'};
				$l += length( $_->{$key}{'template'} );
			}
			for( my $i=$l ; $i<=$local_max ; ++$i ){
				print " ";
			}
			print "  ";
			print $_->{$key}{'help'} if defined( $_->{$key}{'help'} );
			# display default value
			if( defined( $_->{$key}{'parm'} )){
				my $parm_def = $local_parms->{$_->{$key}{'parm'}};
				if( defined( $parm_def ) && defined( $parm_def->{'def'} )){
					if( $parm_def->{'type'} == PARM_TYPE_BOOL ){
						print " [".( $parm_def->{'def'} ? "yes":"no" )."]";
					} else {
						print " [".$parm_def->{'def'}."]";
					}
				}
			}
			print "\n";
		}
	}
	# help end
	print "$option_help_post
";
}

# ---------------------------------------------------------------------
# returns true if the configuration parameter is a boolean
sub cmdline_opt_is_bool( $$ ){
	my $local_parms = shift;			# a ref to the global configuration parameters hash
	my $local_opt = shift;				# a ref to the option definition
	if( defined( $local_opt->{'parm'} )){
		my $parm_def = $local_parms->{$local_opt->{'parm'}};
		if( defined( $parm_def )){
			return( $parm_def->{'type'} == PARM_TYPE_BOOL );
		}
	}
	return( false );
}

# ---------------------------------------------------------------------
# dump the configuration parameters
sub config_dump( $ ){
	my $local_parms = shift;			# a ref to the configuration parameters hash
	my @tmp_dump = config_dump_to_array( $local_parms );
	foreach( @tmp_dump ){
		msg( $_ );
	}
}

# ---------------------------------------------------------------------
# dump the configuration parameters to an array of strings
sub config_dump_to_array( $ ){
	my $local_parms = shift;			# a ref to the configuration parameters hash
	my @out_dump = ();
	my $key_length = 0;
	my $value_length = 0;
	my $orig_length = config_str_origin_max_length();
	my $l;
	# compute max key length, max value length
	foreach my $key ( keys %$local_parms ){
		$l = length( $key );
		$key_length = $l if $l > $key_length;
		#print "key=$key, value=".$local_parms->{$key}."\n";
		my $str = config_str_value( $local_parms->{$key} );
		$l = length( $str );
		$value_length = $l if $l > $value_length;
	}
	$key_length = 9 if $key_length < 9;
	$value_length = 5 if $value_length < 5;
	my $str;
	my $pfx = "   ";
	my $tmp_s;
	push( @out_dump, "Configuration parameters:" );
	$str = $pfx . "parameter";
	$str .= ( " " x ( $key_length-7 ));
	$str .= "value";
	$str .= ( " " x ( $value_length-3 ));
	$str .= "origin";
	push( @out_dump, $str );
	$str = $pfx.( "-" x $key_length );
	$str .= "  ".( "-" x $value_length );
	$str .= "  ".( "-" x $orig_length );
	push( @out_dump, $str );
	foreach my $key ( sort keys %$local_parms ){
		if( $key ne "include" ){
			$str = $pfx.$key;
			$str .= ( " " x ( $key_length - length( $key ) + 2 ));
			$tmp_s = config_str_value( $local_parms->{$key} );
			$l = length( $tmp_s );
			$str .= $tmp_s;
			$str .= ( " " x ( $value_length - $l + 2 ));
			$str .= config_str_origin( $local_parms->{$key} );
			push( @out_dump, $str );
		}
	}
	return( @out_dump );
}

# ---------------------------------------------------------------------
# Handle the configuration files
# It happens that the standard Linux watchdog defines a configuration
# files where a same key may appear multiple times, which is not
# handled by any of the perl modules I have found. So have to deal with
# this here.
# As a free plus, this let us get rid of the perl::Config::Simple bug
# which doesn't know how to deal with an empty configuration file.
# Synoptic:
#   config_read( $parms, $path );
# Ignore parameters from configuration file which are not defined in
# the parameters_definition.
# Returns: true if parameters have been successfully read
sub config_read( $$ ){
	my $local_parms = shift;			# a ref to the global configuration parameters hash
	my $local_path = shift;				# the configuration file name
	my $temp_cfg = {};
	my $temp_errs = 0;
	config_read_file( $local_path, $temp_cfg );
	# only deals with parameters which have not been overriden by a
	# command-line option nor by a dynamic set at runtime
	# $key if the configuration parameter canonical name
	foreach my $key ( keys %$temp_cfg ){
		my $parm_def = parm_get_definition_by_config( $local_parms, $key );
		if( defined( $parm_def )){
			if( $parm_def->{'origin'} == PARM_ORIGIN_DEFAULT || $parm_def->{'origin'} == PARM_ORIGIN_CONFIG ){
				if( ref( $parm_def->{'def'} ) eq "ARRAY" ){
					$parm_def->{'value'} = $temp_cfg->{$parm_def->{'config'}};
				} else {
					$parm_def->{'value'} = $temp_cfg->{$parm_def->{'config'}}[0];
				}
				$parm_def->{'origin'} = PARM_ORIGIN_CONFIG;
			} else {
				my $qualifier = "unknown";
				if( $parm_def->{'origin'} == PARM_ORIGIN_CMDLINE ){
					$qualifier = "command-line";
				} elsif( $parm_def->{'origin'} == PARM_ORIGIN_RUN ){
					$qualifier = "runtime";
				}
				msg( "$key: value from configuration file ignored as superseded by $qualifier" );
			}
		}
	}
	# recompute values which depend of some code
	foreach my $key ( keys %$local_parms ){
		if( defined( $local_parms->{$key}{'def'} ) && ref( $local_parms->{$key}{'def'} ) eq "CODE" ){
			$local_parms->{$key}{'value'} =
							$local_parms->{$key}{'def'}->( $local_parms, $local_parms->{$key}{'parms'} );
		}
	}
	# last check for min/max values
	foreach my $key ( keys %$local_parms ){
		my $parm_def = $local_parms->{$key};
		if( defined( $parm_def->{'value'} ) &&
				( !defined( $parm_def->{'undef'} ) || $parm_def->{'undef'} != $parm_def->{'value'} )){
			# check for min value
			if( defined( $parm_def->{'min'} )){
				if( $parm_def->{'value'} < $parm_def->{'min'} && !$$opt_force ){
					msg( "$key: value=".$parm_def->{'value'}." < min=".$parm_def->{'min'}
						." and force is not set: forcing the value to min" );
					$parm_def->{'value'} = $parm_def->{'min'};
				}
			}
			# check for max value
			if( defined( $parm_def->{'max'} )){
				if( $parm_def->{'value'} > $parm_def->{'max'} && !$$opt_force ){
					msg( "$key: value=".$parm_def->{'value'}." > max=".$parm_def->{'max'}
						." and force is not set: forcing the value to max" );
					$parm_def->{'value'} = $parm_def->{'max'};
				}
			}
		}
	}
	return( $temp_errs == 0 );
}

# ---------------------------------------------------------------------
# Handle the filename spec
# Update the specified hash ref
sub config_read_file( $$ ){
	my $local_path = shift;				# the configuration filename
	my $local_cfg = shift;				# a ref to the output hash
	if( !-r $local_path ){
		msg( "configuration file ${local_path} not found: using default values" );
	} else {
		msg( "reading the configuration file ${local_path}" )
				if $$opt_verbose & LOG_CONFIG_DEBUG1;
		open( my $fh, '<:encoding(UTF-8)', $local_path )
				or die "unable to open $local_path file: $!\n";
		while( <$fh> ){
			chomp;
			my $line = $_;
			$line =~ s/#.*$//;
			$line =~ s/^\s+//;
			$line =~ s/\s*=\s*/=/;
			if( length( $line )){
				my( $key, $val ) = split( /=/, $line, 2 );
				# as a key may be defined more than once, push values
				# into an array
				$local_cfg->{$key} = [] if !defined( $local_cfg->{$key} );
				push( @{$local_cfg->{$key}}, $val );
			}
		}
		close( $fh );
	}
	# deal with includes
	if( defined( $local_cfg->{'include'} )){
		my $f = $local_cfg->{'include'}[0];
		delete( $local_cfg->{'include'} );
		config_read_file( $f, $local_cfg );
	}
}

# ---------------------------------------------------------------------
# returns the value of the parameter as a displayable string
sub config_str_value( $ ){
	my $parm_def = shift;			# a ref to the parameter definition hash
	my $out_str = "";
	if( defined( $parm_def->{'value'} )){
		if( ref( $parm_def->{'value'} ) eq "ARRAY" ){
			$out_str = "[".join( ",", @{$parm_def->{'value'}} )."]";
		} elsif( $parm_def->{'type'} == PARM_TYPE_BOOL ){
			$out_str = $parm_def->{'value'} ? "true":"false";
		} else {
			$out_str = $parm_def->{'value'};
		}
	} else {
		$out_str = "undef";
	}
	return( $out_str );
}

# ---------------------------------------------------------------------
# returns the label for the value's origin
sub config_str_origin( $ ){
	my $parm_def = shift;			# a ref to the parameter definition hash
	my $out_str = "";
	if( defined( $parm_def->{'origin'} )){
		if( $parm_def->{'origin'} == PARM_ORIGIN_DEFAULT ){
			$out_str .= "default";
		} elsif( $parm_def->{'origin'} == PARM_ORIGIN_CONFIG ){
			$out_str .= "configuration";
		} elsif( $parm_def->{'origin'} == PARM_ORIGIN_CMDLINE ){
			$out_str .= "command-line option";
		} elsif( $parm_def->{'origin'} == PARM_ORIGIN_RUN ){
			$out_str .= "daemon command interface";
		} else {
			$out_str .= "(unknown)";
		}
	} else {
		$out_str = "(undef)";
	}
	return( $out_str );
}

# ---------------------------------------------------------------------
# returns the size of the longest label for the value's origin
sub config_str_origin_max_length(){
	return( 24 );
}

# ---------------------------------------------------------------------
# returns true if the daemon is already running
# this command is run at the very beginning of the startup, and before
# configuration and command-line options have been read.
# The daemon has no chance of doing anything before being exited.
# NOTE that this sub is not really exact: another program may run with
# the same name, thus returning a false positive to the process grep...
sub is_running(){
	my $pid = "";
	my @pidlist = `ps -ef`;
	foreach ( @pidlist ){
		chomp;
		my @columns = split( /\s+/, $_, 8 );
		#print "col_1=".$columns[1]."\n";
		next if $columns[1] =~ /$$/;
		#print "col_7=".$columns[7]."\n";
		next if $columns[7] !~ /$me/;
		#print "found: me=$me, pid=".$columns[1]."\n";
		$pid = $columns[1];
		last;
	}
	my $running = length( $pid ) > 0;
	if( $running ){
		msg( "warning: $me is already running with pid $pid" );
		$errs += 1;
	}
	return( $running );
}

# ---------------------------------------------------------------------
# Compute the default value of max-load-5 given max-load-1
# (E): 1. a ref to the global configuration parameters hash
#      2. the parameter specified in the definition which is expected to
#         be a ref to an array of values
sub max_load_5_def( $$ ){
	my $local_parms = shift;
	my $load_key = ${$_[0]}[0];
	my $load = $local_parms->{$load_key};
	#print "in max_load_5_def: key=$load_key load=$load\n";
	return( defined( $load ) ? 3*$load/4 : undef );
}

# ---------------------------------------------------------------------
# Compute the default value of max-load-15 given max-load-1
sub max_load_15_def( $$ ){
	my $local_parms = shift;
	my $load_key = ${$_[0]}[0];
	my $load = $local_parms->{$load_key};
	#print "in max_load_15_def: key=$load_key load=$load\n";
	return( defined( $load ) ? 1*$load/2 : undef );
}

# ---------------------------------------------------------------------
# Display the specified message, either on stdout or in syslog,
# depending if we are running in the foreground or in the background
sub msg( $ ){
	my $str = shift;
	if( $parms->{'daemon'}{'value'} && $background ){
		syslog( LOG_INFO, $str );
	} else {
		print msg_format( $str )."\n";
	}
}

# ---------------------------------------------------------------------
# standard format the message
sub msg_format( $ ){
	my $instr = shift;
	my $outstr = "[${me}] ${instr}";
	return( ${outstr} );
}

# ---------------------------------------------------------------------
sub msg_version(){
	print " NanoWatchdog v${my_version}
 Copyright (C) 2015,2016,2017 Pierre Wieser <pwieser\@trychlos.org>
";
}

# ---------------------------------------------------------------------
# open the communication stream with the client
# returns the newly created handle
sub open_socket( $$ ){
	my $local_ip = shift;
	my $local_port = shift;
	# create a new TCP socket
	my $socket = new IO::Socket::INET (
		LocalHost => $local_ip,
		LocalPort => $local_port,
		Proto => 'tcp',
		Listen => 5,
		Reuse => 1,
		Timeout => 0 )
			or die "cannot create socket on $local_ip:$local_port: $!\n";
	fcntl( $socket, F_GETFL, O_NONBLOCK )
			or die "cannot set non-blocking flag for the TCP socket: $!\n";
	msg( "server waiting for client connection on $local_ip:$local_port" )
			if $$opt_verbose & LOG_CLIENT_DEBUG1;

	return( $socket );
}

# ---------------------------------------------------------------------
# open the communication stream with the serial bus
# handshake with the serial Bus to make sure it is ready
# returns the newly created handle
sub open_serial(){

	# create a new socket on the serial bus
	my $serial = Device::SerialPort->new( $parms->{'device'}{'value'} )
			 or die "unable to connect to ".$parms->{'device'}{'value'}." serial port: $!\n";
	$serial->databits( 8 );
	$serial->baudrate( $parms->{'baudrate'}{'value'} );
	$serial->parity( "none" );
	$serial->stopbits( true );
	$serial->dtr_active( false );
	$serial->write_settings() or die "unable to set serial bus settings: $!\n";
	msg( "opening ".$parms->{'device'}{'value'}."(".$parms->{'baudrate'}{'value'}." bps)" )
			if $$opt_verbose & LOG_BOARD_DEBUG1;

	return( $serial );
}

# ---------------------------------------------------------------------
# Initialize each configuration parameter with its default value and
# the corresponding origin
# This is called once, before parsing the command-line options
sub parm_init( $ ){
	my $local_parms = shift;			# a ref to the parameters hash
	# $key is the canonical name of the configuration parameter
	# default value may rely on other previously computed values
	foreach my $key ( keys %$local_parms ){
		if( defined( $local_parms->{$key}{'def'} )){
			if( ref( $local_parms->{$key}{'def'} ) ne "CODE" ){
				$local_parms->{$key}{'value'} = $local_parms->{$key}{'def'};
				$local_parms->{$key}{'origin'} = PARM_ORIGIN_DEFAULT;
			}
		} else {
			msg( "no hardcoded default value for '$key' parameter" );
				$local_parms->{$key}{'value'} = undef;
				$local_parms->{$key}{'origin'} = PARM_ORIGIN_DEFAULT;
		}
	}
	foreach my $key ( keys %$local_parms ){
		# if parameter has a default value by code
		if( defined( $local_parms->{$key}{'def'} ) && ref( $local_parms->{$key}{'def'} ) eq "CODE" ){
			$local_parms->{$key}{'value'} =
							$local_parms->{$key}{'def'}->( $local_parms, $local_parms->{$key}{'parms'} );
			$local_parms->{$key}{'origin'} = PARM_ORIGIN_DEFAULT;
		}
	}
}

# ---------------------------------------------------------------------
# Returns a ref to the configuration parameter definition hash
sub parm_get_definition_by_config( $$ ){
	my $local_parms = shift;			# a ref to the parameters hash
	my $local_key = shift;				# the searched key from configuration file
	foreach my $key ( keys %$local_parms ){
		if( defined( $local_parms->{$key}{'config'} )){
			if( $local_parms->{$key}{'config'} eq $local_key ){
				return( $local_parms->{$key} );
			}
		}
	}
	msg( "$local_key: unknown configuration file keyword, ignored" );
	return( undef );
}

# ---------------------------------------------------------------------
# Parse a verbosity level string (defaults to base 10)
# Returns the verbosity level number
sub parse_verbose( $ ){
	my $local_str = shift;				# the string to be parsed
	my $out_num = 0;
	if( $local_str =~ /^0x/ || $local_str =~ /^0b/ ){
		$out_num = oct( $local_str );
	} else {
		$out_num = $local_str;
	}
	return( $out_num );
}

# ---------------------------------------------------------------------
# get a command from TCP socket (from an external client)
# send it to the board (if opened)
# get the answer from the serial (if opened)
# send the answer to the client through the TCP socket
sub read_board_command( $ ){
	my $local_socket = shift;
	my $data;
    my $client = read_command( $local_socket, \$data );
    if( defined( $client )){
	    my $answer;
	    if( $parms->{'serial'}{'value'} ){
			$answer = send_serial( $data );
	    } else {
			$answer = msg_format( "${data}" );
	    }
	    write_answer( $client, $answer );
    }
}

# ---------------------------------------------------------------------
# management daemon command interface
# get a daemon command from TCP socket (from an external client)
sub read_daemon_command( $ ){
	my $local_socket = shift;
	my $data;
    my $client = read_command( $local_socket, \$data );
    if( defined( $client )){
	    my $answer = "";
		if( $data =~ /^\s*DUMP\s+OPTS\s*$/ ){
			my @tmp_array = ();
			push( @tmp_array, msg_format( "'DUMP OPTS' command is obsoleted since v8.2016 and will be removed in a next version" ));
			push( @tmp_array, msg_format( "redirecting to 'DUMP PARMS' in the meanwhile" ));
			push( @tmp_array, config_dump_to_array( $parms ));
			$answer = join( "\n", @tmp_array );

		} elsif( $data =~ /^\s*DUMP\s+PARMS\s*$/ ){
			my @tmp_array = config_dump_to_array( $parms );
			$answer = join( "\n", @tmp_array );

		} elsif( $data =~ /^\s*GET\s+/ ){
			my $tmp_arg = $data;
			$tmp_arg =~ s/^\s*GET\s+//;
			$tmp_arg =~ s/\s*$//;
			if( defined( $parms->{$tmp_arg} )){
				$answer = $tmp_arg."=".config_str_value( $parms->{$tmp_arg} );
			}

		} elsif( $data =~ /^\s*HELP\s*$/ ){
			$answer = $option_help_post;

		} elsif( $data =~ /^\s*PING\s+ON|OFF\s*$/ ){
			my $tmp_arg = $data;
			$tmp_arg =~ s/^\s*PING\s+//;
			$tmp_arg =~ s/\s*$//;
			$parms->{'nwping'}{'value'} = ( $tmp_arg eq "ON" );
			$parms->{'nwping'}{'origin'} = PARM_ORIGIN_RUN;
			$answer = msg_format( "OK: $data" );

		} elsif( $data =~ /^\s*QUIT\s*$/ ){
			$have_to_quit = true;
			msg( "QUIT received from daemon command interface" ) if $$opt_verbose & LOG_INFO_QUIT || $background;
			$answer = msg_format( "OK: $data" );

		} elsif( $data =~ /^\s*SET\s+VERBOSE\s+/ ){
			my $tmp_arg = $data;
			$tmp_arg =~ s/^\s*SET\s+VERBOSE\s+//;
			$tmp_arg =~ s/\s*$//;
			$parms->{'verbose'}{'value'} = parse_verbose( $tmp_arg );
			$parms->{'verbose'}{'origin'} = PARM_ORIGIN_RUN;
			$answer = msg_format( "OK: $data" );
		}

		if( !length( $answer )){
			$answer = msg_format( "unknown command: $data" );
		}
		write_answer( $client, $answer );
    }
}

# ---------------------------------------------------------------------
# get a command from TCP socket (from an external client)
# returns a handle to the client
sub read_command( $$ ){
	my $local_socket = shift;			# socket to listen to
	my $local_data = shift;				# ref to the output data
	my $out_client = undef;
    if( $out_client = $local_socket->accept()){
	    # get information about the newly connected client
	    my $client_address = $out_client->peerhost();
	    my $client_port = $out_client->peerport();
	    msg( "connection from $client_address:$client_port" ) if $$opt_verbose & LOG_CLIENT_DEBUG2;

	    # read up to 4096 characters from the connected client
	    $$local_data = "";
	    $out_client->recv( $$local_data, 4096 );
	    msg( "received data from listener socket: '$$local_data'" ) if $$opt_verbose & LOG_CLIENT_DEBUG2;
    }
    return( $out_client );
}

# ---------------------------------------------------------------------
# Compute the default value of send-from
sub send_from_def(){
	return( "nanowatchdog@".hostname );
}

# ---------------------------------------------------------------------
# write the command answer to the client
sub write_answer( $$ ){
	my $local_client = shift;
	my $local_answer = shift;

    # write response data to the connected client
    # if the serial port is not opened, then answer the command
    msg( "answering '${local_answer}' to the client" ) if $$opt_verbose & LOG_CLIENT_DEBUG2;
    $local_client->send( "$local_answer\n" );

    # notify client that response has been sent
    shutdown( $local_client, true );
}

# ---------------------------------------------------------------------
# send a '\n'-terminated command on the serial bus
# returns the ackownledgement received from the serial bus
sub send_serial( $ ){
    my $command = shift;
	my $buffer = "";
	msg( "sending command to ".$parms->{'device'}{'value'}.": '$command'" )
			if $$opt_verbose & LOG_BOARD_DEBUG2;
    if( $parms->{'serial'}{'value'} ){
		# send the command
	    my $out_count = $serial->write( "$command\n" );
	    msg( "${out_count} chars written to ".$parms->{'device'}{'value'} )
				if $$opt_verbose & LOG_BOARD_DEBUG2;

	    # receives the answer
		$serial->read_char_time(0);     # don't wait for each character
		$serial->read_const_time(100);  # 100 ms per unfulfilled "read" call
		my $chars = 0;
		my $timeout = $parms->{'readtimeout'}{'value'};
		while( $timeout>0 ){
	        my ( $count,$saw ) = $serial->read( 255 );	# will read _up to_ 255 chars
	        if( $count > 0 ){
				$chars += $count;
				$buffer .= $saw;
			} else {
				$timeout--;
			}
		}
		$buffer =~ s/\x0D\x0A$//;
		msg( "received '$buffer' ($chars chars) answer from ".$parms->{'device'}{'value'} )
				if $$opt_verbose & LOG_BOARD_DEBUG2;
    }
    return( $buffer );
}

# ---------------------------------------------------------------------
# check specified interfaces
# check that RX/TX are not zero
# returns: true if the system must be rebooted
sub check_interface( $ ){
    my $tick = shift;
    my $reboot = false;
    if( !@{$parms->{'interface'}{'value'}} ){
		msg( "interface(s) check is not enabled" )
			if ( $$opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'}{'value'};
    } else {
	    foreach( @{$parms->{'interface'}{'value'}} ){
			if( !$reboot ){
				my $ifconfig = `ifconfig $_ 2>&1`;
				my $rx = 0;
				my $tx = 0;
				if( $ifconfig =~ m/.*RX packets ([0-9]+).*/ms ){
					$rx = $1;
				}
				if( $ifconfig =~ m/.*TX packets ([0-9]+).*/ms ){
					$tx = $1;
				}
				$reboot = ( $rx+$tx == 0 );
				msg( "interface=$_, rx=$rx, tx=$tx" )
					if $reboot || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
			}
		}
		$reason_code = 23 if $reboot;
	}
	return( $reboot );
}

# ---------------------------------------------------------------------
# check load average
# /proc/loadvg: 0.16 0.19 0.21 1/471 18636
# The first three columns measure CPU and IO utilization of the last
# one, five, and 10 minute periods. The fourth column shows the number
# of currently running processes and the total number of processes. The
# last column displays the last process ID used
# returns: true if the system must be rebooted
sub check_loadavg( $ ){
    my $tick = shift;
    my $reboot = false;

	if(( defined( $parms->{'maxload1'}{'value'} ) && $parms->{'maxload1'}{'value'} > 0 ) ||
			( defined( $parms->{'maxload5'}{'value'} ) && $parms->{'maxload5'}{'value'} > 0 ) ||
			( defined( $parms->{'maxload15'}{'value'} ) && $parms->{'maxload15'}{'value'} > 0 )){

	    open my $fh, "/proc/loadavg";
	    if( defined( $fh )){
			my $line = <$fh>;
			close( $fh );
			chomp $line;
			my ( $avg1, $avg5, $avg10, $processes, $lastpid ) = split( / /, $line );
			if( defined( $parms->{'maxload1'}{'value'} ) &&
					$parms->{'maxload1'}{'value'} > 0 &&
					$avg1 > $parms->{'maxload1'}{'value'} ){
				$reason_code = 16;
				$reboot = true;

			} elsif( defined( $parms->{'maxload5'}{'value'} ) &&
					$parms->{'maxload5'}{'value'} > 0 &&
					$avg5 > $parms->{'maxload5'}{'value'} ){
				$reason_code = 17;
				$reboot = true;

			} elsif( defined( $parms->{'maxload15'}{'value'} ) &&
					$parms->{'maxload15'}{'value'} > 0 &&
					$avg10 > $parms->{'maxload15'}{'value'} ){
				$reason_code = 18;
				$reboot = true;
			}
			msg( "parm:max-load-1=".config_str_value( $parms->{'maxload1'} )
					.", avg1=$avg1, "
					."parm:max-load-5=".config_str_value( $parms->{'maxload5'} )
					.", avg5=$avg5, "
					."parm:max-load-15=".config_str_value( $parms->{'maxload15'} )
					.", avg10=$avg10, "
					."processes=${processes}, lastpid=${lastpid}" )
			    			if $reboot || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
	    } else {
			msg( "unable to open /proc/loadavg: $!" );
	    }
    } else {
    	msg( "load average check is not enabled" )
				if ( $$opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'}{'value'};
    }
    return( $reboot );
}

# ---------------------------------------------------------------------
# check virtual memory (standard watchdog)
# check swap free (NanoWatchdog)
# /proc/meminfo: SwapFree:       10485756 kB
# returns: true if the system must be rebooted
sub check_memory( $ ){
    my $tick = shift;
    my $reboot = false;
    if( $parms->{'memory'}{'value'} > 0 ){
	    open my $fh, "/proc/meminfo";
	    if( defined( $fh )){
			my $line;
			my $swap_free = 0;
			while( $line = <$fh> ){
				chomp $line;
				if( $line =~ /SwapFree:/ ){
					my ( $label, $count, $unit ) = split( /\s+/, $line );
					#msg( "label=${label} count=${count} unit=${unit}" );
					$swap_free = $count / 4;
					last;
				}
			}
			close( $fh );
			$reboot = true if $swap_free < $parms->{'memory'}{'value'};
			$reason_code = 19 if $reboot;
			msg( " parm:min-memory=".$parms->{'memory'}{'value'}.", swap_free=$swap_free" )
					if $reboot || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
	    } else {
			msg( "unable to open /proc/meminfo: $!" );
	    }
    } else {
		msg( "virtual memory check is not enabled" )
				if ( $$opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'}{'value'};
    }
    return( $reboot );
}

# ---------------------------------------------------------------------
# check pid files
# i.e. check that the pid stored in the given files is always alive
# the specified file is expected to contain only one PID number
# returns: true if the system must be rebooted
sub check_pidfile( $ ){
    my $tick = shift;
    my $reboot = false;
    if( !@{$parms->{'pidfile'}{'value'}} ){
		msg( "pid file(s) check is not enabled" )
				if ( $$opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'}{'value'};
    } else {
	    foreach( @{$parms->{'pidfile'}{'value'}} ){
			if( !$reboot ){
				if( open( my $fh, '<', $_ )){
					my $pid = <$fh>;
					close $fh;
					chomp $pid;
					# this only works for process with same UID
					#my $exists = kill 0, $pid;
					my $exists = ( system( "ps --pid $pid 1>/dev/null 2>&1" ) == 0 );
					#print "pid=$pid, exists=".( $exists ? "true":"false" )."\n";
					$reboot = !$exists;
					msg( "pidfile=".$_.", pid=$pid, exists=".( $exists ? "true":"false" ))
						if $reboot || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
				} else {
					msg( "warning: unable to open ".$_." for reading: $!" );
				}
			}
	    }
	    $reason_code = 21 if $reboot;
    }
    return( $reboot );
}

# ---------------------------------------------------------------------
# check hosts by pinging them
# returns: true if the system must be rebooted
sub check_ping( $ ){
    my $tick = shift;
    my $reboot = false;
    if( !@{$parms->{'ping'}{'value'}} ){
		msg( "ping(s) check is not enabled" )
				if ( $$opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'}{'value'};
    } else {
	    foreach( @{$parms->{'ping'}{'value'}} ){
			if( !$reboot ){
				my $alive = ( system( "ping -c1 $_ 1>/dev/null 2>&1" ) == 0 );
				$reboot = !$alive;
				msg( "ipv4=$_, alive=".( $alive ? "true":"false" ))
					if $reboot || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
			}
	    }
	    $reason_code = 22 if $reboot;
    }
    return( $reboot );
}

# ---------------------------------------------------------------------
# check temperature
# /sys/class/thermal/thermal_zone0/temp: 36000
# /sys/class/thermal/thermal_zone1/temp: 41000
# returns: true if the system must be rebooted
# NB: there is no way to disable the temperature check: it is always
#     enabled
sub check_temperature( $ ){
    my $tick = shift;
    my $reboot = false;
    find( sub { check_temperature_wanted( $tick, \$reboot )}, "/sys/class/thermal" );
    $reason_code = 20 if $reboot;
    return( $reboot );
}

sub check_temperature_wanted( $$ ){
	my $tick = shift;
	my $reboot_ref = shift;
	my $reboot_local = false;
	my $ftemp = $File::Find::name."/temp";
	if( -r $ftemp ){
	    open my ( $fh ), $ftemp;
	    if( defined( $fh )){
			my $line = <$fh>;
			close( $fh );
			chomp $line;
			$line /= 1000;
			$reboot_local = ( $line > $parms->{'temperature'}{'value'} );
			msg( "parm:max-temperature=".$parms->{'temperature'}{'value'}.", $ftemp:temperature=${line}" ) 
				if $reboot_local || (( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'} );
			$$reboot_ref |= $reboot_local;
	    } else {
			msg( "unable to open $ftemp: $!" );
	    }
	}
}

# ---------------------------------------------------------------------
# check test directory
sub check_test_directory( $ ){
    my $tick = shift;
    my $reboot = false;
    return( $reboot );
}

# ---------------------------------------------------------------------
# reboot the machine unless --noaction option has been specified
sub reboot(){
	my $pfx = "";
	$pfx = "[noaction] " if !$parms->{'action'}{'value'};
	msg( "${pfx}rebooting the system" );
	if( $parms->{'action'}{'value'} ){
		# actually reboot the machine
		send_serial( "REBOOT $reason_code" );
	}
}

# ---------------------------------------------------------------------
# this is the actual code
# isolated in a function to be used by the child when in daemon mode
sub run_server(){
	msg( "starting NanoWatchdog daemon..." ) if $background || $$opt_verbose & LOG_INFO_START;

	# configuration parameters
	return if !config_read( $parms, $parms->{'config'}{'value'} );
	config_dump( $parms ) if $$opt_verbose & LOG_CONFIG_START;

	# write pid file if requested to
	write_pid();

	# open communication sockets
	$board_socket = open_socket( $parms->{'listener'}{'value'}, $parms->{'boardport'}{'value'} );
	$daemon_socket = open_socket( $parms->{'listener'}{'value'}, $parms->{'daemonport'}{'value'} );
	$serial = open_serial() if $parms->{'serial'}{'value'};
	wait_for_watchdog_init() or die "unable to initialized NanoWatchdog board\n";

	# first start the NanoWatchdog board
	start_watchdog();
	# check status
	$board_status = send_serial( "STATUS" );
#	$board_status =
#"  version: NanoWatchdog 2015.1
#  date:         2015-06-15 00:06:23
#  reason:       43 (specific reason)
#  acknowledged: no";
	write_status( $board_status );
	send_boot_mail( $board_status );

	my $tick = 0;
	my $subtick = $parms->{'interval'}{'value'};	# do the first check right now

	while( true ){
		read_board_command( $board_socket );
		read_daemon_command( $daemon_socket );
		exit if $have_to_quit;
		sleep( 1 );
		$subtick += 1;
		if( $subtick > $parms->{'interval'}{'value'} ){
			$subtick = 0;
			$tick += 1;
			send_serial( "PING" ) if $parms->{'nwping'}{'value'};

			# http://linux.die.net/man/8/watchdog
			# The watchdog daemon does several tests to check the system
			# status:
			# - is the process table full?
			# - is there enough free memory?
			# - are some files accessible?
			# - have some files changed within a given interval?
			# - is the average work load too high?
			# - has a file table overflow occurred?
			# - is a process still running? The process is specified by a pid file.
			# - do some IP addresses answer to ping?
			# - do network interfaces receive traffic?
			# - is the temperature too high? (Temperature data not always available).
			# - execute a user defined command to do arbitrary tests.
			# - execute one or more test/repair commands found in /etc/watchdog.d.
			#   These commands are called with the argument test or repair.
			# If any of these checks fail watchdog will cause a shutdown.
			# Should any of these tests except the user defined binary last longer
			# than one minute the machine will be rebooted, too.

			if( check_memory( $tick ) ||
				check_loadavg( $tick ) ||
				check_temperature( $tick ) ||
				check_pidfile( $tick ) ||
				check_ping( $tick ) ||
				check_interface( $tick ) ||
				check_test_directory( $tick )){
					reboot();
			}

			msg( "going to sleep for ".$parms->{'interval'}{'value'}." sec." )
					if ( $$opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'}{'value'};
			$tick = 0 if $tick >= $parms->{'logtick'}{'value'};
		}
	}
}

# ---------------------------------------------------------------------
# send a mail to admin at boot time
sub send_boot_mail( $ ){
	my $local_status = shift;
	if( $parms->{'sendmail'}{'value'} ne "never" && length( $parms->{'sendto'}{'value'} )){
		my $to = $parms->{'sendto'}{'value'};
		my $from = $parms->{'sendfrom'}{'value'};
		my $subject = hostname." has just boot up";
		my $message = "";
		my $ack = "";
		if( $local_status =~ m/.*acknowledged:\s+(yes|no).*/ms ){
			$ack = $1;
		}
		#print "ack='$ack'\n";
		if( $ack eq "yes" && $parms->{'sendmail'}{'value'} eq "always" ){
			$message = "No left unacknowledged reset event found.";
		} elsif( $ack eq "no" ){
			my $reason = "";
			if( $local_status =~ m/.*reason:\s+(.*\))/ms ){
				$reason = $1;
			}
			#print "reason='$reason'\n";
			$message = "
 Hi,
 I am NanoWatchdog v${my_version}.
 It is very probable that last reboot has been initiated on my own request,
 as I have found that the last reset event is still left unacknowledged.

 Boot up status:
${local_status}
";
		}
		if( length( $message )){
			my $msg = MIME::Lite->new(
				From     => $from,
				To       => $to,
				Subject  => $subject,
				Data     => $message
			);
			$msg->send;
			msg( "send-mail=".$parms->{'sendmail'}{'value'}.", ack=$ack: ".
					"mail sent to ".$parms->{'sendto'}{'value'} ) if $$opt_verbose & LOG_MAIL_START;
		}
		if( $ack eq "no" ){
			send_serial( "ACKNOWLEDGE 0" );
		}
	}
}

# ---------------------------------------------------------------------
# start NanoWatchdog, waiting for the right answer to the sent command
# configure it, setting the current date, and the reboot delay
# return true if the NanoWatchdog board has been successfully
# initialized
sub start_watchdog(){
    if( $parms->{'serial'}{'value'} ){
		msg( "starting NanoWatchdog board..." ) if $$opt_verbose & LOG_INFO_START;
		my $command;

		# set whether we are in test mode
		$command = "SET TEST ";
		$command .= $parms->{'action'}{'value'} ? "OFF" : "ON";
		send_serial( $command );

		# set the current date
		$command = "SET DATE ".time();
		send_serial( $command );

		# set the reboot interval
		$command = "SET DELAY ".$parms->{'delay'}{'value'};
		send_serial( $command );

		# last start the watchdog
		send_serial( "START" );
    }
	return( true );
}

# ---------------------------------------------------------------------
# triggers the NanoWatchdog, waiting for the right answer
# which means the NanoWatchdog is ready
# returns: true/false whether the watchdog is rightly initialized
sub wait_for_watchdog_init(){
	my $answer = "";
	my $command = "NOOP";
    if( $parms->{'serial'}{'value'} ){
		my $timeout = 0;
		while( true ){
			sleep( 1 );
			$timeout += 1;
			$answer = send_serial( $command );
			last if $answer eq "OK: $command";
			last if $timeout > $parms->{'opentimeout'}{'value'};
		}
    }
	return( !$parms->{'serial'}{'value'} || $answer eq "OK: $command" );
}

# ---------------------------------------------------------------------
# write the daemon PID into a file
# this file will be automatically deleted by system when stopping the
# daemon
sub write_pid(){
	if( length( $parms->{'nwpid'}{'value'} )){
		if( open( my $fh, '>', $parms->{'nwpid'}{'value'} )){
			print $fh $$."\n";
			close $fh;
			msg( "pid written in ".$parms->{'nwpid'}{'value'} ) if $$opt_verbose & LOG_DEBUG_START;
		} else {
			msg( "warning: unable to open ".$parms->{'nwpid'}{'value'}." for write: $!" );
		}
	}
}

# ---------------------------------------------------------------------
# write the STATUS into a file
sub write_status( $ ){
	my $local_status = shift;
	#print "status='$local_status'\n";
	if( length( $parms->{'nwstatus'}{'value'} ) && length( $local_status )){
		if( open( my $fh, '>', $parms->{'nwstatus'}{'value'} )){
			print $fh $local_status."\n";
			close $fh;
			msg( "status written in ".$parms->{'nwstatus'}{'value'} ) if $$opt_verbose & LOG_DEBUG_START;
		} else {
			msg( "warning: unable to open ".$parms->{'nwstatus'}{'value'}." for write: $!" );
		}
	}
}

# =====================================================================
# MAIN
# =====================================================================

$SIG{HUP} = \&catch_hup;
$SIG{INT} = \&catch_int;
$SIG{TERM} = \&catch_term;
$SIG{USR1} = \&catch_usr1;

exit if is_running();
parm_init( $parms );
exit if !cmdline_get_options( $parms, $options );

my $child_pid = 0;
if( $parms->{'daemon'}{'value'} ){
	$child_pid = Proc::Daemon::Init() ;
	msg( "child_pid=${child_pid}" ) if $$opt_verbose & LOG_DEBUG_START;
}
# specific daemon code
if( $parms->{'daemon'}{'value'} && !$child_pid ){
	$background = true;
	openlog( $me, "nofatal,pid", LOG_DAEMON );
}
run_server() if !$parms->{'daemon'}{'value'} or !$child_pid;

exit;

END {
	# this last sentence has no chance of being printed if the program
	# exits because of already running (because command-line options
	# have not been set at this time).
	msg( "exiting with code $errs" ) if $$opt_verbose & LOG_INFO_QUIT;
	exit $errs;
}
