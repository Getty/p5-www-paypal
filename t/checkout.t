#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use WWW::PayPal;
use WWW::PayPal::API::Orders;

# Offline only: create() is stubbed, nothing reaches PayPal.

my $pp = WWW::PayPal->new( client_id => 'test', secret => 'test', sandbox => 1 );

my %sent;
no warnings 'redefine';
local *WWW::PayPal::API::Orders::create = sub { my ($self, %a) = @_; %sent = %a; return 1 };

my %base = ( return_url => 'https://e.example/r', cancel_url => 'https://e.example/c' );

$pp->orders->checkout( %base, amount => 19.9, currency => 'EUR',
    items => [ { name => 'a', unit_amount => 9.95, quantity => 2 } ] );
my $pu = $sent{purchase_units}[0];
is $pu->{amount}{value}, '19.90', 'EUR amount is a two-decimal string';
is $pu->{amount}{breakdown}{item_total}{value}, '19.90', 'EUR item_total two decimals';
is $pu->{items}[0]{unit_amount}{value}, '9.95', 'EUR unit_amount two decimals';

$pp->orders->checkout( %base, amount => 1000, currency => 'JPY',
    items => [ { name => 'a', unit_amount => 1000, quantity => 1 } ] );
$pu = $sent{purchase_units}[0];
is $pu->{amount}{value}, '1000', 'JPY amount has no decimals';
is $pu->{amount}{breakdown}{item_total}{value}, '1000', 'JPY item_total has no decimals';
is $pu->{items}[0]{unit_amount}{value}, '1000', 'JPY unit_amount has no decimals';

$pp->orders->checkout( %base, amount => '0.00', currency => 'EUR',
    items => [ { name => 'free', unit_amount => 0 } ] );
$pu = $sent{purchase_units}[0];
is $pu->{items}[0]{unit_amount}{value}, '0.00', 'zero-priced item is accepted';
is $pu->{amount}{breakdown}{item_total}{value}, '0.00', 'zero item_total';

eval { $pp->orders->checkout( %base, amount => 1, currency => 'EUR', items => [ { name => 'x' } ] ) };
like $@, qr/item unit_amount required/, 'missing unit_amount still croaks';

# The breakdown is the sum of the rounded item amounts, not of the raw ones:
# PayPal rejects a breakdown that does not add up.
$pp->orders->checkout( %base, amount => '0.25', currency => 'EUR',
    items => [ { name => 'x', unit_amount => '0.125', quantity => 2 } ] );
$pu = $sent{purchase_units}[0];
is $pu->{items}[0]{unit_amount}{value}, '0.12', 'the item amount is rounded on its own';
is $pu->{amount}{breakdown}{item_total}{value}, '0.24',
    'the item total is the sum of the rounded item amounts';

$pp->orders->checkout( %base, amount => 30, currency => 'JPY',
    items => [ { name => 'x', unit_amount => 10.5, quantity => 3 } ] );
$pu = $sent{purchase_units}[0];
is $pu->{items}[0]{unit_amount}{value}, '10', 'the JPY item amount is rounded on its own';
is $pu->{amount}{breakdown}{item_total}{value}, '30',
    'the JPY item total is the sum of the rounded item amounts';

done_testing;
