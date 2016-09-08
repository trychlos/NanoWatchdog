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
# This program takes options from command-line, and they are set in
# $opts.
# The program also takes parameters from configuration file(s), and
# those are set in $parms.
# Values of configuration parameters which are overriden by a command-
# line option are also set in $parms.

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
my $my_version = "8.2016";
my $errs = 0;							# exit code
my $nbopts = $#ARGV;					# command-line args count

# auto-flush on socket
$| = 1;

sub config_read_file( $$ );
sub max_load_5_def;
sub max_load_15_def;
sub msg;
sub msg_format;
sub msg_version;
sub send_from_def;
sub send_serial;
sub start_watchdog;

# Command-line options definitions
# ================================
# There is one and only one rationale: gather in one single place all
# elements that make a command-line option, so that the maintenance is
# a lot easier when modifying, defining a new or removing an option:
#  1/ the option itself
#  2/ a default value
#  3/ the specification for standard GetOptions()
#  4/ a help line to be displayed on user request.
#
# This rationale has some consequences:
#  1/ the definition must be ordered so that the help message is itself
#     ordered => the definition is an array.
#  2/ each command-line property is set in a hash whose key is the
#     option itself.
#
# Following keys are known:
#  'spec'    : the GetOptions() specifications
#  'def'     : the default value as displayed in the help message
#  'value'   : the actual default value
#  'help'    : the help line
#  'template': an example of the way the option should be entered
#  'ref'     : a ref to a scalar which will holds the option value
#
# The command-line interpretation stops as soon as an error is detected.
# The result is stored in an hash, as order doesn't matter here.
# Whether it has been set in the command-line or not, each defined
# option is set in this hash, and points itself to a hash with the
# following keys:
#  'value': the value to be considered for this option, whether it has
#           been set in the command-line or is the default
#  'orig' : an origin indicator (default, command-line or command).

my $opt_verbose;						# some frequently used options
my $opts = {};							# the final options hash
my $option_specs = [					# the options specification array
	# standard command-line options
	{ 'help'		=> { 'spec'		=> '!', 
						 'def'		=> "no",
						 'value'	=> false,
						 'help'		=> "print this message, and gracefully exit" }},
	{ 'version'		=> { 'spec'		=> '!',
						 'def'		=> "no",
						 'value'	=> false,
						 'help'		=> "print the program version, and gracefully exit" }},
	{ 'verbose'		=> { 'spec'		=> '=i',
						 'def'		=> "2",
						 'value'	=> 2,
						 'help'		=> "specify the verbosity level",
						 'ref'		=> \$opt_verbose }},
	# run behavior
	{ 'config'		=> { 'spec'		=> '=s',
						 'template'	=> '=/path/to/filename',
						 'def'		=> "/etc/nanowatchdog.conf",
						 'help'		=> "configuration filename" }},
	{ 'daemon'		=> { 'spec'		=> '!',
						 'def'		=> "yes",
						 'value'	=> true,
						 'help'		=> "fork in the background and run as a daemon" }},
	# serial bus
	{ 'serial'		=> { 'spec'		=> '!', 
						 'def'		=> "yes",
						 'value'	=> true,
						 'help'		=> "try to talk with a serial device" }},
	# device command-line option overrides eponym configuration parameter
	{ 'device'		=> { 'spec'		=> '=s',
						 'template'	=> '=/path/to/device',
						 'def'		=> "/dev/ttyUSB0",
						 'help'		=> "the serial bus to talk with" }},
	# TCP listener
	# ip command-line option overrides eponym configuration parameter
	{ 'ip'			=> { 'spec'		=> '=s', 
						 'template'	=> '=1.2.3.4',
						 'def'		=> "127.0.0.1",
						 'help'		=> "IP address the TCP server must listen to for commands" }},
	# port command-line option overrides eponym configuration parameter
	{ 'port-daemon'	=> { 'spec'		=> '=i', 
						 'template'	=> '=number',
						 'def'		=> "7778",
						 'help'		=> "port number the TCP server must listen to for daemon commands" }},
	{ 'port-serial'	=> { 'spec'		=> '=i', 
						 'template'	=> '=number',
						 'def'		=> "7777",
						 'help'		=> "port number the TCP server must listen to for board commands" }},
	# watchdog actions
	# delay command-line option overrides eponym configuration parameter
	{ 'delay'		=> { 'spec'		=> '=i',
						 'template'	=> '=number',
						 'def'		=> "60",
						 'help'		=> "delay (secs.) to reboot without ping" }},
	# interval command-line option overrides eponym configuration parameter
	{ 'interval'	=> { 'spec'		=> '=i',
						 'template'	=> '=number',
						 'def'		=> "10",
						 'help'		=> "interval between pings" }},
	{ 'ping'		=> { 'spec'		=> '!',
						 'def'		=> "yes",
						 'value'	=> true,
						 'help'		=> "whether to ping the NanoWatchdog on wake" }},
	# watchdog specific options
	# not all watchdog configuration parameters may be specified as a
	# command-line option - see man watchdog for more information
	{ 'action'		=> { 'spec'		=> '!',
						 'def'		=> "yes",
						 'value'	=> true,
						 'help'		=> "not in test mode, actually reboot the machine" }},
	{ 'sync'		=> { 'spec'		=> '!',
						 'def'		=> "no",
						 'value'	=> false,
						 'help'		=> "synchronize the filesystem during the check loop" }},
	{ 'softboot'	=> { 'spec'		=> '!',
						 'def'		=> "no",
						 'value'	=> false,
						 'help'		=> "soft-boot the system if an error occurs during the check loop" }},
	{ 'force'		=> { 'spec'		=> '!',
						 'def'		=> "no",
						 'value'	=> false,
						 'help'		=> "force the usage of watchdog parameters outside of limits" }},
];

my $option_help_post = " The daemon recognizes following commands:
    DUMP OPTS    dump the command-line options values
    DUMP PARMS   dump the configuration parameters values
    GET <parm>   returns the value of (case-sensitive) parameter or option
    HELP         print this list of commands
    PING ON|OFF  reactive or inhibit the periodic ping
    QUIT         terminates the daemon
 This daemon handles the following signals:
    HUP          reloads the configuration file
    TERM         terminates the daemon
    USR1         restart the NanoWatchdog
The daemon handles following cumulative verbosity levels:
	    1: dump configuration on hup signal
	    2: when terminating the daemon (default)
	    4: dump configuration on startup
	    8: dump command-line options on startup
	   16: when sending the startup mail
	   32: startup informations
	   64: configuration debug level 1
	  128: configuration debug level 2
	  256: client informations
	  512: client debug level 1
	 1024: client debug level 2
	 2048: board informations
	 4096: board debug level 1
	 8192: board debug level 2
	16384: loop debug level 1
	32768: loop debug level 2.";

# origin of option values
use constant { OPT_DEFAULT => 0, OPT_CMDLINE => 1, OPT_COMMAND => 2 };

# verbosity levels
use constant {
	LOG_CONFIG_HUP    => 1 << 0,			#     1: dump configuration on hup signal
	LOG_INFO_QUIT     => 1 << 1,			#     2: when terminating the daemon (default)
	LOG_CONFIG_START  => 1 << 2,			#     4: dump configuration on startup
	LOG_CMDLINE_START => 1 << 3,			#     8: dump command-line options on startup
	LOG_MAIL_START    => 1 << 4,			#    16: when sending the startup mail
	LOG_INFO_START    => 1 << 5,			#    32: startup informations
	LOG_CONFIG_DEBUG1 => 1 << 6,			#    64: configuration debug level 1
	LOG_CONFIG_DEBUG2 => 1 << 7,			#   128: configuration debug level 2
	LOG_CLIENT_INFO   => 1 << 8,			#   256: client informations
	LOG_CLIENT_DEBUG1 => 1 << 9,			#   512: client debug level 1
	LOG_CLIENT_DEBUG2 => 1 << 10,			#  1024: client debug level 2
	LOG_BOARD_INFO    => 1 << 11,			#  2048: board informations
	LOG_BOARD_DEBUG1  => 1 << 12,			#  4096: board debug level 1
	LOG_BOARD_DEBUG2  => 1 << 13,			#  8192: board debug level 2
	LOG_LOOP_DEBUG1   => 1 << 14,			# 16384: loop debug level 1
	LOG_LOOP_DEBUG2   => 1 << 15,			# 32768: loop debug level 2
};

# Configuration parameters definitions
# ====================================
# Configuration parameters are defined here.
# There is no need for an ordered list (an array) as there is no
# displayed help message. So a hash is enough.
#
# Some configuration parameters may be overriden by a command-line
# option. This is specified below. In this case, the definitive
# parameter value is set as a parameter, whether its value come from
# a default value, the configuration file or a command-line option.
# This behavior let the program be sure that the correct value for
# each and every configuration parameter will be found in the resulting
# hash, even if the programmer decides later to overrides one or more
# with a dedicated command-line option.
#
# Following keys are handled:
#  'def'  : the default value (when parameter is not specified in the
#           configuration file); this may be a scalar, of a reference
#           to a subroutine (see 'parms' key), or a reference to an
#           array; in this later case, the parameter may be specified
#           several times
#           Note that it is acceptable to have an 'undef' default value
#           when no value actually means 'do not even consider this'
#           parameter'.
#  'parms': the parameters to be passed to the subroutine which actually
#           computes the default value
#  'opt'  : the command-line option whose value overrides the parameter's
#           one; in this case, the used default value is those of the
#           named command-line option
#  'min'  : the minimal allowed value (when specified)
#  'max'  : the maximal allowed value (when specified)
#
# Handling the configuration file doesn't rely of specification ordering
# here, nor of definition ordering in the configuration file. Instead
# handling takes care of:
#  1/ first handling parameters which are overriden in the command-line
#  2/ then handling parameters which are specified in the configuration
#     file
#  2/ then setting fixed default values
#  3/ only last computing default values for parameters which are not
#     specified anywhere and have a computed default values.
#
# The result is stored as a simple hash { 'parameter' => value },
# because we do not need at this time from where does come the used
# value.

my $parms = {};
my $parm_specs = {
	# specific to NanoWatchdog
	'include'			=> { 'def'		=> "" },
	'device'			=> { 'opt'		=> "device" },
	'baudrate'			=> { 'def'		=> 19200 },
	'open-timeout'		=> { 'def'		=> 10 },
	'read-timeout'		=> { 'def'		=> 5 },
	'ip'				=> { 'def'		=> "127.0.0.1",
							 'opt'		=> "ip" },
	'port-daemon'		=> { 'opt'		=> "port-daemon" },
	'port-serial'		=> { 'opt'		=> "port-serial" },
	'delay'				=> { 'min'		=> 10,
							 'max'		=> 3600,
							 'opt'		=> "delay" },
	'send-mail'			=> { 'def'		=> "never" },
	'send-from'			=> { 'def'		=> \&send_from_def },
	'status-file'		=> { 'def'		=> "" },
	'pid-file'			=> { 'def'		=> "" },
	'interval'			=> { 'min'		=> 5,
							 'max'		=> 60,
							 'opt'		=> "interval" },
	'logtick'			=> { 'def'		=> 1 },
	# as max-load-5 and max-load-15 rely on max-load-1 value, take care
	# of having a max-load-1 suitable default
	'max-load-1'		=> { 'def'		=> undef,
							 'min'		=> 2 },
	'max-load-5'		=> { 'def'		=> \&max_load_5_def,
							 'parms'	=> [ qw/max-load-1/ ],
							 'min'		=> 2 },
	'max-load-15'		=> { 'def'		=> \&max_load_15_def,
							 'parms'	=> [ qw/max-load-1/ ],
							 'min'		=> 2 },
	'min-memory'		=> { 'def'		=> 0 },
	'max-temperature'	=> { 'def'		=> 90 },
	'pidfile'			=> { 'def'		=> [] },
	'ping'				=> { 'def'		=> [] },
	'interface'			=> { 'def'		=> [] },
	'admin'				=> { 'def'		=> "root" },
	'test-directory'	=> { 'def'		=> "/etc/watchdog.d" },
};

my $socket_daemon = undef;
my $socket_serial = undef;
my $serial = undef;
my $background = false;
my $have_to_quit = false;
my $reason_code = 0;
my $nano_status = undef;

# ---------------------------------------------------------------------
# handle HUP signal
sub catch_hup(){
	msg "HUP signal handler: reloading the configuration file ".$opts->{'config'}{'value'};
	$parms = {};
	if( config_read( $parm_specs, $parms, $opts->{'config'}{'value'}, $opts )){
		config_dump( $parm_specs, $parms ) if $opt_verbose & LOG_CONFIG_HUP;
	}
}

# ---------------------------------------------------------------------
# handle Ctrl-C
sub catch_int(){
	msg( "exiting on Ctrl-C" ) if $opt_verbose & LOG_INFO_QUIT;
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
	$socket_serial->close() if defined( $socket_serial );
	$socket_daemon->close() if defined( $socket_daemon );
	msg( "NanoWatchdog terminating..." ) if ( $opt_verbose & LOG_INFO_QUIT ) || $background;
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
# dump cmdline options to stdout or syslog
sub cmdline_dump( $$ ){
	my $local_specs = shift;				# a ref to an array of hash ref specs
	my $local_opts = shift;					# a ref to the final options hash
	my @tmp_array = cmdline_dump_array( $local_specs, $local_opts );
	foreach( @tmp_array ){
		msg( $_ );
	}
}

# ---------------------------------------------------------------------
# dump cmdline options to an array of strings
# returns: an array of strings
sub cmdline_dump_array( $$ ){
	my $local_specs = shift;				# a ref to an array of hash ref specs
	my $local_opts = shift;					# a ref to the final options hash
	my @out_dump = ();
	my $orig_default = "default";
	my $orig_cmdline = "command-line option";
	my $orig_command = "daemon command";
	my $key_length = 0;
	my $value_length = 0;
	my $orig_length = 19;
	my $l;
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			$l = length( $key );
			$key_length = $l if $l > $key_length;
			if( cmdline_opt_is_bool( $_->{$key} )){
				$l = 5;	# false
			} else {
				$l = length( $local_opts->{$key}{'value'} );
			}
			$value_length = $l if $l > $value_length;
		}
	}
	$key_length = 6 if $key_length < 6;
	my $str;
	my $pfx = "   ";
	push( @out_dump, "command-line options:" );
	$str = $pfx . "option";
	$str .= ( " " x ( $key_length-4 ));
	$str .= "value";
	$str .= ( " " x ( $value_length-3 ));
	$str .= "origin";
	push( @out_dump, $str );
	$str = $pfx.( "-" x $key_length );
	$str .= "  ".( "-" x $value_length );
	$str .= "  ".( "-" x $orig_length );
	push( @out_dump, $str );
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			$str = $pfx.$key;
			$str .= ( " " x ( $key_length - length( $key ) + 2 ));
			if( cmdline_opt_is_bool( $_->{$key} )){
				$str .= ( $local_opts->{$key}{'value'} ? "true ":"false" );
				$l = 5;
			} else {
				$str .= $local_opts->{$key}{'value'};
				$l = length( $local_opts->{$key}{'value'} );
			}
			$str .= ( " " x ( $value_length - $l + 2 ));
			$str .= ( $local_opts->{$key}{'orig'} == OPT_DEFAULT ? $orig_default : 
						( $local_opts->{$key}{'orig'} == OPT_CMDLINE ? $orig_cmdline : $orig_command ));
			push( @out_dump, $str );
		}
	}
	return( @out_dump );
}

# ---------------------------------------------------------------------
# deals with cmdline options
# get options specifications as an array of hash refs:
# - spec:     option specification
# - def:      displayed default value
# - help:     help message (single line)
# - value:    actual default value (if not the same than 'def',
#             e.g. for booleans)
# - template: example of option value
# - set:      a ref to a global lexical (for frequently used options)
# return option values as a hash of option names
# handle --help and --version options which both gracefully exits
# return true to continue the program
sub cmdline_get_options( $$ ){
	my $local_specs = shift;				# a ref to an array of hash ref specs
	my $local_opts = shift;					# a ref to the final options hash
	# temporary hash to hold the options values
	my %temp_opts = ();
	# temporary array to hold the options specs
	my @temp_specs = ();
	# build the specification array for GetOptions()
	# simultaneously initializing resulting options hash
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			#print "key=$key\n";
			my $spec = $key;
			$spec .= $_->{$key}{'spec'} if defined( $_->{$key}{'spec'} );
			#print "spec=$spec\n";
			push @temp_specs, $spec;
			#$local_opts->{$key} = {};
			if( defined( $_->{$key}{'value'} )){
				$local_opts->{$key}{'value'} = $_->{$key}{'value'};
			} elsif( defined( $_->{$key}{'def'} )){
				$local_opts->{$key}{'value'} = $_->{$key}{'def'};
			} else {
				$local_opts->{$key}{'value'} = "";
			}
			$local_opts->{$key}{'orig'} = OPT_DEFAULT;
		}
	}
	if( !GetOptions( \%temp_opts, @temp_specs )){
		msg "try '${0} --help' to get full usage syntax";
		$errs = 1;
		return( false );
	}
	# write in the final option hash two keys
	# - value which comes from default or from the command-line
	# - set which is true if value comes from command-line
	foreach my $key ( keys %temp_opts ){
		#print "found $key=".$temp_opts{$key}."\n";
		$local_opts->{$key}{'value'} = $temp_opts{$key};
		$local_opts->{$key}{'orig'} = OPT_CMDLINE;
	}
	# if some options are frequently used, one can define a global
	# lexical for direct access
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			if( defined( $_->{$key}{'ref'} ) && ref( $_->{$key}{'ref'} ) eq "SCALAR" ){
				${$_->{$key}{'ref'}} = $local_opts->{$key}{'value'};
				#print "set frequently used value\n";
			}
		}
	}
	# handle --help option
	$local_opts->{'help'}{'value'} = true if $nbopts < 0;
	if( $local_opts->{'help'}{'value'} ){
		cmdline_help( $local_specs );
		return( false );
	}
	# handle --version option
	if( $local_opts->{'version'}{'value'} ){
		msg_version();
		exit;
	}
	#cmdline_dump( $local_specs, $local_opts );
	return( true );
}

# ---------------------------------------------------------------------
# return the option specs for this key
sub cmdline_get_specs( $$ ){
	my $local_specs = shift;				# a ref to an array of hash refs
	my $local_key = shift;
	my $spec = undef;
	GNN: foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			#print "cmdline_get_specs: local=$local_key key=$key\n";
			if( $key eq $local_key ){
				$spec = $_->{$key};
			}
			last GNN if defined( $spec );
		}
	}
	return( $spec );
}

# ---------------------------------------------------------------------
# deals with cmdline options
# get options specifications as an array of hash refs
# return option values as a hash of option names
# handle --help and --version options which both gracefully exits
# return true to continue the program
sub cmdline_help( $ ){
	my $local_specs = shift;				# a ref to an array of hash refs
	# help preambule
	msg_version();
	print " Usage: $0 [options]\n";
	# display help messages
	# compute max length
	my $local_max = 0;
	my $l;
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			$l = length( $key );
			$l += 4 if cmdline_opt_is_bool( $_->{$key} );
			$l += length( $_->{$key}{'template'} ) if defined( $_->{$key}{'template'} );
			if( $l > $local_max ){
				$local_max = $l;
			}
		}
	}
	# display help line for each option
	foreach( @$local_specs ){
		foreach my $key ( keys %$_ ){
			print "  --";
			if( cmdline_opt_is_bool( $_->{$key} )){
				print "[no]";
			}
			print "$key";
			$l = length( $key );
			$l += 4 if cmdline_opt_is_bool( $_->{$key} );
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
			if( defined( $_->{$key}{'def'} )){
				print " [".$_->{$key}{'def'}."]";
			}
			print "\n";
		}
	}
	# help end
	print "$option_help_post
";
}

# ---------------------------------------------------------------------
# returns true if the opt specs is a boolean
# input is the spec of the option as a hash ref 
sub cmdline_opt_is_bool( $ ){
	my $local_spec = shift;
	return !defined( $local_spec->{'spec'} ) || $local_spec->{'spec'} eq "!";
}

# ---------------------------------------------------------------------
# dump the configuration parameters
sub config_dump( $$ ){
	my $local_specs = shift;
	my $local_parms = shift;
	my @tmp_dump = config_dump_array( $local_specs, $local_parms );
	foreach( @tmp_dump ){
		msg( $_ );
	}
}

# ---------------------------------------------------------------------
# dump the configuration parameters to an array of strings
sub config_dump_array( $$ ){
	my $local_specs = shift;
	my $local_parms = shift;
	my @out_dump = ();
	my $key_length = 0;
	my $value_length = 0;
	my $l;
	foreach my $key ( keys %$local_specs ){
		$l = length( $key );
		$key_length = $l if $l > $key_length;
		#print "key=$key, value=".$local_parms->{$key}."\n";
		my $str = config_str_value( $local_parms->{$key} );
		$l = length( $str );
		$value_length = $l if $l > $value_length;
	}
	$key_length = 9 if $key_length < 9;
	my $str;
	my $pfx = "   ";
	push( @out_dump, "configuration parameters:" );
	$str = $pfx . "parameter";
	$str .= ( " " x ( $key_length-7 ));
	$str .= "value";
	$str .= ( " " x ( $value_length-3 ));
	push( @out_dump, $str );
	$str = $pfx.( "-" x $key_length );
	$str .= "  ".( "-" x $value_length );
	push( @out_dump, $str );
	foreach my $key ( sort keys %$local_specs ){
		if( $key ne "include" ){
			$str = $pfx.$key;
			$str .= ( " " x ( $key_length - length( $key ) + 2 ));
			$str .= config_str_value( $local_parms->{$key} );
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
#  my $cfg = config_read( $path, $opts );
# where $cfg is a hash reference where keys are parameter values, maybe
# overriden by option values.
# Ignore parameters from configuration file which are not defined in
# the parm_specs.
# Returns: true if parameters have been successfully read
# parm_specs is a hash ref with keys:
# - def: default value (useless if overriden by option)
# - min
# - max
# - opt: the option name which overrides this parameter
sub config_read( $$$$ ){
	my $local_specs = shift;			# a ref to the hash of specs
	my $local_config = shift;
	my $local_path = shift;				# the configuration file name
	my $local_opts = shift;				# a ref to the hash of option values
	my $temp_cfg = {};
	my $temp_errs = 0;
	config_read_file( $local_path, $temp_cfg );
	# first set values which have been overriden by a command-line
	# option or are set from the configuration file
	foreach my $key ( keys %$local_specs ){
		# if parameter has been overriden by a command-line option
		if( defined( $local_specs->{$key}{'opt'} ) && 
				$local_opts->{$local_specs->{$key}{'opt'}}{'orig'} == OPT_CMDLINE ){
			$local_config->{$key} = $local_opts->{$local_specs->{$key}{'opt'}}{'value'};
		# if parameter is set in the configuration file(s)
		} elsif( defined( $temp_cfg->{$key} )){
			if( ref( $local_specs->{$key}{'def'} ) eq "ARRAY" ){
				$local_config->{$key} = $temp_cfg->{$key};
			} else {
				$local_config->{$key} = $temp_cfg->{$key}[0];
				#print "key=$key value=".$temp_cfg->{$key}[0]."\n";
				#print "key=$key value=".$local_config->{$key}."\n";
			}
		}
	}
	# next compute default values (which may rely on other previously
	# computed values)
	foreach my $key ( keys %$local_specs ){
		if( !defined( $local_config->{$key} )){
			# if parameter has a default value
			if( defined( $local_specs->{$key}{'def'} )){
				if( ref( $local_specs->{$key}{'def'} ) ne "CODE" ){
					$local_config->{$key} = $local_specs->{$key}{'def'};
				}
			} elsif( defined( $local_specs->{$key}{'opt'} ) && 
					defined( $local_opts->{$local_specs->{$key}{'opt'}}{'value'} )){
				$local_config->{$key} = $local_opts->{$local_specs->{$key}{'opt'}}{'value'};
			}
		}
	}
	foreach my $key ( keys %$local_specs ){
		if( !defined( $local_config->{$key} )){
			# if parameter has a default value by code
			if( defined( $local_specs->{$key}{'def'} )){
				if( ref( $local_specs->{$key}{'def'} ) eq "CODE" ){
					$local_config->{$key} = 
							$local_specs->{$key}{'def'}->( $local_config, $local_specs->{$key}{'parms'} );
				}
			#} else {
			#	msg "warning: no suitable default value found for parm=$key\n";
			#	$temp_errs += 1;
			}
		}
	}
	# last check for min/max values
	foreach my $key ( keys %$local_specs ){
		# check for min value
		if( defined( $local_specs->{$key}{'min'} ) && defined( $local_config->{$key} )){
			if( $local_config->{$key} < $local_specs->{$key}{'min'} && !$local_opts->{'force'}{'value'} ){
				msg( "$key: value=".$local_config->{$key}." < min=".$local_specs->{$key}{'min'}
					." and force is not set: forcing the value to min" );
				$local_config->{$key} = $local_specs->{$key}{'min'};
			}
		}
		# check for max value
		if( defined( $local_specs->{$key}{'max'} ) && defined( $local_config->{$key} )){
			if( $local_config->{$key} > $local_specs->{$key}{'max'} && !$local_opts->{'force'}{'value'} ){
				msg( "$key: value=".$local_config->{$key}." > max=".$local_specs->{$key}{'max'}
					." and force is not set: forcing the value to max" );
				$local_config->{$key} = $local_specs->{$key}{'max'};
			}
		}
	}
	return( $temp_errs == 0 );
}

# ---------------------------------------------------------------------
# Handle the filename spec
# Update the specified hash ref
sub config_read_file( $$ ){
	my $local_path = shift;
	my $local_cfg = shift;
	if( !-r $local_path ){
		msg( "configuration file ${local_path} not found: using default values" );
	} else {
		msg( "reading the configuration file ${local_path}" )
				if $opt_verbose & LOG_CONFIG_DEBUG1;
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
	my $local_value = shift;
	my $out_str;
	if( defined( $local_value )){
		if( ref( $local_value ) eq "ARRAY" ){
			$out_str = "[".join( ",", @$local_value )."]";
		} else {
			$out_str = $local_value;
		}
	} else {
		$out_str = "undef";
	}
	return( $out_str );
}

# ---------------------------------------------------------------------
# returns true if the daemon is already running
# this command is run at very startup, even before command-line options
# are checked; the daemon has no chance of doing anything before being
# exited.
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
# Compute the default value of send-from
sub send_from_def(){
	return( "nanowatchdog@".hostname );
}

# ---------------------------------------------------------------------
# Display the specified message, either on stdout or in syslog, 
# depending if we are running in the foreground or in the background 
sub msg( $ ){
	my $str = shift;
	if( $opts->{'daemon'}{'value'} && $background ){
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
 Copyright (C) 2015, Pierre Wieser <pwieser\@trychlos.org>
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
			if $opt_verbose & LOG_CLIENT_DEBUG1;

	return( $socket );
}

# ---------------------------------------------------------------------
# open the communication stream with the serial bus
# handshake with the serial Bus to make sure it is ready
# returns the newly created handle
sub open_serial(){

	# create a new socket on the serial bus
	my $serial = Device::SerialPort->new( $parms->{'device'} )
			 or die "unable to connect to ".$parms->{'device'}." serial port: $!\n";
	$serial->databits( 8 );
	$serial->baudrate( $parms->{'baudrate'} );
	$serial->parity( "none" );
	$serial->stopbits( true );
	$serial->dtr_active( false );
	$serial->write_settings() or die "unable to set serial bus settings: $!\n";
	msg( "opening ".$parms->{'device'}."(".$parms->{'baudrate'}." bps)" )
			if $opt_verbose & LOG_BOARD_DEBUG1;

	return( $serial );
}

# ---------------------------------------------------------------------
# get a command from TCP socket (from an external client)
# send it to the serial (if opened)
# get the answer from the serial (if opened)
# send the answer to the client through the TCP socket
sub read_serial_command( $ ){
	my $local_socket = shift;
	my $data;
    my $client = read_command( $local_socket, \$data );
    if( defined( $client )){
	    my $answer;
	    if( $opts->{'serial'}{'value'} ){
			$answer = send_serial( $data );
	    } else {
	    	$answer = msg_format( "${data}" );
	    }
	    write_answer( $client, $answer );
    }
}

# ---------------------------------------------------------------------
# get a daemon command from TCP socket (from an external client)
sub read_daemon_command( $ ){
	my $local_socket = shift;
	my $data;
    my $client = read_command( $local_socket, \$data );
    if( defined( $client )){
	    my $answer = "";
		if( $data =~ /^\s*DUMP\s+OPTS\s*$/ ){
			my @tmp_array = cmdline_dump_array( $option_specs, $opts );
			$answer = join( "\n", @tmp_array );

		} elsif( $data =~ /^\s*DUMP\s+PARMS\s*$/ ){
			my @tmp_array = config_dump_array( $parm_specs, $parms );
			$answer = join( "\n", @tmp_array );

		} elsif( $data =~ /^\s*GET\s+/ ){
			my $temp_parm = $data;
			$temp_parm =~ s/^\s*GET\s+//;
			if( defined( $parms->{$temp_parm} )){
				$answer = $parms->{$temp_parm};
			} elsif( defined( $opts->{$temp_parm}{'value'} )){
				$answer = $opts->{$temp_parm}{'value'};
			}

		} elsif( $data =~ /^\s*HELP\s*$/ ){
			$answer = $option_help_post;

		} elsif( $data =~ /^\s*PING\s+ON|OFF\s*$/ ){
			my $temp_parm = $data;
			$temp_parm =~ s/^\s*PING\s+//;
			$temp_parm =~ s/\s*$//;
			$opts->{'ping'}{'value'} = ( $temp_parm eq "ON" );
			$opts->{'ping'}{'orig'} = OPT_COMMAND;
			$answer = msg_format( "OK: $data" );

		} elsif( $data =~ /^\s*QUIT\s*$/ ){
			$have_to_quit = true;
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
	    msg( "connection from $client_address:$client_port" ) if $opt_verbose & LOG_CLIENT_DEBUG2;

	    # read up to 4096 characters from the connected client
	    $$local_data = "";
	    $out_client->recv( $$local_data, 4096 );
	    msg( "received data: '$$local_data'" ) if $opt_verbose & LOG_CLIENT_DEBUG2;
    }
    return( $out_client );
}

# ---------------------------------------------------------------------
# write the command answer to the client
sub write_answer( $$ ){
	my $local_client = shift;
	my $local_answer = shift;

    # write response data to the connected client
    # if the serial port is not opened, then answer the command
    msg( "answering '${local_answer}' to the client" ) if $opt_verbose & LOG_CLIENT_DEBUG2;
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
	msg( "sending command to ".$parms->{'device'}.": '$command'" )
			if $opt_verbose & LOG_BOARD_DEBUG2;
    if( $opts->{'serial'}{'value'} ){
    	# send the command
	    my $out_count = $serial->write( "$command\n" );
	    msg( "${out_count} chars written to ".$parms->{'device'} )
	    		if $opt_verbose & LOG_BOARD_DEBUG2;

	    # receives the answer
		$serial->read_char_time(0);     # don't wait for each character
		$serial->read_const_time(100);  # 100 ms per unfulfilled "read" call
		my $chars = 0;
		my $timeout = $parms->{'read-timeout'};
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
		msg( "received '$buffer' ($chars chars) answer from ".$parms->{'device'} )
				if $opt_verbose & LOG_BOARD_DEBUG2;
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
    if( !@{$parms->{'interface'}} ){
    	msg( "interface(s) check is not enabled" )
    			if ( $opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'};
    } else {
	    foreach( @{$parms->{'interface'}} ){
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
	    			if $reboot || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
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

    if(( defined( $parms->{'max-load-1'} ) && $parms->{'max-load-1'} > 0 ) ||
    		( defined( $parms->{'max-load-5'} ) && $parms->{'max-load-5'} > 0 ) ||
    		( defined( $parms->{'max-load-15'} ) && $parms->{'max-load-15'} > 0 )){

	    open my $fh, "/proc/loadavg";
	    if( defined( $fh )){
	    	my $line = <$fh>;
	    	close( $fh );
	    	chomp $line;
	    	my ( $avg1, $avg5, $avg10, $processes, $lastpid ) = split( / /, $line );
	    	if( defined( $parms->{'max-load-1'} ) &&
	    			$parms->{'max-load-1'} > 0 &&
	    			$avg1 > $parms->{'max-load-1'} ){
	    		$reason_code = 16;
	    		$reboot = true;

	    	} elsif( defined( $parms->{'max-load-5'} ) &&
	    			$parms->{'max-load-5'} > 0 &&
	    			$avg5 > $parms->{'max-load-5'} ){
	    		$reason_code = 17;
	    		$reboot = true;

	    	} elsif( defined( $parms->{'max-load-15'} ) &&
	    			$parms->{'max-load-15'} > 0 &&
	    			$avg10 > $parms->{'max-load-15'} ){
	    		$reason_code = 18;
	    		$reboot = true;
	    	}
	    	msg( "parm:max-load-1=".config_str_value( $parms->{'max-load-1'} )
	    			.", avg1=$avg1, "
	    			."parm:max-load-5=".config_str_value( $parms->{'max-load-5'} )
	    			.", avg5=$avg5, "
	    			."parm:max-load-15=".config_str_value( $parms->{'max-load-15'} )
	    			.", avg10=$avg10, "
	    			."processes=${processes}, lastpid=${lastpid}" )
			    			if $reboot || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
	    } else {
	    	msg( "unable to open /proc/loadavg: $!" );
	    }
    } else {
    	msg( "load average check is not enabled" )
				if ( $opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'};
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
    if( $parms->{'min-memory'} > 0 ){
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
	    	$reboot = true if $swap_free < $parms->{'min-memory'};
		    $reason_code = 19 if $reboot;
	    	msg( " parm:min-memory=".$parms->{'min-memory'}.", swap_free=$swap_free" )
	    			if $reboot || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
	    } else {
	    	msg( "unable to open /proc/meminfo: $!" );
	    }
    } else {
    	msg( "virtual memory check is not enabled" )
				if ( $opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'};
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
    if( !@{$parms->{'pidfile'}} ){
    	msg( "pid file(s) check is not enabled" )
    			if ( $opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'};
    } else {
	    foreach( @{$parms->{'pidfile'}} ){
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
		    			if $reboot || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
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
    if( !@{$parms->{'ping'}} ){
    	msg( "ping(s) check is not enabled" )
    			if ( $opt_verbose & LOG_LOOP_DEBUG1 ) && $tick >= $parms->{'logtick'};
    } else {
	    foreach( @{$parms->{'ping'}} ){
	    	if( !$reboot ){
		    	my $alive = ( system( "ping -c1 $_ 1>/dev/null 2>&1" ) == 0 );
	    		$reboot = !$alive;
	    		msg( "ipv4=$_, alive=".( $alive ? "true":"false" ))
	    			if $reboot || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
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
	    	$reboot_local = ( $line > $parms->{'max-temperature'} );
	    	msg( "parm:max-temperature=".$parms->{'max-temperature'}.", $ftemp:temperature=${line}" ) 
    			if $reboot_local || (( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'} );
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
	$pfx = "[noaction] " if !$opts->{'action'}{'value'};
	msg( "${pfx}rebooting the system" );
	if( $opts->{'action'}{'value'} ){
		# actually reboot the machine
		send_serial( "REBOOT $reason_code" );
	}
}

# ---------------------------------------------------------------------
# this is the actual code
# isolated in a function to be used by the child when in daemon mode
sub run_server(){
	msg( "starting NanoWatchdog daemon..." ) if $background || $opt_verbose & LOG_INFO_START;
	
	# command-line options
	cmdline_dump( $option_specs, $opts ) if $opt_verbose & LOG_CMDLINE_START;

	# configuration parameters
	return if !config_read( $parm_specs, $parms, $opts->{'config'}{'value'}, $opts );
	config_dump( $parm_specs, $parms ) if $opt_verbose & LOG_CONFIG_START;

	# write pid file if requested to
	write_pid();

	# open communication sockets
	$socket_serial = open_socket( $parms->{'ip'}, $parms->{'port-serial'} );
	$socket_daemon = open_socket( $parms->{'ip'}, $parms->{'port-daemon'} );
	$serial = open_serial() if $opts->{'serial'}{'value'};
	wait_for_watchdog_init() or die "unable to initialized NanoWatchdog board\n";
	
	# first start the NanoWatchdog board
	start_watchdog();
	# check status
	$nano_status = send_serial( "STATUS" );
#	$nano_status =
#"  version: NanoWatchdog 2015.1
#  date:         2015-06-15 00:06:23
#  reason:       43 (specific reason)
#  acknowledged: no";
	write_status( $nano_status );
	send_boot_mail( $nano_status );
	
	my $tick = 0;
	my $subtick = $parms->{'interval'};	# do the first check right now

	while( true ){
		read_serial_command( $socket_serial );
		read_daemon_command( $socket_daemon );
		exit if $have_to_quit;
		sleep( 1 );
		$subtick += 1;
		if( $subtick > $parms->{'interval'} ){
			$subtick = 0;
			$tick += 1;
			send_serial( "PING" ) if $opts->{'ping'}{'value'};
	
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
			# - is the temperature too high? (Temperature data not always available.)
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
		    msg( "going to sleep for ".$parms->{'interval'}." sec." )
		    		if ( $opt_verbose & LOG_LOOP_DEBUG2 ) && $tick >= $parms->{'logtick'};
		    $tick = 0 if $tick >= $parms->{'logtick'};
		}
	}
}

# ---------------------------------------------------------------------
# send a mail to admin at boot time
sub send_boot_mail( $ ){
	my $local_status = shift;
	if( $parms->{'send-mail'} ne "never" && length( $parms->{'admin'} )){
		my $to = $parms->{'admin'};
		my $from = $parms->{'send-from'};
		my $subject = hostname." has just boot up";
		my $message = "";
		my $ack = "";
		if( $local_status =~ m/.*acknowledged:\s+(yes|no).*/ms ){
			$ack = $1;
		}
		#print "ack='$ack'\n";
		if( $ack eq "yes" && $parms->{'send-mail'} eq "always" ){
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
			msg( "send-mail=".$parms->{'send-mail'}.", ack=$ack: ".
					"mail sent to ".$parms->{'admin'} ) if $opt_verbose & LOG_MAIL_START;
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
	msg( "starting NanoWatchdog board..." ) if $opt_verbose & LOG_BOARD_INFO;
	my $command;

	# set whether we are in test mode
	$command = "SET TEST ";
	$command .= $opts->{'action'}{'value'} ? "OFF" : "ON";
	send_serial( $command );

	# set the current date
	$command = "SET DATE ".time();
	send_serial( $command );

	# set the reboot interval
	$command = "SET INTERVAL ".$parms->{'delay'};
	send_serial( $command );
	
	# last start the watchdog
	send_serial( "START" );

	return( true );
}

# ---------------------------------------------------------------------
# triggers the NanoWatchdog, waiting for the right answer
# which means the NanoWatchdog is ready
# returns: true/false whether the watchdog is rightly initialized
sub wait_for_watchdog_init(){
	my $command = "NOOP";
	my $answer = "";
	my $timeout = 0;
	while( true ){
		sleep( 1 );
		$timeout += 1;
		$answer = send_serial( $command );
		last if $answer eq "OK: $command";
		last if $timeout > $parms->{'open-timeout'};
		last if !$opts->{'serial'}{'value'};
	}
	#print "timeout=$timeout answer='$answer'\n";
	return( !$opts->{'serial'}{'value'} || $answer eq "OK: $command" );
}

# ---------------------------------------------------------------------
# write the daemon PID into a file
# this file will be automatically deleted by system when stopping the
# daemon
sub write_pid(){
	if( length( $parms->{'pid-file'} )){
		if( open( my $fh, '>', $parms->{'pid-file'} )){
			print $fh $$."\n";
			close $fh;
			msg( "pid written in ".$parms->{'pid-file'} ) if $opt_verbose & LOG_INFO_START;
		} else {
			msg( "warning: unable to open ".$parms->{'pid-file'}." for write: $!" );
		}
	}
}

# ---------------------------------------------------------------------
# write the STATUS into a file
sub write_status( $ ){
	my $local_status = shift;
	#print "status='$local_status'\n";
	if( length( $parms->{'status-file'} ) && length( $local_status )){
		if( open( my $fh, '>', $parms->{'status-file'} )){
			print $fh $local_status."\n";
			close $fh;
			msg( "status written in ".$parms->{'status-file'} ) if $opt_verbose & LOG_INFO_START;
		} else {
			msg( "warning: unable to open ".$parms->{'status-file'}." for write: $!" );
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
exit if !cmdline_get_options( $option_specs, $opts );

my $child_pid = 0;
if( $opts->{'daemon'}{'value'} ){
	$child_pid = Proc::Daemon::Init() ;
	msg( "child_pid=${child_pid}" ) if $opt_verbose & LOG_INFO_START;
}
# specific daemon code
if( $opts->{'daemon'}{'value'} && !$child_pid ){
	$background = true;
	openlog( $me, "nofatal,pid", LOG_DAEMON );
}
run_server() if !$opts->{'daemon'}{'value'} or !$child_pid;

exit;

END {
	# this last sentence has no chance of being printed if the program
	# exits because of already running (because command-line options
	# have not been set at this time).
	msg( "exiting with code $errs" ) if $opt_verbose & LOG_INFO_QUIT;
	exit $errs;
}
