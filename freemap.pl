#!/usr/bin/perl -w

#
# freemap.pl:
#
# Utility to get a free sector map of an Apple II DOS 3.3 disk image.
#
# 20190115 LSH
#

use strict;

use DOS33;

my $debug = 0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  }
}

my $dskfile = shift or die "Must supply .dsk filename\n";

freemap($dskfile, $debug);

1;

