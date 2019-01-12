#!/usr/bin/perl -w

use strict;

use PO;

my $debug = 0;

my $blk = -1;
my $dst_blk = -1;
my $write = 0;

my @mods = ();

while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  } elsif ($ARGV[0] eq '-b' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $blk = $ARGV[1];
    shift;
    shift;
  } elsif ($ARGV[0] eq '-db' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $dst_blk = $ARGV[1];
    shift;
    shift;
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

my $pofile = shift or die "Must supply filename\n";
die "Must supply block number 0-280\n" unless $blk >= 0 && $blk <= 280;

$dst_blk = $blk unless $dst_blk >= 0;

my $buf;

if (read_blk($pofile, $blk, \$buf)) {
  dump_blk($buf);

  if ($write) {
    print "WRITING $dst_blk\n" if $debug;
    my @bytes = unpack "C512", $buf;

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

    my $buf = pack "C*", @bytes;

    if (write_blk($pofile, $dst_blk, $buf)) {
      if (read_blk($pofile, $dst_blk, \$buf)) {
        dump_blk($buf);
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

