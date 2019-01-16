#!/usr/bin/perl -w

#
# profree.pl:
#
# Utility to get a free sector map of an Apple II ProDOS volume.
#
# 20190116 LSH
#

use strict;

use ProDOS;

my $debug = 0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  }
}

my $pofile = shift or die "Must supply filename\n";

freemap($pofile, $debug);

1;

