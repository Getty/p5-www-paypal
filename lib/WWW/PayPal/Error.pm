package WWW::PayPal::Error;

# ABSTRACT: Exception object thrown for failed PayPal API calls

use Moo;
use Carp qw(croak);
use namespace::clean;
# after namespace::clean on purpose: it would sweep the overload entries
use overload
    '""'     => sub { $_[0]->to_string },
    'bool'   => sub { 1 },
    fallback => 1;

our $VERSION = '0.004';

=head1 SYNOPSIS

    use Scalar::Util qw(blessed);

    my $order = eval { $pp->orders->get($id) };
    if ( my $err = $@ ) {
        if ( blessed $err && $err->isa('WWW::PayPal::Error') ) {
            if ( ( $err->name // '' ) eq 'RESOURCE_NOT_FOUND' ) { ... }
            warn 'retry later' if $err->is_network;
            warn $err->debug_id;
        }
        die $err;    # stringifies to "PayPal API error (GET /v2/...): ..."
    }

=head1 DESCRIPTION

Thrown by L<WWW::PayPal::Role::HTTP> whenever a call to PayPal fails: a
non-2xx response, a response body that is not valid JSON, a transport failure
or a failed OAuth2 token exchange.

The object stringifies to the same message the library used to croak as a
plain string, so C<$@ =~ /PayPal API error \(POST \/v2\/[^)]*\): .../> keeps
working. The string carries no C<at FILE line N> suffix and no trailing
newline. It is always true in boolean context.

=cut

has message => ( is => 'ro', default => sub { 'unknown error' } );

=attr message

Human readable message: PayPal's C<message> (or C<error_description>), falling
back to the HTTP status line.

=cut

has method => ( is => 'ro' );

=attr method

HTTP method of the failed request. Undefined for OAuth2 token failures.

=cut

has path => ( is => 'ro' );

=attr path

Request path of the failed call. Undefined for OAuth2 token failures.

=cut

has status => ( is => 'ro' );

=attr status

HTTP status code, e.g. C<422>. Also C<500> for network failures, where it is
LWP's own synthetic status.

=cut

has name => ( is => 'ro' );

=attr name

PayPal's error name, e.g. C<UNPROCESSABLE_ENTITY> or C<RESOURCE_NOT_FOUND>.
Undefined if the body carried none.

=cut

has issue => ( is => 'ro' );

=attr issue

The C<issue> of the first entry in C<details>, e.g. C<ORDER_ALREADY_CAPTURED>,
or undef.

=cut

has details => ( is => 'ro', default => sub { [] } );

=attr details

ArrayRef of PayPal's C<details> entries. Empty when there are none.

=cut

has debug_id => ( is => 'ro' );

=attr debug_id

PayPal's C<debug_id>, the value to quote to PayPal support. Undef if absent.

=cut

has data => ( is => 'ro' );

=attr data

The decoded response body, or undef if it was missing or not valid JSON.
Undef for a failed OAuth2 token exchange: the token endpoint's answer does
not go into the error.

=cut

has body => ( is => 'ro' );

=attr body

The raw response body as received. Undef for a failed OAuth2 token exchange.

=cut

has is_network => ( is => 'ro', default => sub { 0 } );

=attr is_network

True when no HTTP answer came back from PayPal at all (DNS, connect, TLS,
timeout), as opposed to PayPal answering with an error.

=cut

sub throw {
    my ( $class, %args ) = @_;
    croak $class->new(%args);
}

=method throw

    WWW::PayPal::Error->throw( message => '...', status => 500 );

Constructs the object and throws it.

=cut

sub to_string {
    my ($self) = @_;
    return defined $self->method && defined $self->path
        ? 'PayPal API error (' . $self->method . ' ' . $self->path . '): ' . $self->message
        : $self->message;
}

=method to_string

The string form: C<PayPal API error (METHOD PATH): message> for API calls,
the bare C<message> (C<PayPal OAuth2 failed: ...>) for token failures.

=cut

=seealso

=over 4

=item * L<WWW::PayPal::Role::HTTP>

=back

=cut

1;
