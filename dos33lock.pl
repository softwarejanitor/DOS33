#!/usr/bin/perl -w

#
# dos33lock.pl:
#
# Utility to lock a file on an Apple II DOS 3.3 disk image.
#
# 20190116 LSH
#

use strict;

use DOS33;

my $debug = 0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Debug
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  } else {
    die "Unknown command line argument $ARGV[0]\n";
  }
}

my $dskfile = shift or die "Must supply .dsk filename\n";
my $filename = shift or die "Must supply filename (on disk image)\n";

lock_file($dskfile, $filename, $debug);

1;

