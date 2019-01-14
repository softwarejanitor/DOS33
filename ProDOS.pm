#!/usr/bin/perl -w

package ProDOS;

use strict;

use PO;

use Exporter::Auto;

my $debug = 0;

# ProDOS file types
my %ftype = (
  #       00        Typeless file
  0x00 => '   ',
  #       01    BAD Bad block(s) file
  0x01 => 'BAD',
  #       04    TXT Text file (ASCII text, msb off)
  0x04 => 'TXT',
  #       06    BIN Binary file (8-bit binary image)
  0x06 => 'BIN',
  #       0f    DIR Directory file
  0x0f => 'DIR',
  #       19    ADB AppleWorks data base file
  0x19 => 'ADB',
  #       1a    AWP AppleWorks word processing file
  0x1a => 'AWP',
  #       1b    ASP AppleWorks spreadsheet file
  0x1b => 'ASP',
  #       ef    PAS ProDOS PASCAL file
  0xef => 'PAS',
  #       f0    CMD ProDOS added command file
  0xf0 => 'CMD',
  #       f1-f8     User defined file types 1 through 8
  0xf1 => 'UD1',
  0xf2 => 'UD2',
  0xf3 => 'UD3',
  0xf4 => 'UD4',
  0xf5 => 'UD5',
  0xf6 => 'UD6',
  0xf7 => 'UD7',
  0xf8 => 'UD8',
  #       fc    BAS Applesoft BASIC program file
  0xfc => 'BAS',
  #       fd    VAR Applesoft stored variables file
  0xfd => 'VAR',
  #       fe    REL Relocatable object module file (EDASM)
  0xfe => 'REL',
  #       ff    SYS ProDOS system file
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
my $key_vol_dir_blk_tmpl = 'vvCa15x8nnCCCCCvvva470';

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
my $file_desc_ent_tmpl = 'Ca15Cvva3nnCCCvnnv';

my $key_dir_file_desc_ent_tmpl = '';
for (my $i = 0; $i < 12; $i++) {
  $key_dir_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
}

my $dir_file_desc_ent_tmpl = '';
for (my $i = 0; $i < 12; $i++) {
  $dir_file_desc_ent_tmpl .= $file_desc_ent_tmpl;
}

sub date_convert {
  my ($ymd, $hm) = @_;

  return "<NO DATE>" unless (defined $ymd && defined $hm && $ymd != 0);

  my $year = ($ymd & 0xfe00) >> 9;  # bits 9-15
  #print "year=$year\n";
  my $mon = (($ymd & 0x01e0) >> 5 - 1);  # bits 5-8
  $mon++;
  #print "mon=$mon\n";
  my $day = $ymd & 0x001f;  # bits 0-4
  #print "day=$day\n";
  my $hour = ($hm & 0x1f00) >> 8;  # bits 8-12
  #print "hour=$hour\n";
  my $min = $hm & 0x003f;  # bits 0-5
  #print "min=$min\n";
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
  print sprintf("storage_type=%02x\n", $storage_type) if $debug;
  my $name_length = $storage_type_name_length & 0x0f;
  print sprintf("name_length=%02x\n", $name_length) if $debug;

  my $volname = substr($volume_name, 0, $name_length);

  if ($debug) {
    print sprintf("prv_vol_dir_blk=%04x\n", $prv_vol_dir_blk);
    print sprintf("nxt_vol_dir_blk=%04x\n", $nxt_vol_dir_blk);
    print sprintf("storage_type_name_length=%02x\n", $storage_type_name_length);
    print sprintf("name_length=%02x\n", $name_length);
    print sprintf("volume_name=%s\n", $volume_name);
    print sprintf("volume_name=%s\n", substr($volume_name, 0, $name_length));
    print sprintf("creation=%04x %04x\n", $creation_ymd, $creation_hm);
print"\n";
    print sprintf("create_date=%s\n", date_convert($creation_ymd, $creation_hm));
print"\n";
    print sprintf("version=%02x\n", $version);
    print sprintf("min_version=%02x\n", $min_version);
    print sprintf("access=%02x\n", $access);
    print sprintf("entry_length=%02x\n", $entry_length);
    print sprintf("entries_per_block=%02x\n", $entries_per_block);
    print sprintf("file_count=%04x\n", $file_count);
    print sprintf("bit_map_pointer=%04x\n", $bit_map_pointer);
    print sprintf("total_blocks=%02x\n", $total_blocks);
  }

  my @flds = unpack $key_dir_file_desc_ent_tmpl, $dir_ents;

  my @files = ();
  for (my $i = 0; $i < 12; $i++) {
    my $storage_type_name_length = shift @flds;
    print sprintf("storage_type_name_length=%02x\n", $storage_type_name_length) if $debug;
    my $storage_type = $storage_type_name_length & 0xf0;
    print sprintf("storage_type=%02x\n", $storage_type) if $debug;
    my $name_length = $storage_type_name_length & 0x0f;
    print sprintf("name_length=%02x\n", $name_length) if $debug;
    my $file_name = shift @flds;
    print sprintf("file_name=%s\n", $file_name) if $debug;
    my $fname = substr($file_name, 0, $name_length);
    print sprintf("fname=%s\n", $fname) if $debug;
    my $file_type = shift @flds;
    print sprintf("file_type=%02x\n", $file_type) if $debug;
    my $key_pointer = shift @flds;
    print sprintf("key_pointer=%04x\n", $key_pointer) if $debug;
    my $blocks_used = shift @flds;
    print sprintf("blocks_used=%04x\n", $blocks_used) if $debug;
    my $eof = shift @flds;
    #print sprintf("eof=%04x\n", $eof);
    my ($e1, $e2, $e3)  = unpack "C*", $eof;
    my $endfile = (($e3 << 16) + ($e2 << 8) + $e1);
    print sprintf("eof=%06x\n", $endfile) if $debug;
    my $creation_ymd = shift @flds;
    print sprintf("creation_ymd=%04x\n", $creation_ymd) if $debug;
    my $creation_hm = shift @flds;
    print sprintf("creation_hm=%04x\n", $creation_hm) if $debug;
    my $cdate = date_convert($creation_ymd, $creation_hm);
    print sprintf("create_date=%s\n", $cdate) if $debug;
    my $version = shift @flds;
    print sprintf("version=%02x\n", $version) if $debug;
    my $min_version = shift @flds;
    print sprintf("min_version=%02x\n", $min_version) if $debug;
    my $access = shift @flds;
    print sprintf("access=%02x\n", $access) if $debug;
    my $aux_type = shift @flds;
    print sprintf("aux_type=%02x\n", $aux_type) if $debug;
    my $atype = '';
    if ($file_type == 0x06) {
      $atype = sprintf("A=\$%04X", $aux_type);
    }
    my $last_mod_ymd = shift @flds;
    print sprintf("last_mod_ymd=%04x\n", $last_mod_ymd) if $debug;
    my $last_mod_hm = shift @flds;
    my $mdate = date_convert($last_mod_ymd, $last_mod_hm);
    print sprintf("last_mod_hm=%04x\n", $last_mod_hm) if $debug;
    my $header_pointer = shift @flds;
    print sprintf("header_pointer=%04x\n", $header_pointer) if $debug;
    if ($storage_type != 0) {
      #print "pushing $file_name\n";
      push @files, { 'filename' => $fname, 'ftype' => $ftype{$file_type}, 'used' => $blocks_used, 'mdate' => $mdate, 'cdate' => $cdate, 'atype' => $aux_type, 'atype' => $atype, 'access' => $access, 'eof' => $endfile };
    }
  }

  if ($debug) {
    foreach my $file (@files) {
      print "file=$file->{'filename'}\n";
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

  if ($debug) {
    print sprintf("prv_vol_dir_blk=%04x\n", $prv_vol_dir_blk);
    print sprintf("nxt_vol_dir_blk=%04x\n", $nxt_vol_dir_blk);
  }

  my @flds = unpack $dir_file_desc_ent_tmpl, $dir_ents;

  my @files = ();
  for (my $i = 0; $i < 12; $i++) {
    my $storage_type_name_length = shift @flds;
    print sprintf("storage_type_name_length=%02x\n", $storage_type_name_length) if $debug;
    my $file_name = shift @flds;
    print sprintf("file_name=%s\n", $file_name) if $debug;
    my $storage_type = $storage_type_name_length & 0xf0;
    my $name_length = $storage_type_name_length & 0x0f;
    my $fname = substr($file_name, 0, $name_length);
    print sprintf("fname=%s\n", $fname) if $debug;
    my $file_type = shift @flds;
    print sprintf("file_type=%02x\n", $file_type) if $debug;
    my $key_pointer = shift @flds;
    print sprintf("key_pointer=%04x\n", $key_pointer) if $debug;
    my $blocks_used = shift @flds;
    print sprintf("blocks_used=%04x\n", $blocks_used) if $debug;
    my $eof = shift @flds;
    #print sprintf("eof=%04x\n", $eof);
    my ($e1, $e2, $e3)  = unpack "C*", $eof;
    my $endfile = (($e3 << 16) + ($e2 << 8) + $e1);
    print sprintf("eof=%06x\n", $endfile) if $debug;
    my $creation_ymd = shift @flds;
    print sprintf("creation_ymd=%04x\n", $creation_ymd) if $debug;
    my $creation_hm = shift @flds;
    print sprintf("creation_hm=%04x\n", $creation_hm) if $debug;
    my $cdate = date_convert($creation_ymd, $creation_hm);
    print sprintf("create_date=%s\n", $cdate) if $debug;
    my $version = shift @flds;
    print sprintf("version=%02x\n", $version) if $debug;
    my $min_version = shift @flds;
    print sprintf("min_version=%02x\n", $min_version) if $debug;
    my $access = shift @flds;
    print sprintf("access=%02x\n", $access) if $debug;
    my $aux_type = shift @flds;
    print sprintf("aux_type=%02x\n", $aux_type) if $debug;
    my $atype = '';
    if ($file_type == 0x06) {
      $atype = sprintf("A=\$%04X", $aux_type);
    }
    my $last_mod_ymd = shift @flds;
    print sprintf("last_mod_ymd=%04x\n", $last_mod_ymd) if $debug;
    my $last_mod_hm = shift @flds;
    print sprintf("last_mod_hm=%04x\n", $last_mod_hm) if $debug;
    my $mdate = date_convert($last_mod_ymd, $last_mod_hm);
    my $header_pointer = shift @flds;
    print sprintf("header_pointer=%04x\n", $header_pointer) if $debug;
    if ($storage_type != 0) {
      #print "pushing $file_name\n";
      push @files, { 'filename' => $fname, 'ftype' => $ftype{$file_type}, 'used' => $blocks_used, 'mdate' => $mdate, 'cdate' => $cdate, 'atype' => $aux_type, 'atype' => $atype, 'access' => $access, 'eof' => $endfile };
    }
  }

  if ($debug) {
    foreach my $file (@files) {
      print "file=$file->{'filename'}\n";
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
    #print printf("access=%02x\n", $file->{'access'});
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
      #print printf("access=%02x\n", $file->{'access'});
      if ($file->{'access'} == 0x01) {
        $lck = '*';
      }
      print sprintf("%s%-15s %3s %7d %16s %16s  %7s %s\n", $lck, $file->{'filename'}, $file->{'ftype'}, $file->{'used'}, $file->{'mdate'}, $file->{'cdate'}, $file->{'eof'}, $file->{'atype'});
    }
    $vol_dir_blk = $nxt_vol_dir_blk;
  }
}

1;

