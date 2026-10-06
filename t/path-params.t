#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use HTTP::Response;
use WWW::PayPal;

# Offline only: a recording user agent stands in for LWP. It answers the
# OAuth2 token request and every API call with canned JSON, so nothing reaches
# PayPal, and keeps the last API request for inspection.

{
    package t::RecordingUA;

    sub new { bless { requests => [] }, shift }

    sub request {
        my ($self, $req) = @_;
        my $res = HTTP::Response->new(200, 'OK', [ 'Content-Type' => 'application/json' ]);
        if ($req->uri->path eq '/v1/oauth2/token') {
            $res->content('{"access_token":"T","expires_in":3600}');
        }
        else {
            push @{ $self->{requests} }, $req;
            $res->content('{}');
        }
        return $res;
    }

    sub count { scalar @{ $_[0]{requests} } }
    sub last  { $_[0]{requests}[-1] }
}

my $ua = t::RecordingUA->new;
my $pp = WWW::PayPal->new(
    client_id => 'test',
    secret    => 'test',
    sandbox   => 1,
    ua        => $ua,
);

# Values a path parameter must survive as ONE segment. Each of them would,
# put into the path as is, change which endpoint the request addresses.
my @hostile = (
    [ 'slash'              => 'A/B' ],
    [ 'query'              => 'A?x=1' ],
    [ 'fragment'           => 'A#frag' ],
    [ 'percent'            => '100%' ],
    [ 'encoded slash'      => 'A%2FB' ],
    [ 'space'              => 'A B' ],
    [ 'backslash'          => 'A\\B' ],
    [ 'semicolon, amp'     => 'A;b=1&c=2' ],
    [ 'leading dot-dot'    => '../captures' ],
    [ 'embedded dot-dot'   => 'A/../B' ],
    [ 'latin-1 character'  => "Gr\x{fc}n" ],
    [ 'wide character'     => "\x{20ac}uro\x{263a}" ],
    [ 'traversal + query'  => 'X/../../payments/captures/CAP1/refund?x=' ],
);

# What one path segment carrying $value has to look like on the wire: the
# value as UTF-8, everything but the unreserved characters percent-encoded.
# Written out here on purpose, independent of the library's own escaping.
sub segment_for {
    my ($value) = @_;
    my $bytes = $value;
    utf8::encode($bytes);
    $bytes =~ s/([^A-Za-z0-9._~-])/sprintf '%%%02X', ord $1/ge;
    return $bytes;
}

# Asserts that $req addresses exactly the endpoint of $template, with $value
# carried in every placeholder segment and nowhere else.
sub endpoint_ok {
    my ($req, $method, $template, $value, $name) = @_;
    my $uri = $req->uri;

    my @want = map { /\A\{[^}]+\}\z/ ? segment_for($value) : $_ }
        split m{/}, $template, -1;
    my @got = split m{/}, $uri->path, -1;

    my $ok = $req->method eq $method
        && !defined $uri->fragment
        && @got == @want
        && !grep { $got[$_] ne $want[$_] } 0 .. $#want;

    ok $ok, $name
        or diag sprintf '%s %s (expected %s %s)',
            $req->method, $uri, $method, join '/', @want;
    return $ok;
}

# ---------------------------------------------------------------------------
# (a) The reported case: the order id of the return URL is browser-controlled.
# ---------------------------------------------------------------------------
{
    my $token = 'X/../../payments/captures/CAP1/refund?x=';
    $pp->orders->capture($token);
    my $req = $ua->last;

    is $req->uri->path,
        '/v2/checkout/orders/X%2F..%2F..%2Fpayments%2Fcaptures%2FCAP1%2Frefund%3Fx%3D/capture',
        'orders->capture: hostile id stays one segment of the capture endpoint';
    is $req->uri->query, undef, 'orders->capture: hostile id opens no query string';
}

# ---------------------------------------------------------------------------
# (b) Every operation of every controller that has a path parameter.
# ---------------------------------------------------------------------------
for my $api (qw( orders payments products plans subscriptions webhooks )) {
    my $ctrl  = $pp->$api;
    my $ops   = $ctrl->openapi_operations;
    my $swept = 0;
    for my $op_id (sort keys %$ops) {
        my $op = $ops->{$op_id};
        my @params = $op->{path} =~ /\{([^}]+)\}/g or next;
        $swept++;

        for my $case (@hostile) {
            my ($label, $value) = @$case;
            my $before = $ua->count;
            $ctrl->call_operation($op_id, path => { map { $_ => $value } @params });
            is $ua->count, $before + 1, "$op_id [$label]: one request sent"
                or next;
            endpoint_ok($ua->last, $op->{method}, $op->{path}, $value,
                "$op_id [$label]: same endpoint, one encoded segment");
            is $ua->last->uri->query, undef, "$op_id [$label]: no query string";
        }
    }
    ok $swept, "$api: swept $swept operations with a path parameter";
}

# ---------------------------------------------------------------------------
# (c) The public methods, so the id really takes the encoded route.
# ---------------------------------------------------------------------------
my @methods = (
    [ orders        => get          => 'GET',    '/v2/checkout/orders/{id}' ],
    [ orders        => capture      => 'POST',   '/v2/checkout/orders/{id}/capture' ],
    [ orders        => authorize    => 'POST',   '/v2/checkout/orders/{id}/authorize' ],
    [ payments      => get_capture  => 'GET',    '/v2/payments/captures/{capture_id}' ],
    [ payments      => refund       => 'POST',   '/v2/payments/captures/{capture_id}/refund' ],
    [ payments      => get_refund   => 'GET',    '/v2/payments/refunds/{refund_id}' ],
    [ products      => get          => 'GET',    '/v1/catalogs/products/{id}' ],
    [ plans         => get          => 'GET',    '/v1/billing/plans/{id}' ],
    [ plans         => activate     => 'POST',   '/v1/billing/plans/{id}/activate' ],
    [ plans         => deactivate   => 'POST',   '/v1/billing/plans/{id}/deactivate' ],
    [ subscriptions => get          => 'GET',    '/v1/billing/subscriptions/{id}' ],
    [ subscriptions => suspend      => 'POST',   '/v1/billing/subscriptions/{id}/suspend' ],
    [ subscriptions => activate     => 'POST',   '/v1/billing/subscriptions/{id}/activate' ],
    [ subscriptions => cancel       => 'POST',   '/v1/billing/subscriptions/{id}/cancel' ],
    [ subscriptions => capture      => 'POST',   '/v1/billing/subscriptions/{id}/capture',
        amount => '9.99', currency => 'EUR', note => 'n' ],
    [ subscriptions => transactions => 'GET',    '/v1/billing/subscriptions/{id}/transactions',
        start_time => '2026-01-01T00:00:00Z', end_time => '2026-02-01T00:00:00Z' ],
    [ webhooks      => get          => 'GET',    '/v1/notifications/webhooks/{id}' ],
    [ webhooks      => delete       => 'DELETE', '/v1/notifications/webhooks/{id}' ],
);

for my $m (@methods) {
    my ($api, $method, $http, $template, @extra) = @$m;
    for my $value ('A/B?x=1#f', "\x{20ac}/..") {
        my $before = $ua->count;
        $pp->$api->$method($value, @extra);
        is $ua->count, $before + 1, "$api->$method: one request sent"
            or next;
        endpoint_ok($ua->last, $http, $template, $value,
            "$api->$method: hostile id stays inside its endpoint");

        # the id must not add to the query either; transactions() has its own
        my %query = $ua->last->uri->query_form;
        is_deeply [ sort keys %query ],
            [ $method eq 'transactions' ? qw( end_time start_time ) : () ],
            "$api->$method: id adds nothing to the query";
    }
}

# ---------------------------------------------------------------------------
# (d) Ordinary PayPal ids are sent exactly as before.
# ---------------------------------------------------------------------------
for my $id (qw( 5O190127TN364715T I-BW452GLLEP1G P-5ML4271244454362WXNWU5NQ PROD-XY.1_2~3 )) {
    is $pp->orders->_resolve_path('/v2/checkout/orders/{id}/capture', { id => $id }),
        '/v2/checkout/orders/'.$id.'/capture', "plain id $id unchanged";
}

# Each placeholder of a path is encoded on its own.
is $pp->orders->_resolve_path('/a/{x}/b/{y}', { x => '1/2', y => '3?4' }),
    '/a/1%2F2/b/3%3F4', 'two placeholders, each one segment';

# ---------------------------------------------------------------------------
# (e) Non-ASCII goes out as UTF-8, however Perl happens to hold the string.
# ---------------------------------------------------------------------------
{
    my $template = '/v1/catalogs/products/{id}';
    my ($narrow, $wide) = ("Gr\x{fc}n") x 2;
    utf8::downgrade($narrow);
    utf8::upgrade($wide);

    is $pp->products->_resolve_path($template, { id => $narrow }),
        '/v1/catalogs/products/Gr%C3%BCn', 'latin-1 held string is sent as UTF-8';
    is $pp->products->_resolve_path($template, { id => $wide }),
        '/v1/catalogs/products/Gr%C3%BCn', 'upgraded string gives the same segment';
    is $pp->products->_resolve_path($template, { id => "\x{20ac}" }),
        '/v1/catalogs/products/%E2%82%AC', 'wide character is sent as UTF-8';
}

# ---------------------------------------------------------------------------
# (f) Values that cannot be one segment under any encoding are refused before
#     anything is sent: '' drops the segment, '.' and '..' are dot segments
#     even when written as %2E.
# ---------------------------------------------------------------------------
for my $value ('', '.', '..') {
    my $before = $ua->count;
    eval { $pp->orders->call_operation('orders.capture', path => { id => $value }, body => {}) };
    like $@, qr/path parameter 'id'/, "path parameter '$value' croaks";
    is $ua->count, $before, "path parameter '$value': nothing sent";
}

{
    my $before = $ua->count;
    eval { $pp->orders->capture('..') };
    like $@, qr/path parameter 'id'/, q{orders->capture('..') croaks};
    is $ua->count, $before, q{orders->capture('..'): nothing sent};
}

done_testing;
