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

our $VERSION = '0.002';

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
refreshed 60 seconds before its PayPal-reported expiry.

The role requires its consumer to provide C<client_id>, C<secret> and
C<base_url>.

=cut

requires 'client_id';
requires 'secret';
requires 'base_url';

has ua => (
    is      => 'lazy',
    builder => sub {
        LWP::UserAgent->new(
            agent   => 'WWW-PayPal/' . $WWW::PayPal::Role::HTTP::VERSION,
            timeout => 30,
        );
    },
);

=attr ua

The L<LWP::UserAgent> instance used for all HTTP traffic.

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
    my $res = $self->ua->request($req);
    unless ($res->is_success) {
        $log->errorf('PayPal OAuth2 failed: %s', $res->status_line);
        croak 'PayPal OAuth2 failed: ' . $res->status_line . ' ' . $res->decoded_content;
    }
    my $data = decode_json($res->decoded_content);
    $self->_access_token($data->{access_token});
    # refresh 60s before expiry to be safe
    $self->_token_expires_at(time + ($data->{expires_in} // 0) - 60);
    return $data->{access_token};
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

    my $req = HTTP::Request->new($method => $uri);
    $req->header(
        Authorization => 'Bearer ' . $self->access_token,
        Accept        => 'application/json',
    );
    for my $k (keys %{$args{headers} || {}}) {
        $req->header($k => $args{headers}{$k});
    }

    if (defined $args{body}) {
        my $ct = $args{content_type} || 'application/json';
        $req->header('Content-Type' => $ct);
        if (ref $args{body}) {
            $req->content(encode_json($args{body}));
        } else {
            $req->content($args{body});
        }
    }

    $log->debugf('PayPal %s %s', $method, $uri);
    my $res = $self->ua->request($req);

    my $body = $res->decoded_content;
    my $data;
    if (length $body && $body =~ /\A\s*[\{\[]/) {
        $data = decode_json($body);
    }

    unless ($res->is_success) {
        my $msg = ref $data eq 'HASH'
            ? ($data->{message} || $data->{error_description} || $data->{error} || $res->status_line)
            : $res->status_line;
        $log->errorf('PayPal API error: %s', $msg);
        croak "PayPal API error ($method $path): $msg";
    }

    return $data;
}

=method request

    my $data = $self->request('POST', '/v2/checkout/orders', body => \%payload);

Low-level request method used by the API controllers. Accepts C<body>,
C<query>, C<headers> and C<content_type> named arguments. Returns the decoded
JSON response; croaks with the PayPal error message on non-2xx.

=cut

=seealso

=over 4

=item * L<WWW::PayPal>

=item * L<WWW::PayPal::Role::OpenAPI>

=item * L<https://developer.paypal.com/api/rest/authentication/>

=back

=cut

1;
