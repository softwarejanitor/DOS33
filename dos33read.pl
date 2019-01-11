#!/usr/bin/perl -w

use strict;

use DOS33;

my $mode = 'T';
my $conv = 1;
my $debug = 0;

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq '-m' && defined $ARGV[1] && $ARGV[1] ne '') {
    if ($ARGV[1] eq 'T') {
      $mode = 'T';
      $conv = 1;
    } elsif ($ARGV[1] eq 'I') {
      $mode = 'I';
      $conv = 0;
    } elsif ($ARGV[1] eq 'A') {
      $mode = 'A';
      $conv = 0;
    } elsif ($ARGV[1] eq 'B') {
      $mode = 'B';
      $conv = 0;
    } elsif ($ARGV[1] eq 'S') {
      $mode = 'S';
      $conv = 0;
    } else {
      die "Unknown mode for -m, must be T, I, A, B or S\n";
    }
    shift;
    shift;
  } elsif ($ARGV[0] eq '-c') {
    $conv = 0;
    shift;
  } elsif ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  }
}

my $dskfile = shift or die "Must supply filename\n";
my $filename = shift or die "Must supply filename\n";

read_file($dskfile, $filename, $mode, $conv, $debug);

1;

