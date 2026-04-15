package WWW::PayPal::Role::OpenAPI;

# ABSTRACT: operationId-based dispatch against a cached OpenAPI spec

use Moo::Role;
use Carp qw(croak);
use Log::Any qw($log);

our $VERSION = '0.001';

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
substituted from the C<path> argument to L</call_operation>.

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

sub _resolve_path {
    my ($self, $path, $params) = @_;
    $params ||= {};
    $path =~ s!\{([^}]+)\}!
        defined $params->{$1}
            ? $params->{$1}
            : croak "missing path parameter '$1' for $path"
    !ge;
    return $path;
}

sub call_operation {
    my ($self, $operation_id, %args) = @_;
    my $op = $self->get_operation($operation_id);
    my $path = $self->_resolve_path($op->{path}, $args{path});
    $log->debugf('PayPal op %s -> %s %s', $operation_id, $op->{method}, $path);
    return $self->client->request(
        $op->{method},
        $path,
        (defined $args{body}  ? (body  => $args{body})  : ()),
        (defined $args{query} ? (query => $args{query}) : ()),
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
