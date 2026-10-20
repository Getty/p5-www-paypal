#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use HTTP::Response;
use Scalar::Util qw(blessed);
use WWW::PayPal;

# Offline only: a scripted user agent stands in for LWP. Token requests and API
# requests each draw from their own queue of canned responses; every request is
# recorded so the tests can count them and inspect the bearer token.
#
# WWW::PayPal::Error is deliberately not `use`d: the assertions go through
# ->isa, so a lib without the class fails the tests instead of the compile.

{
    package t::ScriptedUA;

    sub new { bless { token => [], api => [], reqs => [], tokreqs => [] }, shift }

    sub request {
        my ($self, $req) = @_;
        my ($queue, $log) = $req->uri->path eq '/v1/oauth2/token'
            ? ($self->{token}, $self->{tokreqs})
            : ($self->{api},   $self->{reqs});
        push @$log, $req;
        my $res = shift @$queue;
        die 'no scripted response left for ' . $req->uri unless $res;
        return $res;
    }
}

sub res {
    my ($code, $msg, $body, %h) = @_;
    my $r = HTTP::Response->new($code, $msg, [ 'Content-Type' => 'application/json', %h ]);
    $r->content($body) if defined $body;
    return $r;
}

sub token {
    my ($tok, $expires) = @_;
    return res(200, 'OK', '{"access_token":"' . $tok . '"'
        . ( defined $expires ? ',"expires_in":' . $expires : '' ) . '}');
}

sub fixture {
    my $ua = t::ScriptedUA->new;
    my $pp = WWW::PayPal->new( client_id => 'test', secret => 'test', sandbox => 1, ua => $ua );
    return ( $pp, $ua );
}

sub caught {
    my ($code) = @_;
    return eval { $code->(); 1 } ? undef : $@;
}

my $declined_msg = 'The requested action could not be performed, semantically incorrect, or failed business validation.';
my $declined = '{"name":"UNPROCESSABLE_ENTITY","message":"' . $declined_msg . '",'
    . '"debug_id":"abc123def456","details":[{"issue":"INSTRUMENT_DECLINED","description":"The instrument presented was either declined by the processor or bank, or it can\'t be used for this payment."}],'
    . '"links":[{"href":"https://developer.paypal.com/docs/api/orders/v2/#error-INSTRUMENT_DECLINED","rel":"information_link"}]}';

# --- 422 with PayPal error body ---------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(422, 'Unprocessable Entity', $declined);

    my $err = caught( sub { $pp->request(POST => '/v2/checkout/orders/ORD1/capture', body => {}) } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), '422: thrown as WWW::PayPal::Error';
    is eval { $err->status }, 422,                    '422: status';
    is eval { $err->name },   'UNPROCESSABLE_ENTITY', '422: name';
    is eval { $err->issue },  'INSTRUMENT_DECLINED',  '422: issue from first detail';
    is ref eval { $err->details }, 'ARRAY',           '422: details is an array';
    is scalar @{ ( eval { $err->details } ) || [] }, 1, '422: one detail';
    is eval { $err->details->[0]{issue} }, 'INSTRUMENT_DECLINED', '422: detail content';
    is eval { $err->debug_id }, 'abc123def456',       '422: debug_id';
    is eval { $err->message }, $declined_msg,         '422: message';
    is eval { $err->method }, 'POST',                 '422: method';
    is eval { $err->path }, '/v2/checkout/orders/ORD1/capture', '422: path';
    is ref eval { $err->data }, 'HASH',               '422: data is decoded body';
    is eval { $err->data->{debug_id} }, 'abc123def456', '422: data content';
    ok eval { !$err->is_network },                    '422: not a network error';
    is eval { $err->body }, $declined,                '422: raw body kept';

    my $str = "$err";
    is $str, 'PayPal API error (POST /v2/checkout/orders/ORD1/capture): ' . $declined_msg,
        '422: stringification';
    unlike $str, qr/ at .* line \d+/, '422: no "at ... line" suffix';
    unlike $str, qr/\n/,              '422: no newline';
    ok( ( $err ? 1 : 0 ), '422: true in boolean context' );

    eval { die $err };
    like $@, qr/PayPal API error \(POST \/v2\/checkout\/orders\/ORD1\/capture\)/,
        '422: $@ matches the legacy string pattern';
    is scalar @{ $ua->{reqs} }, 1, '422: not retried';
}

# --- error body without details ---------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(404, 'Not Found',
        '{"name":"RESOURCE_NOT_FOUND","message":"The specified resource does not exist.","debug_id":"d404"}');
    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/NOPE') } );
    is eval { $err->status }, 404,                  '404: status';
    is eval { $err->name },   'RESOURCE_NOT_FOUND', '404: name';
    is eval { $err->issue },  undef,                '404: no issue without details';
    is_deeply eval { $err->details }, [],           '404: details is an empty arrayref';
}

# --- broken JSON ------------------------------------------------------------
for my $case ( [ 502, 'Bad Gateway' ], [ 400, 'Bad Request' ], [ 200, 'OK' ] ) {
    my ( $code, $msg ) = @$case;
    my $label = 'broken JSON on ' . $code;
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    my $body = '{"name": "oops", "message": ';
    push @{ $ua->{api} }, res($code, $msg, $body);

    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), "$label: Error object, not a raw JSON exception";
    is eval { $err->status }, $code, "$label: status";
    is eval { $err->body },   $body, "$label: raw body";
    is eval { $err->data },   undef, "$label: data undef";
    like "$err", qr/\APayPal API error \(GET \/v2\/checkout\/orders\/X\): /, "$label: stringifies as API error";
}

# --- a 2xx answer that is no JSON at all ------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    my $body = '<html><body>Captive portal login</body></html>';
    push @{ $ua->{api} }, res(200, 'OK', $body);

    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), '200 with an HTML body: Error object';
    is eval { $err->status }, 200,                 '200 with an HTML body: status';
    is eval { $err->method }, 'GET',               '200 with an HTML body: method';
    is eval { $err->path }, '/v2/checkout/orders/X', '200 with an HTML body: path';
    is eval { $err->body }, $body,                 '200 with an HTML body: raw body';
    is eval { $err->data }, undef,                 '200 with an HTML body: data undef';
    is( blessed $err ? "$err" : '', 'PayPal API error (GET /v2/checkout/orders/X): HTTP 200: the answer was no JSON',
        '200 with an HTML body: stringification' );
}

# --- an empty body stays allowed ---------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(204, 'No Content');

    my $err = caught( sub { $pp->request(DELETE => '/v1/notifications/webhooks/WH1') } );
    is $err, undef, '204 without a body: no error';
}

# --- a redirect is not followed ----------------------------------------------
{
    # A redirect must not be followed: the Authorization header carries the
    # bearer token, and it would go to the redirect target with it.
    my $pp = WWW::PayPal->new( client_id => 'test', secret => 'test' );
    is $pp->ua->max_redirect, 0, 'the user agent does not follow redirects';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(302, 'Found', '', Location => 'https://elsewhere.example/orders');

    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), '302: Error object';
    is eval { $err->status }, 302,                  '302: status';
    is eval { $err->method }, 'GET',                '302: method';
    is eval { $err->path }, '/v2/checkout/orders/X', '302: path';
    is( blessed $err ? "$err" : '', 'PayPal API error (GET /v2/checkout/orders/X): 302 Found',
        '302: stringification' );
}

# --- network failure vs. real 500 -------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(500, "Can't connect to api.sandbox.paypal.com:443",
        "Can't connect", 'Client-Warning' => 'Internal response');
    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), 'network failure: Error object';
    ok eval { $err->is_network },  'network failure (Client-Warning): is_network';
    is eval { $err->status }, 500, 'network failure: status 500';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(500, 'Internal Server Error', 'timeout', 'X-Died' => 'read timeout at LWP');
    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok eval { $err->is_network }, 'X-Died: is_network';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} },   res(500, 'Internal Server Error',
        '{"name":"INTERNAL_SERVER_ERROR","message":"An internal service error has occurred.","debug_id":"d500"}');
    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/X') } );
    ok eval { !$err->is_network }, 'real 500 with JSON body: not is_network';
    is eval { $err->name }, 'INTERNAL_SERVER_ERROR', 'real 500: name parsed';
    is eval { $err->message }, 'An internal service error has occurred.', 'real 500: message';
}

# --- 401 retry --------------------------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('OLD', 3600), token('NEW', 3600);
    push @{ $ua->{api} },
        res(401, 'Unauthorized', '{"name":"AUTHENTICATION_FAILURE","message":"Authentication failed."}'),
        res(200, 'OK', '{"id":"ORD1","status":"CREATED"}');

    my $data = eval { $pp->request(GET => '/v2/checkout/orders/ORD1') };
    is_deeply $data, { id => 'ORD1', status => 'CREATED' }, '401 retry: data returned';
    is scalar @{ $ua->{tokreqs} }, 2, '401 retry: token endpoint hit twice';
    is scalar @{ $ua->{reqs} },    2, '401 retry: two API requests';
    is eval { $ua->{reqs}[0]->header('Authorization') }, 'Bearer OLD', '401 retry: first request used the old token';
    is eval { $ua->{reqs}[1]->header('Authorization') }, 'Bearer NEW', '401 retry: second request used the fresh token';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('OLD', 3600), token('NEW', 3600), token('NEVER', 3600);
    my $body = '{"name":"AUTHENTICATION_FAILURE","message":"nope"}';
    push @{ $ua->{api} }, res(401, 'Unauthorized', $body), res(401, 'Unauthorized', $body), res(200, 'OK', '{}');

    my $err = caught( sub { $pp->request(GET => '/v2/checkout/orders/ORD1') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), '401 twice: Error object';
    is eval { $err->status }, 401, '401 twice: status 401';
    is scalar @{ $ua->{reqs} }, 2, '401 twice: exactly two requests, no loop';
    is scalar @{ $ua->{api} },  1, '401 twice: third scripted response untouched';
}

# --- expires_in -------------------------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1');    # no expires_in
    push @{ $ua->{api} }, res(200, 'OK', '{}'), res(200, 'OK', '{}');
    my $t0 = time;
    eval { $pp->request(GET => '/v2/a'); $pp->request(GET => '/v2/b') };
    is scalar @{ $ua->{tokreqs} }, 1, 'no expires_in: token cached, fetched once';
    my $delta = $pp->_token_expires_at - $t0;
    ok $delta >= 299 && $delta <= 302, 'no expires_in: expiry about now+300 (got +' . $delta . ')';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, token('T1', 3600);
    push @{ $ua->{api} }, res(200, 'OK', '{}');
    my $t0 = time;
    eval { $pp->request(GET => '/v2/a') };
    my $delta = $pp->_token_expires_at - $t0;
    ok $delta >= 3539 && $delta <= 3542, 'expires_in 3600: expiry about now+3540 (got +' . $delta . ')';
}

# --- OAuth failure ----------------------------------------------------------
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, res(401, 'Unauthorized',
        '{"error":"invalid_client","error_description":"Client Authentication failed"}');
    my $err = caught( sub { $pp->request(GET => '/v2/a') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), 'OAuth failure: Error object';
    like eval { $err->message }, qr/\APayPal OAuth2 failed:/, 'OAuth failure: message prefix';
    like "$err", qr/\APayPal OAuth2 failed:/, 'OAuth failure: stringification';
    is scalar @{ $ua->{reqs} }, 0, 'OAuth failure: no API request sent';
}
{
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, res(200, 'OK', '{"scope":"x"}');
    my $err = caught( sub { $pp->request(GET => '/v2/a') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), 'OAuth 200 without access_token: Error object';
    like eval { $err->message }, qr/\APayPal OAuth2 failed:/, 'OAuth 200 without access_token: message prefix';
}

# --- the OAuth2 path keeps the answer of the token endpoint out -------------
{
    # The token endpoint may answer with the secret: it must not end up in the
    # error message, in the stringification or in the error fields.
    my $secret = 's3cr3t-e7f1';
    my $body   = '{"error":"invalid_client","error_description":"the secret is ' . $secret . '"}';
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, res(401, 'Unauthorized', $body);

    my $err = caught( sub { $pp->request(GET => '/v2/a') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), 'OAuth failure with a secret: Error object';
    is eval { $err->message }, 'PayPal OAuth2 failed: 401 Unauthorized',
        'OAuth failure: the message names the status line only';
    unlike eval { $err->message }, qr/\Q$secret\E/, 'OAuth failure: no secret in the message';
    unlike eval { $err->message }, qr/\Q$body\E/,   'OAuth failure: no body in the message';
    unlike "$err", qr/\Q$secret\E/,                 'OAuth failure: no secret in the string';
    unlike "$err", qr/\Q$body\E/,                   'OAuth failure: no body in the string';
    is eval { $err->body }, undef,                  'OAuth failure: no raw body in the error';
    is eval { $err->data }, undef,                  'OAuth failure: no decoded body in the error';
    is eval { $err->status }, 401,                  'OAuth failure: status';
    is eval { $err->name }, 'invalid_client',       'OAuth failure: the error code is kept';
}
{
    my $secret = 's3cr3t-3a9c';
    my $body   = '{"scope":"x","secret":"' . $secret . '"}';
    my ($pp, $ua) = fixture();
    push @{ $ua->{token} }, res(200, 'OK', $body);

    my $err = caught( sub { $pp->request(GET => '/v2/a') } );
    ok blessed $err && $err->isa('WWW::PayPal::Error'), 'unusable token response: Error object';
    is eval { $err->message }, 'PayPal OAuth2 failed: 200 OK unusable token response',
        'unusable token response: the message names the status line and the reason';
    unlike eval { $err->message }, qr/\Q$secret\E/, 'unusable token response: no secret in the message';
    unlike eval { $err->message }, qr/\Q$body\E/,   'unusable token response: no body in the message';
    unlike "$err", qr/\Q$secret\E/,                 'unusable token response: no secret in the string';
    is eval { $err->body }, undef,                  'unusable token response: no raw body in the error';
    is eval { $err->data }, undef,                  'unusable token response: no decoded body in the error';
}

done_testing;
