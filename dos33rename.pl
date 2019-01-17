#!/usr/bin/perl -w

#
# dos33rename.pl:
#
# Utility to rename a file on an Apple II DOS 3.3 disk image.
#
# 20190117 LSH
#

use strict;

use DOS33;

my $debug = 0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Debug
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  }
}

my $dskfile = shift or die "Must supply .dsk filename\n";
my $filename = shift or die "Must supply filename (on disk image)\n";
my $new_filename = shift or die "Must supply new filename\n";

rename_file($dskfile, $filename, $new_filename, $debug);

1;

