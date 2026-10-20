#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;
use FindBin;
use Test::More;

my $cpanfile = File::Spec->catfile( $FindBin::Bin, File::Spec->updir, 'cpanfile' );

plan skip_all => 'cpanfile is not part of the distribution' unless -f $cpanfile;

open my $fh, '<', $cpanfile or die "cannot read $cpanfile: $!";
my %requires;
while ( my $line = <$fh> ) {
    next unless $line =~ /^\s*requires\s+'([^']+)'/;
    $requires{ $1 } = 1;
}
close $fh;

# Every module the library loads at runtime has to be a declared prerequisite.
# Without LWP::Protocol::https a fresh install breaks on the first request,
# and a prerequisite that only the code knows about stays unnoticed otherwise.
for my $module (
    qw(
      Moo
      namespace::clean
      JSON::MaybeXS
      LWP::UserAgent
      LWP::Protocol::https
      HTTP::Request
      URI
      Log::Any
    )
) {
    ok( $requires{$module}, "$module is a declared prerequisite" );
}

done_testing;
