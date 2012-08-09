# This program is copyright 2012 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# VersionCheck package
# ###########################################################################
{
# Package: Pingback
# Pingback gets and reports program versions to Percona.
package Pingback;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use File::Basename ();
use Data::Dumper ();

sub Dumper {
   local $Data::Dumper::Indent    = 1;
   local $Data::Dumper::Sortkeys  = 1;
   local $Data::Dumper::Quotekeys = 0;

   Data::Dumper::Dumper(@_);
}

local $EVAL_ERROR;
eval {
   require HTTPMicro;
   require VersionCheck;
};

sub ping_for_updates {
   my (%args) = @_;
   my $advice = "";
   my $response = pingback(%args);

   PTDEBUG && _d('Server response:', Dumper($response));
   if ( $response && $response->{success} ) {
      $advice = $response->{content};
      $advice =~ s/\r\n/\n/g; # Normalize linefeeds
   }

   return $advice;
}

sub pingback {
   my (%args) = @_;
   my @required_args = qw(url);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($url) = @args{@required_args};

   # Optional args
   my ($dbh, $ua, $vc) = @args{qw(dbh ua VersionCheck)};

   $ua ||= HTTP::Micro->new( timeout => 5 );
   $vc ||= VersionCheck->new();

   # GET http://upgrade.percona.com, the server will return
   # a plaintext list of items/programs it wants the tool
   # to get, one item per line with the format ITEM;TYPE[;VARS]
   # ITEM is the pretty name of the item/program; TYPE is
   # the type of ITEM that helps the tool determine how to
   # get the item's version; and VARS is optional for certain
   # items/types that need extra hints.
   my $response = $ua->request('GET', $url);
   PTDEBUG && _d('Server response:', Dumper($response));
   return unless $response->{status} == 200;

   # Parse the plaintext server response into a hashref keyed on
   # the items like:
   #    "MySQL" => {
   #      item => "MySQL",
   #      type => "mysql_variables",
   #      vars => ["version", "version_comment"],
   #    }
   my $items = $vc->parse_server_response(
      response => $response->{content}
   );
   return unless scalar keys %$items;

   # Get the versions for those items in another hashref also keyed on
   # the items like:
   #    "MySQL" => "MySQL Community Server 5.1.49-log",
   my $versions = $vc->get_versions(
      items => $items,
      dbh   => $dbh,
   );
   return unless scalar keys %$versions;

   # Join the items and whatever versions are available and re-encode
   # them in same simple plaintext item-per-line protocol, and send
   # it back to Percona.
   my $client_content = encode_client_response(
      items    => $items,
      versions => $versions,
   );

   my $client_response = {
      headers => { "X-Percona-Toolkit-Tool" => File::Basename::basename($0) },
      content => $client_content,
   };

   PTDEBUG && _d('Sending back to the server:', Dumper($response));
   
   return $ua->request('POST', $url, $client_response);
}

sub encode_client_response {
   my (%args) = @_;
   my @required_args = qw(items versions);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($items, $versions) = @args{@required_args};

   # There may not be a version for each item.  For example, the server
   # may have requested the "MySQL" (version) item, but if the tool
   # didn't connect to MySQL, there won't be a $versions->{MySQL}.
   # That's ok; just use what we've got.
   # NOTE: the sort is only need to make testing deterministic.
   my @lines;
   foreach my $item ( sort keys %$items ) {
      next unless exists $versions->{$item};
      push @lines, join(';', $item,$items->{$item}->{type},$versions->{$item});
   }

   my $client_response = join("\n", @lines) . "\n";
   PTDEBUG && _d('Client response:', $client_response);
   return $client_response;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Pingback package
# ###########################################################################
