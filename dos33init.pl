#!/usr/bin/perl -w

#
# dos33init.pl:
#
# Utility to initialize an Apple II DOS 3.3 disk image.
#
# 20190310 LSH
#

use strict;

use DOS33;

my $debug = 0;
my $volume = 254;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Volume
  if ($ARGV[0] eq '-v' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $volume = $ARGV[1];
    shift;
    shift;
  # Debug
  } elsif ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  } else {
    die "Unknown command line argument $ARGV[0]\n";
  }
}

my $dskfile = shift or die "Must supply .dsk filename\n";
die "Volume must be 1-254\n" if $volume < 1 || $volume > 254;

init($dskfile, $volume, $debug);

1;

