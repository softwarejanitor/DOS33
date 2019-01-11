#!/usr/bin/perl -w

package DSK;

use strict;

use Exporter::Auto;

my $debug = 0;

my $min_trk = 0;  # Minimum track number
my $max_trk = 34;  # Maximum track number
my $min_sec = 0;  # Minimum sector number
my $max_sec = 15;  # Maximum sector number
my $sec_size = 256;  # Sector size

#
# Read entire .dsk image.
#
sub read_dsk {
  my ($dskfile) = @_;

  my %dsk = ();

  my $dfh;

  if (open($dfh, "<$dskfile")) {
    for (my $trk = 0; $trk <= $max_trk; $trk++) {
      for (my $sec = 0; $sec <= $max_sec; $sec++) {
        my $bytes_read = read($dfh, $dsk{$trk}{$sec}, $sec_size);
        if (defined $bytes_read && $bytes_read == $sec_size) {
          print '.';
        } else {
          print "\nError reading $trk, $sec\n";
        }
      }
    }
    print "\n";
  } else {
    print "Unable to open $dskfile\n";
  }

  return %dsk;
}

#
# Calculate position in .dsk file based on track/sector.
#
sub calc_pos {
  my ($trk, $sec) = @_;

  my $pos = ($trk * ($sec_size * ($max_sec + 1))) + ($sec * $sec_size);

  #print "pos=$pos\n";

  return $pos;
}

#
# Hex dump of sector
#
sub dump_sec {
  my ($buf) = @_;

  my @bytes = unpack "C$sec_size", $buf;

  print "   ";
  for (my $c = 0; $c < 16; $c++) {
    print sprintf(" %01x ", $c);
  }
  print "\n";

  print " +------------------------------------------------\n";

  for (my $r = 0; $r < 16; $r++) {
    print sprintf("%01x| ", $r);
    for (my $c = 0; $c < 16; $c++) {
      print sprintf("%02x ", $bytes[($r * 16) + $c]);
    }
    print "\n";
    print " |";
    for (my $c = 0; $c < 16; $c++) {
      my $a = $bytes[($r * 16) + $c] & 0x7f;
      if (($a > 32) && ($a < 127)) {
        print sprintf(" %c ", $a);
      } else {
        print "  ";
      }
    }
    print "\n";
  }
  print "\n";
}

#
# Read Track/Sector
#
sub rts {
  my ($dskfile, $trk, $sec, $buf) = @_;

  #print "trk=$trk sec=$sec\n";

  my $dfh;

  my $pos = calc_pos($trk, $sec);

  if (open($dfh, "<$dskfile")) {
    binmode $dfh;

    seek($dfh, $pos, 0);

    my $bytes_read = read($dfh, $$buf, $sec_size);

    close $dfh;

    if (defined $bytes_read && $bytes_read == $sec_size) {
      #print "bytes_read=$bytes_read\n";
      return 1;
    } else {
      print "Error reading $trk, $sec\n";
    }
  } else {
    print "Unable to open $dskfile\n";
  }

  return 0;
}

#
# Write Track/Sector
#
sub wts {
  my ($dskfile, $trk, $sec, $buf) = @_;

  #print "trk=$trk sec=$sec\n";

  my $dfh;

  my $pos = calc_pos($trk, $sec);

  if (open($dfh, "+<$dskfile")) {
    binmode $dfh;

    seek($dfh, $pos, 0);

    print $dfh $buf;

    close $dfh;

    return 1;
  } else {
    print "Unable to write $dskfile\n";
  }

  return 0;
}

1;

