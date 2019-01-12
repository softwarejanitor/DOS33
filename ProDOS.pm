#!/usr/bin/perl -w

package ProDOS;

use strict;

use PO;

use Exporter::Auto;

my $debug = 0;

my $key_vol_dir_blk = 2;

#
# Volume Directory Block
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
my $vol_dir_blk_tmpl = 'vvCa15x8nnCCCCCvvv';

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
my $file_desc_ent_tmpl = 'Ca15CnnnnnCCCa8nnCC';

# Parse a Volume Directory Block
sub parse_vol_dir_blk {
  my ($buf, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my ($prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_yymmdd, $creation_hhmm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks) = unpack $vol_dir_blk_tmpl, $buf;

  my $name_length = $storage_type_name_length & 0x0f;
  if ($debug) {
    print sprintf("prv_vol_dir_blk=%04x\n", $prv_vol_dir_blk);
    print sprintf("nxt_vol_dir_blk=%04x\n", $nxt_vol_dir_blk);
    print sprintf("storage_type_name_length=%02x\n", $storage_type_name_length);
    print sprintf("name_length=%02x\n", $name_length);
    print sprintf("volume_name=%s\n", $volume_name);
    print sprintf("volume_name=%s\n", substr($volume_name, 0, $name_length));
    print sprintf("creation=%04x%04x\n", $creation_yymmdd, $creation_hhmm);
    print sprintf("version=%02x\n", $version);
    print sprintf("min_version=%02x\n", $min_version);
    print sprintf("access=%02x\n", $access);
    print sprintf("entry_length=%02x\n", $entry_length);
    print sprintf("entries_per_block=%02x\n", $entries_per_block);
    print sprintf("file_count=%04x\n", $file_count);
    print sprintf("bit_map_pointer=%04x\n", $bit_map_pointer);
    print sprintf("total_blocks=%02x\n", $total_blocks);
  }

  return $prv_vol_dir_blk, $nxt_vol_dir_blk, $storage_type_name_length, $volume_name, $creation_yymmdd, $creation_hhmm, $version, $min_version, $access, $entry_length, $entries_per_block, $file_count, $bit_map_pointer, $total_blocks;
}

#
# Get Volume Directory Block
#
sub get_vol_dir_blk {
  my ($pofile, $dbg) = @_;

  $debug = 1 if defined $dbg && $dbg;

  my $buf;

  if (read_blk($pofile, $key_vol_dir_blk, \$buf)) {
    dump_blk($buf) if $debug;
    return parse_vol_dir_blk($buf, $debug);
  }

  return 0;
}

1;

