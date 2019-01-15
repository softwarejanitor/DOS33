#!/usr/bin/perl -w

#
# zap.pl:
#
# Utility to edit a DOS 3.3 sector (.DSK or .DO disk image).
#
# 20190115 LSH
#

use strict;

use DSK;

my $debug = 0;

my $trk = -1;
my $sec = -1;
my $dst_trk = -1;
my $dst_sec = -1;
my $write = 0;

my @mods = ();

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Debug
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  # Track
  } elsif ($ARGV[0] eq '-t' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $trk = $ARGV[1];
    shift;
    shift;
  # Sector
  } elsif ($ARGV[0] eq '-s' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $sec = $ARGV[1];
    shift;
    shift;
  # Destination track
  } elsif ($ARGV[0] eq '-dt' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $dst_trk = $ARGV[1];
    shift;
    shift;
  # Destination sector
  } elsif ($ARGV[0] eq '-ds' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $dst_sec = $ARGV[1];
    shift;
    shift;
  # Allow modifying data.
  } elsif ($ARGV[0] =~ /^-m([ahA])/ && defined $ARGV[1] && $ARGV[1] ne '') {
    my $typ = $1;
    print "$ARGV[1] typ=$typ\n" if $debug;
    if ($ARGV[1] =~ /^([0-9a-fA-F]+):\s*(.+)$/) {
      print "1=$1 2=$2\n" if $debug;
      push @mods, { 'typ' => $typ, 'addr' => $1, 'vals' => $2 };
    }
    shift;
    shift;
  } elsif ($ARGV[0] eq "-w") {
    $write = 1;
    shift;
  }
}

my $dskfile = shift or die "Must supply filename\n";
die "Must supply track number 0-35\n" unless $trk >= 0 && $trk <= 35;
die "Must supply sector number 0-16\n" unless $sec >= 0 && $sec <= 16;

$dst_trk = $trk unless $dst_trk >= 0;
$dst_sec = $sec unless $dst_sec >= 0;

my $buf;

if (rts($dskfile, $trk, $sec, \$buf)) {
  # Display the data in the sector.
  dump_sec($buf);

  # Allow modifying data.
  if ($write) {
    print "WRITING $dst_trk $dst_sec\n" if $debug;
    # Unpack the data in the sector.
    my @bytes = unpack "C256", $buf;

    foreach my $mod (@mods) {
      my @mbytes = ();
      if ($mod->{'typ'} eq 'a') {
        print "ASCII vals=$mod->{'vals'}\n" if $debug;
        # Normal ASCII
        @mbytes = map { pack('C', ord($_)) } ($mod->{'vals'} =~ /(.)/g);
      } elsif ($mod->{'typ'} eq 'A') {
        print "HEX vals=$mod->{'vals'}\n" if $debug;
        # Apple II ASCII
        @mbytes = map { pack('C', ord($_) | 0x80) } ($mod->{'vals'} =~ /(.)/g);
      } elsif ($mod->{'typ'} eq 'h') {
        print "A2 ASCII vals=$mod->{'vals'}\n" if $debug;
        # HEX
        @mbytes = map { pack('C', hex(lc($_))) } ($mod->{'vals'} =~ /(..)/g);
      }
      my $addr = hex($mod->{'addr'});
      print "addr=$addr\n" if $debug;
      foreach my $byte (@mbytes) {
        print sprintf("byte=%02x\n", ord($byte)) if $debug;
        $bytes[$addr++] = ord($byte);
      }
    }

    # Re-pack the data in the sector.
    $buf = pack "C*", @bytes;

    # Write the sector.
    if (wts($dskfile, $dst_trk, $dst_sec, $buf)) {
      # Read the sector back in.
      if (rts($dskfile, $dst_trk, $dst_sec, \$buf)) {
        # Display the data in the modified sector.
        dump_sec($buf);
      } else {
        print "Failed final read!\n";
      }
    } else {
      print "Failed write!\n";
    }
  }
} else {
  print "Failed initial read!\n";
}

1;

