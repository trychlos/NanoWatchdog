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

use strict;
use File::Basename;
use Getopt::Long;
use IO::Socket::INET;

my $me = basename( $0 );
use constant { true => 1, false => 0 };
 
# auto-flush on socket
$| = 1;

my $errs = 0;
my $nbopts = $#ARGV;
my $opt_help_def = "no";
my $opt_help = false;
my $opt_version_def = "no";
my $opt_version = false;
my $opt_verbose_def = "no";
my $opt_verbose = false;

my $opt_listen_ip_def = "127.0.0.1";
my $opt_listen_ip = $opt_listen_ip_def;
my $opt_listen_port_def = 7777;
my $opt_listen_port = $opt_listen_port_def;
my $opt_command_def = "";
my $opt_command = $opt_command_def;

# ---------------------------------------------------------------------
sub msg_help(){
	msg_version();
	print " Usage: $0 [options]
  --[no]help              print this message, and exit [${opt_help_def}]
  --[no]version           print script version, and exit [${opt_version_def}]
  --[no]verbose           run verbosely [$opt_verbose_def]
  --listen=ip             IP address to communicate with the daemon [${opt_listen_ip_def}]
  --port=port             port number to communicate with the dameon [${opt_listen_port_def}]
  --command=command       command to send [${opt_command_def}]
";
}

# ---------------------------------------------------------------------
sub msg_version(){
	print ' NanoWatchdog v2015.3
 Copyright (C) 2015, Pierre Wieser <pwieser@trychlos.org>
';
}

# ---------------------------------------------------------------------
# open the communication stream with the client
# returns the newly created handle
sub open_socket(){

	# create a new TCP socket
	my $socket = new IO::Socket::INET (
		PeerHost => $opt_listen_ip,
		PeerPort => $opt_listen_port,
		Proto => 'tcp' );
	die "cannot connect to the server $!\n" unless $socket;
	print "connected to the server\n" if $opt_verbose;
	
	return( $socket );
}

# =====================================================================
# MAIN
# =====================================================================

if( !GetOptions(
	"help!"			=> \$opt_help,
	"version!"		=> \$opt_version,
	"verbose!"		=> \$opt_verbose,
	"listen=s"		=> \$opt_listen_ip,
	"port=i"		=> \$opt_listen_port,
	"command=s"		=> \$opt_command )){
		
		print "try '${0} --help' to get full usage syntax\n";
		exit( 1 );
}

#print "nbopts=$nbopts\n";
$opt_help = 1 if $nbopts < 0;

if( $opt_help ){
	msg_help();
	exit( 0 );
}

if( $opt_version ){
	msg_version();
	exit( 0 );
}

# create a connecting socket
my $socket = open_socket();
 
# send the command to the server
my $size = $socket->send( $opt_command );
print "sent data of length $size\n" if $opt_verbose;
 
# notify server that request has been sent
shutdown( $socket, true );
 
# receive a response of up to 4096 characters from server
my $response = "";
$socket->recv( $response, 4096 );
print "$response";
 
$socket->close();
