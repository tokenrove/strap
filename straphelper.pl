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

my ($ribbondata, $ribbonlen, $bootdata, $bootlen) = (undef, 512, undef, 512);

my $fp = new IO::File($ARGV[0], 'r');
$fp->sysread($ribbondata, $ribbonlen);
undef $fp;
$fp = new IO::File($ARGV[1], 'r');
$fp->sysread($bootdata, $bootlen);

# Open the device early, before eth0 is shut down
$fp = new IO::File('/dev/strap', 'w');

# System specific commands here.
system('ifconfig eth0 down');

# Shutdown.
$fp->syswrite($ribbondata, $ribbonlen);
$fp->syswrite($bootdata, $bootlen);

# EOF straphelper.pl
