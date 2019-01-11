#!/usr/bin/perl -w

package PRODOS;

use strict;

use DSK;

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
my $vol_dir_blk_tmpl = 'CCCCa252';
my $vol_dir_hdr_tmpl = '';

#
# Volume Bit Map
#
my $vol_bit_map_tmpl = '';

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
my $file_desc_ent_tmpl = '';

sub read_blk {
  my ($dskfile) = @_;
}

1;

