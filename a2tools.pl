#!/usr/bin/perl -w

#
#   a2tools - utilities for transferring data between Unix and Apple II
#             DOS 3.3 disk images.
#
#   Copyright (C) 1998, 2001 Terry Kyriacopoulos
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#   Author's e-mail address: terryk@echo-on.net
#
#   -------------------------------------------------------------------
#
#   Modified to be more portable: Unix specifics are marked as such.
#   ANSI-C is assumed, code is now acceptable to C++ as well,
#   type definitions are straighetend up, unused variables are removed,
#   casts are added when required by C++.
#
#   Paul Schlyter, 2001-03-20,  pausch@saaf.se
#
#   -------------------------------------------------------------------
#
#   Improvements to accomodate MS-DOS have been made:
#
# - code fixed to work properly on a 16-bit platform
# - conditional compilation used to select OS-specific code
#   automatically
# - user interface is now more OS-specific:
#    - argv[0] command selection for UNIX, argv[1] for DOS
#    - stdin/stdout forbidden on binary data in DOS
# - optional source/destination pathnames for in/out commands
# - improved documentation
#   Terry Kyriacopoulos, April 8, 2001    terryk@echo-on.net
#
# Ported to Perl 20190226 Leeland Heins
#

use strict;

use File::Basename;

my $SEEK_SET = 0;

my $FILENAME_LENGTH = 30;

my $NUM_TRACKS = 35;
my $NUM_SECTORS = 16;

my $BYTES_PER_SECTOR = 256;

my $EOF = undef;

my $HelpText = "a2tools - utility for transferring files from/to Apple II .dsk images
          Copyright (C) 1998, 2001  Terry Kyriacopoulos

          Perl port 20190226 Leeland Heins

    Usage:

        a2 dir <dsk_image>
        a2 out [-r] <dsk_image> <a2_name> [<dest_file>]
        a2 in [-r] <type>[.<hex_addr>] <dsk_image> <a2_name> [<source>]
        a2 del <dsk_image> <a2_name>

        -r (raw mode):  Suppress all filetype-dependent processing
                        and copy everything as-is.

        <type>: one of t,i,a,b,s,r,x,y (do not use -)
        <hex_addr>: base address in hex, for type B (binary)
\n
        Quotes may be used around names with spaces, use \\\"
        to include a quote in the name.\n";

# Apple Integer and AppleSoft BASIC tokens.

my @Integer_tokens = (
" HIMEM:",      "",             " _ ",          ":",
" LOAD ",       " SAVE ",       " CON ",        " RUN ",
" RUN ",        " DEL ",        ",",            " NEW ",
" CLR ",	" AUTO ",	",",		" MAN ",
" HIMEM:",	" LOMEM:",	"+",		"-",
"*",		"/",		"=",		"#",
">=",		">",		"<=",		"<>",
"<",		" AND ",	" OR ",		" MOD ",
" ^ ",		"+",		"(",		",",
" THEN ",	" THEN ",	",",		",",
"\"",		"\"",		"(",		"!",
"!",		"(",		" PEEK ",	" RND ",
" SGN ",	" ABS ",	" PDL ",	" RNDX ",
"(",		"+",		"-",		" NOT ",
"(",		"=",		"#",		" LEN(",
" ASC(",	" SCRN(",	",",		"(",

"\$",		"\$",		"(",		",",
",",		";",		";",		";",
",",		",",		",",		" TEXT ",
" GR ",		" CALL ",	" DIM ",	" DIM ",
" TAB ",	" END ",	" INPUT ",	" INPUT ",
" INPUT ",	" FOR ",	"=",		" TO ",
" STEP ",	" NEXT ",	",",		" RETURN ",
" GOSUB ",	" REM ",	" LET ",	" GOTO ",
" IF ",		" PRINT ",	" PRINT ",	" PRINT ",
" POKE ",	",",		" COLOR=",	" PLOT ",
",",		" HLIN ",	",",		" AT ",
" VLIN ",	",",		" AT ",		" VTAB ",
"=",		"=",		")",		")",
" LIST ",	",",		" LIST ",	" POP ",
" NODSP ",	" NODSP ",	" NOTRACE ",	" DSP ",
" DSP ",	" TRACE ",	" PR#",		" IN#"
);


my @Applesoft_tokens = (
" END ",	" FOR ",	" NEXT ",	" DATA ",
" INPUT ",	" DEL ",	" DIM ",	" READ ",
" GR ",		" TEXT ",	" PR#",		" IN#",
" CALL ",	" PLOT ",	" HLIN ",	" VLIN ",
" HGR2 ",	" HGR ",	" HCOLOR=",	" HPLOT ",
" DRAW ",	" XDRAW ",	" HTAB ",	" HOME ",
" ROT=",	" SCALE=",	" SHLOAD ",	" TRACE ",
" NOTRACE ",	" NORMAL ",	" INVERSE ",	" FLASH ",
" COLOR=",	" POP ",	" VTAB ",	" HIMEM:",
" LOMEM:",	" ONERR ",	" RESUME ",	" RECALL ",
" STORE ",	" SPEED=",	" LET ",	" GOTO ",
" RUN ",	" IF ",		" RESTORE ",	" & ",
" GOSUB ",	" RETURN ",	" REM ",	" STOP ",
" ON ",		" WAIT ",	" LOAD ",	" SAVE ",
" DEF ",	" POKE ",	" PRINT ",	" CONT ",
" LIST ",	" CLEAR ",	" GET ",	" NEW ",

" TAB(",	" TO ",		" FN ",		" SPC(",
" THEN ",	" AT ",		" NOT ",	" STEP ",
" + ",		" - ",		" * ",		" / ",
" ^ ",		" AND ",	" OR ",		" > ",
" = ",		" < ",		" SGN ",	" INT ",
" ABS ",	" USR ",	" FRE ",	" SCRN(",
" PDL ",	" POS ",	" SQR ",	" RND ",
" LOG ",	" EXP ",	" COS ",	" SIN ",
" TAN ",	" ATN ",	" PEEK ",	" LEN ",
" STR\$ ",	" VAL ",	" ASC ",	" CHR\$ ",
" LEFT\$ ",	" RIGHT\$ ",	" MID\$ ",	"  ",

" SYNTAX ",			" RETURN WITHOUT GOSUB ",
" OUT OF DATA ",		" ILLEGAL QUANTITY ",
" OVERFLOW ",			" OUT OF MEMORY ",
" UNDEF'D STATEMENT ",		" BAD SUBSCRIPT ",
" REDIM'D ARRAY ",		" DIVISION BY ZERO ",
" ILLEGAL DIRECT ",		" TYPE MISMATCH ",
" STRING TOO LONG ",		" FORMULA TOO COMPLEX ",
" CAN'T CONTINUE ",		" UNDEF'D FUNCTION ",

" ERROR \a",	"",		"",		""
);

my $FILETYPE_T = 0x00;
my $FILETYPE_I = 0x01;
my $FILETYPE_A = 0x02;
my $FILETYPE_B = 0x04;
my $FILETYPE_S = 0x08;
my $FILETYPE_R = 0x10;
my $FILETYPE_X = 0x20;
my $FILETYPE_Y = 0x40;
# X - "new A", Y - "new B"

my $MAX_HOPS = 560;

my $VTOC_CHK_NO = 6;

my @vtoc_chk_offset = (0x03, 0x27, 0x34, 0x35, 0x36, 0x37);
my @vtoc_chk_value = (0x03, 0x7a, 0x23, 0x10, 0x00, 0x01);

my $from_file;
my $to_file;
my $image_fp;
my $extfilename;
my $extfilemode;

my @padded_name;
my @dir_entry_data;

my $vtocbuffer = '';
my $begun;
my $baseaddress;
my $rawmode;
my $filetype;
my $new_sectors;
my $dir_entry_pos;

sub quit {
  my ($exitcode, $exitmsg) = @_;

  print STDERR sprintf("%s", $exitmsg);

  if ($image_fp) {
    close($image_fp);
  }
  if ($from_file) {
    close($from_file);
  }
  if ($to_file) {
    close($to_file);
  }

  exit $exitcode;
}

sub seek_sect {
  my ($track, $sector) = @_;

 if ($track >= $NUM_TRACKS || $sector >= $NUM_SECTORS) {
    quit(1, "seek on .dsk out of range trk=$track sec=$sector.\n");
  }

  return seek($image_fp, ($track * $NUM_SECTORS + $sector) * $BYTES_PER_SECTOR, $SEEK_SET);
}

sub read_sect {
  my ($track, $sector, $buffer) = @_;

  seek_sect($track, $sector);

  my $rv = read($image_fp, $buffer, $BYTES_PER_SECTOR);

  $_[2] = $buffer;

  return $rv;
}

sub write_sect {
  my ($track, $sector, $buffer) = @_;

  seek_sect($track, $sector);

  print $image_fp $buffer;
}

sub dump_sect {
  my ($buf) = @_;

  print "BUFFER=\n";

  my @bytes = unpack "C*", $buf;

  my $i = 0;
  foreach my $byte (@bytes) {
    printf("%02x ", $byte);
    $i++;
    print "\n" if !($i % 16);
  }
  print "\n";
}

sub dir_do {
  my ($what_to_do) = @_;

  my $buffer;
  my $cur_trk;
  my $cur_sec;
  my $i;
  my $found;
  my $hop;

  $hop = 0;
  $found = 0;

  my @vtoc_bytes = unpack "C*", $vtocbuffer;

  $cur_trk = $vtoc_bytes[1];
  $cur_sec = $vtoc_bytes[2];

  while (++$hop < $MAX_HOPS && !$found && ($cur_trk || $cur_sec)) {
    read_sect($cur_trk, $cur_sec, $buffer);
    my @bytes = unpack "C*", $buffer;
    my $nxt_trk = $bytes[1];
    my $nxt_sec = $bytes[2];
    $i = 0x0b;
    while ($i <= 0xdd && !($found = $what_to_do->(substr($buffer, $i, 35)))) {
      $i += 35;
    }
    if ($found) {
      $dir_entry_pos = ($cur_trk * $NUM_SECTORS + $cur_sec) * $BYTES_PER_SECTOR + $i;
    }
    $cur_trk = $nxt_trk;
    $cur_sec = $nxt_sec;
  }
  if ($hop >= $MAX_HOPS) {
    quit(2, "\n***Corrupted directory\n\n");
  }

  return $found;
}

sub dir_find_name {
  my ($buffer) = @_;

  my @bytes = unpack "C*", $buffer;

  if ($bytes[0] == 0xff || $bytes[3] == 0) {
    return 0;
  }

  for (my $j = 0; $j < $FILENAME_LENGTH; $j++) {
    if ($padded_name[$j] != (($bytes[$j + 3]) & 0x7f)) {
      return 0;
    }
  }
  my $y = 0;
  for (my $x = 0; $x < 35; $x++) {
    $dir_entry_data[$y++] = $bytes[$x];
  }

  return 1;
}

sub dir_find_space {
  my ($buffer) = @_;

  my @bytes = unpack "C*", $buffer;

  return ($bytes[0] == 0xff || $bytes[3] == 0);
}

sub dir_print_entry {
  my ($buffer) = @_;

  my $j;

  my @bytes = unpack "C*", $buffer;

  if ($bytes[0] != 0xff && $bytes[3] != 0) {
    # entry is present
    print " ";
    if ($bytes[2] & 0x80) {
      print "*";
    } else {
      print " ";
    }
    my $filet = ($bytes[2] & 0x7f);

    if ($filet == $FILETYPE_T) {
      print "T";
    } elsif ($filet == $FILETYPE_I) {
      print "I";
    } elsif ($filet == $FILETYPE_A) {
      print "A";
    } elsif ($filet == $FILETYPE_B) {
      print "B";
    } elsif ($filet == $FILETYPE_S) {
      print "S";
    } elsif ($filet == $FILETYPE_R) {
      print "R";
    } elsif ($filet == $FILETYPE_X) {
      print "X";
    } elsif ($filet == $FILETYPE_Y) {
      print "Y";
    } else {
      print "?";
    }
    print sprintf(" %03u ", $bytes[33] + $bytes[34] * $BYTES_PER_SECTOR);

    for ($j = 3; $j < 33; $j++) {
      print sprintf("%c", ($bytes[$j] & 0x7f));
    }
    print "\n";
  }

  return 0;
}

sub preproc {
  my ($procmode) = @_;

  # procmode: 0 - raw, 1 - text, 2 - binary

  my $bytepos;
  my $lengthspec_pos;
  my $c;
  my $sect_pos;
  $sect_pos = 0;
  if (!$begun) {
    $begun = 1;
    $bytepos = 0;
    $c = getc($from_file);

    if ($procmode == 2) {
      print $image_fp ($baseaddress & 0xff);
      print $image_fp ($baseaddress >> 8);
      # we don't know the length now, so save the spot in the image
      $lengthspec_pos = ftell($image_fp);
      print $image_fp 0xff;
      print $image_fp 0xff;
      $sect_pos = 4;
    }
  }
  while ($c != $EOF && $sect_pos < $BYTES_PER_SECTOR) {
    if ($procmode == 1) {
      if (($c & 0x7f) == '\n') {
        $c = '\r';
      }
      $c |= 0x80;
    }
    print $image_fp $c;
    $c = getc($from_file);
    $sect_pos++;
    $bytepos++;
  }
  while ($sect_pos++ < $BYTES_PER_SECTOR) {
    print $image_fp 0x00;
  }
  if ($c == $EOF && $procmode == 2) {
    # now we know the length
    seek($image_fp, $lengthspec_pos, $SEEK_SET);
    print $image_fp, ($bytepos & 0xff);
    print $image_fp ($bytepos >> 8);
  }

  return ($c == $EOF);
}

sub new_sector {
  my ($track, $sector) = @_;

  # find a free sector, quit if no more
  my $byteoffset;
  my $bitmask;

  my $lasttrack;
  my $cur_track;
  my $cur_sector;
  my $direction;

  my @vtoc_bytes = unpack "C*", $vtocbuffer;

  # force sane values, in case vtoc contains garbage
  if ($vtoc_bytes[0x31] == 1) {
    $direction = 1;
  } else {
    $direction = -1;
  }
  $lasttrack = $vtoc_bytes[0x30] % 35;
  $cur_track = $lasttrack;
  $cur_sector = 15;
  for (;;) {
    $byteoffset = 0x39 + ($cur_track << 2) - ($cur_sector >> 3 & 1);
    $bitmask = (1 << ($cur_sector & 0x07));
    if ($vtoc_bytes[$byteoffset] & $bitmask) {
      $vtoc_bytes[$byteoffset] &= 0xff ^ $bitmask;
      last;
    } elsif (!$cur_sector--) {
      $cur_sector = 15;
      $cur_track += $direction;
      if ($cur_track >= $NUM_TRACKS) {
        $cur_track = 17;
        $direction = -1;
      } elsif ($cur_track < 0) {
        $cur_track = 18;
        $direction = 1;
      }
      if ($cur_track == $lasttrack) {
        quit(3, "Disk Full.\n");
      }
    }
  }
  $track = $cur_track;
  $vtoc_bytes[0x30] = $cur_track;
  $sector = $cur_sector;
  $vtoc_bytes[0x31] = $direction % $BYTES_PER_SECTOR;
  $new_sectors++;

  $vtocbuffer = pack "C*", @vtoc_bytes;
}

sub free_sector {
  my ($track, $sector) = @_;

  my @vtoc_bytes = unpack "C*", $vtocbuffer;

  $vtoc_bytes[0x39 + ($track << 2) - ($sector >> 3&1)] |= 1 << ($sector & 0x07);

  $vtocbuffer = pack "C*", @vtoc_bytes;
}

sub postproc_B  {
  my $filelength = 0;
  my $bytepos = 0;
  my $sect_pos = 0;
  if (!$begun) {
    $begun = 1;
    $bytepos = 0;
    getc($image_fp);  # Ignore 2 byte base address
    getc($image_fp);
    my $len_lo = ord(getc($image_fp));
    my $len_hi = ord(getc($image_fp));
    $filelength = ($len_hi << 8) + $len_lo;
    $sect_pos = 4;
  }
  while ($bytepos < $filelength && $sect_pos < $BYTES_PER_SECTOR) {
    print $to_file getc($image_fp);
    $sect_pos++;
    $bytepos++;
  }
}

sub postproc_A {
  my $bufstat;
  my $tokens_left;
  my $lastspot;
  my @lineheader;
  my $sect_pos = 0;
  my $c;

  if (!$begun) {  # first sector, initialize
    $begun = 1;
    getc($image_fp);  # ignore the length data, we use
    getc($image_fp);  # null line pointer as EOF
    $sect_pos = 2;
    $lastspot = 0x0801;  # normal absolute beginning address
    $tokens_left = 0;
    $bufstat = 0;
  }
  while ($lastspot && $sect_pos < $BYTES_PER_SECTOR) {
    if (!$tokens_left && !$bufstat) {
      $bufstat = 4;
    }
    while ($bufstat > 0 && $sect_pos < $BYTES_PER_SECTOR) {
      $lineheader[4 - $bufstat] = getc($image_fp);
      $sect_pos++;
      $bufstat--;
    }
    if (!$tokens_left && !$bufstat && ($lastspot = ord($lineheader[0]) + ord($lineheader[1]) * 0x100)) {
      $tokens_left = 1;
      printf $to_file "\n";
      print $to_file sprintf(" %u ", ord($lineheader[2]) + ord($lineheader[3]) * 0x100);
    }
    while ($tokens_left && $lastspot && $sect_pos < $BYTES_PER_SECTOR) {
      if (($tokens_left = $c = ord(getc($image_fp))) & 0x80) {
        print $to_file sprintf("%s", $Applesoft_tokens[($c & 0x7f)]);
      } elsif ($c) {
        print $to_file sprintf("%c", $c);
      }
      $sect_pos++;
    }
  }
  if (!$lastspot) {
    print $to_file "\n\n";
  }
}

sub postproc_I {
  my $filelength;
  my $bytepos;
  my $bufstat;
  my $inputmode;
  my $quotemode;
  my $varmode;
  my @numbuf;
  my $sect_pos;
  my $c;

  $sect_pos = 0;

  if (!$begun) {  # first sector, initialize
    $begun = 1;
    $filelength = getc($image_fp) + (getc($image_fp) * $BYTES_PER_SECTOR);
    $sect_pos = 2;
    $bytepos = $inputmode = $bufstat = $quotemode = $varmode = 0;
  }
  # inputmode: 0 - header, 1 - integer, 2 - tokens
  # varmode: 1 means we are in the middle of an identifier
  while ($bytepos < $filelength && $sect_pos < $BYTES_PER_SECTOR) {
    if ($inputmode < 2 && !$bufstat) {
      $bufstat = 3 - $inputmode;
    }
    while ($bufstat > 0 && $bytepos < $filelength && $sect_pos < $BYTES_PER_SECTOR) {
      $numbuf[3 - $bufstat] = getc($image_fp);
      $sect_pos++;
      $bytepos++;
      $bufstat--;
    }
    if (!$bufstat && $inputmode == 0) {
      print $to_file "\n";
      print $to_file sprintf("%5u ", $numbuf[1] + ($numbuf[2] * $BYTES_PER_SECTOR));
      $inputmode = 2;
    }
    if (!$bufstat && $inputmode == 1) {
      printf $to_file sprintf("%u", $numbuf[1] + ($numbuf[2] * $BYTES_PER_SECTOR));
      $inputmode = 2;
    }
    while ($inputmode == 2 && $bytepos < $filelength && $sect_pos < $BYTES_PER_SECTOR) {
      $c = getc($image_fp);
      $sect_pos++;
      $bytepos++;
      # 0x28: open quote, 0x29: close quote, 0x5d: REM token
      if ($c == 0x28 || $c == 0x5d) {
        $quotemode = 1;
      }
      if ($c == 0x29) {
        $quotemode = 0;
      }
      # Look for integer, unless in comment, string, or identifier
      if (!$quotemode && !$varmode && $c >= 0xb0 && $c <= 0xb9) {
         $inputmode = 1;
      } else {
        # Identifiers begin with letter, may contain digit
        $varmode = ($c >= 0xc1 && $c <= 0xda) || (($c >= 0xb0 && $c <= 0xb9) && $varmode);
        if ($c == 0x01) {
          $inputmode = $quotemode = 0;
        } else {
          if ($c & 0x80) {
            print $to_file sprintf("%c", ($c & 0x7f));
          } else {
            print $to_file sprintf("%s", $Integer_tokens[$c]);
          }
        }
      }
    }
  }
  if ($bytepos >= $filelength) {
    print $to_file "\n\n";
  }
}

sub postproc_T {
  my $not_eof;
  my $sect_pos;
  my $c;

  $sect_pos = 0;

  if (!$begun) {
    $begun = $not_eof = 1;
  }
  while ($not_eof && $sect_pos < $BYTES_PER_SECTOR && ($not_eof = $c = getc($image_fp))) {
    $c &= 0x7f;
    if ($c == '\r') {
      $c = '\n';
    }
    print $to_file, $c;
    $sect_pos++;
  }
}

sub postproc_raw {
  my $sect_pos;

  for ($sect_pos = 0; $sect_pos < $BYTES_PER_SECTOR; $sect_pos++) {
    print $to_file getc($image_fp);
  }
}

sub a2ls {
  my $trkmap;
  my $i;
  my $j;
  my $free_sect = 0;

  my @vtoc_bytes = unpack "C*", $vtocbuffer;

  # count the free sectors
  for ($i = 0x38; $i <= 0xc0; $i += 4) {
    $trkmap = $vtoc_bytes[$i] * 256 + $vtoc_bytes[$i + 1];
    for ($j = 0; $j < $NUM_SECTORS; $j++) {
      $free_sect += (($trkmap & (1 << $j)) != 0);
    }
  }
  print sprintf("\nDisk Volume %u, Free Blocks: %u\n\n", $vtoc_bytes[0x06], $free_sect);
  dir_do(\&dir_print_entry);
  print "\n";
}

sub a2rm {
  my $listbuffer;
  my $hop;
  my $next_trk;
  my $next_sec;
  my $i;
  if (!dir_do(\&dir_find_name)) {
    quit(4, "File not found.\n");
  }
  $hop = 0;
  $begun = 0;
  $next_trk = $dir_entry_data[0];
  $next_sec = $dir_entry_data[1];
  seek($image_fp, $dir_entry_pos, $SEEK_SET);
  print $image_fp 0xff;  # mark as deleted
  while (++$hop < $MAX_HOPS && ($next_trk || $next_sec)) {
    read_sect($next_trk, $next_sec, $listbuffer);
    my @list_bytes = unpack "C*", $listbuffer;
    free_sector($next_trk, $next_sec);
    $next_trk = $list_bytes[1];
    $next_sec = $list_bytes[2];
    for ($i = 0x0c; $i <= 0xfe; $i += 2) {
      if ($list_bytes[$i] || $list_bytes[$i + 1]) {
        free_sector($list_bytes[$i], $list_bytes[$i + 1]);
      }
    }
  }
  if ($hop >= $MAX_HOPS) {
    quit(5, "Corrupted sector list\n\n");
  }

  write_sect(0x11, 0, $vtocbuffer);
}

sub a2out {
  my $listbuffer;
  my $hop;
  my $next_trk;
  my $next_sec;
  my $i;
  my $j;
  my $postproc_function = '';

  if (!dir_do(\&dir_find_name)) {
    quit(6, "File not found.\n");
  }
  $hop = 0;
  $begun = 0;
  $next_trk = $dir_entry_data[0];
  $next_sec = $dir_entry_data[1];
  $filetype = $dir_entry_data[2] & 0x7f;

  if ($filetype == $FILETYPE_T) {
    $postproc_function = \&postproc_T;
  } elsif ($filetype == $FILETYPE_B) {
    $postproc_function = \&postproc_B;
  } elsif ($filetype == $FILETYPE_A) {
    $postproc_function = \&postproc_A;
  } elsif ($filetype == $FILETYPE_I) {
    $postproc_function = \&postproc_I;
  } elsif (!$rawmode) {
    quit(7, "File type supported in raw mode only.\n");
  }
  if ($rawmode) {
    $postproc_function = \&postproc_raw;
  }

  $extfilemode = "w";

  if ((! defined $to_file || ! $to_file) && !(open($to_file, ">$extfilename"))) {
    print "Error writing $extfilename\n";
    quit(9, "");
  }

  while (++$hop < $MAX_HOPS && ($next_trk || $next_sec)) {
    read_sect($next_trk, $next_sec, $listbuffer);
    my @list_bytes = unpack "C*", $listbuffer;
    $next_trk = $list_bytes[1];
    $next_sec = $list_bytes[2];
    for ($i = 0x0c; $i <= 0xfe; $i += 2) {
      if (!$list_bytes[$i] && !$list_bytes[$i + 1]) {
        if ($filetype != $FILETYPE_T || !$rawmode) {
          $next_trk = 0;
          $next_sec = 0;
          last;
        } else {
          for ($j = 0; $j < $BYTES_PER_SECTOR; $j++) {
            print $to_file 0x00;
          }
        }
      } else {
        ++$hop;
        seek_sect($list_bytes[$i], $list_bytes[$i + 1]);
        $postproc_function->();
      }
    }
  }
  if ($hop >= $MAX_HOPS) {
    quit(10, "Corrupted sector list\n\n");
  }

  close($to_file);
}

sub a2in  {
  my $listbuffer;
  my @databuffer;
  my $i;
  my $curlist_trk;
  my $curlist_sec;
  my $listentry_pos;
  my $list_no;
  my $curdata_trk;
  my $curdata_sec;
  my $procmode;
  my $newlist_trk;
  my $newlist_sec;
  my $c;

  $new_sectors = 0;
  $list_no = 0;
  $procmode = 0;
  if (!$rawmode) {
    if ($filetype == $FILETYPE_T) {
      $procmode = 1;
    } elsif ($filetype == $FILETYPE_B) {
      $procmode = 2;
    } else {
      quit(11, "This type is supported only in raw mode.\n");
    }
  }

  $extfilemode = "r";

  if (!$from_file && !($from_file = open($extfilename, $extfilemode))) {
    perror($extfilename);
    quit(13, "");
  }

  if (dir_do(\&dir_find_name)) {
    quit(14, "File exists.\n");
  }
  if (!dir_do(\&dir_find_space)) {
    quit(15, "No space in directory.\n");
  }
  if ($padded_name[0] < 'A') {
    quit(16, "Bad first filename character, must be >= 'A'.\n");
  }
  for ($i = 0; $i < $FILENAME_LENGTH; $i++) {
    if ($padded_name[$i] == ',') {
      quit(17, "Filename must not contain a comma.\n");
    }
  }
  for ($i = 0; $i < $FILENAME_LENGTH; $i++) {
    $dir_entry_data[$i + 3] = $padded_name[$i] | 0x80;
  }
  $dir_entry_data[2] = $filetype;

  new_sector($curlist_trk, $curlist_sec);
  $dir_entry_data[0] = $curlist_trk;
  $dir_entry_data[1] = $curlist_sec;
  my @list_bytes = ();
  for ($i = 0; $i < $BYTES_PER_SECTOR; $i++) {
    $list_bytes[$i] = 0;
  }
  $listentry_pos = 0;

  for (;;) {
    if (!$rawmode || $filetype != $FILETYPE_T) {
      new_sector($curdata_trk, $curdata_sec);
      $list_bytes[0x0c + ($listentry_pos << 1)] = $curdata_trk;
      $list_bytes[0x0d + ($listentry_pos << 1)] = $curdata_sec;
      seek_sect($curdata_trk, $curdata_sec);
      if (preproc($procmode)) {
        last;
      }
    } else {
      # Check for all-zero sectors for sparse T file
      for ($i = 0; $i < $BYTES_PER_SECTOR; $i++) {
        $databuffer[$i] = 0;
      }
      $i = 0;
      while (($c = getc($from_file)) != $EOF && $i < $BYTES_PER_SECTOR) {
        $databuffer[$i++] = $c;
      }
      while ($i && !$databuffer[$i - 1]) {
        $i--;
      }
      if (!$i) {
        $list_bytes[0x0c + ($listentry_pos << 1)] = 0;
        $list_bytes[0x0d + ($listentry_pos << 1)] = 0;
      } else {
        new_sector($curdata_trk, $curdata_sec);
        $list_bytes[0x0c + ($listentry_pos << 1)] = $curdata_trk;
        $list_bytes[0x0d + ($listentry_pos << 1)] = $curdata_sec;
        write_sect($curdata_trk, $curdata_sec, \@databuffer);
      }
      if ($c == $EOF) {
        last;
      }
      ungetc($c, $from_file);
    }
    if (++$listentry_pos >= 0x7a) {
      new_sector($newlist_trk, $newlist_sec);
      $list_bytes[1] = $newlist_trk;
      $list_bytes[2] = $newlist_sec;
      $listbuffer = pack "C*", @list_bytes;
      write_sect($curlist_trk, $curlist_sec, $listbuffer);
      $curlist_trk = $newlist_trk;
      $curlist_sec = $newlist_sec;
      for ($i = 0; $i < $BYTES_PER_SECTOR; $i++) {
        $list_bytes[$i] = 0;
      }
      $listentry_pos = 0;
      $list_bytes[5] = (++$list_no * 0x7a) & 0xff;
      $list_bytes[6] = ($list_no * 0x7a) >> 8;
    }
  }

  $list_bytes[1] = $list_bytes[2] = 0;
  $listbuffer = pack "C*", @list_bytes;
  write_sect($curlist_trk, $curlist_sec, $listbuffer);
  write_sect(0x11, 0, $vtocbuffer);
  $dir_entry_data[33] = $new_sectors & 0xff;
  $dir_entry_data[34] = $new_sectors >> 8;
  seek($image_fp, $dir_entry_pos, $SEEK_SET);
  # writing ff first ensures directory is always in a safe state
  print $image_fp 0xff;
  for ($i = 1; $i < 35; $i++) {
    print $image_fp $dir_entry_data[$i];
  }
  seek($image_fp, $dir_entry_pos, $SEEK_SET);
  print $image_fp $dir_entry_data[$0];

  close($from_file);
}

## MAIN

  my $image_name;
  my $a2_name;
  my $basename;
  my $typestr;
  my $i;
  my $bad_vtoc;
  my $in_cmd;
  my $rm_cmd;
  my $ls_hlp;
  my $in_hlp;
  my $out_hlp;
  my $rm_hlp;
  my $command = '';

  $baseaddress = 0x2000;  # default, hi-res page 1
  $rawmode = 0;
  $begun = 0;
  $extfilename = "";
  $a2_name = "";
  $image_name = "";

  $basename = basename($0);
  $basename =~ s/\.pl$//g;

  if (defined $ARGV[0] && $ARGV[0] eq '-h') {
    print $HelpText;
    exit 1;
  }

  if ($basename eq 'a2ls') {
    $image_name = shift;
    if (! defined $image_name) {
      quit(18, "Usage: a2ls <disk_image>\n");
    } else {
      $command = \&a2ls;
    }
  } elsif ($basename eq 'a2out') {
    if (defined $ARGV[0] && $ARGV[0] eq "-r") {
      $rawmode = 1;
      shift;
    }
    $image_name = shift;
    if (! defined $image_name) {
      quit(19, "Usage: a2out [-r] <disk_image> <a2file> [<destination>]\n");
    } else {
      $a2_name = shift;
      if (! defined $image_name) {
        quit(19, "Usage: a2out [-r] <disk_image> <a2file> [<destination>]\n");
      } else {
        $extfilename = shift;
        if (! defined $extfilename) {
          $to_file = \*STDOUT;
        }
        $command = \&a2out;
      }
    }
  } elsif ($basename eq 'a2in') {
    if (defined $ARGV[0] && $ARGV[0] eq "-r") {
      $rawmode = 1;
      shift;
    }
    $typestr = shift;
    if (! defined $typestr) {
      quit(20, "Usage: a2in [-r] <type>[.<hex_addr>] <disk_image> <a2file> [<source>]\n");
    }
    $a2_name = shift;
    if (! defined $a2_name) {
      $extfilename = $a2_name;
    } else {
      $from_file = \*STDIN;
    }
    $image_name = shift;
    if (! defined $image_name) {
      quit(20, "Usage: a2in [-r] <type>[.<hex_addr>] <disk_image> <a2file> [<source>]\n");
    } else {
      if ($typestr =~ /^[Tt]/) {
        $filetype = $FILETYPE_T;
      } elsif ($typestr =~  /^[Ii]/) {
        $filetype = $FILETYPE_I;
      } elsif ($typestr =~  /^[Aa]/) {
        $filetype = $FILETYPE_A;
      } elsif ($typestr =~  /^[Bb]/) {
        $filetype = $FILETYPE_B;
        if ($typestr =~ /,([0-9a-fA-F]+)/) {
          $baseaddress = hex(lc($1));
        }
      } elsif ($typestr =~  /^[Ss]/) {
        $filetype = $FILETYPE_S;
      } elsif ($typestr =~  /^[Rr]/) {
        $filetype = $FILETYPE_R;
      } elsif ($typestr =~  /^[Xx]/) {
        $filetype = $FILETYPE_X;
      } elsif ($typestr =~  /^[Yy]/) {
        $filetype = $FILETYPE_Y;
      } else {
        quit(21, "<type>: one of t,i,a,b,s,r,x,y without -\n");
      }
      $command = \&a2in;
    }
  } elsif ($basename eq 'a2rm') {
    $image_name = shift;
    if (! defined $image_name) {
      quit(24, "Usage: a2rm <disk_image> <a2file>\n");
    } else {
      $a2_name = shift;
      if (! defined $a2_name) {
        quit(24, "Usage: a2rm <disk_image> <a2file>\n");
      } else {
        $command = \&a2rm;
      }
    }
  } else {
    quit(25, "Invoke as a2ls, a2in, a2out, or a2rm.\n");
  }

  if (!open($image_fp, "<$image_name")) {
    print "Error in $image_name\n";
    quit(26, "");
  }

  # prepare source filename by padding blanks
  my @a2_name_bytes = split //, $a2_name;
  $i = 0;
  while ($i < $FILENAME_LENGTH && $a2_name_bytes[$i]) {
    $padded_name[$i] = ord($a2_name_bytes[$i]) & 0x7f;
    $i++;
  }

  while ($i < $FILENAME_LENGTH) {
    $padded_name[$i++] = ord(' ') & 0x7f;
  }

  # get VTOC and check validity
  read_sect(0x11, 0, $vtocbuffer);
  my @vtoc_bytes = unpack "C*", $vtocbuffer;
  $bad_vtoc = 0;
  for ($i = 0; $i < $VTOC_CHK_NO; $i++) {
    $bad_vtoc |= ($vtoc_bytes[$vtoc_chk_offset[$i]] != $vtoc_chk_value[$i]);
  }
  if ($bad_vtoc) {
    quit(27, "Not an Apple DOS 3.3 .dsk image.\n");
  }

  $command->();

  close($image_fp);

  exit 1;

1;

