#!/usr/bin/perl -w

package ProDOS;

use strict;

use PO;

use Exporter::Auto;

my $debug = 0;

# ProDOS file types
my %ftype = (
  # 00        Typeless file
  0x00 => '   ',
  # 01    BAD Bad block(s) file
  0x01 => 'BAD',
  # 04    TXT Text file (ASCII text, msb off)
  0x04 => 'TXT',
  # 06    BIN Binary file (8-bit binary image)
  0x06 => 'BIN',
  # 0f    DIR Directory file
  0x0f => 'DIR',
  # 19    ADB AppleWorks data base file
  0x19 => 'ADB',
  # 1a    AWP AppleWorks word processing file
  0x1a => 'AWP',
  # 1b    ASP AppleWorks spreadsheet file
  0x1b => 'ASP',
  # ef    PAS ProDOS PASCAL file
  0xef => 'PAS',
  # f0    CMD ProDOS added command file
  0xf0 => 'CMD',
  # f1-f8     User defined file types 1 through 8
  0xf1 => 'UD1',
  0xf2 => 'UD2',
  0xf3 => 'UD3',
  0xf4 => 'UD4',
  0xf5 => 'UD5',
  0xf6 => 'UD6',
  0xf7 => 'UD7',
  0xf8 => 'UD8',
  0xfa => 'INT',
  0xfb => 'IVR',
  # fc    BAS Applesoft BASIC program file
  0xfc => 'BAS',
  # fd    VAR Applesoft stored variables file
  0xfd => 'VAR',
  # fe    REL Relocatable object module file (EDASM)
  0xfe => 'REL',
  # ff    SYS ProDOS system file
  0xff => 'SYS',
);

my %months = (
   1, 'JAN',
   2, 'FEB',
   3, 'MAR',
   4, 'APR',
   5, 'MAY',
   6, 'JUN',
   7, 'JUL',
   8, 'AUG',
   9, 'SEP',
  10, 'OCT',
  11, 'NOV',
  12, 'DEC',
);

my $key_vol_dir_blk = 2;

#
# Key Volume Directory Block
#
# 00-01 Previous Volume Directory Block
# 02-03 Next Volume Directory Block
#
# Volumne Directory Header
#
# 04    STORAGE_TYPE/NAME_LENGTH
#       fx where x is length of VOLUME_NAME
# 05-13 VOLUME_NAME
# 14-1b Not used
# 1c-1f CREATION
#       0-1 yyyyyyymmmmddddd  year/month/day
#       2-3 000hhhhh00mmmmmm  hours/minues
# 20    VERSION
# 21    MIN_VERSION
# 22    ACCESS
# 23    ENTRY_LENGTH
# 24    ENTRIES_PER_BLOCK
# 25-26 FILE_COUNT
# 27-28 BIT_MAP_POINTER
# 29-2a TOTAL_BLOCKS
#
my $key_vol_dir_blk_tmpl = 'vvCa15x8vvCCCCCvvva470';

my $vol_dir_blk_tmpl = 'vva504';

#
# Volume Bit Map
#
my $vol_bit_map_tmpl = 'C*';

#
# File Descriptive Entries
#
# 00    STORAGE_TYPE/NAME_LENGTH
#       0x Deleted entry. Available for reuse.
#       1x File is a seedling file (only one block)
#       2x File is a sapling file (2-256 blocks)
#       3x File is a tree file (257-32768 blocks)
#       dx File is a subdirectory
#       ex Reserved for Subdirectory Header entry
#       fx Reserved for Volume Directory Header entry
#          x is the length of FILE_NAME
# 01-0f FILE_NAME
# 10    FILE_TYPE
#       00        Typeless file
#       01    BAD Bad block(s) file
#       04    TXT Text file (ASCII text, msb off)
#       06    BIN Binary file (8-bit binary image)
#       0f    DIR Directory file
#       19    ADB AppleWorks data base file
#       1a    AWP AppleWorks word processing file
#       1b    ASP AppleWorks spreadsheet file
#       ef    PAS ProDOS PASCAL file
#       f0    CMD ProDOS added command file
#       f1-f8     User defined file types 1 through 8
#       fc    BAS Applesoft BASIC program file
#       fd    VAR Applesoft stored variables file
#       fe    REL Relocatable object module file (EDASM)
#       ff    SYS ProDOS system file
# 11-12 KEY_POINTER
# 13-14 BLOCKS_USED
# 15-17 EOF
# 18-1b CREATION
#       0-1 yyyyyyymmmmddddd  year/month/day
#       2-3 000hhhhh00mmmmmm  hours/minues
# 1c    VERSION
# 1d    MIN_VERSION
# 1e    ACCESS
#       80 File may be destroyed
#       40 File may be renamed
#       20 File has changed since last backup
#       02 File may be written to
#       01 File may be read
# 1f-20 AUX_TYPE
#       TXT Random access record length (L from OPEN)
#       BIN Load address for binary image (A from BSAVE)
#       BAS Load address for program image (when SAVEd)
#       VAR Address of compressed variables inmage (when STOREd)
#       SYS Load address for system program (usually $2000)
# 21-24 LAST_MOD
# 25-26 HEADER_POINTER
#
my $file_desc_ent_tmpl = 'Ca15Cvva3vvCCCvvvv';

my $key_dir_file_desc_ent_tmpl = '';
my $subdir_hdr_file_desc_ent_tmpl = '';
for (my $i = 0; $i < 12; $i++) {
  $key_dir_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
  $subdir_hdr_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
}

my $dir_file_desc_ent_tmpl = '';
my $subdir_file_desc_ent_tmpl = '';
for (my $i = 0; $i < 12; $i++) {
  $dir_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
  $subdir_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
}

#
# Subdirectory Header
#
# 00-01 Previous Subdirectory Block
# 02-03 Next Subdirectory Block
#
# 04    STORAGE_TYPE/NAME_LENGTH
#       ex where x is length of SUBDIR NAME
#
# 05-13 SUBDIR_NAME
# 14    Must contain $75
# 15-1b Reserved for future use
# 1c-1f CREATION
#       0-1 yyyyyyymmmmddddd  year/month/day
#       2-3 000hhhhh00mmmmmm  hours/minues
# 20    VERSION
# 21    MIN_VERSION
# 22    ACCESS
# 23    ENTRY_LENGTH
# 24    ENTRIES_PER_BLOCK
# 25-26 FILE_COUNT
# 27-28 PARENT_POINTER
# 29    PARENT_ENTRY
# 2a    PARENT_ENTRY_LENGTH
#
my $subdir_hdr_blk_tmpl = 'vvCa15Cx7vvCCCCCvvCCa469';


#
# Convert a ProDOS date to DD-MMM-YY string.
#
sub date_convert {
  my ($ymd, $hm) = @_;

  return "<NO DATE>" unless (defined $ymd && defined $hm && $ymd != 0);

  my $year = ($ymd & 0xfe00) >> 9;  # bits 9-15
  my $mon = ($ymd & 0x01e0) >> 5;  # bits 5-8
  my $day = $ymd & 0x001f;  # bits 0-4
  my $hour = ($hm & 0x1f00) >> 8;  # bits 8-12
  my $min = $hm & 0x003f;  # bits 0-5
  $mon = 0 if $mon > 12;

  return "<NO DATE>" if $mon < 1;

  return sprintf("%2d-%s-%02d %2d:%02d", $day, $months{$mon}, $year, $hour, $min);
}

# Parse Key Volume Directory Block
sub parse_key_vol_dir_blk {
  my ($buf, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks, $dir_ents) = unpack $key_vol_dir_blk_tmpl, $buf;

  my $storage_type = $storage_type_name_length & 0xf0;
  my $name_length = $storage_type_name_length & 0x0f;

  my $volname = substr($volume_name, 0, $name_length);

  my @flds = unpack $key_dir_file_desc_ent_tmpl, $dir_ents;

  my @files = ();
  for (my $i = 0; $i < 12; $i++) {
    my $storage_type_name_length = shift @flds;
    my $storage_type = $storage_type_name_length & 0xf0;
    my $name_length = $storage_type_name_length & 0x0f;
    my $file_name = shift @flds;
    my $fname = substr($file_name, 0, $name_length);
    my $file_type = shift @flds;
    my $key_pointer = shift @flds;
    my $blocks_used = shift @flds;
    my $eof = shift @flds;
    my ($e1, $e2, $e3)  = unpack "C*", $eof;
    my $endfile = (($e3 << 16) + ($e2 << 8) + $e1);
    my $creation_ymd = shift @flds;
    my $creation_hm = shift @flds;
    my $cdate = date_convert($creation_ymd, $creation_hm);
    my $version = shift @flds;
    my $min_version = shift @flds;
    my $access = shift @flds;
    my $aux_type = shift @flds;
    my $atype = '';
    if ($file_type == 0x06) {
      $atype = sprintf("A=\$%04X", $aux_type);
    }
    my $last_mod_ymd = shift @flds;
    my $last_mod_hm = shift @flds;
    my $mdate = date_convert($last_mod_ymd, $last_mod_hm);
    my $header_pointer = shift @flds;
    if ($storage_type != 0) {
      my $f_type = $ftype{$file_type};
      $f_type = sprintf("\$%02x", $file_type) unless defined $f_type;
      push @files, { 'filename' => $fname, 'ftype' => $f_type, 'used' => $blocks_used, 'mdate' => $mdate, 'cdate' => $cdate, 'atype' => $aux_type, 'atype' => $atype, 'access' => $access, 'eof' => $endfile };
    }
  }

  return $prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volname, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks, @files;
}

#
# Get Key Volume Directory Block
#
sub get_key_vol_dir_blk {
  my ($pofile, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my $buf;

  if (read_blk($pofile, $key_vol_dir_blk, \$buf)) {
    dump_blk($buf) if $debug;
    return parse_key_vol_dir_blk($buf, $debug);
  }

  return 0;
}

# Parse Volume Directory Block
sub parse_vol_dir_blk {
  my ($buf, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $dir_ents) = unpack $vol_dir_blk_tmpl, $buf;

  my @flds = unpack $dir_file_desc_ent_tmpl, $dir_ents;

  my @files = ();
  for (my $i = 0; $i < 12; $i++) {
    my $storage_type_name_length = shift @flds;
    my $file_name = shift @flds;
    my $storage_type = $storage_type_name_length & 0xf0;
    my $name_length = $storage_type_name_length & 0x0f;
    my $fname = substr($file_name, 0, $name_length);
    my $file_type = shift @flds;
    my $key_pointer = shift @flds;
    my $blocks_used = shift @flds;
    my $eof = shift @flds;
    my ($e1, $e2, $e3)  = unpack "C*", $eof;
    my $endfile = (($e3 << 16) + ($e2 << 8) + $e1);
    my $creation_ymd = shift @flds;
    my $creation_hm = shift @flds;
    my $cdate = date_convert($creation_ymd, $creation_hm);
    my $version = shift @flds;
    my $min_version = shift @flds;
    my $access = shift @flds;
    my $aux_type = shift @flds;
    my $atype = '';
    if ($file_type == 0x06) {
      $atype = sprintf("A=\$%04X", $aux_type);
    }
    my $last_mod_ymd = shift @flds;
    my $last_mod_hm = shift @flds;
    my $mdate = date_convert($last_mod_ymd, $last_mod_hm);
    my $header_pointer = shift @flds;
    if ($storage_type != 0) {
      my $f_type = $ftype{$file_type};
      $f_type = sprintf("\$%02x", $file_type) unless defined $f_type;
      push @files, { 'filename' => $fname, 'ftype' => $f_type, 'used' => $blocks_used, 'mdate' => $mdate, 'cdate' => $cdate, 'atype' => $aux_type, 'atype' => $atype, 'access' => $access, 'eof' => $endfile };
    }
  }

  return $prv_vol_dir_blk, $nxt_vol_dir_blk, @files;
}

#
# Get Volume Directory Block
#
sub get_vol_dir_blk {
  my ($pofile, $vol_dir_blk, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my $buf;

  if (read_blk($pofile, $vol_dir_blk, \$buf)) {
    dump_blk($buf) if $debug;
    return parse_vol_dir_blk($buf, $debug);
  }

  return 0;
}

# Parse Key Volume Directory Block
sub parse_subdir_hdr_blk {
  my ($buf, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $subdir_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $parent_pointer, $parent_entry, $parent_entry_length, $dir_ents) = unpack $subdir_hdr_blk_tmpl, $buf;

  my $storage_type = $storage_type_name_length & 0xf0;
  my $name_length = $storage_type_name_length & 0x0f;

  my $subdir_nm = substr($subdir_name, 0, $name_length);

  my @flds = unpack $subdir_hdr_file_desc_ent_tmpl, $dir_ents;

  my @files = ();
  for (my $i = 0; $i < 12; $i++) {
    my $storage_type_name_length = shift @flds;
    my $storage_type = $storage_type_name_length & 0xf0;
    my $name_length = $storage_type_name_length & 0x0f;
    my $file_name = shift @flds;
    my $fname = substr($file_name, 0, $name_length);
    my $file_type = shift @flds;
    my $key_pointer = shift @flds;
    my $blocks_used = shift @flds;
    my $eof = shift @flds;
    my ($e1, $e2, $e3)  = unpack "C*", $eof;
    my $endfile = (($e3 << 16) + ($e2 << 8) + $e1);
    my $creation_ymd = shift @flds;
    my $creation_hm = shift @flds;
    my $cdate = date_convert($creation_ymd, $creation_hm);
    my $version = shift @flds;
    my $min_version = shift @flds;
    my $access = shift @flds;
    my $aux_type = shift @flds;
    my $atype = '';
    if ($file_type == 0x06) {
      $atype = sprintf("A=\$%04X", $aux_type);
    }
    my $last_mod_ymd = shift @flds;
    my $last_mod_hm = shift @flds;
    my $mdate = date_convert($last_mod_ymd, $last_mod_hm);
    my $header_pointer = shift @flds;
    if ($storage_type != 0) {
      my $f_type = $ftype{$file_type};
      $f_type = sprintf("\$%02x", $file_type) unless defined $f_type;
      push @files, { 'filename' => $fname, 'ftype' => $f_type, 'used' => $blocks_used, 'mdate' => $mdate, 'cdate' => $cdate, 'atype' => $aux_type, 'atype' => $atype, 'access' => $access, 'eof' => $endfile };
    }
  }

  return $prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $subdir_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $parent_pointer, $parent_entry, $parent_entry_length, @files;
}

sub get_subdir_hdr {
  my ($pofile, $subdir_blk, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my $buf;

  if (read_blk($pofile, $subdir_blk, \$buf)) {
    dump_blk($buf) if $debug;
    dump_blk($buf);
    return parse_subdir_hdr_blk($buf, $debug);
  }

  return 0;
}

#
# Get disk catalog.
#
sub cat {
  my ($pofile, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_ymd, $creation_hm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks, @files) = get_key_vol_dir_blk($pofile, $debug);

  print "/$volume_name\n\n";

  print " NAME           TYPE  BLOCKS  MODIFIED         CREATED          ENDFILE SUBTYPE\n\n";

  foreach my $file (@files) {
    my $lck = ' ';
    if ($file->{'access'} == 0x01) {
      $lck = '*';
    }
    print sprintf("%s%-15s %3s %7d %16s %16s  %7s %s\n", $lck, $file->{'filename'}, $file->{'ftype'}, $file->{'used'}, $file->{'mdate'}, $file->{'cdate'}, $file->{'eof'}, $file->{'atype'});
  }

  my $vol_dir_blk = $nxt_vol_dir_blk;

  while ($vol_dir_blk) {
    my ($prv_vol_dir_blk, $nxt_vol_dir_blk, @files) = get_vol_dir_blk($pofile, $vol_dir_blk, $debug);
    foreach my $file (@files) {
      my $lck = ' ';
      if ($file->{'access'} == 0x01) {
        $lck = '*';
      }
      print sprintf("%s%-15s %3s %7d %16s %16s  %7s %s\n", $lck, $file->{'filename'}, $file->{'ftype'}, $file->{'used'}, $file->{'mdate'}, $file->{'cdate'}, $file->{'eof'}, $file->{'atype'});
    }
    $vol_dir_blk = $nxt_vol_dir_blk;
  }
}

1;

