package WWW::PayPal::Role::HTTP;

# ABSTRACT: HTTP + OAuth2 role for the PayPal REST API

use Moo::Role;
use Carp qw(croak);
use JSON::MaybeXS qw(decode_json encode_json);
use HTTP::Request;
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);
use URI;
use Log::Any qw($log);
use WWW::PayPal::Error;

our $VERSION = '0.004';

=head1 SYNOPSIS

    package WWW::PayPal;
    use Moo;

    has client_id => ( is => 'ro' );
    has secret    => ( is => 'ro' );
    has base_url  => ( is => 'ro' );

    with 'WWW::PayPal::Role::HTTP';

    # Now: $self->request(POST => '/v2/checkout/orders', body => \%payload);

=head1 DESCRIPTION

HTTP + OAuth2 client-credentials role consumed by L<WWW::PayPal>. Builds and
executes JSON requests against PayPal's REST API, handling bearer-token
acquisition and caching transparently. The token is cached in memory and
refreshed 60 seconds before its PayPal-reported expiry (five minutes after
fetching if PayPal reports none). A C<401> response discards the cached token
and repeats the request once with a fresh one.

Every failure is thrown as a L<WWW::PayPal::Error> object, which stringifies
to C<PayPal API error (METHOD PATH): message>. This covers non-2xx answers,
unparseable response bodies, transport failures and failed token exchanges
(C<PayPal OAuth2 failed: ...>).

The role requires its consumer to provide C<client_id>, C<secret> and
C<base_url>.

=cut

requires 'client_id';
requires 'secret';
requires 'base_url';

has ua => (
    is      => 'lazy',
    builder => sub {
        # no redirects: the Authorization header carries the bearer token, and
        # a followed redirect would hand it to the redirect target
        LWP::UserAgent->new(
            agent        => 'WWW-PayPal/' . $WWW::PayPal::Role::HTTP::VERSION,
            timeout      => 30,
            max_redirect => 0,
        );
    },
);

=attr ua

The L<LWP::UserAgent> instance used for all HTTP traffic. It follows no
redirect: a 3xx is answered as an error.

=cut

has _access_token => ( is => 'rw' );
has _token_expires_at => ( is => 'rw', default => sub { 0 } );

sub _fetch_token {
    my ($self) = @_;
    croak "client_id required" unless $self->client_id;
    croak "secret required" unless $self->secret;

    my $uri = URI->new($self->base_url . '/v1/oauth2/token');
    my $req = HTTP::Request->new(POST => $uri);
    $req->header(
        Authorization => 'Basic ' . encode_base64($self->client_id . ':' . $self->secret, ''),
        'Content-Type' => 'application/x-www-form-urlencoded',
        Accept         => 'application/json',
    );
    $req->content('grant_type=client_credentials');

    $log->debugf('PayPal OAuth2 token request to %s', $uri);
    my $res  = $self->ua->request($req);
    my $body = $res->decoded_content;
    $body = '' unless defined $body;
    my $data = eval { decode_json($body) };
    undef $data unless ref $data eq 'HASH';

    unless ($res->is_success) {
        $log->errorf('PayPal OAuth2 failed: %s', $res->status_line);
        WWW::PayPal::Error->throw(
            message => 'PayPal OAuth2 failed: ' . $res->status_line . ' ' . $body,
            $self->_error_fields($res, $data, $body),
        );
    }
    unless ($data && defined $data->{access_token}) {
        $log->errorf('PayPal OAuth2 failed: unusable token response');
        WWW::PayPal::Error->throw(
            message => 'PayPal OAuth2 failed: ' . $res->status_line . ' unusable token response ' . $body,
            $self->_error_fields($res, $data, $body),
        );
    }
    $self->_access_token($data->{access_token});
    # refresh 60s before expiry to be safe; without expires_in assume 5 minutes
    $self->_token_expires_at(
        defined $data->{expires_in} ? time + $data->{expires_in} - 60 : time + 300
    );
    return $data->{access_token};
}

sub _error_fields {
    my ($self, $res, $data, $body) = @_;
    my $hash    = ref $data eq 'HASH' ? $data : {};
    my $details = ref $hash->{details} eq 'ARRAY' ? $hash->{details} : [];
    my $first   = ref $details->[0] eq 'HASH' ? $details->[0] : {};
    # LWP answers transport failures itself with a synthetic 500
    my $network = $res->code == 500
        && ( $res->header('Client-Warning') || $res->header('X-Died') ) ? 1 : 0;
    return (
        status     => $res->code,
        name       => $hash->{name} // $hash->{error},
        issue      => $first->{issue},
        details    => $details,
        debug_id   => $hash->{debug_id},
        data       => $data,
        body       => $body,
        is_network => $network,
    );
}

sub access_token {
    my ($self) = @_;
    return $self->_access_token
        if $self->_access_token && time < $self->_token_expires_at;
    return $self->_fetch_token;
}

=method access_token

Returns the current OAuth2 bearer token, fetching a new one from PayPal when
missing or expired.

=cut

sub request {
    my ($self, $method, $path, %args) = @_;

    my $uri = URI->new($self->base_url . $path);
    $uri->query_form($args{query}) if $args{query};

    my ($content, $ct);
    if (defined $args{body}) {
        $ct = $args{content_type} || 'application/json';
        $content = ref $args{body} ? encode_json($args{body}) : $args{body};
    }

    my $retried = 0;
    while (1) {
        my $req = HTTP::Request->new($method => $uri);
        $req->header(
            Authorization => 'Bearer ' . $self->access_token,
            Accept        => 'application/json',
        );
        for my $k (keys %{$args{headers} || {}}) {
            $req->header($k => $args{headers}{$k});
        }
        if (defined $content) {
            $req->header('Content-Type' => $ct);
            $req->content($content);
        }

        $log->debugf('PayPal %s %s', $method, $uri);
        my $res = $self->ua->request($req);

        # A 401 usually means the cached token was revoked or expired early:
        # drop it and retry exactly once with a fresh one.
        if ($res->code == 401 && !$retried++) {
            $log->debugf('PayPal %s %s: 401, refreshing token', $method, $uri);
            $self->_access_token(undef);
            $self->_token_expires_at(0);
            next;
        }

        my $body = $res->decoded_content;
        $body = '' unless defined $body;
        my ($data, $broken);
        if (length $body) {
            # Every non-empty body is decoded. A captive portal, a proxy or a
            # maintenance page answers with HTML, and that must not pass as a
            # success - and it must not stay an undef either.
            $data = eval { decode_json($body) };
            if ($@ || ( ref $data ne 'HASH' && ref $data ne 'ARRAY' )) {
                $broken = 1;
                undef $data;
            }
        }

        if (!$res->is_success || $broken) {
            my $msg;
            if ($broken && $res->is_success) {
                # The call itself succeeded, the answer is what is unusable.
                # The status line would not say that, so say it plainly.
                $msg = 'HTTP ' . $res->code . ': the answer was no JSON';
            }
            else {
                $msg = ref $data eq 'HASH'
                    ? ($data->{message} || $data->{error_description} || $data->{error} || $res->status_line)
                    : $res->status_line;
            }
            $log->errorf('PayPal API error: %s', $msg);
            WWW::PayPal::Error->throw(
                message => $msg,
                method  => $method,
                path    => $path,
                $self->_error_fields($res, $data, $body),
            );
        }

        return $data;
    }
}

=method request

    my $data = $self->request('POST', '/v2/checkout/orders', body => \%payload);

Low-level request method used by the API controllers. Accepts C<body>,
C<query>, C<headers> and C<content_type> named arguments. Returns the decoded
JSON response. On non-2xx, on a body that is not valid JSON, or on a
transport failure it throws a L<WWW::PayPal::Error> (C<status>, C<name>,
C<issue>, C<debug_id>, C<is_network>, ...). A C<401> is retried once with a
fresh token before it is thrown. An empty body is allowed - a C<204> answers
without one.

C<$path> is appended to C<base_url> as given. Values that end up inside it
have to be percent-encoded by the caller;
L<WWW::PayPal::Role::OpenAPI/call_operation> does that for its path
parameters.

=cut

=seealso

=over 4

=item * L<WWW::PayPal>

=item * L<WWW::PayPal::Role::OpenAPI>

=item * L<https://developer.paypal.com/api/rest/authentication/>

=back

=cut

1;
