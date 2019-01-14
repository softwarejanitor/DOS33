#!/usr/bin/perl -w

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

#my $buf;

#if (read_blk($pofile, $blk, \$buf)) {
#  dump_blk($buf);

  #my @bytes = unpack "C512", $buf;

  #$bytes[8] = ord('H');
  #$bytes[9] = ord('E');
  #$bytes[10] = ord('L');
  #$bytes[11] = ord('L');
  #$bytes[12] = ord('O');
  #$bytes[13] = ord('!');

  #my $buf = pack "C*", @bytes;

  #if (write_blk($pofile, $blk, $buf)) {
  #  if (read_blk($pofile, $blk, \$buf)) {
  #    dump_blk($buf);
  #  } else {
  #    print "Failed final read!\n";
  #  }
  #} else {
  #  print "Failed write!\n";
  #}
#} else {
#  print "Failed initial read!\n";
#}


#my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks, @files) = get_key_vol_dir_blk($pofile, $debug);

#print "/$volume_name\n\n";

#print " NAME           TYPE  BLOCKS  MODIFIED         CREATED          ENDFILE SUBTYPE\n\n";

#foreach my $file (@files) {
#  print sprintf(" %-15s %3s %7d %16s %16s  %7s %s\n", $file->{'filename'}, $file->{'ftype'}, $file->{'used'}, $file->{'mdate'}, $file->{'cdate'}, '', $file->{'atype'});
#}

#my $vol_dir_blk = $nxt_vol_dir_blk;

#while ($vol_dir_blk) {
#  #my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks, @files) = get_vol_dir_blk($pofile, $vol_dir_blk, $debug);
#  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, @files) = get_vol_dir_blk($pofile, $vol_dir_blk, $debug);
#  foreach my $file (@files) {
#    print sprintf(" %-15s %3s %7d %16s %16s  %7s %s\n", $file->{'filename'}, $file->{'ftype'}, $file->{'used'}, $file->{'mdate'}, $file->{'cdate'}, '', $file->{'atype'});
#  }
#  $vol_dir_blk = $nxt_vol_dir_blk;
#}

cat($pofile, $debug);

1;

