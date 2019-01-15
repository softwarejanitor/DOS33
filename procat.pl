#!/usr/bin/perl -w

#
# procat.pl:
#
# Utility to get a 'catalog' (directory listing) of an Apple II ProDOS volume.
#
# 20190115 LSH
#

use strict;

use ProDOS;

my $debug = 0;

my $blk = 0x0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  } elsif ($ARGV[0] eq '-b' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $blk = $ARGV[1];
    shift;
    shift;
  }
}

my $pofile = shift or die "Must supply filename\n";

cat($pofile, $debug);

1;

