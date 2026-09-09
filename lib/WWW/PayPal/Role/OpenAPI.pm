package WWW::PayPal::Role::OpenAPI;

# ABSTRACT: operationId-based dispatch against a cached OpenAPI spec

use Moo::Role;
use Carp qw(croak);
use Log::Any qw($log);
use URI::Escape qw(uri_escape_utf8);

our $VERSION = '0.004';

=head1 SYNOPSIS

    package WWW::PayPal::API::Orders;
    use Moo;

    has client => ( is => 'ro', required => 1, weak_ref => 1 );

    has openapi_operations => (
        is      => 'lazy',
        builder => sub {
            return {
                'orders.create'  => { method => 'POST', path => '/v2/checkout/orders' },
                'orders.capture' => { method => 'POST', path => '/v2/checkout/orders/{id}/capture' },
                # ...
            };
        },
    );

    with 'WWW::PayPal::Role::OpenAPI';

    sub capture {
        my ($self, $id) = @_;
        return $self->call_operation('orders.capture',
            path => { id => $id },
            body => {},
        );
    }

=head1 DESCRIPTION

Role for API controllers that dispatch by OpenAPI C<operationId>. The consumer
ships a pre-computed operation table via L</openapi_operations>, avoiding any
YAML/JSON parsing at runtime. Inspired by L<Langertha::Role::OpenAPI> but
trimmed down: no L<OpenAPI::Modern>, no spec loading, just the cached lookup
table.

Path parameters in curly braces (C<{id}>, C<{capture_id}>, ...) are
substituted from the C<path> argument to L</call_operation>. Each value is
sent as exactly one path segment: it is encoded as UTF-8 and everything
outside C<A-Z a-z 0-9 - . _ ~> is percent-encoded, so a C</>, C<?>, C<#> or
C<%> in an id can never address a different endpoint. Ids may therefore be
passed on as received, including from a request parameter; pass them
B<unencoded> (as character strings), an already percent-encoded value would be
encoded a second time. The empty string, C<.> and C<..> cannot be sent as a
path segment and croak.

Consumers must provide:

=over 4

=item * C<client> - A L<WWW::PayPal> instance (used for HTTP).

=item * C<openapi_operations> - HashRef mapping C<operationId> to
C<{ method, path, content_type? }>.

=back

=cut

requires 'client';
requires 'openapi_operations';

sub get_operation {
    my ($self, $operation_id) = @_;
    my $op = $self->openapi_operations->{$operation_id}
        or croak ref($self) . ": unknown operationId '$operation_id'";
    return $op;
}

=method get_operation

    my $op = $self->get_operation('orders.create');

Returns the operation HashRef (C<method>, C<path>, optional C<content_type>)
for the given C<operationId>.

=cut

# The one place a caller-supplied value becomes part of a request path. Ids
# reach this from outside (the order id of a checkout return URL comes from
# the buyer's browser), so the value must stay one segment whatever it holds.
sub _path_segment {
    my ($self, $name, $value) = @_;
    # No encoding helps for these: '' removes the segment, and '.' / '..' are
    # dot segments to every URL normaliser even when written as %2E.
    croak "path parameter '$name' cannot be empty, '.' or '..'"
        if $value eq '' || $value eq '.' || $value eq '..';
    return uri_escape_utf8($value);
}

sub _resolve_path {
    my ($self, $path, $params) = @_;
    $params ||= {};
    $path =~ s!\{([^}]+)\}!
        defined $params->{$1}
            ? $self->_path_segment($1, $params->{$1})
            : croak "missing path parameter '$1' for $path"
    !ge;
    return $path;
}

sub call_operation {
    my ($self, $operation_id, %args) = @_;
    my $op = $self->get_operation($operation_id);
    my $path = $self->_resolve_path($op->{path}, $args{path});
    $log->debugf('PayPal op %s -> %s %s', $operation_id, $op->{method}, $path);

    # Idempotency: a PayPal-Request-Id header makes create/capture retries
    # replay the original result instead of creating a second object. Merge
    # it into any headers the caller already passed.
    my %headers = %{ $args{headers} || {} };
    $headers{'PayPal-Request-Id'} = $args{request_id}
        if defined $args{request_id};

    return $self->client->request(
        $op->{method},
        $path,
        (defined $args{body}  ? (body  => $args{body})  : ()),
        (defined $args{query} ? (query => $args{query}) : ()),
        (%headers ? (headers => \%headers) : ()),
        (defined $op->{content_type}
            ? (content_type => $op->{content_type}) : ()),
    );
}

=method call_operation

    my $data = $self->call_operation('orders.capture',
        path => { id => $order_id },
        body => {},
    );

Dispatches an OpenAPI operation by C<operationId>, substitutes path
parameters, and returns the decoded JSON response.

The optional C<request_id> argument is forwarded as a C<PayPal-Request-Id>
header for idempotency (retry-safe create/capture); it is merged with any
C<headers> HashRef also passed. When omitted, no such header is sent and the
request is unchanged.

=cut

=seealso

=over 4

=item * L<WWW::PayPal>

=item * L<WWW::PayPal::Role::HTTP>

=item * L<Langertha::Role::OpenAPI> - the caching pattern this role is modeled on

=item * L<https://github.com/paypal/paypal-rest-api-specifications>

=back

=cut

1;
