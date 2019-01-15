#!/usr/bin/perl -w

#
# catalog.pl:
#
# Utility to get a 'catalog' (directory) of an Apple II DOS 3.3 disk image.
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

my $dskfile = shift or die "Must supply filename\n";

catalog($dskfile, $debug);

1;

