#!/usr/bin/perl
# 
# straphelper.pl
# Created: Fri Jul 28 07:50:16 2000 by tek@wiw.org
# Revised: Fri Jul 28 07:50:16 2000 (pending)
# Copyright 2000 Julian E. C. Squires (tek@wiw.org)
# This program comes with ABSOLUTELY NO WARRANTY.
# $Id$
# 
#

use IO::File;
use strict;

my $codelen = 1024;

my ($ribbondata, $ribbonlen, $bootdata, $bootlen) = (undef, $codelen/2,
						     undef, $codelen/2);

my $fp = new IO::File($ARGV[0], 'r') or die $!;
$_ = $fp->sysread($ribbondata, $ribbonlen) or die $!;
if($_ < $ribbonlen) { $ribbonlen = $_; }
undef $fp;
$fp = new IO::File($ARGV[1], 'r') or die $!;
$fp->sysread($bootdata, $bootlen) or die $!;
undef $fp;

# Open the device early, before eth0 is shut down
$fp = new IO::File('/dev/strap', 'w') or die $!;

# System specific commands here.
system('ifconfig eth0 down');

# Shutdown.
$fp->syswrite($ribbondata, $ribbonlen) or die $!;
$fp->syswrite($bootdata, $bootlen) or die $!;
if($ribbonlen < $bootlen) {
  $fp->syswrite('A'x($bootlen-$ribbonlen), ($bootlen-$ribbonlen));
}
# the point of no return

# EOF straphelper.pl
