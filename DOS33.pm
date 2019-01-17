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
  0x00 => ' T',  # Unlocked text file
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

  print sprintf("%-2s %03d %s\n", $file_types{$file_type}, $file_length, $filename);
}

# Parse a file entry
sub parse_file_entry {
  my ($file_desc_entry) = @_;

  my ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = unpack $file_desc_ent_dmt_tmpl, $file_desc_entry;

  return if $first_tslist_trk eq '';
  return if $first_tslist_trk == 0xff;  # Deleted
  return if $first_tslist_trk == 0x00;  # Never used

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

  my ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length);
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($first_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 1 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($second_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 2 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($third_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 3 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($fourth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 4 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($fifth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 5 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($sixth_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 6 };
  }
  ($first_tslist_trk, $first_tslist_sec, $file_type, $filename, $file_length) = parse_file_entry($seventh_file_desc_ent);
  if (defined $first_tslist_trk && $first_tslist_trk ne '') {
    push @files, { 'file_type' => $file_type, 'filename' => $filename, 'file_length' => $file_length, 'trk' => $first_tslist_trk, 'sec' => $first_tslist_sec, 'cat_offset' => 7 };
  }

  return $trk_num_nxt_cat_sec, $sec_num_nxt_cat_sec, @files;
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
    do {
      ($cat_buf, $next_cat_trk, $next_cat_sec, @files) = get_cat_sec($dskfile, $next_cat_trk, $next_cat_sec);
      if (defined $next_cat_trk && $next_cat_trk ne '') {
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
  }
  #print "bit_map_free_secs=";
  #my @bytes = unpack "C*", $bit_map_free_secs;
  #foreach my $byte (@bytes) {
  #  print sprintf("%02x ", $byte);
  #}
  #print "\n";
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

#
# Parse a sector of a track/sector list
#
sub parse_tslist_sec {
  my ($buf) = @_;

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

  my ($next_tslist_trk, $next_tslist_sec, $soffset, $tslist) = unpack $tslist_fmt_tmpl, $buf;

  if ($debug) {
    print "tslist=";
    my @bytes = unpack "C*", $tslist;
    foreach my $byte (@bytes) {
      print sprintf("%02x ", $byte);
    }
    print "\n";
  }

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
    #print "trk=$trk sec=$sec\n";
    unshift @secs, { 'trk' => $trk, 'sec' => $sec };
  }

  return $next_tslist_trk, $next_tslist_sec, @secs;
}

#
# Get a sector of a track/sector list
#
sub get_tslist_sec {
  my ($dskfile, $tslist_trk, $tslist_sec) = @_;

  my $buf;

  if (rts($dskfile, $tslist_trk, $tslist_sec, \$buf)) {
    dump_sec($buf) if $debug;
    return parse_tslist_sec($buf);
  }

  return 0;
}

#
# Get a track/sector list
#
sub get_tslist {
  my ($dskfile, $tslist_trk, $tslist_sec) = @_;

  my ($next_tslist_trk, $next_tslist_sec) = ($tslist_trk, $tslist_sec);

  my @secs = ();

  do {
    ($next_tslist_trk, $next_tslist_sec, @secs) = get_tslist_sec($dskfile, $next_tslist_trk, $next_tslist_sec);
    if (defined $next_tslist_trk && $next_tslist_trk ne '') {
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
      ($cat_buf, $next_cat_trk, $next_cat_sec, @files) = get_cat_sec($dskfile, $next_cat_trk, $next_cat_sec);
      if (defined $next_cat_trk && $next_cat_trk ne '') {
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
  if ($file->{'trk'}) {
    my $buf;

    my @secs = get_tslist($dskfile, $file->{'trk'}, $file->{'sec'});
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
  if ($file->{'trk'}) {
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

    # Re-pack the data in the sector.
    $cat_buf = pack "C*", @bytes;

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
  if ($file->{'trk'}) {
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
    $cat_buf = pack "C*", @bytes;

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
  if ($file->{'trk'}) {
    ##FIXME

    # Mark file as deleted.

    # Write back catalog sector.

    # get the files t/s list and free those sectors
  }
}

#
# Rename a file
#
sub rename_file {
  my ($dskfile, $filename, $new_filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if ($file->{'trk'}) {
    ##FIXME

    # Change filename

    # Write back catalog sector.
  }
}

#
# Copy a file
#
sub copy_file {
  my ($dskfile, $filename, $new_filename, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  my ($file, $cat_trk, $cat_sec, $cat_buf) = find_file($dskfile, $filename);
  if ($file->{'trk'}) {
    ##FIXME

  }
}

#
# Write a file to disk image.
#
sub write_file {
  my ($dskfile, $filename, $new_filename, $mode, $conv, $dbg) = @_;

  $debug = 1 if (defined $dbg && $dbg);

  ##FIXME
}


1;

