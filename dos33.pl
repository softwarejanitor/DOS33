#!/usr/bin/perl -w

#
# dos33 version 0.1
# by Vince Weaver <vince@deater.net>
# Perl port 20190225 by Leeland Heins <softwarejanitor@yahoo.com>
#

use strict;

use File::Basename;

# For now hard-coded
# Could be made dynamic if we want to be useful
# On dos3.2 disks, or larger filesystems
my $TRACKS_PER_DISK = 0x23;  # 35
my $SECTORS_PER_TRACK = 0x10;  # 16
my $BYTES_PER_SECTOR = 0x100;  # 256

my $VTOC_TRACK = 0x11;  # 17
my $VTOC_SECTOR = 0x00;  # 0

# VTOC Values
my $VTOC_CATALOG_T = 0x01;  # 1
my $VTOC_CATALOG_S = 0x02;  # 2
my $VTOC_DOS_RELEASE = 0x03;  # 3
my $VTOC_DISK_VOLUME = 0x06;  # 6
my $VTOC_MAX_TS_PAIRS = 0x27;  # 39
my $VTOC_LAST_ALLOC_T = 0x30;  # 48
my $VTOC_ALLOC_DIRECT = 0x31;  # 49
my $VTOC_NUM_TRACKS = 0x34;  # 52
my $VTOC_S_PER_TRACK = 0x35;  # 53
my $VTOC_BYTES_PER_SL = 0x36;  # 54
my $VTOC_BYTES_PER_SH = 0x37;  # 55
my $VTOC_FREE_BITMAPS = 0x38;  # 56

# CATALOG_VALUES
my $CATALOG_NEXT_T = 0x01;  # 1
my $CATALOG_NEXT_S = 0x02;  # 2
my $CATALOG_FILE_LIST = 0x0b;  # 11

my $CATALOG_ENTRY_SIZE = 0x23;  # 35

# CATALOG ENTRY
my $FILE_TS_LIST_T = 0x00;  # 0
my $FILE_TS_LIST_S = 0x01;  # 1
my $FILE_TYPE = 0x02;  # 2
my $FILE_NAME = 0x03;  # 3
my $FILE_SIZE_L = 0x21;  # 33
my $FILE_SIZE_H = 0x22;  # 34

my $FILE_NAME_SIZE = 0x1e;  # 30

# TSL
my $TSL_NEXT_TRACK = 0x01;  # 1
my $TSL_NEXT_SECTOR = 0x02;  # 2
my $TSL_OFFSET_L = 0x05;  # 5
my $TSL_OFFSET_H = 0x06;  # 6
my $TSL_LIST = 0x0c;  # 12

my $TSL_ENTRY_SIZE = 0x02; # 2
my $TSL_MAX_NUMBER = 122;  # 0x7a

my $SEEK_SET = 0;

my $VERSION = "0.1";

# Helper Subs
sub TS_TO_INT {
  my ($x, $y) = @_;

  return (($x << 8) + $y);
}

sub DISK_OFFSET {
  my ($track, $sector) = @_;

  my $off = ((($track * $SECTORS_PER_TRACK) + $sector) * $BYTES_PER_SECTOR);

  return $off;
}

my $sector_buffer;

my %ones_lookup = (
  0x00 => 0,  # 0x0 = 0000  0
  0x01 => 1,  # 0x1 = 0001  1
  0x02 => 1,  # 0x2 = 0010  1
  0x03 => 2,  # 0x3 = 0011  2
  0x04 => 1,  # 0x4 = 0100  1
  0x05 => 2,  # 0x5 = 0101  2
  0x06 => 2,  # 0x6 = 0110  2
  0x07 => 3,  # 0x7 = 0111  3
  0x08 => 1,  # 0x8 = 1000  1
  0x09 => 2,  # 0x9 = 1001  2
  0x0a => 2,  # 0xA = 1010  2
  0x0b => 3,  # 0xB = 1011  3
  0x0c => 2,  # 0xC = 1100  2
  0x0d => 3,  # 0xd = 1101  3
  0x0e => 3,  # 0xe = 1110  3
  0x0f => 4,  # 0xf = 1111  4
);

sub get_high_byte {
  my ($value) = @_;
  return ($value >> 8) & 0xff;
}

sub get_low_byte {
  my ($value) = @_;
  return ($value & 0xff);
}

my $debug = 0;

my $FILE_NORMAL = 0;
my $FILE_DELETED = 1;

sub dos33_file_type {
  my ($value) = @_;

  my $result = '?';

  my $v2 = $value & 0x7f;

  if ($v2 == 0x00) {
    $result = 'T';
  } elsif ($v2 == 0x01) {
    $result = 'I';
  } elsif ($v2 == 0x02) {
    $result = 'A';
  } elsif ($v2 == 0x04) {
    $result = 'B';
  } elsif ($v2 == 0x08) {
    $result = 'S';
  } elsif ($v2 == 0x10) {
    $result = 'R';
  } elsif ($v2 == 0x20) {
    $result = 'N';
  } elsif ($v2 == 0x40) {
    $result = 'L';
  } else {
    $result = '?';
  }

  return $result;
}


sub dos33_char_to_type {
  my ($type, $lock) = @_;

  my $result = 0x00;
  my $temp_type;

  # Covert to upper case
  $temp_type = uc($type);

  if ($temp_type eq 'T') {
    $result = 0x00;
  } elsif ($temp_type eq 'I') {
    $result = 0x01;
  } elsif ($temp_type eq 'A') {
    $result = 0x02;
  } elsif ($temp_type eq 'B') {
    $result = 0x04;
  } elsif ($temp_type eq 'S') {
    $result = 0x08;
  } elsif ($temp_type eq 'R') {
    $result = 0x10;
  } elsif ($temp_type eq 'N') {
    $result = 0x20;
  } elsif ($temp_type eq 'L') {
    $result = 0x40;
  } else {
    $result = 0x00;
  }

  if ($lock) {
    $result |= 0x80;
  }

  return $result;
}

# dos33 filenames have high bit set on ascii chars
# and are padded with spaces
sub dos33_filename_to_ascii {
  my ($dest, $src, $len) = @_;

  my @srcbytes = unpack "C*", $src;
  my @destbytes = ();

  my $l = 0;
  foreach my $byte (@srcbytes) {
    push @destbytes, $byte & 0x7f;
    $l++;
    last if $l > $len;
  }

  $dest = pack "C*", @destbytes;

  $_[0] = $dest;

  return $dest;
}

# Read VTOC into a buffer
sub dos33_read_vtoc {
  my ($fd) = @_;

  # Seek to VTOC
  seek($fd, DISK_OFFSET($VTOC_TRACK, $VTOC_SECTOR), $SEEK_SET);

  # read in VTOC
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  if (! defined $result || $result < 0) {
    print STDERR "Error on I/O\n";
  }

  return 0;
}

# Calculate available freespace
sub dos33_free_space {
  my ($fd) = @_;

  my @bitmap = ();
  my $sectors_free = 0;

  # Read Vtoc
  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @bytes = unpack "C*", $sector_buffer;

  for (my $i = 0; $i < $TRACKS_PER_DISK; $i++) {
    $bitmap[0] = $bytes[$VTOC_FREE_BITMAPS + ($i * 4)];
    $bitmap[1] = $bytes[$VTOC_FREE_BITMAPS + ($i * 4) + 1];

    $sectors_free += $ones_lookup{$bitmap[0] & 0x0f};
    $sectors_free += $ones_lookup{($bitmap[0] >> 4) & 0x0f};
    $sectors_free += $ones_lookup{$bitmap[1] & 0x0f};
    $sectors_free += $ones_lookup{($bitmap[1] >> 4) & 0x0f};
  }

  return $sectors_free * $BYTES_PER_SECTOR;
}

# Get a T/S value from a Catalog Sector
sub dos33_get_catalog_ts {
  my ($fd) = @_;

  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @bytes = unpack "C*", $sector_buffer;

  return TS_TO_INT($bytes[$VTOC_CATALOG_T], $bytes[$VTOC_CATALOG_S]);
}

# returns the next valid catalog entry
# after the one passed in
sub dos33_find_next_file {
  my ($fd, $catalog_tsf) = @_;

  my $catalog_file = $catalog_tsf >> 16;
  my $catalog_track = ($catalog_tsf >> 8) & 0xff;
  my $catalog_sector = ($catalog_tsf & 0xff);

catalog_loop:

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  my @bytes = unpack "C*", $sector_buffer;

  my $i = $catalog_file;
  while ($i < 7) {
    my $file_track = $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)];
    # 0xff means file deleted
    # 0x0 means empty
    if (($file_track != 0xff) && ($file_track != 0x00)) {
      return (($i << 16) + ($catalog_track << 8) + $catalog_sector);
    }
    $i++;
  }
  $catalog_track = $bytes[$CATALOG_NEXT_T];
  $catalog_sector = $bytes[$CATALOG_NEXT_S];
  if ($catalog_sector != 0) {
    $catalog_file = 0;
    goto catalog_loop;
  }

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  return -1;
}

sub dos33_print_file_info {
  my ($fd, $catalog_tsf) = @_;

  my $temp_string;

  my $catalog_file = $catalog_tsf >> 16;
  my $catalog_track = ($catalog_tsf >> 8) & 0xff;
  my $catalog_sector = ($catalog_tsf & 0xff);

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  my @bytes = unpack "C*", $sector_buffer;

  # Print a * if the file locked
  if ($bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE] > 0x7f) {
    print "*";
  } else {
    print " ";
  }

  # Print the file type
  printf("%s", dos33_file_type($bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE]));
  print " ";

  # Print the file size, stored in LO/HI
  printf("%.3i ", $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE + $FILE_SIZE_L)] +
    ($bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE + $FILE_SIZE_H)] << 8));

  # Print filename.
  my $filenamestr = substr($sector_buffer, ($CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE + $FILE_NAME)), 30);
  dos33_filename_to_ascii($temp_string, $filenamestr, 30);

  print "$temp_string\n";

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  return 0;
}

# Checks if "filename" exists
# returns entry/track/sector
sub dos33_check_file_exists {
  my ($fd, $filename, $file_deleted) = @_;

  $filename =~ s/\s+$//g;

  # read the VTOC into buffer
  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @vtoc_bytes = unpack "C*", $sector_buffer;

  # get the catalog track and sector from the VTOC
  my $catalog_track = $vtoc_bytes[$VTOC_CATALOG_T];
  my $catalog_sector = $vtoc_bytes[$VTOC_CATALOG_S];

repeat_catalog:

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  my @bytes = unpack "C*", $sector_buffer;

  # scan all file entries in catalog sector
  for (my $i = 0; $i < 7; $i++) {
    my $file_track = $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)];
    # 0xff means file deleted
    # 0x0 means empty
    if ($file_track != 0x00) {
      if ($file_track == 0xff) {
        my $filenamestr = substr($sector_buffer, ($CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE + $FILE_NAME)), 29);
        my $file_name = '';
        dos33_filename_to_ascii($file_name, $filenamestr, 29);
        $file_name =~ s/\s+$//g;

        if ($file_deleted) {
          # return if we found the file
          if ($filename eq $file_name) {
            return (($i << 16) + ($catalog_track << 8) + $catalog_sector);
          }
        }
      } else {
        my $filenamestr = substr($sector_buffer, ($CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE +$FILE_NAME)), 30);
        my $file_name = '';
        dos33_filename_to_ascii($file_name, $filenamestr, 30);
        $file_name =~ s/\s+$//g;
        # return if we found the file
        if ($filename eq $file_name) {
          return (($i << 16) + ($catalog_track << 8) + $catalog_sector);
        }
      }
    }
  }

  # point to next catalog track/sector
  $catalog_track = $bytes[$CATALOG_NEXT_T];
  $catalog_sector = $bytes[$CATALOG_NEXT_S];

  if ($catalog_sector != 0) {
    goto repeat_catalog;
  }

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  return -1;
}

# could be replaced by "find leading 1" instruction
# if available
sub find_first_one {
  my ($byte) = @_;

  my $i = 0;

  if ($byte == 0) {
    return -1;
  }

  while (($byte & (0x01 << $i)) == 0) {
    $i++;
  }

  return $i;
}

sub dos33_free_sector {
  my ($fd, $track, $sector) = @_;

  my $vtoc;

  # Seek to VTOC
  seek($fd, DISK_OFFSET($VTOC_TRACK, $VTOC_SECTOR), $SEEK_SET);
  # read in VTOC
  my $result = read($fd, $vtoc, $BYTES_PER_SECTOR);

  # Unpack VTOC data.
  my @bytes = unpack "C*", $vtoc;

  # each bitmap is 32 bits.  With 16-sector tracks only first 16 used
  # 1 indicates free, 0 indicates used
  if ($sector < 8) {
    $bytes[$VTOC_FREE_BITMAPS + ($track * 4) + 1] |= (0x01 << $sector);
  } else {
    $bytes[$VTOC_FREE_BITMAPS + ($track * 4)] |= (0x01 << ($sector - 8));
  }

  # Re-pack VTOC data.
  $vtoc = pack "C*", @bytes;

  # write modified VTOC back out
  seek($fd, DISK_OFFSET($VTOC_TRACK, $VTOC_SECTOR), $SEEK_SET);
  print $fd $vtoc;

  return 0;
}

sub dos33_allocate_sector {
  my ($fd) = @_;

  my $found_track = 0;
  my $found_sector = 0;
  my @bitmap;
  my $start_track;
  my $track_dir;
  my $byte;

  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @bytes = unpack "C*", $sector_buffer;

  # Originally used to keep things near center of disk for speed
  # We can use to avoid fragmentation possibly
  $start_track = $bytes[$VTOC_LAST_ALLOC_T] % $TRACKS_PER_DISK;
  $track_dir = $bytes[$VTOC_ALLOC_DIRECT];

  if ($track_dir == 255) {
    $track_dir = -1;
  }

  if (($track_dir != 1) && ($track_dir != -1)) {
    print STDERR sprintf("ERROR! Invalid track dir %i\n", $track_dir);
  }

  if ((($start_track > $VTOC_TRACK) && ($track_dir != 1)) || (($start_track < $VTOC_TRACK) && ($track_dir != -1))) {
    print STDERR sprintf("Warning! Non-optimal values for track dir t=%i d=%i!\n", $start_track, $track_dir);
  }

  my $i = $start_track;

  do {
    for ($byte = 1; $byte > -1; $byte--) {
      $bitmap[$byte] = $bytes[$VTOC_FREE_BITMAPS + ($i * 4) + $byte];
      if ($bitmap[$byte] != 0x00) {
        $found_sector = find_first_one($bitmap[$byte]);
        $found_track = $i;
        # clear bit indicating in use
        $bytes[$VTOC_FREE_BITMAPS + ($i * 4) + $byte] &= ~(0x01 << $found_sector);
        $found_sector += (8*(1 - $byte));
        goto found_one;
      }
    }

    # Move to next track, handling overflows
    $i += $track_dir;
    if ($i < 0) {
      $i = $VTOC_TRACK;
      $track_dir = 1;
    }

    if ($i >= $TRACKS_PER_DISK) {
      $i = $VTOC_TRACK;
      $track_dir = -1;
    }
  } while ($i != $start_track);

  print STDERR "No room left!\n";
  return -1;

found_one:
  # store new track/direction info
  $bytes[$VTOC_LAST_ALLOC_T] = $found_track;

  if ($found_track > $VTOC_TRACK) {
    $bytes[$VTOC_ALLOC_DIRECT] = 1;
  } else {
    $bytes[$VTOC_ALLOC_DIRECT] = -1;
  }

  # Re-pack VTOC data.
  $sector_buffer = pack "C*", @bytes;

  # Seek to VTOC
  seek($fd, DISK_OFFSET($VTOC_TRACK, $VTOC_SECTOR), $SEEK_SET);

  # Write out VTOC
  print $fd $sector_buffer;

  return (($found_track << 8) + $found_sector);
}

my $track = 0;
my $sector = 0;

# FIXME: currently assume sector is going to be 0
sub dos33_force_allocate_sector {
  my ($fd) = @_;

  my $found_track = 0;
  my $found_sector = 0;
  #unsigned char bitmap[4];
  my $i;
  my $start_track;  #, track_dir, byte;
  my $result;
  my $so;

  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @bytes = unpack "C*", $sector_buffer;

  # Originally used to keep things near center of disk for speed
  # We can use to avoid fragmentation possibly
#  $start_track = $bytes[$VTOC_LAST_ALLOC_T] % $TRACKS_PER_DISK;
#  $track_dir = $bytes[$VTOC_ALLOC_DIRECT];

  $start_track = $track;

  $i = $start_track;
  $so = !(!$sector / 8);
  $found_sector = $sector % 8;

  # FIXME: check if free
  #$bitmap[$so] = $bytes[$VTOC_FREE_BITMAPS + ($i * 4) + $so];
  # clear bit indicating in use
  $bytes[$VTOC_FREE_BITMAPS + ($i * 4) + $so] &= ~(0x01 << $found_sector);
  $found_sector += (8 * (1 - $so));
  $found_track = $i;

  printf("VMW: want %d/%d, found %d/%d\n", $track, $sector, $found_track, $found_sector) if $debug;

  $sector++;
  if ($sector > 15) {
    $sector = 0;
    $track++;
  }

#  print STDERR "No room for raw-write!\n";
#  return -1;

#found_one:
  # store new track/direction info
  #$bytes[$VTOC_LAST_ALLOC_T] = $found_track;
#
#  $bytes[$VTOC_ALLOC_DIRECT] = 1;
#  else $bytes[$VTOC_ALLOC_DIRECT] = -1;

  # Re-pack VTOC data.
  $sector_buffer = pack "C*", @bytes;

  # Seek to VTOC
  seek($fd, DISK_OFFSET($VTOC_TRACK, $VTOC_SECTOR), $SEEK_SET);

  # Write out VTOC
  print $fd $sector_buffer;

  printf("raw: T=%d S=%d\n", $found_track, $found_sector) if $debug;

  return (($found_track << 8) + $found_sector);
}

my $ERROR_INVALID_FILENAME = 1;
my $ERROR_FILE_NOT_FOUND = 2;
my $ERROR_NO_SPACE = 3;
my $ERROR_IMAGE_NOT_FOUND = 4;
my $ERROR_CATALOG_FULL = 5;

my $ADD_RAW = 0;
my $ADD_BINARY = 1;

# creates file apple_filename on the image from local file filename
# returns ??
sub dos33_add_file {
  my ($fd, $dos_type, $file_type, $address, $length, $filename, $apple_filename) = @_;

  my $free_space;
  my $file_size;
  my $needed_sectors;
  my $size_in_sectors = 0;
  my $initial_ts_list = 0;
  my $ts_list = 0;
  my $data_ts;
  my $bytes_read = 0;
  my $old_ts_list;
  my $catalog_track;
  my $catalog_sector;
  my $sectors_used = 0;
  my $input_fd;
  my $result;
  my $first_write = 1;

  if ($apple_filename !~ /^[A-Z]/) {
    print STDERR "Error! First char of filename must be ASCII 64 or above!\n";
    return $ERROR_INVALID_FILENAME;
  }

  # Check for comma in filename
  if ($apple_filename =~ /,/) {
    print STDERR "Error! Cannot have , in a filename!\n";
    return $ERROR_INVALID_FILENAME;
  }

  # FIXME
  # check type
  # and sanity check a/b filesize is set properly

  # Determine size of file to upload
  my @file_info = stat $filename;
  if (! @file_info) {
    print STDERR "Error! $filename not found!\n", $filename;
    return $ERROR_FILE_NOT_FOUND;
  }

  $file_size = $file_info[7];

  print "Filesize: $file_size\n" if $debug;

  if ($file_type == $ADD_BINARY) {
    print "Adding 4 bytes for size/offset\n" if $debug;
    if ($length == 0) {
      $length = $file_size;
    }
    $file_size += 4;
  }

  # We need to round up to nearest sector size
  # Add an extra sector for the T/S list
  # Then add extra sector for a T/S list every 122*256 bytes (~31k)
  $needed_sectors = ($file_size / $BYTES_PER_SECTOR) +  # round sectors
      (($file_size % $BYTES_PER_SECTOR) != 0) +  # tail if needed
      1 +  # first T/S list
      ($file_size / (122 * $BYTES_PER_SECTOR));  # extra t/s lists

  # Get free space on device
  $free_space = dos33_free_space($fd);

  # Check for free space
  if ($needed_sectors * $BYTES_PER_SECTOR > $free_space) {
    print STDERR sprintf("Error! Not enough free space on disk image (need %d have %d)\n", ($needed_sectors * $BYTES_PER_SECTOR), $free_space);
    return $ERROR_NO_SPACE;
  }

  # plus one because we need a sector for the tail
  $size_in_sectors = ($file_size / $BYTES_PER_SECTOR) + (($file_size % $BYTES_PER_SECTOR) != 0);
  printf("Need to allocate %i data sectors\n", $size_in_sectors) if $debug;
  printf("Need to allocate %i total sectors\n", $needed_sectors) if $debug;

  my $ifh;

  # Open the local file
  if (!open($input_fd, "<$filename")) {
    print STDERR sprintf("Error! could not open %s\n", $filename);
    return $ERROR_IMAGE_NOT_FOUND;
  }

  my $i = 0;
  while ($i < $size_in_sectors) {
    # Create new T/S list if necessary
    if ($i % $TSL_MAX_NUMBER == 0) {
      $old_ts_list = $ts_list;

      # allocate a sector for the new list
      $ts_list = dos33_allocate_sector($fd);
      $sectors_used++;
      if ($ts_list < 0) {
        return -1;
      }

      # Initialize sector data.
      my @bytes = ();

      # clear the t/s sector
      for (my $x = 0; $x < $BYTES_PER_SECTOR; $x++) {
        $bytes[$x] = 0;
      }

      # Re-pack tslist data.
      $sector_buffer = pack "C*", @bytes;

      seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
      print $fd $sector_buffer;

      if ($i == 0) {
        $initial_ts_list = $ts_list;
      } else {
        # we aren't the first t/s list so do special stuff

        # load in the old t/s list
        seek($fd, DISK_OFFSET(get_high_byte($old_ts_list), get_low_byte($old_ts_list)), $SEEK_SET);

        $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

        # Unpack tslist sector data.
        my @bytes = unpack "C*", $sector_buffer;

        # point from old ts list to new one we just made
        $bytes[$TSL_NEXT_TRACK] = get_high_byte($ts_list);
        $bytes[$TSL_NEXT_SECTOR] = get_low_byte($ts_list);

        # set offset into file
        $bytes[$TSL_OFFSET_H] = get_high_byte(($i - 122) * 256);
        $bytes[$TSL_OFFSET_L] = get_low_byte(($i - 122) * 256);

        # Re-pack tslist sector data.
        $sector_buffer = pack "C*", @bytes;

        # write out the old t/s list with updated info
        seek($fd, DISK_OFFSET(get_high_byte($old_ts_list), get_low_byte($old_ts_list)), $SEEK_SET);

        print $fd $sector_buffer;
      }
    }

    # Allocate a sector
    $data_ts = dos33_allocate_sector($fd);
    $sectors_used++;

    if ($data_ts < 0) {
      return -1;
    }

    # clear sector
    my @bytes = ();
    for (my $x = 0; $x < $BYTES_PER_SECTOR; $x++) {
      $bytes[$x] = 0;
    }

    # read from input
    if (($first_write) && ($file_type == $ADD_BINARY)) {
      $first_write = 0;
      $bytes[0] = $address & 0xff;
      $bytes[1] = ($address >> 8) & 0xff;
      $bytes[2] = ($length) & 0xff;
      $bytes[3] = (($length) >> 8) & 0xff;
      my $buf;
      $bytes_read = read($input_fd, $buf, ($BYTES_PER_SECTOR - 4));
      $sector_buffer .= $buf;
      my @bytes2 = unpack "C*", $buf;
      foreach my $byte (@bytes2) {
        push @bytes, $byte;
      }
      $bytes_read += 4;
    } else {
      $bytes_read = read($input_fd, $sector_buffer, $BYTES_PER_SECTOR);
      @bytes = unpack "C*", $sector_buffer;
    }
    $first_write = 0;

    if ($bytes_read < 0) {
      print STDERR "Error reading bytes!\n";
    }

    # Re-pack sector data.
    $sector_buffer = pack "C*", @bytes;

    # write to disk image
    seek($fd, DISK_OFFSET(($data_ts >> 8) & 0xff, $data_ts & 0xff), $SEEK_SET);
    print $fd $sector_buffer;

    printf("Writing %i bytes to %i/%i\n", $bytes_read, ($data_ts >> 8) & 0xff, $data_ts & 0xff) if $debug;

    # add to T/s table

    # read in t/s list
    seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
    $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

    my @ts_bytes = unpack "C*", $sector_buffer;

    # point to new data sector
    $ts_bytes[(($i % $TSL_MAX_NUMBER) * 2) + $TSL_LIST] = ($data_ts >> 8) & 0xff;
    $ts_bytes[(($i % $TSL_MAX_NUMBER) * 2) + $TSL_LIST + 1] = ($data_ts & 0xff);

    # Re-pack sector data.
    $sector_buffer = pack "C*", @ts_bytes;

    # write t/s list back out
    seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
    print $fd $sector_buffer;

    $i++;
  }

  # Add new file to Catalog

  # read in vtoc
  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @vtoc_bytes = unpack "C*", $sector_buffer;

  $catalog_track = $vtoc_bytes[$VTOC_CATALOG_T];
  $catalog_sector = $vtoc_bytes[$VTOC_CATALOG_S];

continue_parsing_catalog:

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  # Find empty directory entry
  $i = 0;
  while ($i < 7) {
    # for undelete purposes might want to skip 0xff
    # (deleted) files first and only use if no room

    if (($bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] == 0xff) || ($bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] == 0x00)) {
      goto got_a_dentry;
    }
    $i++;
  }

  if (($catalog_track == 0x11) && ($catalog_sector == 1)) {
    # in theory can only have 105 files
    # if full, we have no recourse!
    # can we allocate new catalog sectors
    # and point to them??
    print STDERR "Error! No more room for files!\n";
    return $ERROR_CATALOG_FULL;
  }

  $catalog_track = $bytes[$CATALOG_NEXT_T];
  $catalog_sector = $bytes[$CATALOG_NEXT_S];

  goto continue_parsing_catalog;

got_a_dentry:
#  printf("Adding file at entry %i of catalog 0x%x:0x%x\n", $i, $catalog_track, $catalog_sector);

  # Point entry to initial t/s list
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] = ($initial_ts_list >> 8) & 0xff;
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + 1] = ($initial_ts_list & 0xff);
  # set file type
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_TYPE] = dos33_char_to_type($dos_type, 0);

#  printf("Pointing T/S to %x/%x\n", ($initial_ts_list >> 8) & 0xff, $initial_ts_list & 0xff);

  # copy over filename
  for (my $x = 0; $x < length($apple_filename); $x++) {
    $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(substr($apple_filename, $x, 1)) ^ 0x80;
  }

  # pad out the filename with spaces
  for (my $x = length($apple_filename); $x < $FILE_NAME_SIZE; $x++) {
    $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(' ') ^ 0x80;
  }

  # fill in filesize in sectors
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_SIZE_L] = $sectors_used & 0xff;
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_SIZE_H] = ($sectors_used >> 8) & 0xff;

  # Re-pack catalog sector data.
  $sector_buffer = pack "C*", @bytes;

  # write out catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

# Create raw file on disk starting at track/sector
# returns ??
sub dos33_raw_file {
  my ($fd, $dos_type, $track, $sector, $filename, $apple_filename) = @_;

  my $free_space;
  my $file_size;
  my $needed_sectors;
  my $size_in_sectors = 0;
  my $initial_ts_list = 0;
  my $ts_list = 0;
  my $data_ts;
  my $bytes_read = 0;
  my $old_ts_list;
  my $catalog_track;
  my $catalog_sector;
  my $sectors_used = 0;
  my $input_fd;
  my $result;

  if ($apple_filename !~ /^[A-Z]/) {
    print STDERR "Error! First char of filename must be ASCII 64 or above!\n";
    return $ERROR_INVALID_FILENAME;
  }

  # Check for comma in filename
  if ($apple_filename =~ /,/) {
    print STDERR "Error! Cannot have , in a filename!\n";
    return $ERROR_INVALID_FILENAME;
  }

  # FIXME
  # check type
  # and sanity check a/b filesize is set properly

  # Determine size of file to upload
  my @file_info = stat $filename;
  if (! @file_info) {
    print STDERR "Error! $filename not found!\n";
    return $ERROR_FILE_NOT_FOUND;
  }

  $file_size = $file_info[7];

  print "Filesize: $file_size\n" if $debug;

  # We need to round up to nearest sector size
  # Add an extra sector for the T/S list
  # Then add extra sector for a T/S list every 122*256 bytes (~31k)
  $needed_sectors = ($file_size / $BYTES_PER_SECTOR) +  # round sectors
      (($file_size % $BYTES_PER_SECTOR) != 0) +  # tail if needed
      1 +  # first T/S list
      ($file_size / (122 * $BYTES_PER_SECTOR));  # extra t/s lists

  # Get free space on device
  $free_space = dos33_free_space($fd);

  # Check for free space
  if ($needed_sectors * $BYTES_PER_SECTOR > $free_space) {
    print STDERR sprintf("Error! Not enough free space on disk image (need %d have %d)\n", ($needed_sectors * $BYTES_PER_SECTOR), $free_space);
    return $ERROR_NO_SPACE;
  }

  # plus one because we need a sector for the tail
  $size_in_sectors = ($file_size / $BYTES_PER_SECTOR) + (($file_size % $BYTES_PER_SECTOR) != 0);

  print "Need to allocate $size_in_sectors data sectors\n" if $debug;
  print "Need to allocate $needed_sectors total sectors\n" if $debug;

  # Open the local file
  if (!open($input_fd, "<$filename")) {
    print STDERR "Error! could not open $filename\n";
    return $ERROR_IMAGE_NOT_FOUND;
  }

  my $i = 0;
  while ($i < $size_in_sectors) {
    # Create new T/S list if necessary
    if ($i % $TSL_MAX_NUMBER == 0) {
      $old_ts_list = $ts_list;

      # allocate a sector for the new list
      $ts_list = dos33_allocate_sector($fd);
      $sectors_used++;
      if ($ts_list < 0) {
        return -1;
      }

      # clear the t/s sector
      my @bytes = ();
      for (my $x = 0; $x < $BYTES_PER_SECTOR; $x++) {
        $bytes[$x] = 0;
      }

      # Re-pack sector data.
      $sector_buffer = pack "C*", @bytes;

      seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
      print $fd $sector_buffer;

      if ($i == 0) {
        $initial_ts_list = $ts_list;
      } else {
        # we aren't the first t/s list so do special stuff

        # load in the old t/s list
        seek($fd, DISK_OFFSET(get_high_byte($old_ts_list), get_low_byte($old_ts_list)), $SEEK_SET);

        $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

        # Unpack tslist sector data.
        my @bytes = unpack "C*", $sector_buffer;

        # point from old ts list to new one we just made
        $bytes[$TSL_NEXT_TRACK] = get_high_byte($ts_list);
        $bytes[$TSL_NEXT_SECTOR] = get_low_byte($ts_list);

        # set offset into file
        $bytes[$TSL_OFFSET_H] = get_high_byte(($i - 122) * 256);
        $bytes[$TSL_OFFSET_L] = get_low_byte(($i - 122) * 256);

        # Re-pack sector data.
        $sector_buffer = pack "C*", @bytes;

        # write out the old t/s list with updated info
        seek($fd, DISK_OFFSET(get_high_byte($old_ts_list), get_low_byte($old_ts_list)), $SEEK_SET);

        print $fd $sector_buffer;
      }
    }

    # force-allocate a sector
# VMW
    $data_ts = dos33_force_allocate_sector($fd);
    $sectors_used++;

    if ($data_ts < 0) {
      return -1;
    }

    # clear sector
    my @bytes = ();
    for (my $x = 0; $x < $BYTES_PER_SECTOR; $x++) {
      $bytes[$x] = 0;
    }

    $bytes_read = read($input_fd, $sector_buffer, $BYTES_PER_SECTOR);

    # Unpack tslist sector data.
    @bytes = unpack "C*", $sector_buffer;

    if ($bytes_read < 0) {
      print STDERR "Error reading bytes!\n";
    }

    # Re-pack sector data.
    $sector_buffer = pack "C*", @bytes;

    # write to disk image
    seek($fd, DISK_OFFSET(($data_ts >> 8) & 0xff, $data_ts & 0xff), $SEEK_SET);
    print $fd $sector_buffer;

    printf("Writing %i bytes to %i/%i\n", $bytes_read, (($data_ts >> 8) & 0xff), ($data_ts & 0xff)) if $debug;

    # add to T/s table

    # read in t/s list
    seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
    $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

    # Unpack tslist sector data.
    @bytes = unpack "C*", $sector_buffer;

    # point to new data sector
    $bytes[(($i % $TSL_MAX_NUMBER) * 2) + $TSL_LIST] = ($data_ts >> 8) & 0xff;
    $bytes[(($i % $TSL_MAX_NUMBER) * 2) + $TSL_LIST + 1] = ($data_ts & 0xff);

    # Re-pack sector data.
    $sector_buffer = pack "C*", @bytes;

    # write t/s list back out
    seek($fd, DISK_OFFSET(($ts_list >> 8) & 0xff, $ts_list & 0xff), $SEEK_SET);
    print $fd $sector_buffer;

    $i++;
  }

  # Add new file to Catalog

  # read in vtoc
  dos33_read_vtoc($fd);

  # Unpack VTOC data.
  my @vtoc_bytes = unpack "C*", $sector_buffer;

  $catalog_track = $vtoc_bytes[$VTOC_CATALOG_T];
  $catalog_sector = $vtoc_bytes[$VTOC_CATALOG_S];

continue_parsing_catalog:

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  # Find empty directory entry
  $i = 0;
  while ($i < 7) {
    # for undelete purposes might want to skip 0xff
    # (deleted) files first and only use if no room

    if (($bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] == 0xff) || ($bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] == 0x00)) {
      goto got_a_dentry;
    }
    $i++;
  }

  if (($catalog_track == 0x11) && ($catalog_sector == 1)) {
    # in theory can only have 105 files
    # if full, we have no recourse!
    # can we allocate new catalog sectors
    # and point to them??
    print STDERR "Error! No more room for files!\n";
    return $ERROR_CATALOG_FULL;
  }

  $catalog_track = $bytes[$CATALOG_NEXT_T];
  $catalog_sector = $bytes[$CATALOG_NEXT_S];

  goto continue_parsing_catalog;

got_a_dentry:
#  printf("Adding file at entry %i of catalog 0x%x:0x%x\n", $i, $catalog_track, $catalog_sector);

  # Point entry to initial t/s list
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE)] = ($initial_ts_list >> 8) & 0xff;
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + 1] = ($initial_ts_list & 0xff);
  # set file type
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_TYPE] = dos33_char_to_type($dos_type, 0);

#  printf("Pointing T/S to %x/%x\n", ($initial_ts_list >> 8) & 0xff, $initial_ts_list & 0xff);

  # copy over filename
  for (my $x = 0; $x < length($apple_filename); $x++) {
    $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(substr($apple_filename, $x, 1)) | 0x80;
  }

  # pad out the filename with spaces
  for (my $x = length($apple_filename); $x < $FILE_NAME_SIZE; $x++) {
    $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(' ') | 0x80;
  }

  # fill in filesize in sectors
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_SIZE_L] = $sectors_used & 0xff;
  $bytes[$CATALOG_FILE_LIST + ($i * $CATALOG_ENTRY_SIZE) + $FILE_SIZE_H] = ($sectors_used >> 8) & 0xff;

  # Re-pack sector data.
  $sector_buffer = pack "C*", @bytes;

  # write out catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

# load a file.  fts=entry/track/sector
sub dos33_load_file {
  my ($fd, $fts, $filename) = @_;

  #print "filename=$filename\n";

  my $output_fd;
  my $file_size = -1;
  my $data_t;
  my $data_s;
  my $data_sector;
  my $tsl_pointer = 0;
  my $output_pointer = 0;

  # FIXME!Warn if overwriting file!
  if (!open($output_fd, ">$filename")) {
    print STDERR "Error! could not open $filename for local save\n";
    return -1;
  }
  chmod 0666, $filename;

  my $catalog_file = $fts >> 16;
  my $catalog_track = ($fts >> 8) & 0xff;
  my $catalog_sector = ($fts & 0xff);

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  my $tsl_track = $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TS_LIST_T];
  my $tsl_sector = $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TS_LIST_S];
  my $file_type = dos33_file_type($bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE]);

  if ($file_type eq 'T') {
    $file_size = 0;
  }

#  printf("file_type: %s\n", $file_type);

keep_saving:
  # Read in TSL Sector
  my $tsl_buf;
  seek($fd, DISK_OFFSET($tsl_track, $tsl_sector), $SEEK_SET);
  $result = read($fd, $tsl_buf, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @tsl_bytes = unpack "C*", $tsl_buf;

  $tsl_pointer = 0;

  # check each track/sector pair in the list
  while ($tsl_pointer < $TSL_MAX_NUMBER) {
    # get the t/s value
    #printf("data_t offset = %d\n", ($TSL_LIST + ($tsl_pointer * $TSL_ENTRY_SIZE)));
    #printf("data_s offset = %d\n", ($TSL_LIST + ($tsl_pointer * $TSL_ENTRY_SIZE) + 1));
    $data_t = $tsl_bytes[$TSL_LIST + ($tsl_pointer * $TSL_ENTRY_SIZE)];
    $data_s = $tsl_bytes[$TSL_LIST + ($tsl_pointer * $TSL_ENTRY_SIZE) + 1];

    if (($data_s == 0) && ($data_t == 0)) {
      # empty
      last;
    } else {
      seek($fd, DISK_OFFSET($data_t, $data_s), $SEEK_SET);
      $result = read($fd, $data_sector, $BYTES_PER_SECTOR);

      # Unpack catalog sector data.
      my @data_bytes = unpack "C*", $data_sector;

      # some file formats have the size in the first sector
      # so cheat and get real file size from file itself
      if ($output_pointer == 0) {
        if ($file_type eq 'A' || $file_type eq 'I') {
          $file_size = $data_bytes[0] + ($data_bytes[1] << 8) + 2;
        } elsif ($file_type eq 'B') {
          $file_size = $data_bytes[2] + ($data_bytes[3] << 8) + 4;
        } else {
          $file_size = -1;
        }
      }

      # Re-pack sector data.
      $data_sector = pack "C*", @data_bytes;

      # write the block read in out to the output file
      seek($output_fd, $output_pointer * $BYTES_PER_SECTOR, $SEEK_SET);
      print $output_fd $data_sector;

      if ($file_type eq 'T') {
        $file_size += length($data_sector);
      }
    }
    $output_pointer++;
    $tsl_pointer++;
  }

  # finished with TSL sector, see if we have another
  $tsl_track = $tsl_bytes[$TSL_NEXT_TRACK];
  $tsl_sector = $tsl_bytes[$TSL_NEXT_SECTOR];

#  printf("Next track/sector=%d/%d op=%d\n", $tsl_track, $tsl_sector, ($output_pointer * $BYTES_PER_SECTOR));

  if (($tsl_track == 0) && ($tsl_sector == 0)) {
  } else {
    goto keep_saving;
  }

  # Correct the file size
  if ($file_size >= 0) {
#    print "Truncating file size to $file_size\n";
    $result = truncate $output_fd, $file_size;
  }

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  return 0;
}

# lock a file.  fts=entry/track/sector
sub dos33_lock_file {
  my ($fd, $fts, $lock) = @_;

  my $catalog_file = $fts >>16;
  my $catalog_track = ($fts >> 8) & 0xff;
  my $catalog_sector = ($fts & 0xff);

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  my $file_type = $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE];

  if ($lock) {
    $file_type |= 0x80;
  } else {
    $file_type &= 0x7f;
  }

  $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE] = $file_type;

  # Re-pack catalog sector data.
  $sector_buffer = pack "C*", @bytes;

  # write back modified catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

# rename a file.  fts=entry/track/sector
# FIXME: can we rename a locked file?
# FIXME: validate the new filename is valid
sub dos33_rename_file {
  my ($fd, $fts, $new_name) = @_;

  my $catalog_file = $fts >> 16;
  my $catalog_track = ($fts >> 8) & 0xff;
  my $catalog_sector = ($fts & 0xff);

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  # copy over filename
  for (my $x = 0; $x < length($new_name); $x++) {
    $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(substr($new_name, $x, 1)) | 0x80;
  }

  # pad out the filename with spaces
  for (my $x = length($new_name); $x < $FILE_NAME_SIZE; $x++) {
    $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_NAME + $x] = ord(' ') | 0x80;
  }

  # Re-pack catalog sector data.
  $sector_buffer = pack "C*", @bytes;

  # write back modified catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

# undelete a file.  fts=entry/track/sector
# FIXME: validate the new filename is valid
sub dos33_undelete_file {
  my ($fd, $fts, $new_name) = @_;

  my $catalog_file = $fts >> 16;
  my $catalog_track = ($fts>>8) & 0xff;
  my $catalog_sector = ($fts & 0xff);

  # Read in Catalog Sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  # get the stored track value, and put it back
  # FIXME: should walk file to see if T/s valild
  # by setting the track value to FF which indicates deleted file
  $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE)] = $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_NAME + 29];

  # restore file name if possible

  my $replacement_char = 0xa0;
  if (length($new_name) > 29) {
    $replacement_char = ord(substr($new_name, 29, 1)) | 0x80;
  }

  $bytes[$CATALOG_FILE_LIST + ($catalog_file * $CATALOG_ENTRY_SIZE) + $FILE_NAME + 29] = $replacement_char;

  # Re-pack catalog sector data.
  $sector_buffer = pack "C*", @bytes;

  # write back modified catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

sub dos33_delete_file {
  my ($fd, $fsl) = @_;

  # unpack file/track/sector info
  my $catalog_entry = $fsl >> 16;
  my $catalog_track = ($fsl >> 8) & 0xff;
  my $catalog_sector = ($fsl & 0xff);

  # Load in the catalog table for the file
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @bytes = unpack "C*", $sector_buffer;

  my $file_type = $bytes[$CATALOG_FILE_LIST + ($catalog_entry * $CATALOG_ENTRY_SIZE) + $FILE_TYPE];
  if ($file_type & 0x80) {
    print STDERR "File is locked! Unlock before deleting!\n";
    exit(1);
  }

  # get pointer to t/s list
  my $ts_track = $bytes[$CATALOG_FILE_LIST + $catalog_entry*$CATALOG_ENTRY_SIZE + $FILE_TS_LIST_T];
  my $ts_sector = $bytes[$CATALOG_FILE_LIST + $catalog_entry * $CATALOG_ENTRY_SIZE + $FILE_TS_LIST_S];

keep_deleting:

  # load in the t/s list info
  seek($fd, DISK_OFFSET($ts_track, $ts_sector), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @ts_bytes = unpack "C*", $sector_buffer;

  # Free each sector listed by t/s list
  for (my $i = 0; $i < $TSL_MAX_NUMBER; $i++) {
    # If t/s = 0/0 then no need to clear
    if (($ts_bytes[$TSL_LIST + 2 * $i] == 0) && ($ts_bytes[$TSL_LIST + 2 * $i + 1] == 0)) {
    } else {
      dos33_free_sector($fd, $ts_bytes[$TSL_LIST + 2 * $i], $ts_bytes[$TSL_LIST + 2 * $i + 1]);
    }
  }

  # free the t/s list
  dos33_free_sector($fd, $ts_track, $ts_sector);

  # Point to next t/s list
  $ts_track = $ts_bytes[$TSL_NEXT_TRACK];
  $ts_sector = $ts_bytes[$TSL_NEXT_SECTOR];

  # If more tsl lists, keep looping
  if (($ts_track == 0x0) && ($ts_sector == 0x0)) {
  } else {
    goto keep_deleting;
  }

  # Erase file from catalog entry

  # First reload proper catalog sector
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  my @cat_bytes = unpack "C*", $sector_buffer;

  # save track as last char of name, for undelete purposes
  $cat_bytes[$CATALOG_FILE_LIST + ($catalog_entry * $CATALOG_ENTRY_SIZE) + ($FILE_NAME + $FILE_NAME_SIZE - 1)] = $cat_bytes[$CATALOG_FILE_LIST + ($catalog_entry * $CATALOG_ENTRY_SIZE)];

  # Actually delete the file
  # by setting the track value to FF which indicates deleted file
  $cat_bytes[$CATALOG_FILE_LIST + ($catalog_entry * $CATALOG_ENTRY_SIZE)] = 0xff;

  # Re-pack catalog sector data.
  $sector_buffer = pack "C*", @cat_bytes;

  # Re-seek to catalog position and write out changes
  seek($fd, DISK_OFFSET($catalog_track, $catalog_sector), $SEEK_SET);
  print $fd $sector_buffer;

  return 0;
}

sub dump_sector {
  # Unpack sector data.
  my @bytes = unpack "C*", $sector_buffer;

  for (my $i = 0; $i < 16; $i++) {
    printf("\$%02x : ", $i * 16);
    for (my $j = 0; $j < 16; $j++) {
      printf("%02x ", $bytes[$i * 16 + $j]);
    }
    print "\n";
  }

  return 0;
}

sub dos33_dump {
  my ($fd) = @_;

  my $file;
  my $ts_t;
  my $ts_s;
  my $track;
  my $sector;
  my $deleted = 0;
  my $temp_string;
  my $tslist;

  # Read Track 1 Sector 9
  seek($fd, DISK_OFFSET(1, 9), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack sector data.
  my @bytes = unpack "C*", $sector_buffer;

  print "Finding name of startup file, Track 1 Sector 9 offset \$75\n";
  dump_sector();

  print "Startup Filename: ";
  for (my $i = 0; $i < 30; $i++) {
    printf("%c", $bytes[0x75 + $i] & 0x7f);
  }
  print "\n";

  dos33_read_vtoc($fd);

  # Unpack VTOC sector data.
  @bytes = unpack "C*", $sector_buffer;

  print "\nVTOC Sector:\n";
  dump_sector();

  print "\n\n";
  print "VTOC INFORMATION:\n";
  my $catalog_t = $bytes[$VTOC_CATALOG_T];
  my $catalog_s = $bytes[$VTOC_CATALOG_S];
  printf("  First Catalog = %02x/%02x\n", $catalog_t, $catalog_s);
  printf("  DOS RELEASE = 3.%i\n", $bytes[$VTOC_DOS_RELEASE]);
  printf("  DISK VOLUME = %i\n", $bytes[$VTOC_DISK_VOLUME]);
  my $ts_total = $bytes[$VTOC_MAX_TS_PAIRS];
  printf("  T/S pairs that will fit in T/S List = %i\n", $ts_total);

  printf("  Last track where sectors were allocated = \$%02x\n", $bytes[$VTOC_LAST_ALLOC_T]);
  printf("  Direction of track allocation = %i\n", $bytes[$VTOC_ALLOC_DIRECT]);

  my $num_tracks = $bytes[$VTOC_NUM_TRACKS];
  printf("  Number of tracks per disk = %i\n", $num_tracks);
  printf("  Number of sectors per track = %i\n", $bytes[$VTOC_S_PER_TRACK]);
  printf("  Number of bytes per sector = %i\n", ($bytes[$VTOC_BYTES_PER_SH] << 8) + $bytes[$VTOC_BYTES_PER_SL]);

  print "\nFree sector bitmap:\n";
  print "Track FEDCBA98 76543210\n";
  for (my $trk = 0; $trk < $num_tracks; $trk++) {
    printf("  \$%02x:", $trk);
    for (my $sec = 0; $sec < 8; $sec++) {
      if (($bytes[$VTOC_FREE_BITMAPS + ($trk * 4)] << $sec) & 0x80) {
        print ".";
      } else {
        print "U";
      }
    }
    print " ";
    for (my $sec = 0; $sec < 8; $sec++) {
      if (($bytes[$VTOC_FREE_BITMAPS + ($trk * 4) + 1] << $sec) & 0x80) {
        print ".";
      } else {
        print "U";
      }
    }
    print "\n";
  }

repeat_catalog:

  printf("\nCatalog Sector \$%02x/\$%02x\n", $catalog_t, $catalog_s);
  seek($fd, DISK_OFFSET($catalog_t, $catalog_s), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  @bytes = unpack "C*", $sector_buffer;

  dump_sector();

  for ($file = 0; $file < 7; $file++) {
    #print "\n\n";
    print "\n";

    $ts_t = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_TS_LIST_T))];
    $ts_s = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_TS_LIST_S))];

    printf("%i+\$%02x/\$%02x - ", $file, $catalog_t, $catalog_s);
    $deleted = 0;

    if ($ts_t == 0xff) {
      print "**DELETED** ";
      $deleted = 1;
      $ts_t = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_NAME + 0x1e))];
    }

    if ($ts_t == 0x00) {
      print "UNUSED!";
      goto continue_dump;
    }

    my $filenamestr = substr($sector_buffer, ($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_NAME)), 30);
    dos33_filename_to_ascii($temp_string, $filenamestr, 30);

    print "$temp_string";

    print "\n";
    printf("  Locked = %s\n", $bytes[$CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE] > 0x7f ?  "YES" : "NO");
    printf("  Type = %s\n", dos33_file_type($bytes[$CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE) + $FILE_TYPE]));
    printf("  Size in sectors = %i\n", $bytes[$CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_SIZE_L)] + ($bytes[$CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_SIZE_H)] << 8));

repeat_tsl:
    printf("  T/S List \$%02x/\$%02x:\n", $ts_t, $ts_s);
    if ($deleted) {
      goto continue_dump;
    }
    seek($fd, DISK_OFFSET($ts_t, $ts_s), $SEEK_SET);
    $result = read($fd, $tslist, $BYTES_PER_SECTOR);

    # Unpack tslist sector data.
    my @tslist_bytes = unpack "C*", $tslist;

    for (my $i = 0; $i < $ts_total; $i++) {
      $track = $tslist_bytes[$TSL_LIST + ($i * $TSL_ENTRY_SIZE)];
      $sector = $tslist_bytes[$TSL_LIST + ($i * $TSL_ENTRY_SIZE) + 1];
      if (($track == 0) && ($sector == 0)) {
        print ".";
      } else {
        printf("\n  %02x/%02x", $track, $sector);
      }
    }
    $ts_t = $tslist_bytes[$TSL_NEXT_TRACK];
    $ts_s = $tslist_bytes[$TSL_NEXT_SECTOR];

    if (!(($ts_s == 0) && ($ts_t == 0))) {
      goto repeat_tsl;
    }
continue_dump:;
  }

  print "\n";

  $catalog_t = $bytes[$CATALOG_NEXT_T];
  $catalog_s = $bytes[$CATALOG_NEXT_S];

  if ($catalog_s != 0) {
    $file = 0;
    goto repeat_catalog;
  }

  print "\n";

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  return 0;
}

sub dos33_showfree {
  my ($fd) = @_;

  my $file;
  my $ts_t;
  my $ts_s;
  my $track;
  my $sector;
  my $deleted = 0;
  my $temp_string;
  my $tslist;

  my $catalog_used;
  my $next_letter = ord('A');
  my %file_key;
  my $num_files = 0;

  my @usage;

  for (my $i = 0; $i < 35; $i++) {
    for (my $j = 0; $j < 16; $j++) {
      $usage[$i][$j] = 0;
    }
  }

  # Read Track 1 Sector 9
  seek($fd, DISK_OFFSET(1, 9), $SEEK_SET);
  my $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack sector data.
  my @bytes = unpack "C*", $sector_buffer;

  printf("Finding name of startup file, Track 1 Sector 9 offset \$75\n");
  printf("Startup Filename: ");
  for (my $i = 0; $i < 30; $i++) {
    printf("%c", $bytes[0x75 + $i] & 0x7f);
  }
  printf("\n");

  dos33_read_vtoc($fd);

  # Unpack VTOC sector data.
  @bytes = unpack "C*", $sector_buffer;

  printf("\n");
  printf("VTOC INFORMATION:\n");
  my $catalog_t = $bytes[$VTOC_CATALOG_T];
  my $catalog_s = $bytes[$VTOC_CATALOG_S];
  printf("  First Catalog = %02x/%02x\n", $catalog_t, $catalog_s);
  printf("  DOS RELEASE = 3.%i\n", $bytes[$VTOC_DOS_RELEASE]);
  printf("  DISK VOLUME = %i\n", $bytes[$VTOC_DISK_VOLUME]);
  my $ts_total = $bytes[$VTOC_MAX_TS_PAIRS];
  printf("  T/S pairs that will fit in T/S List = %i\n", $ts_total);

  printf("  Last track where sectors were allocated = \$%02x\n", $bytes[$VTOC_LAST_ALLOC_T]);
  printf("  Direction of track allocation = %i\n", $bytes[$VTOC_ALLOC_DIRECT]);

  my $num_tracks = $bytes[$VTOC_NUM_TRACKS];
  printf("  Number of tracks per disk = %i\n", $num_tracks);
  printf("  Number of sectors per track = %i\n", $bytes[$VTOC_S_PER_TRACK]);
  my $sectors_per_track = $bytes[$VTOC_S_PER_TRACK];

  printf("  Number of bytes per sector = %i\n", ($bytes[$VTOC_BYTES_PER_SH] << 8) + $bytes[$VTOC_BYTES_PER_SL]);

  printf("\nFree sector bitmap:\n\n");
  printf("                    1111111111111111222\n");
  printf("    0123456789ABCDEF0123456789ABCDEF012\n");

  my $disp_sec = 0;
  for (my $sec = ($sectors_per_track - 1); $sec >= 0; $sec--) {
    printf("\$%01x: ", $disp_sec++);
    for (my $trk = 0; $trk < $num_tracks; $trk++) {

      if ($sec < 8) {
        if (($bytes[$VTOC_FREE_BITMAPS + ($trk * 4)] << $sec) & 0x80) {
          printf(".");
        } else {
          printf("U");
        }
      } else {
        if (($bytes[$VTOC_FREE_BITMAPS + ($trk * 4) + 1] << ($sec - 8)) & 0x80) {
          printf(".");
        } else {
          printf("U");
        }
      }
    }
    printf("\n");
  }

  printf("Key: U=used, .=free\n\n");

  # Reserve DOS
  for (my $i = 0; $i < 3; $i++) {
    for (my $j = 0; $j < 16; $j++) {
      $usage[$i][$j] = '$';
    }
  }

  # Reserve CATALOG (not all used?)
  my $i = 0x11;
  for (my $j = 0; $j < 16; $j++) {
    $usage[$i][$j] = '#';
  }

repeat_catalog:

  $catalog_used = 0;

  seek($fd, DISK_OFFSET($catalog_t, $catalog_s), $SEEK_SET);
  $result = read($fd, $sector_buffer, $BYTES_PER_SECTOR);

  # Unpack catalog sector data.
  @bytes = unpack "C*", $sector_buffer;

  for ($file = 0; $file < 7; $file++) {
    $ts_t = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_TS_LIST_T))];
    $ts_s = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_TS_LIST_S))];

    $deleted = 0;

    if ($ts_t == 0xff) {
      printf("**DELETED** ");
      $deleted = 1;
      $ts_t = $bytes[($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_NAME + 0x1e))];
    }

    if ($ts_t == 0x00) {
      goto continue_dump;
    }

    my $filenamestr = substr($sector_buffer, ($CATALOG_FILE_LIST + ($file * $CATALOG_ENTRY_SIZE + $FILE_NAME)), 30);
    dos33_filename_to_ascii($temp_string, $filenamestr, 30);

    printf("%s %s", chr($next_letter), $temp_string);

    printf("\n");

    if (!$deleted) {
      $catalog_used++;
      $usage[$catalog_t][$catalog_s] = '@';
    }

repeat_tsl:
    if ($deleted) {
      goto continue_dump;
    }

    $usage[$ts_t][$ts_s] = chr($next_letter);
    $file_key{$temp_string} = chr($next_letter);

    $num_files++;


    seek($fd, DISK_OFFSET($ts_t, $ts_s), $SEEK_SET);
    $result = read($fd, $tslist, $BYTES_PER_SECTOR);

    # Unpack tslist sector data.
    my @tslist_bytes = unpack "C*", $tslist;

    for ($i = 0; $i < $ts_total; $i++) {
      $track = $tslist_bytes[$TSL_LIST + ($i * $TSL_ENTRY_SIZE)];
      $sector = $tslist_bytes[$TSL_LIST + ($i * $TSL_ENTRY_SIZE) + 1];
      if (($track == 0) && ($sector == 0)) {
      } else {
        $usage[$track][$sector] = chr($next_letter);
      }
    }
    $ts_t = $tslist_bytes[$TSL_NEXT_TRACK];
    $ts_s = $tslist_bytes[$TSL_NEXT_SECTOR];

    if (!(($ts_s == 0) && ($ts_t == 0))) {
      goto repeat_tsl;
    }

continue_dump:

    if ($next_letter == ord('Z')) {
      $next_letter = ord('a');
    } elsif ($next_letter == ord('z')) {
      $next_letter = ord('0');
    } else {
      $next_letter++;
    }
  }

  $catalog_t = $bytes[$CATALOG_NEXT_T];
  $catalog_s = $bytes[$CATALOG_NEXT_S];

  if ($catalog_s != 0) {
    $file = 0;
    goto repeat_catalog;
  }

  print "\n";

  if ($result < 0) {
    print STDERR "Error on I/O\n";
  }

  print "\nDetailed sector bitmap:\n\n";
  print "                    1111111111111111222\n";
  print "    0123456789ABCDEF0123456789ABCDEF012\n";

  for (my $j = 0; $j < $sectors_per_track; $j++) {
    printf("\$%01x: ", $j);
    for ($i = 0; $i < $num_tracks; $i++) {
      if ($usage[$i][$j] eq '0') {
        print ".";
      } else {
        printf("%s", $usage[$i][$j]);
      }
    }
    print "\n";
  }

  print "Key: \$=DOS, @=catalog used, #=catalog reserved, .=free\n\n";
  foreach my $val (sort values %file_key) {
    if (defined $val) {
      if (defined $file_key{$val}) {
        printf("        %s %s\n", $val, $file_key{$val});
      }
    }
  }

  return 0;
}

# ???
sub dos33_rename_hello {
  my ($fd, $new_name) = @_;

  my $buffer;

  seek($fd, DISK_OFFSET(1, 9), $SEEK_SET);
  read($fd, $buffer, $BYTES_PER_SECTOR);

  # Unpack sector data.
  my @bytes = unpack "C*", $buffer;

  for (my $i = 0; $i < 30; $i++) {
    if ($i < length($new_name)) {
      $bytes[0x75 + $i] = ord(substr($new_name, $i, 1)) | 0x80;
    } else {
      $bytes[0x75 + $i] = ord(' ') | 0x80;
    }
  }

  # Re-pack sector data.
  $buffer = pack "C*", @bytes;

  seek($fd, DISK_OFFSET(1, 9), $SEEK_SET);
  print $fd $buffer;

  return 0;
}

sub display_help {
  my ($name, $version_only) = @_;

  printf("\ndos33 version %s\n", $VERSION);
  printf("by Vince Weaver <vince\@deater.net>\n");
  printf("Perl port by Leeland Heins <softwarejanitor\@yahoo.com>\n");
  printf("\n");

  if ($version_only) {
    return;
  }

  printf("Usage: %s [-h] [-y] disk_image COMMAND [options]\n", $name);
  printf("    -h : this help message\n");
  printf("    -y : always answer yes for anying warning questions\n");
  printf("\n");
  printf("Where disk_image is a valid dos3.3 disk image\nand COMMAND is one of the following:\n");
  printf("    CATALOG\n");
  printf("    LOAD apple_file <local_file>\n");
  printf("    SAVE type local_file <apple_file>\n");
  printf("    BSAVE [-a addr] [-l len] local_file <apple_file>\n");
  printf("    DELETE apple_file\n");
  printf("    LOCK apple_file\n");
  printf("    UNLOCK apple_file\n");
  printf("    RENAME apple_file_old apple_file_new\n");
  printf("    UNDELETE apple_file\n");
  printf("    DUMP\n");
  printf("    SHOWFREE\n");
  printf("    HELLO apple_file\n");
  #printf("    INIT\n");
  #printf("    COPY\n");
  printf("\n");

  return;
}

sub truncate_filename {
  my ($out) = @_;

  my $truncated = 0;

  # Truncate filename if too long
  if (length($out) > 30) {
    $out = substr($out, 0, 30);
    print STDERR sprintf("Warning! Truncating %s to 30 chars\n", $out);
    $_[0] = $out;
    $truncated = 1;
  }

  return $truncated;
}

## MAIN

  my $type = 'b';

  my $catalog_entry;
  my $temp_string;
  my $apple_filename;
  my $new_filename;
  my $local_filename;
  my $always_yes = 0;
  my $address = 0;
  my $length = 0;

  # Process command line arguments.
  while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
    # Set base address in decimal.
    if ($ARGV[0] eq '-a' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
      $address = $ARGV[1];
      shift;
      shift;
    } elsif ($ARGV[0] eq '-l' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
      $length = $ARGV[1];
      shift;
      shift;
    } elsif ($ARGV[0] eq '-t' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
      $track = $ARGV[1];
      shift;
      shift;
    } elsif ($ARGV[0] eq '-v') {
      display_help($ARGV[0], 1);
      exit 1;
    } elsif ($ARGV[0] eq '-h') {
      display_help($ARGV[0], 0);
      exit 1;
    } else {
      die "Invalid argument $ARGV[0]\n";
    }
  }

  # get argument 1, which is image name
  my $image = shift;
  if (! defined $image) {
    print STDERR "ERROR!Must specify disk image!\n\n";
    exit 0;
  }

  my $dos_fd;
  if (!open($dos_fd, "+<$image")) {
    print STDERR "Error opening disk_image: $image\n";
    exit 0;
  }

  # Grab command
  my $command = shift;
  if (! defined $command) {
    print STDERR "ERROR! Must specify command!\n\n";
    exit 0;
  }

  # Make command be uppercase
  $command = uc($command);

  # Load a file from disk image to local machine
  if ($command eq "LOAD") {
    # check and make sure we have apple_filename
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need apple file_name\n";
      print STDERR "$0 $image LOAD apple_filename\n";
    } else {
      print "  Apple filename: $apple_filename\n" if $debug;

      truncate_filename($apple_filename);

      # get output filename
      my $local_filename = shift;
      if (! defined $local_filename) {
        $local_filename = $apple_filename;
        print "Using $local_filename for filename\n" if $debug;
      } else {
        print "Using $apple_filename for filename\n" if $debug;
      }

      print "  Output filename: $local_filename\n" if $debug;

      # get the entry/track/sector for file
      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);
      if ($catalog_entry < 0) {
        print STDERR "Error! $apple_filename not found!\n";
      } else {
        dos33_load_file($dos_fd, $catalog_entry, $local_filename);
      }
    }
  } elsif ($command eq "CATALOG") {
    # get first catalog
    $catalog_entry = dos33_get_catalog_ts($dos_fd);

    # Unpack sector data.
    my @bytes = unpack "C*", $sector_buffer;

    printf("\nDISK VOLUME %i\n\n", $bytes[$VTOC_DISK_VOLUME]);
    while ($catalog_entry > 0) {
      $catalog_entry = dos33_find_next_file($dos_fd, $catalog_entry);
      if ($catalog_entry > 0) {
        dos33_print_file_info($dos_fd, $catalog_entry);
        # why 1 << 16 ?
        $catalog_entry += (1 << 16);
        # dos33_find_next_file() handles wrapping issues
      }
    }
    print "\n";
  } elsif ($command eq "SAVE") {
    # argv3 == type == A, B, T, I, N, L etc
    # argv4 == name of local file
    # argv5 == optional name of file on disk image

    my $type = shift;
    if (! defined $type || $type eq '') {
      print STDERR "Error! Need type\n";
      print STDERR "$0 $image SAVE type file_name apple_filename\n\n";
    } else {
      print "  type=$type\n" if $debug;

      if ($type !~ /^[TIABSRNL]$/i) {
        print STDERR "Error! Invalied type - must be T, I, A, B, S, R, N or L\n";
      } else {
        my $local_filename = shift;
        if (! defined $local_filename || $local_filename eq '') {
          print STDERR "Error! Need file_name\n";
          print STDERR "$0 $image SAVE type file_name apple_filename\n\n";
        } else {
          my $apple_filename = shift;
          if (! defined $apple_filename || $apple_filename eq '') {
            print STDERR "Error! Need apple_filename\n";
            print STDERR "$0 $image SAVE type file_name apple_filename\n\n";
          } else {
            printf("  Apple filename: %s\n", $apple_filename) if $debug;

            $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);

            my $result_string = 'y';
            if ($catalog_entry >= 0) {
              print STDERR "Warning! $apple_filename exists!\n";
              if (!$always_yes) {
                printf("Over-write (y/n)?");
                $result_string = <STDIN>;
                if (($result_string eq '') || ($result_string !~ /^[yY]/)) {
                  printf("Exiting early...\n");
                }
              }
              if ($result_string =~ /^[Yy]/) {
                print STDERR "Deleting previous version...\n";
                dos33_delete_file($dos_fd, $catalog_entry);
              }
            }

            if ($result_string =~ /^[Yy]/) {
              dos33_add_file($dos_fd, $type, $ADD_RAW, $address, $length, $local_filename, $apple_filename);
            }
          }
        }
      }
    }
  } elsif ($command eq "BSAVE") {
    my $local_filename = shift;
    if (! defined $local_filename || $local_filename eq '') {
      print STDERR "Error! Need file_name\n";
      print STDERR "$0 $image BSAVE file_name apple_filename\n\n";
    } else {
      print "  Local filename: $local_filename\n" if $debug;

      my $apple_filename = shift;
      if (! defined $apple_filename || $apple_filename eq '') {
        # apple filename specified
        print STDERR "Error! Need apple_filename\n";
        print STDERR "$0 $image BSAVE file_name apple_filename\n\n";
      } else {
        truncate_filename($apple_filename);
        # If no filename specified for apple name
        # Then use the input name.Note, we strip
        # everything up to the last slash so useless
        # path info isn't used
        $apple_filename = basename($local_filename);

        truncate_filename($apple_filename);
      }

      printf("  Apple filename: %s\n", $apple_filename) if $debug;

      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);

      my $result_string = 'y';
      if ($catalog_entry >= 0) {
        print STDERR "Warning! $apple_filename exists!\n";
        if (!$always_yes) {
          printf("Over-write (y/n)?");
          $result_string = <STDIN>;
          if (($result_string eq '') || ($result_string !~ /^[yY]/)) {
            printf("Exiting early...\n");
          }
        }
        if ($result_string =~ /^[Yy]/) {
          print STDERR "Deleting previous version...\n";
          dos33_delete_file($dos_fd, $catalog_entry);
        }
      }

      if ($result_string =~ /^[Yy]/) {
        dos33_add_file($dos_fd, $type, $ADD_BINARY, $address, $length, $local_filename, $apple_filename);
      }
    }
  } elsif ($command eq "RAWWRITE") {
    # ???
    printf("  type=%s\n", $type) if $debug;

    my $local_filename = shift;
    if (! defined $local_filename) {
      print STDERR "Error! Need file_name\n";

      print STDERR "$0 $image RAWWRITE file_name apple_filename\n\n";
    } else {
      printf("  Local filename: %s\n", $local_filename) if $debug;

      my $apple_filename = shift;
      if (defined $apple_filename) {
        # apple filename specified
        truncate_filename($apple_filename);
      } else {
        $apple_filename = basename($local_filename);
        # If no filename specified for apple name
        # Then use the input name.  Note, we strip
        # everything up to the last slash so useless
        # path info isn't used

        truncate_filename($apple_filename);
      }

      printf("  Apple filename: %s\n", $apple_filename) if $debug;

      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);

      my $result_string = 'y';
      if ($catalog_entry >= 0) {
        print STDERR "Warning! $apple_filename exists!\n";
        if (!$always_yes) {
          print "Over-write (y/n)?";
          $result_string = <STDIN>;
          if (($result_string eq '') || ($result_string !~ /[yY]/)) {
            print "Exiting early...\n";
          }
        }
        if ($result_string =~ /^[Yy]/) {
          print STDERR "Deleting previous version...\n";
          dos33_delete_file($dos_fd, $catalog_entry);
        }
      }

      if ($result_string =~ /^[Yy]/) {
        dos33_raw_file($dos_fd, $type, $track, $sector, $local_filename, $apple_filename);
      }
    }
  } elsif ($command eq "DELETE") {
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need file_name\n";
      print STDERR "$0 $image DELETE apple_filename\n";
    } else {
      truncate_filename($apple_filename);

      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);

      if ($catalog_entry < 0) {
        print STDERR "Error! File $apple_filename does not exist\n";
      } else {
        dos33_delete_file($dos_fd, $catalog_entry);
      }
    }
  } elsif ($command eq "DUMP") {
    printf("Dumping %s!\n", $image);
    dos33_dump($dos_fd);
  } elsif ($command eq "SHOWFREE") {
    printf("Showing Free %s!\n", $image);
    dos33_showfree($dos_fd);
  } elsif ($command eq "LOCK" || $command eq "UNLOCK") {
    # check and make sure we have apple_filename
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need apple file_name\n";
      print STDERR "$0 $image $command apple_filename\n";
    } else {
      truncate_filename($apple_filename);

      # get the entry/track/sector for file
      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);
      if ($catalog_entry < 0) {
        print STDERR "Error! $apple_filename not found!\n";
      } else {
        dos33_lock_file($dos_fd, $catalog_entry, $command eq "LOCK");
      }
    }
  } elsif ($command eq "RENAME") {
    # check and make sure we have apple_filename
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need two filenames\n";
      print STDERR "$0 $image LOCK apple_filename_old apple_filename_new\n";
    } else {
      # Truncate filename if too long
      truncate_filename($apple_filename);

      my $new_filename = shift;
      if (! defined $new_filename) {
        print STDERR "Error! Need two filenames\n";
        print STDERR "$0 $image LOCK apple_filename_old apple_filename_new\n";
      } else {
        truncate_filename($new_filename);

        # get the entry/track/sector for file
        $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);
        if ($catalog_entry < 0) {
          print STDERR "Error! $apple_filename not found!\n";
        } else {
          dos33_rename_file($dos_fd, $catalog_entry, $new_filename);
        }
      }
    }
  } elsif ($command eq "UNDELETE") {
    # check and make sure we have apple_filename
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need apple file_name\n";
      print STDERR "$0 $image UNDELETE apple_filename\n\n";
    } else {
      truncate_filename($apple_filename);

      # get the entry/track/sector for file
      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_DELETED);

      if ($catalog_entry < 0) {
        print STDERR "Error! $apple_filename not found!\n";
      } else {
        dos33_undelete_file($dos_fd, $catalog_entry, $apple_filename);
      }
    }
  } elsif ($command eq "HELLO") {
    my $apple_filename = shift;
    if (! defined $apple_filename) {
      print STDERR "Error! Need file_name\n";
      print "$0 $image HELLO apple_filename\n\n";
    } else {
      truncate_filename($apple_filename);

      $catalog_entry = dos33_check_file_exists($dos_fd, $apple_filename, $FILE_NORMAL);

      if ($catalog_entry < 0) {
        print STDERR "Warning! File $apple_filename does not exist\n";
      }
      dos33_rename_hello($dos_fd, $apple_filename);
    }
  } elsif ($command eq "INIT") {
    # use common code from mkdos33fs?
  } elsif ($command eq "COPY") {
    # use temp file?  Walking a sector at a time seems a pain
  } else {
    print STDERR "ERROR! Unknown command $command\n";
    print STDERR "        Try \"$0 -h\" for help.\n\n";
  }

  close($dos_fd);

  exit 1;

1;

