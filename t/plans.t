#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use WWW::PayPal;
use WWW::PayPal::API::Plans;

# Offline only: create() is stubbed, nothing reaches PayPal.

my $pp = WWW::PayPal->new( client_id => 'test', secret => 'test', sandbox => 1 );

my %sent;
no warnings 'redefine';
local *WWW::PayPal::API::Plans::create = sub { my ($self, %a) = @_; %sent = %a; return 1 };

# A price goes to PayPal with the decimals of its currency: JPY has none,
# everything else has two.
$pp->plans->create_monthly( product_id => 'P1', name => 'Monthly', price => '9.99', currency => 'JPY' );
is $sent{billing_cycles}[0]{pricing_scheme}{fixed_price}{value}, '10',
    'a JPY price is sent without decimals';
is $sent{billing_cycles}[0]{pricing_scheme}{fixed_price}{currency_code}, 'JPY',
    'the JPY currency code is sent';

$pp->plans->create_monthly( product_id => 'P1', name => 'Monthly', price => 10, currency => 'EUR' );
is $sent{billing_cycles}[0]{pricing_scheme}{fixed_price}{value}, '10.00',
    'a EUR price is sent with two decimals';

# The free trial of a plan is a price of zero and is normalised like one.
$pp->plans->create_monthly( product_id => 'P1', name => 'Monthly', price => 10, currency => 'EUR',
    trial_days => 7 );
is $sent{billing_cycles}[0]{tenure_type}, 'TRIAL', 'the trial cycle comes first';
is $sent{billing_cycles}[0]{pricing_scheme}{fixed_price}{value}, '0.00',
    'a EUR trial price is sent with two decimals';

$pp->plans->create_monthly( product_id => 'P1', name => 'Monthly', price => 10, currency => 'JPY',
    trial_days => 7 );
is $sent{billing_cycles}[0]{pricing_scheme}{fixed_price}{value}, '0',
    'a JPY trial price is sent without decimals';

done_testing;
