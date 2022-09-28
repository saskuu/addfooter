#!/usr/bin/perl -w
use strict;
use utf8;
use Encode;
use MIME::QuotedPrint;
use MIME::Base64;

use FindBin '$Bin';
use lib "$Bin";
our %config;
require "$Bin/addfooter.conf";



no warnings 'utf8';

#sub encode_base64;
sub out;
sub add_footer;
sub save_log;
sub cleanCnt;

######################
# Const
######################
my $SENDMAIL="/usr/sbin/sendmail -G -i @ARGV"; # NEVER NEVER NEVER use "-t" here.
my $RE_BOUNDARY = qr/boundary=\"?([a-zA-Z0-9'\(\)+_,\-.\/:=? ]*)(?<! )\"?/; #'
my $RE_CHARSET = qr/charset=\"?([a-zA-Z0-9+_\-.\/:=? ]*)(?<! )\"?/;
my $TIME = time().sprintf("%03d",int(rand(999)));
my $debug = $config{debug} || 0;
my $full_log = $config{full_log} || 0;
my $full_log_dir = $config{full_log_dir} || '/tmp';

save_log(\@ARGV,'.0') if !$debug;

# regex for headers message
# 1st check allow
# 2nd check deny
# footer inserted if "allow and not deny"
my $allow_filter = $config{allow_filter} || '';
my $deny_filter = $config{deny_filter} || '';
my $block_filter_header = $config{block_filter_header} || '';

my $fl_allow_footer = 0;
my $fl_deny_footer = 0;

my $footer_html = decode('utf8',$config{footer_html});
my $footer_txt = decode('utf8',$config{footer_txt});


my $content_type = '';
my $charset = '';
my $boundary = '';
my $content_transfer_encoding = '';
my $fl_header = 1;
my $fl_add = 0;
my $fl_add_txt = 0;
my $fl_add_html = 0;

my $part_content_type = '';
my $part_charset = '';
my $part_content_transfer_encoding = '';
my $fl_part_header = 0;  # =1 if header reading
my $fl_part_started = 0; # =1 if body reading

my $line='';
my @body = ();
my @message = ();
my @newmessage = ();




{
  binmode(STDIN, ":raw");
  while ($line=<STDIN>) {
    push @message, $line;
  }
  save_log(\@message,'.01') if !$debug;
}

##################################
# parsing message
##################################
foreach $line (@message) {
  my $raw = $line;
  $raw =~ s/[\r|\n]//g;

  $fl_header = 0 if $line=~m/^\r?\n$/;

  if ($fl_header) { # reading header
    $fl_allow_footer = 1 if $allow_filter && ($line =~ /$allow_filter/i);
    $fl_deny_footer = 1 if $deny_filter && ($line =~ /$deny_filter/i);
    exit 0 if $block_filter_header && ($line =~ /$block_filter_header/i);

#print  "$fl_allow_footer/$fl_deny_footer " if $debug;

    if (!$content_type && ($raw =~ /^Content-Type:( |\t)(.*)$/i )) {
      my $s = $2;
      ($content_type) = split(/(;)/, $s);
      $content_type = lc $content_type;
    }

    if ($content_type && ($raw =~ /$RE_CHARSET/i )) {
      $charset = lc $1;
    }

    if (($content_type =~ /multipart/) && ($raw =~ /$RE_BOUNDARY/)) {
      $boundary = "--" . $1;
      $fl_part_header = 1;
    }

    if (!$content_transfer_encoding && ($raw =~ /^Content-Transfer-Encoding:( |\t)(.*)$/i )) {
      my $s = $2;
      $content_transfer_encoding = lc $2;
    }

  } else { # reading body of message
    push @body,$line;
    if ($boundary) { # multipart message
#      if ($raw =~ /^$boundary(|--)$/) {
      if (($raw eq $boundary) || ($raw eq "$boundary--")) {
        if ($fl_part_started) { # end part (start next part). add footer ?
          $line = add_footer($line,$part_content_type,$part_charset,$part_content_transfer_encoding);
        }

        $fl_part_header = 1;
        $fl_part_started = 0;
        $part_content_type = '';
        $part_charset = '';
        $part_content_transfer_encoding = '';
        @body = ();
      }

      if ($fl_part_header) {
        if (!$part_content_type && ($raw =~ /^Content-Type:( |\t)(.*)$/i )) {
          my $s = $2;
          ($part_content_type) = split(/(;)/, $s);
          $part_content_type = lc $part_content_type;
        }

        if ($part_content_type && ($raw =~ /$RE_CHARSET/i )) {
          $part_charset = lc $1;
        }

        if (!$part_content_transfer_encoding && ($raw =~ /^Content-Transfer-Encoding:( |\t)(.*)$/i )) {
          $part_content_transfer_encoding = lc $2;
        }

        if (($line=~m/^\r?\n$/)) { # new line: end header, start body
          $fl_part_header = 0;
          $fl_part_started = 1;
        }
      }

      if ((($part_content_type =~ /^multipart\/alternative$/) || ($part_content_type =~ /^multipart\/related$/))
           && ($raw =~ /$RE_BOUNDARY/)) {
        $boundary = "--" . $1;
        $fl_part_started = 0;
        $fl_part_header = 0;
        $part_content_type = '';
      }


    } else { #single part
    }
  }

  out($line);
}

$line='';
$fl_add = $fl_add_txt || $fl_add_html;
if (!$fl_add) { # end message
  $line = add_footer('',$content_type,$charset,$content_transfer_encoding);
  $fl_add = $fl_add_txt || $fl_add_html;
  out($line);
}

save_log(\@newmessage,'.02'.$fl_add) if (!$debug && $fl_allow_footer && !$fl_deny_footer);

if (!$debug) {
  open (PIPE, " | $SENDMAIL");
#  binmode(PIPE, ":utf8");
  binmode(PIPE, ":raw");
  foreach my $s (@newmessage) {
    print PIPE $s;
  }
} else {
  binmode(STDOUT, ":raw");
  foreach my $s (@newmessage) {
    print $s;
  }
}



exit 0;
#########################################


sub out {
  my ($text) = @_;
#  print PIPE $text;
  push @newmessage, $text;
}

sub add_footer {
  my ($str,$ct,$chs,$cte) = @_;
  if ($fl_allow_footer && !$fl_deny_footer) {
#print "============== $fl_add_txt $fl_add_html $ct =================\n";
    my $add = '';
    my $add_str = '';
    if (!$fl_add_txt && ($ct =~ /text\/plain/)) {
      $add_str = $footer_txt;
      $fl_add_txt = 1;
    } elsif (!$fl_add_html && ($ct =~ /text\/html/)) {
      $add_str = $footer_html;
      $fl_add_html = 1;
    }

    if ($add_str) {
      if ($chs =~ /utf.?8/i) {
#        $add = encode('utf-8', $add_str);
        $add = $add_str;
      } else {
        eval {
          $add = encode($chs, $add_str);
          1;  # ok
        } or do { # error
          $add = $add_str;
        };
      }

#print "=================== FOOTER $chs============\n";
      if ($cte =~ /base64/i) {
        if ($chs =~ /utf.?8/i) {
          $add = encode_base64(encode('utf-8',$add));
        } else {
          $add = encode_base64($add);
        }
      } elsif ($cte =~ /quoted-printable/i) {
        if ($chs =~ /utf.?8/i) {
          $add = encode_qp(encode('utf-8',$add));
        } else {
          eval { $add = encode_qp($add); };
        }
      }

      {
      # check if body has footer and footer is located at the end of body, then do not add footer
        my $body_str = join('', @body);
        my ($lb,$lf,$pos) = (length($body_str), length($add), index($body_str, $add));
        $add = '+' if ($pos>0 && ($lb - $lf - $pos)<$lf);
      }
      $str = "$add\n$str" if $add;
    }
  }
  return $str;
}

# https://metacpan.org/dist/MIME-Base64-Perl/source/lib/MIME/Base64/Perl.pm
sub _encode_base64 ($;$)
{
    if ($] >= 5.006) {
        require bytes;
        if (bytes::length($_[0]) > length($_[0]) ||
            ($] >= 5.008 && $_[0] =~ /[^\0-\xFF]/))
        {
            require Carp;
            Carp::croak("The Base64 encoding is only defined for bytes");
        }
    }

    use integer;

    my $eol = $_[1];
    $eol = "\n" unless defined $eol;

    my $res = pack("u", $_[0]);
    # Remove first character of each line, remove newlines
    $res =~ s/^.//mg;
    $res =~ s/\n//g;

    $res =~ tr|` -_|AA-Za-z0-9+/|;               # `# help emacs
    # fix padding at the end
    my $padding = (3 - length($_[0]) % 3) % 3;
    $res =~ s/.{$padding}$/'=' x $padding/e if $padding;
    # break encoded string into lines of no more than 76 characters each
    if (length $eol) {
        $res =~ s/(.{1,76})/$1$eol/g;
    }
    return $res;
}


# for debug
sub cleanCnt {
  my ($path, $maxitems) = @_;

  $maxitems++;
  my @a=`/bin/ls -t $path | /usr/bin/tail -n +$maxitems`;
  foreach (@a)
  {
    chomp;
    unlink "$path/$_";
  }
}

sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub save_log {
  my ($msg,$sufix) = @_;
  return if !$full_log;
  return if $debug;

  $sufix = '' if !$sufix;
  if (open (FH, '>', "$full_log_dir/".$TIME."$sufix")) {
#    binmode(FH, ":utf8");
    binmode(FH, ":raw");

    foreach my $s (@$msg) {
      print FH $s;
    }
    close FH;
    cleanCnt("$full_log_dir",5000);
  }

}
