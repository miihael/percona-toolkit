#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 14;

use MySQLStatusWaiter;
use PerconaTest;

my $oktorun = 1;
my @checked = ();
my $slept   = 0;
my @vals    = ();

sub oktorun {
   return $oktorun;
}

sub get_status {
   my ($var) = @_;
   push @checked, $var;
   my $vals = shift @vals;
   if ( $vals ) {
      return $vals->{$var} || 0;
   }
   $oktorun = 0;
   return;
}

sub sleep {
   $slept++;
   return;
}

# #############################################################################
# _parse_spec()
# #############################################################################

throws_ok(
   sub { new MySQLStatusWaiter(
      max_spec => '100',
      get_status => \&get_status,
      sleep      => \&sleep,
      oktorun    => \&oktorun,
   ) },
   qr/Invalid spec/,
   "Validate max_spec"
);

# ############################################################################
# Use initial vals + 20%.
# ############################################################################
@vals = (
   # initial values
   { Threads_connected => 10, },
   { Threads_running   => 5,  },

   # first check, no wait
   { Threads_connected => 1, },
   { Threads_running   => 1, },

   # second check, wait
   { Threads_connected => 12, }, # too high
   { Threads_running   => 6,  }, # too high

   # third check, wait
   { Threads_connected => 12, }, # too high
   { Threads_running   => 5,  },

   # fourth check, wait
   { Threads_connected => 10, },
   { Threads_running   => 6,  }, # too high
   
   # fifth check, no wait
   { Threads_connected => 10, },
   { Threads_running   => 5,  },
);

my $sw = new MySQLStatusWaiter(
   oktorun    => \&oktorun,
   get_status => \&get_status,
   sleep      => \&sleep,
   max_spec   => [qw(Threads_connected Threads_running)],
);

is_deeply(
   $sw->max_values(),
   {
      Threads_connected => int(10 + (10 * 0.20)),
      Threads_running   => int(5  + (5  * 0.20)),
   },
   "Initial values +20%"
);

# first check
@checked = ();
$slept   = 0;
$sw->wait();

is_deeply(
   \@checked,
   [qw(Threads_connected Threads_running)],
   "Checked both vars"
);

is(
   $slept,
   0,
   "Vals not too high, did not sleep"
);

# second through fifth checks
@checked = ();
$slept   = 0;
$sw->wait();

is_deeply(
   \@checked,
   [qw(
      Threads_connected Threads_running
      Threads_connected Threads_running
      Threads_connected Threads_running
      Threads_connected Threads_running
   )],
   "Rechecked all variables"
);

is(
   $slept,
   3,
   "Slept until values low enough"
);

# ############################################################################
# Use static vals.
# ############################################################################
@vals = (
   # first check, no wait
   { Threads_connected => 1, },
   { Threads_running   => 1, },
);

$sw = new MySQLStatusWaiter(
   oktorun    => \&oktorun,
   get_status => \&get_status,
   sleep      => \&sleep,
   max_spec   => [qw(Threads_connected=5 Threads_running=5)],
);

is_deeply(
   $sw->max_values(),
   {
      Threads_connected => 5,
      Threads_running   => 5,
   },
   "Static max values"
);

# first check
@checked = ();
$slept   = 0;
$sw->wait();

is_deeply(
   \@checked,
   [qw(Threads_connected Threads_running)],
   "Checked both vars"
);

is(
   $slept,
   0,
   "Vals not too high, did not sleep"
);

# ############################################################################
# No spec, no wait.
# ############################################################################
@vals = (
   # first check, no wait
   { Threads_connected => 1, },
   { Threads_running   => 1, },
);

$sw = new MySQLStatusWaiter(
   oktorun    => \&oktorun,
   get_status => \&get_status,
   sleep      => \&sleep,
   max_spec   => [],
);

is(
   $sw->max_values(),
   undef,
   "No spec, no max values"
);

# first check
@checked = ();
$slept   = 0;
$sw->wait();

is_deeply(
   \@checked,
   [],
   "No spec, no vars checked"
);

is(
   $slept,
   0,
   "No spec, no sleep"
);

# ############################################################################
# Critical thresholds (with static vals).
# ############################################################################
@vals = (
   # first check, no wait
   { Threads_running => 1, },
   { Threads_running => 9, },
);

$sw = new MySQLStatusWaiter(
   oktorun       => \&oktorun,
   get_status    => \&get_status,
   sleep         => \&sleep,
   max_spec      => [qw(Threads_running=4)],
   critical_spec => [qw(Threads_running=8)],

);

@checked = ();
$slept   = 0;
$sw->wait();

is(
   $slept,
   0,
   "Vals not critical, did not sleep"
);

throws_ok(
   sub { $sw->wait(); },
   qr/Threads_running=9 exceeds its critical threshold 8/,
   "Die on critical threshold"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $sw->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
