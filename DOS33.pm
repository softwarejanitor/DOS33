#!/usr/bin/perl -w

package DOS33;

#
# DOS33.pm:
#
# Module to access Apple II DOS 3.3 disk images.
#
# 20190115 LSH
#

use strict;

use POSIX;

use DSK;

use Exporter::Auto;

my $debug = 0;

my $min_trk = 0;  # Minimum track number
my $max_trk = 34;  # Maximum track number
my $min_sec = 0;  # Minimum sector number
my $max_sec = 15;  # Maximum sector number
my $sec_size = 256;  # Sector size

my $vtoc_trk = 0x11;  # Default VTOC track
my $vtoc_sec = 0x00;  # Default VTOC sector

# DOS 3.3 file types
my %file_types = (
  0x00 => ' T',  # Text file
  0x01 => ' I',  # INTBASIC file
  0x02 => ' A',  # Applesoft file
  0x04 => ' B',  # Binary file
  0x08 => ' S',  # Special file
  0x10 => ' R',  # Relocatable file
  0x20 => ' A',  # A file
  0x40 => ' B',  # B file
);

# DOS 3.3 file types (display)
my %disp_file_types = (
  0x00 => ' T',  # Unlocked Text file
  0x01 => ' I',  # Unlocked INTBASIC file
  0x02 => ' A',  # Unlocked Applesoft file
  0x04 => ' B',  # Unlocked Binary file
  0x08 => ' S',  # Unlocked Special file
  0x10 => ' R',  # Unlocked Relocatable file
  0x20 => ' A',  # Unlocked A file
  0x40 => ' B',  # Unlocked B file
  0x80 => '*T',  # Locked text file
  0x81 => '*I',  # Locked INTBASIC file
  0x82 => '*A',  # Locked Applesoft file
  0x84 => '*B',  # Locked Binary file
  0x88 => '*S',  # Locked Special file
  0x90 => '*R',  # Locked Relocatable file
  0xa0 => '*A',  # Locked A file
  0xb0 => '*B',  # Locked B file
);

# For free space counts.
my %ones_count = (
  0x00 => 0,  # 0000
  0x01 => 1,  # 0001
  0x02 => 1,  # 0010
  0x03 => 2,  # 0011
  0x04 => 1,  # 0100
  0x05 => 2,  # 0101
  0x06 => 2,  # 0110
  0x07 => 3,  # 0111
  0x08 => 1,  # 1000
  0x09 => 2,  # 1001
  0x0a => 2,  # 1010
  0x0b => 3,  # 1011
  0x0c => 2,  # 1100
  0x0d => 3,  # 1101
  0x0e => 3,  # 1110
  0x0f => 4,  # 1111
);

#
# Volume Table of Contents (VTOC) Format
#
# 00    Not used
# 01    Track number of first catalog sector
# 02    Sector number of first catalog sector
# 03    Release number of DOS used to INIT this diskette
# 04-05 Not used
# 06    Diskette volume number
# 07-26 Not used
# 27    Maximum number of track/sector list sector (122 for 256 byte sectors)
# 28-2f Not used
# 30    Last track where sectors were allocated
# 31    Direction of track allocation (+1 or -1)
# 32-33 Not used
# 34    Number of tracks per diskette (normally 35)
# 35    Number of sectors per track (13 or 16)
# 36-37 Number of bytes per sector (LO/HI format)
# 38-3b Bit map of free sectors in track 0
# 3c-3f Bit map of free sectors in track 1
# 40-43 Bit map of free sectors in track 2
#       ...
# bc-bf Bit map of free sectors in track 33
# c0-c3 Bit map of free sectors in track 34
# c4-cf Bit maps for additional tracks if there are more than 35 tracks per diskette
#
my $vtoc_fmt_tmpl = 'xCCCx2Cx32Cx8CCx2CCva140';

#
# Bit maps of free sectors on a given track
#
# BYTE     SECTORS
# 0        FDEC BA98
# 1        7654 3210
# 2        .... .... (not used)
# 3        .... .... (not used)
#
my $bit_map_free_sec_tmpl = 'nx2';

#
#
# Catalog Sector Format
#
# 00    Not used
# 01    Track number of next catalog sector (usually 11 hex)
# 02    Sector number of next catalog sector
# 03-0a Not used
# 0b-2d First file descriptive entry
# 2e-50 Second file descriptive entry
# 51-73 Third file descriptive entry
# 74-96 Fourth file descriptive entry
# 97-b9 Fifth file descriptive entry
# ba-dc Sixth file descriptive entry
# dd-ff Seventh file descriptive entry
#
my $cat_sec_fmt_tmpl = 'xCCx8a35a35a35a35a35a35a35';

#
# File Descriptive Entry Format
#
# 00    Track of first track/sector list sector.
# 01    Sector of first track/sector list sector.
# 02    File type and flags:
# 03-20 File name (30 characters)
# 21-22 Length of file in sectors (LO/HI format).
#
my $file_desc_ent_dmt_tmpl = 'CCCa30C';

#
# Track/Sector ListFormat
#
# 00    Not used
# 01    Track number of next T/S List sector if one was needed or zero if no more T/S List sectors.
# 02    Sector number of next T/S List sector (if present).
# 03-04 Not used
# 05-06 Sector offset in file of the first sector described by this list.
# 07-0b Not used
# 0c-0d Track and sector of first data sector or zeros
# 0e-0f Track and sector of second data sector or zeros
# 10-ff Up to 120 more Track/Sector pairs
#
my $tslist_fmt_tmpl = 'xCCx2vx5a122';

my %dsk = ();  # Memory for disk image.

#
# Display a file entry in DOS 3.3 catalog format.
#
sub display_file_entry {
  my ($file_type, $filename, $file_length) = @_;

  print sprintf("%-2s %03d %s\n", $disp_file_types{$file_type}, $file_length, $filename);
}

# Parse a file entry
sub parse_file_entry {
  my ($file_desc_entry) = @_;

  my ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = unpack $file_desc_ent_dmt_tmpl, $file_desc_entry;

  return undef if $first_tslist_trk eq '';
  return undef if $first_tslist_trk == 0xff;  # Deleted
  return undef if $first_tslist_trk == 0x00;  # Never used

  $file_length = 0 unless defined $file_length;

  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    # Convert Apple ASCII to normal (clear the high bit)
    my $fname = '';
    my @bytes = unpack "C*", $filename;
    foreach my $byte (@bytes) {
      $fname .= sprintf("%c", $byte & 0x7f);
    }

    return $first_tslist_trk, $first_tslist_sec, $file_type, $fname, $file_length;
  }

  return 0;
}

# Parse a catalog sector
sub parse_cat_sec {
  my ($buf) = @_;

  my ($trk_num_nxt_cat_sec, $sec_num_nxt_cat_sec, $first_file_desc_ent, $second_file_desc_ent, $third_file_desc_ent, $fourth_file_desc_ent, $fifth_file_desc_ent, $sixth_file_desc_ent, $seventh_file_desc_ent) = unpack $cat_sec_fmt_tmpl, $buf;

  my @files = ();

  my $empty_file_entry = 0;
  my ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length);
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($first_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 1 };
  } else {
    $empty_file_entry = 1;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($second_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 2 };
  } else {
    $empty_file_entry = 2 if $empty_file_entry == 0;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($third_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 3 };
  } else {
    $empty_file_entry = 3 if $empty_file_entry == 0;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($fourth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 4 };
  } else {
    $empty_file_entry = 4 if $empty_file_entry == 0;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($fifth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 5 };
  } else {
    $empty_file_entry = 5 if $empty_file_entry == 0;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($sixth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 6 };
  } else {
    $empty_file_entry = 6 if $empty_file_entry == 0;
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($seventh_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 7 };
  } else {
    $empty_file_entry = 7 if $empty_file_entry == 0;
  }

  return $trk_num_nxt_cat_sec, $sec_num_nxt_cat_sec, $empty_file_entry, @files;
}

# Get catalog sector
sub get_cat_sec {
  my ($dskfile, $cat_trk, $cat_sec) = @_;

  my $buf;

  if (rts($dskfile, $cat_trk, $cat_sec, \$buf)) {
    return $buf, parse_cat_sec($buf);
  }

  return 0;
}

#
# Display disk catalog
#
sub catalog {
  my ($dskfile, $dbg) = @_;

  if (defined $dbg && $dbg) {
    $debug = 1;
  }

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  if (defined $trk_num_1st_cat_sec && $trk_num_1st_cat_sec ne '') {
    print sprintf("DISK VOLUME %d\n\n", $dsk_vol_num);

    my $cat_buf;
    my ($next_cat_trk, $next_cat_sec) = ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec);
    my @files = ();
    my $empty_file_entry;
    do {
      ($cat_buf, $next_cat_trk, $next_cat_sec, $empty_file_entry, @files) = get_cat_sec($dskfile, $next_cat_trk, $next_cat_sec);
      #if (defined $next_cat_trk && $next_cat_trk ne '') {
      if (scalar @files) {
        foreach my $file (@files) {
          display_file_entry($file->{'file_type'}, $file->{'filename'}, $file->{'file_length'});
        }
      }
    } while ($next_cat_trk != 0);
  } else {
    return 0;
  }

  return 1;
}

#
# Calculate free space
#
sub freespace {
  my ($dskfile, $dbg) = @_;

  if (defined $dbg && $dbg) {
    $debug = 1;
  }

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  my $tmpl = '';
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    $tmpl .= $bit_map_free_sec_tmpl;
  }

  my $free_sectors = 0;
  my @flds = unpack $tmpl, $bit_map_free_secs;
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    $free_sectors += $ones_count{($flds[$t] >> 12)};  # Sectors fdec
    $free_sectors += $ones_count{($flds[$t] >> 8) & 0x0f};  # Sectors ba98
    $free_sectors += $ones_count{($flds[$t] >> 4) & 0x0f};  # Sectors 7654
    $free_sectors += $ones_count{$flds[$t] & 0x0f};  # Sectors 3210
  }

  #print "$free_sectors sectors free\n";

  return $free_sectors;
}

#
# Display sector free map
#
sub freemap {
  my ($dskfile, $dbg) = @_;

  if (defined $dbg && $dbg) {
    $debug = 1;
  }

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  print "   0123456789abcdef\n";
  print "  +----------------\n";
  my $tmpl = '';
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    $tmpl .= $bit_map_free_sec_tmpl;
  }
  print "tmpl=$tmpl\n" if $debug;
  my $free_sectors = 0;
  my @flds = unpack $tmpl, $bit_map_free_secs;
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    print sprintf("%2d %04x\n", $t, $flds[$t]) if $debug;
    print sprintf("%2d %016b\n", $t, $flds[$t]) if $debug;
    my $fr = sprintf("%016b", $flds[$t]);
    print "fr=$fr\n" if $debug;
    my $fm = reverse $fr;
    print "fm=$fm\n" if $debug;
    $fm =~ s/0/ /g;
    $fm =~ s/1/*/g;
    print "fm=$fm\n" if $debug;
    print sprintf("%2d|%s\n", $t, $fm);

    $free_sectors += $ones_count{($flds[$t] >> 12)};  # Sectors fdec
    $free_sectors += $ones_count{($flds[$t] >> 8) & 0x0f};  # Sectors ba98
    $free_sectors += $ones_count{($flds[$t] >> 4) & 0x0f};  # Sectors 7654
    $free_sectors += $ones_count{$flds[$t] & 0x0f};  # Sectors 3210
  }
  #print "bit_map_free_secs=";
  #my @bytes = unpack "C*", $bit_map_free_secs;
  #foreach my $byte (@bytes) {
  #  print sprintf("%02x ", $byte);
  #}
  print "\n";

  print "$free_sectors sectors free\n";
}

# Parse a VTOC sector
sub parse_vtoc_sec {
  my ($buf) = @_;

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = unpack $vtoc_fmt_tmpl, $buf;

  if ($debug) {
    print sprintf("trk_num_1st_cat_sec=%02x\n", $trk_num_1st_cat_sec);
    print sprintf("sec_num_1st_cat_sec=%02x\n", $sec_num_1st_cat_sec);
    print sprintf("rel_num_dos=%02x\n", $rel_num_dos);
    print sprintf("dsk_vol_num=%02x\n", $dsk_vol_num);
    print sprintf("max_tslist_secs=%02x\n", $max_tslist_secs);
    print sprintf("last_trk_secs_alloc=%02x\n", $last_trk_secs_alloc);
    print sprintf("dir_trk_alloc=%02x\n", $dir_trk_alloc);
    print sprintf("num_trks_dsk=%02x\n", $num_trks_dsk);
    print sprintf("num_secs_dsk=%02x\n", $num_secs_dsk);
    print sprintf("num_bytes_sec=%04x\n", $num_bytes_sec);
    print "bit_map_free_secs=";
    my @bytes = unpack "C*", $bit_map_free_secs;
    foreach my $byte (@bytes) {
      print sprintf("%02x ", $byte);
    }
    print "\n";
  }

  return $trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs;
}

#
# Get VTOC Sector
#
sub get_vtoc_sec {
  my ($dskfile) = @_;

  my $buf;

  if (rts($dskfile, $vtoc_trk, $vtoc_sec, \$buf)) {
    dump_sec($buf) if $debug;
    return parse_vtoc_sec($buf);
  }

  return 0;
}

sub write_vtoc {
  my ($dskfile, $trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = @_;

  # Re-pack vtoc sector, the double pack is to pad the sector with zero bytes.
  my $buf = pack "a$sec_size", pack $vtoc_fmt_tmpl, ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs);

  print "Writing vtoc\n" if $debug;

  if ($debug) {
    print "vtoc=";
    my @bytes = unpack "C*", $buf;
    foreach my $byte (@bytes) {
      print sprintf("%02x ", $byte);
    }
    print "\n";
  }

  dump_sec($buf) if $debug;

  # Write back vtoc sector.
  if (!wts($dskfile, $vtoc_trk, $vtoc_sec, $buf)) {
    print "Failed to write vtoc sector $vtoc_trk $vtoc_sec!\n";
    return 0;
  }

  return 1;
}

#
# Parse a sector of a track/sector list
#
sub parse_tslist_sec {
  my ($buf, $num_secs) = @_;

  #dump_sec($buf);
# Track/Sector ListFormat
#
# 00    Not used
# 01    Track number of next T/S List sector if one was needed or zero if no more T/S List sectors.
# 02    Sector number of next T/S List sector (if present).
# 03-04 Not used
# 05-06 Sector offset in file of the first sector described by this list.
# 07-0b Not used
# 0c-0d Track and sector of first data sector or zeros
# 0e-0f Track and sector of second data sector or zeros
# 10-ff Up to 120 more Track/Sector pairs
#
#$tslist_fmt_tmpl = 'xCCx2vx5a122';
  my @secs = ();

##FIXME -- tslist_fmt_tmpl should not have 122 hard coded, that value shoulc come from vtoc.
  my ($next_tslist_trk, $next_tslist_sec, $soffset, $tslist) = unpack $tslist_fmt_tmpl, $buf;

  #if ($debug) {
    print "num_secs=$num_secs\n";
    print "tslist=";
    my @bytes = unpack "C*", $tslist;
    foreach my $byte (@bytes) {
      print sprintf("%02x ", $byte);
    }
    print "\n";
  #}

  my $tmpl = '';
  for (my $ts = 0; $ts < 122; $ts++) {
    $tmpl .= 'CC';
  }
  my (@tsl) = unpack $tmpl, $tslist;

  for (my $ts = 0; $ts < 122; $ts++) {
    my $sec = pop @tsl;
    my $trk = pop @tsl;
    last unless defined $trk;
    last if $trk eq '';
    next if $trk == 0 && $sec == 0;
    print "Adding trk=$trk sec=$sec to tslist\n";
    unshift @secs, { 'trk' => $trk, 'sec' => $sec };
  }

  return $next_tslist_trk, $next_tslist_sec, @secs;
}

#
# Get a sector of a track/sector list
#
sub get_tslist_sec {
  my ($dskfile, $tslist_trk, $tslist_sec, $num_secs) = @_;

  my $buf;

  if (rts($dskfile, $tslist_trk, $tslist_sec, \$buf)) {
    #dump_sec($buf) if $debug;
    dump_sec($buf);
    return parse_tslist_sec($buf, $num_secs);
  }

  return 0;
}

#
# Get a track/sector list
#
sub get_tslist {
  my ($dskfile, $tslist_trk, $tslist_sec, $num_secs) = @_;

  my ($next_tslist_trk, $next_tslist_sec) = ($tslist_trk, $tslist_sec);

  my @secs = ();

  do {
    ($next_tslist_trk, $next_tslist_sec, @secs) = get_tslist_sec($dskfile, $next_tslist_trk, $next_tslist_sec, $num_secs);
    if (defined $next_tslist_trk && $next_tslist_trk ne '') {
      print "pushing trk $next_tslist_trk sec $next_tslist_sec\n";
      push @secs, { 'trk' => $next_tslist_trk, 'sec', $next_tslist_sec };
    }
  } while ($next_tslist_trk != 0);

  return @secs;
}

#
# Find a file in the catalog
#
sub find_file {
  my ($dskfile, $filename) = @_;

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  if (defined $trk_num_1st_cat_sec && $trk_num_1st_cat_sec ne '') {
    my ($next_cat_trk, $next_cat_sec) = ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec);
    my $cat_buf;
    my @files = ();
    do {
      my $cur_cat_trk = $next_cat_trk;
      my $cur_cat_sec = $next_cat_sec;
      my $empty_file_entry;
      ($cat_buf, $next_cat_trk, $next_cat_sec, $empty_file_entry, @files) = get_cat_sec($dskfile, $next_cat_trk, $next_cat_sec);
      #if (defined $next_cat_trk && $next_cat_trk ne '') {
      if (scalar @files) {
        foreach my $file (@files) {
          my $fn = $file->{'filename'};
          $fn =~ s/\s+$//g;
          if ($fn eq $filename) {
            #print "trk=$file->{'trk'} sec=$file->{'sec'}\n";
            return $file, $cur_cat_trk, $cur_cat_sec, $cat_buf;
          }
        }
      }
    } while ($next_cat_trk != 0);
  } else {
    return 0;
  }

  print "File $filename NOT FOUND\n";

  return 0;
}

#
# Read a file
#
sub read_file {
  my ($dskfile, $filename, $mode, $conv, $dbg) = @_;

  $mode = '' unless defined $mode;
  $conv = 0 unless defined $conv;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    my $buf;

    my @secs = get_tslist($dskfile, $file->{'trk'}, $file->{'sec'}, $file->{'file_length'});
    foreach my $sec (@secs) {
      next if $sec->{'trk'} == 0 && $sec->{'sec'} == 0;
      #print "**** trk=$sec->{'trk'} sec=$sec->{'sec'}\n";
      if (rts($dskfile, $sec->{'trk'}, $sec->{'sec'}, \$buf)) {
        dump_sec($buf) if $debug;
        #my @bytes = unpack "C$sec_size", $buf;
        my @bytes = unpack "C*", $buf;
        foreach my $byte (@bytes) {
          # For text file translation.
          last if $byte == 0x00 && $mode eq 'T';
          # Translate \r to \n
          $byte = 0x0a if $byte == 0x8d && $conv;
          # Convert Apple II ASCII to standard ASCII (clear high bit)
          $byte &= 0x7f if $mode eq 'T';
          #print sprintf("%c", $byte & 0x7f);
          print sprintf("%c", $byte);
        }
##FIXME -- need to handle additional file types + handle incomplete last sectors properly here.
      }
    }
  }
}

#
# Unlock a file
#
sub unlock_file {
  my ($dskfile, $filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    print "cat_trk=$cat_trk cat_sec=$cat_sec\n" if $debug;
    dump_sec($cat_buf) if $debug;
    my @bytes = unpack "C*", $cat_buf;

    # 12 is number of bytes before file descriptive entries, 35 is length of file descriptive entry.
    my $file_type = $bytes[13 + (($file->{'cat_offset'} - 1) * 35)];

    print sprintf("cat_offset=%d\n", $file->{'cat_offset'}) if $debug;
    print sprintf("file_type=%02x\n", $file_type) if $debug;

    # Mark file as unlocked.
    my $new_file_type = $bytes[13 + (($file->{'cat_offset'} - 1) * 35)] & 0x7f;
    print sprintf("new_file_type=%02x\n", $new_file_type) if $debug;
    $bytes[13 + (($file->{'cat_offset'} - 1) * 35)] = $new_file_type;

    # Re-pack the data in the catalog sector.
    $cat_buf = pack "a$sec_size", pack "C*", @bytes;

    dump_sec($cat_buf) if $debug;
    # Write back catalog sector.
    if (!wts($dskfile, $cat_trk, $cat_sec, $cat_buf)) {
      print "Failed to write catalog sector $cat_trk $cat_sec!\n";
    }
  }
}

#
# Lock a file
#
sub lock_file {
  my ($dskfile, $filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    print "cat_trk=$cat_trk cat_sec=$cat_sec\n" if $debug;
    dump_sec($cat_buf) if $debug;
    my @bytes = unpack "C*", $cat_buf;

    # 12 is number of bytes before file descriptive entries, 35 is length of file descriptive entry.
    my $file_type = $bytes[13 + (($file->{'cat_offset'} - 1) * 35)];

    print sprintf("cat_offset=%d\n", $file->{'cat_offset'}) if $debug;
    print sprintf("file_type=%02x\n", $file_type) if $debug;

    # Mark file as locked.
    my $new_file_type = $bytes[13 + (($file->{'cat_offset'} - 1) * 35)] | 0x80;
    print sprintf("new_file_type=%02x\n", $new_file_type) if $debug;
    $bytes[13 + (($file->{'cat_offset'} - 1) * 35)] = $new_file_type;

    # Re-pack the data in the sector.
    $cat_buf = pack "a$sec_size", pack "C*", @bytes;

    dump_sec($cat_buf) if $debug;
    # Write back catalog sector.
    if (!wts($dskfile, $cat_trk, $cat_sec, $cat_buf)) {
      print "Failed to write catalog sector $cat_trk $cat_sec!\n";
    }
  }
}

#
# Delete a file
#
sub delete_file {
  my ($dskfile, $filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    print "cat_trk=$cat_trk cat_sec=$cat_sec\n" if $debug;
    dump_sec($cat_buf) if $debug;
    my @bytes = unpack "C*", $cat_buf;

    # Mark file as deleted.
    # 11 is first tslist sector track
    my $first_tslist_sec_trk = $bytes[11 + (($file->{'cat_offset'} - 1) * 35)];
    print sprintf("first_tslist_sec_trk=%02x\n", $first_tslist_sec_trk) if $debug;
    $bytes[11 + (($file->{'cat_offset'} - 1) * 35)] = 0x00;
    # Set last byte of filename to first tslist sector track
    $bytes[43 + (($file->{'cat_offset'} - 1) * 35)] = $first_tslist_sec_trk;

    # Re-pack the data in the sector.
    $cat_buf = pack "a$sec_size", pack "C*", @bytes;

    dump_sec($cat_buf) if $debug;
    # Write back catalog sector.
    if (!wts($dskfile, $cat_trk, $cat_sec, $cat_buf)) {
      print "Failed to write catalog sector $cat_trk $cat_sec!\n";
    }

    my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = get_vtoc_sec($dskfile);

    my $tmpl = '';
    for (my $t = $min_trk; $t <= $max_trk; $t++) {
      $tmpl .= $bit_map_free_sec_tmpl;
    }

    print "tmpl=$tmpl\n" if $debug;
    my @flds = unpack $tmpl, $bit_map_free_secs;

    if ($debug) {
      for (my $t = $min_trk; $t <= $max_trk; $t++) {
        print sprintf("%2d %04x\n", $t, $flds[$t]) if $debug;
        print sprintf("%2d %016b\n", $t, $flds[$t]) if $debug;
        my $fr = sprintf("%016b", $flds[$t]);
        print "fr=$fr\n" if $debug;
        my $fm = reverse $fr;
        print "fm=$fm\n" if $debug;
        $fm =~ s/0/ /g;
        $fm =~ s/1/*/g;
        print "fm=$fm\n" if $debug;
        print sprintf("%2d|%s\n", $t, $fm);
      }
    }

    # get the files t/s list and free those sectors
    my @secs = get_tslist($dskfile, $file->{'trk'}, $file->{'sec'}, $file->{'file_length'});
    foreach my $sec (@secs) {
      next if $sec->{'trk'} == 0 && $sec->{'sec'} == 0;
      print "Freeing trk=$sec->{'trk'} sec=$sec->{'sec'}\n";
      my $fr = sprintf("%016b", $flds[$sec->{'trk'}]);
      #print "fr=$fr\n";
      $flds[$sec->{'trk'}] |= (1 << $sec->{'sec'});
      my $fr2 = sprintf("%016b", $flds[$sec->{'trk'}]);
      #print "fr=$fr2\n";
    }
    ##FIXME -- may need to free additional tslist sectors.
    $flds[$file->{'trk'}] |= (1 << $file->{'sec'});

    if ($debug) {
      for (my $t = $min_trk; $t <= $max_trk; $t++) {
        print sprintf("%2d %04x\n", $t, $flds[$t]) if $debug;
        print sprintf("%2d %016b\n", $t, $flds[$t]) if $debug;
        my $fr = sprintf("%016b", $flds[$t]);
        print "fr=$fr\n" if $debug;
        my $fm = reverse $fr;
        print "fm=$fm\n" if $debug;
        $fm =~ s/0/ /g;
        $fm =~ s/1/*/g;
        print "fm=$fm\n" if $debug;
        print sprintf("%2d|%s\n", $t, $fm);
      }
    }

    $bit_map_free_secs = pack $tmpl, @flds;

    # Write back vtoc
    if (!write_vtoc($dskfile, $trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs)) {
      print "I/O ERROR!\n";
    }
  }
}

#
# Rename a file
#
sub rename_file {
  my ($dskfile, $filename, $new_filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  if (length($new_filename) > 30) {
    print "Filename $new_filename too long\n";
    return;
  }

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    print "cat_trk=$cat_trk cat_sec=$cat_sec\n" if $debug;
    dump_sec($cat_buf) if $debug;
    my @bytes = unpack "C*", $cat_buf;

    my $fname_start = 14 + (($file->{'cat_offset'} - 1) * 35);
    print sprintf("fname_start=%02x\n", $fname_start) if $debug;

    # Change filename
    for (my $i = 0; $i < length($new_filename); $i++) {
      # Set the high bit
      $bytes[$fname_start + $i] = ord(substr($new_filename, $i, 1)) | 0x80;
    }
    # Make sure new filename is space padded
    for (my $i = length($new_filename); $i < 30; $i++) {
      # 0xa0 is Apple II space (high bit set)
      $bytes[$fname_start + $i] = 0xa0;
    }

    # Re-pack the data in the catalog sector.
    $cat_buf = pack "a$sec_size", pack "C*", @bytes;

    dump_sec($cat_buf) if $debug;
    # Write back catalog sector.
    if (!wts($dskfile, $cat_trk, $cat_sec, $cat_buf)) {
      print "Failed to write catalog sector $cat_trk $cat_sec!\n";
    }
  }
}

#
# Find empty file descriptive entry for writing a file.
#
sub find_empty_file_desc_ent {
  my ($dskfile, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  if (defined $trk_num_1st_cat_sec && $trk_num_1st_cat_sec ne '') {
    my ($next_cat_trk, $next_cat_sec) = ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec);
    my $cat_buf;
    my @files = ();
    my $empty_file_entry;
    do {
      my $cur_cat_trk = $next_cat_trk;
      my $cur_cat_sec = $next_cat_sec;
      ($cat_buf, $next_cat_trk, $next_cat_sec, $empty_file_entry, @files) = get_cat_sec($dskfile, $next_cat_trk, $next_cat_sec);
      return ($cat_buf, $cur_cat_trk, $cur_cat_sec, $empty_file_entry) if $empty_file_entry > 0;
    } while ($next_cat_trk != 0);
  } else {
    print "I/O ERROR!\n";
    return 0;
  }

  print "DISK FULL!\n";

  return 0;
}

#
# Get a list of free sectors
#
sub find_free_sectors {
  my ($dskfile, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = get_vtoc_sec($dskfile);

  my @secs = ();

  my $tmpl = '';
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    $tmpl .= $bit_map_free_sec_tmpl;
  }
  print "tmpl=$tmpl\n" if $debug;
  my @flds = unpack $tmpl, $bit_map_free_secs;
  for (my $t = $min_trk; $t <= $max_trk; $t++) {
    for (my $s = 0; $s < 16; $s++) {
      if ($flds[$t] & 1 << $s) {
        print "Free $t $s\n" if $debug;
        push @secs, { 'trk' => $t, 'sec' => $s };
      }
    }
  }

  return @secs;
}

#
# Copy a file
#
sub copy_file {
  my ($dskfile, $filename, $new_filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if (defined $file && $file && $file->{'trk'}) {
    ##FIXME

  }
}

#
# Write a file to disk image.
#
sub write_file {
  my ($dskfile, $filename, $new_filename, $mode, $conv, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

$debug = 1;

  # Find empty catalog file descriptive entry.
  my ($cat_buf, $cat_trk, $cat_sec, $empty_file_entry) = find_empty_file_desc_ent($dskfile);

  print "cat_trk=$cat_trk cat_sec=$cat_sec empty_file_entry=$empty_file_entry\n" if $debug;

  if ($empty_file_entry) {
    # Find free sectors.
    my @used_secs = ();
    my @free_secs = find_free_sectors($dskfile, $debug);
    if (scalar @free_secs) {
      my $sectors_used = 0;

      my $buf;

      # Read input file a sector worth at a time.
      my $file_length = 0;

      my $ifh;

      if (open($ifh, "<$filename")) {
        my $done = 0;
        my $error = 0;
        while (! $done) {
          # Initialize sector buffer.
          $buf = pack "C*", 0x00 x $sec_size;

          # Read a sectors worth of data.
          my $bytes_read = read($ifh, $buf, $sec_size);
          print "Read $bytes_read bytes\n" if $debug;
          if ($bytes_read < $sec_size) {
            # Last sector
            $done = 1;
          }

          # Keep track of file size.
          $file_length += $bytes_read;

          # Pop a sector from the free sector list.
          my $next_sec;
          if (scalar @free_secs) {
            $next_sec = pop @free_secs;
            print "Next free sector is trk $next_sec->{'trk'} sec $next_sec->{'sec'}\n" if $debug;
            # Push it onto the used sector list.
            push @used_secs, { 'trk' => $next_sec->{'trk'}, 'sec' => $next_sec->{'sec'} };

            # Write the data to the next sector.
            print "Writing trk $next_sec->{'trk'} sec $next_sec->{'sec'}\n" if $debug;
            if (!wts($dskfile, $next_sec->{'trk'}, $next_sec->{'sec'}, $buf)) {
              print "Failed to write sector $next_sec->{'trk'} $next_sec->{'sec'}!\n";
            }
            $sectors_used++;
          } else {
            # Disk full.
            print "DISK FULL!\n";
            $error = 1;
            $done = 1;
          }
        }
        print sprintf("sectors_used=%04x\n", $sectors_used);
        print sprintf("num_used_secs=%d\n", scalar @used_secs);

        # Number of tslists is number of sectors used / 121.
        my $num_tslists = ceil($sectors_used / 121);
        print "Need $num_tslists tslist sector(s)\n" if $debug;

        # Create t/s list(s).
        my $first_tslist_trk = 0;
        my $first_tslist_sec = 0;

        my @tslist_secs = ();
        my $cur_tslist = 1;
        for (my $ts = 0; $ts < $num_tslists; $ts++) {
          my $next_sec;
          if (scalar @free_secs) {
            $next_sec = pop @free_secs;
            print "Next free sector is trk $next_sec->{'trk'} sec $next_sec->{'sec'}\n" if $debug;
            if ($cur_tslist++ == 1) {
              $first_tslist_trk = $next_sec->{'trk'};
              $first_tslist_sec = $next_sec->{'sec'};
            }

            print "Writing tslist $ts\n" if $debug;
            my $next_tslist_trk = 0x00;
            my $next_tslist_sec = 0x00;
            if ($ts < $num_tslists) {
              $next_tslist_trk = $free_secs[0]->{'trk'};
              $next_tslist_sec = $free_secs[0]->{'sec'};
            }
            my $soffset = pack "CCC", (0x00, 0x00, 0x00);
            if ($ts > 0) {
              # Calculate soffset for this sector.
              my $off = $ts * 121;
              my $of1 = ($off & 0xff0000) >> 16;
              my $of2 = ($off & 0x00ff00) >> 8;
              my $of3 = $off & 0x0000ff;
              $soffset = pack "CCC", ($of1, $of2, $of3);
            }
            # Make data for this tslist sector -- hunks of 121 t/s pairs.
            #print sprintf("\*\*\*\* num_used_secs=%d\n", scalar @used_secs);
            #my @temp_used_secs = map { [@$_] } @used_secs;
            #my @tsl = splice @temp_used_secs, ($ts * 121), 121;
            #print sprintf("\*\*\*\* num_used_secs=%d\n", scalar @used_secs);
            #print sprintf("num_secs_in_tsl_tsl=%d\n", scalar @tsl);
            my @tsl = ();
            for (my $cur_ts = $ts * 121; $cur_ts < ($ts * 121) + 121; $cur_ts++) {
              print "cur_ts=$cur_ts\n";
              last if $cur_ts > scalar @used_secs;
              print "tsl trk $used_secs[$cur_ts]->{'trk'} sec $used_secs[$cur_ts]->{'sec'}\n";
              push @tsl, { 'trk' => $used_secs[$cur_ts]->{'trk'}, 'sec' => $used_secs[$cur_ts]->{'sec'} };
            }

            my $tslst_fmt = 'C' x 242;
            my $tslist = pack $tslst_fmt, @tsl;
            my $tslist_buf = pack "a$sec_size", pack $tslist_fmt_tmpl, ($next_tslist_trk, $next_tslist_sec, $soffset, $tslist);

            print "Writing tslist\n" if $debug;
            if (!wts($dskfile, $next_sec->{'trk'}, $next_sec->{'sec'}, $tslist_buf)) {
              print "Failed to write catalog sector $cat_trk $cat_sec!\n";
            }
            push @tslist_secs, { 'trk' => $next_sec->{'trk'}, 'sec' =>  $next_sec->{'sec'} };
          } else {
            print "DISK FULL!\n";
            return;
          }
        }
        print "first tslist trk $first_tslist_trk sec $first_tslist_sec\n" if $debug;

        dump_sec($cat_buf) if $debug;
        my @bytes = unpack "C*", $cat_buf;

        # Create file descriptive entry in catalog.

        # Set first tslist track.
        $bytes[11 + (($empty_file_entry - 1) * 35)] = $first_tslist_trk;
        # Set first tslist sector.
        $bytes[12 + (($empty_file_entry - 1) * 35)] = $first_tslist_sec;

        # Handle file type.
        my $file_type = 0x00;  # Default T
        if ($mode eq "I") {
          $file_type = 0x01;
        } elsif ($mode eq "A") {
          $file_type = 0x02;
        } elsif ($mode eq "B") {
          $file_type = 0x04;
        }

        # Set file type
        $bytes[13 + (($empty_file_entry - 1) * 35)] = $file_type;

        # Handle Filename
        my $fname_start = 14 + (($empty_file_entry - 1) * 35);
        print sprintf("fname_start=%02x\n", $fname_start) if $debug;

        # Put in the filename
        for (my $i = 0; $i < length($filename); $i++) {
          # Set the high bit
          $bytes[$fname_start + $i] = ord(substr($filename, $i, 1)) | 0x80;
        }
        # Make sure new filename is space padded
        for (my $i = length($filename); $i < 30; $i++) {
          # 0xa0 is Apple II space (high bit set)
          $bytes[$fname_start + $i] = 0xa0;
        }

        print sprintf("sectors_used=%04x\n", $sectors_used);
        my $file_secs_lo = $sectors_used & 0x00ff;
        print sprintf("file_secs_lo=%02x\n", $file_secs_lo);
        my $file_secs_hi = ($sectors_used & 0xff00) >> 8;
        print sprintf("file_secs_hi=%02x\n", $file_secs_hi);

        print sprintf("num_used_secs=%d\n", scalar @used_secs);

        # Set file length in sectors.
        my $file_length_secs = ceil($file_length / $sec_size);
        $bytes[44 + (($empty_file_entry - 1) * 35)] = $file_secs_lo;
        $bytes[45 + (($empty_file_entry - 1) * 35)] = $file_secs_hi;

        # Re-pack the data in the catalog sector.
        $cat_buf = pack "a$sec_size", pack "C*", @bytes;

        dump_sec($cat_buf);
        # Write back catalog sector with new file descriptive entry.
        print "Writing catalog sector $cat_trk $cat_sec\n" if $debug;
        if (!wts($dskfile, $cat_trk, $cat_sec, $cat_buf)) {
          print "Failed to write catalog sector $cat_trk $cat_sec!\n";
        }

        print sprintf("num_used_secs=%d\n", scalar @used_secs);

        # Mark sectors used.
        my ($trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs) = get_vtoc_sec($dskfile);

        my $tmpl = '';
        for (my $t = $min_trk; $t <= $max_trk; $t++) {
          $tmpl .= $bit_map_free_sec_tmpl;
        }

        print "tmpl=$tmpl\n" if $debug;
        my @flds = unpack $tmpl, $bit_map_free_secs;

        print sprintf("num_used_secs=%d\n", scalar @used_secs);

        # Mark sectors used
        foreach my $sec (@used_secs) {
          #next unless defined $sec;
          next unless defined $sec->{'trk'};
          #next if $sec->{'trk'} == 0 && $sec->{'sec'} == 0;
          print "Marking trk $sec->{'trk'} sec $sec->{'sec'} used\n" if $debug;
          $flds[$sec->{'trk'}] &= ~(1 << $sec->{'sec'});
        }
        # Mark tslist sectors used.
        foreach my $sec (@tslist_secs) {
          print "Marking tslist sector used trk $sec->{'trk'} sec $sec->{'sec'}\n" if $debug;
          $flds[$sec->{'trk'}] &= ~(1 << $sec->{'sec'});
        }

        $bit_map_free_secs = pack $tmpl, @flds;

        # Write back vtoc
        if (!write_vtoc($dskfile, $trk_num_1st_cat_sec, $sec_num_1st_cat_sec, $rel_num_dos, $dsk_vol_num, $max_tslist_secs, $last_trk_secs_alloc, $dir_trk_alloc, $num_trks_dsk, $num_secs_dsk, $num_bytes_sec, $bit_map_free_secs)) {
          print "I/O ERROR!\n";
        }

        close $ifh;
      } else {
        print "Can't open $filename\n";
      }
    } else {
      print "DISK FULL\n";
    }
  } else {
    print "DISK FULL\n";
  }
}

1;

