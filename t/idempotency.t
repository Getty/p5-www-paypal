#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use WWW::PayPal;

# Idempotency plumbing: when a caller supplies request_id, it must reach the
# HTTP layer as a PayPal-Request-Id header; when omitted, no such header is
# added and the request is otherwise unchanged.
#
# This is an offline test: no WWW::PayPal / LWP is exercised. A tiny mock
# client records the %args its request() receives, standing in for the real
# transport. Controllers hold their client weak_ref, so the mock is kept in a
# lexical for the lifetime of the test.

package Test::MockClient {
    sub new { bless { calls => [] }, shift }

    sub request {
        my ($self, $method, $path, %args) = @_;
        push @{ $self->{calls} }, { method => $method, path => $path, args => \%args };
        # Canned decoded-JSON response; enough for the controllers to _wrap().
        return { id => 'MOCK-ID', status => 'CREATED' };
    }

    sub last_call { $_[0]{calls}[-1] }
}

package main;

my $mock = Test::MockClient->new;

# --- Orders->create: request_id forwarded as PayPal-Request-Id header ---
{
    my $orders = WWW::PayPal::API::Orders->new(client => $mock);
    $orders->create(
        intent         => 'CAPTURE',
        purchase_units => [{ amount => { currency_code => 'EUR', value => '1.00' } }],
        request_id     => 'order-abc-123',
    );
    my $c = $mock->last_call;
    is $c->{method}, 'POST',                 'orders.create method POST';
    is $c->{path},   '/v2/checkout/orders',  'orders.create path';
    is ref($c->{args}{headers}), 'HASH',     'headers hashref forwarded';
    is $c->{args}{headers}{'PayPal-Request-Id'}, 'order-abc-123',
        'PayPal-Request-Id header carries request_id (create)';
    ok defined $c->{args}{body}, 'body still forwarded alongside headers';
}

# --- Orders->create: omitted request_id => no header, behavior unchanged ---
{
    my $orders = WWW::PayPal::API::Orders->new(client => $mock);
    $orders->create(
        intent         => 'CAPTURE',
        purchase_units => [{ amount => { currency_code => 'EUR', value => '1.00' } }],
    );
    my $c = $mock->last_call;
    ok !exists $c->{args}{headers},
        'no headers arg forwarded when request_id omitted';
    is $c->{args}{body}{intent}, 'CAPTURE',
        'body unchanged when request_id omitted';
}

# --- Orders->capture: $id positional + request_id named ---
{
    my $orders = WWW::PayPal::API::Orders->new(client => $mock);
    $orders->capture('ORDER-XYZ', request_id => 'cap-1');
    my $c = $mock->last_call;
    is $c->{path}, '/v2/checkout/orders/ORDER-XYZ/capture',
        'capture path param resolved';
    is $c->{args}{headers}{'PayPal-Request-Id'}, 'cap-1',
        'PayPal-Request-Id header carries request_id (capture)';
}

# --- Orders->checkout: request_id threads through the convenience wrapper ---
{
    my $orders = WWW::PayPal::API::Orders->new(client => $mock);
    $orders->checkout(
        amount     => '9.99',
        currency   => 'EUR',
        return_url => 'https://x/r',
        cancel_url => 'https://x/c',
        request_id => 'checkout-1',
    );
    my $c = $mock->last_call;
    is $c->{args}{headers}{'PayPal-Request-Id'}, 'checkout-1',
        'checkout wrapper threads request_id to orders.create';
}

# --- Subscriptions->create: request_id forwarded ---
{
    my $subs = WWW::PayPal::API::Subscriptions->new(client => $mock);
    $subs->create(plan_id => 'P-1', request_id => 'sub-1');
    my $c = $mock->last_call;
    is $c->{path}, '/v1/billing/subscriptions', 'subscriptions.create path';
    is $c->{args}{headers}{'PayPal-Request-Id'}, 'sub-1',
        'PayPal-Request-Id header carries request_id (subscription create)';
}

# --- call_operation merges request_id with a caller-supplied headers hashref ---
{
    my $orders = WWW::PayPal::API::Orders->new(client => $mock);
    $orders->call_operation('orders.create',
        body       => {},
        headers    => { 'X-Custom' => 'keep-me' },
        request_id => 'merge-1',
    );
    my $c = $mock->last_call;
    is $c->{args}{headers}{'X-Custom'}, 'keep-me',
        'pre-existing header preserved';
    is $c->{args}{headers}{'PayPal-Request-Id'}, 'merge-1',
        'request_id merged into existing headers';
}

done_testing;
