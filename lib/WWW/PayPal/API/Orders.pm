package WWW::PayPal::API::Orders;

# ABSTRACT: PayPal Checkout / Orders v2 API

use Moo;
use Carp qw(croak);
use WWW::PayPal::Order;
use namespace::clean;

our $VERSION = '0.001';

=head1 SYNOPSIS

    my $order = $pp->orders->create(
        intent         => 'CAPTURE',
        purchase_units => [{
            amount => { currency_code => 'EUR', value => '42.00' },
        }],
        return_url => 'https://example.com/paypal/return',
        cancel_url => 'https://example.com/paypal/cancel',
    );

    my $same = $pp->orders->get($order->id);
    my $done = $pp->orders->capture($order->id);

=head1 DESCRIPTION

Controller for PayPal's Checkout / Orders v2 API. Dispatches via cached
OpenAPI C<operationId> entries.

=cut

has client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

=attr client

The parent L<WWW::PayPal> client providing HTTP transport.

=cut

has openapi_operations => (
    is      => 'lazy',
    builder => sub {
        # Pre-computed from paypal-rest-api-specifications
        # (openapi/checkout_orders_v2.json). Regenerate manually when the
        # spec changes.
        return {
            'orders.create'  => { method => 'POST',  path => '/v2/checkout/orders' },
            'orders.get'     => { method => 'GET',   path => '/v2/checkout/orders/{id}' },
            'orders.patch'   => { method => 'PATCH', path => '/v2/checkout/orders/{id}' },
            'orders.confirm' => { method => 'POST',  path => '/v2/checkout/orders/{id}/confirm-payment-source' },
            'orders.authorize' => { method => 'POST', path => '/v2/checkout/orders/{id}/authorize' },
            'orders.capture' => { method => 'POST',  path => '/v2/checkout/orders/{id}/capture' },
        };
    },
);

=attr openapi_operations

Pre-computed operation table (C<operationId> → C<{method, path}>).

=cut

with 'WWW::PayPal::Role::OpenAPI';

sub _wrap {
    my ($self, $data) = @_;
    return WWW::PayPal::Order->new(client => $self->client, data => $data);
}

sub create {
    my ($self, %args) = @_;

    croak 'intent required' unless $args{intent};
    croak 'purchase_units required'
        unless ref $args{purchase_units} eq 'ARRAY' && @{$args{purchase_units}};

    my $body = {
        intent         => $args{intent},
        purchase_units => $args{purchase_units},
    };

    # Application context: return/cancel URLs and branding
    my %ctx;
    $ctx{return_url}   = $args{return_url} if $args{return_url};
    $ctx{cancel_url}   = $args{cancel_url} if $args{cancel_url};
    $ctx{brand_name}   = $args{brand_name} if $args{brand_name};
    $ctx{locale}       = $args{locale}     if $args{locale};
    $ctx{user_action}  = $args{user_action} // 'PAY_NOW';
    $ctx{shipping_preference} = $args{shipping_preference}
        if $args{shipping_preference};
    if (%ctx) {
        # PayPal supports both payment_source.paypal.experience_context (new)
        # and application_context (legacy). We use application_context for
        # broad compatibility.
        $body->{application_context} = \%ctx;
    }

    $body->{payer} = $args{payer} if $args{payer};

    my $data = $self->call_operation('orders.create', body => $body);
    return $self->_wrap($data);
}

=method create

    my $order = $pp->orders->create(
        intent         => 'CAPTURE',
        purchase_units => [ ... ],
        return_url     => '...',
        cancel_url     => '...',
    );

Creates an order and returns a L<WWW::PayPal::Order>. The buyer must be
redirected to C<< $order->approve_url >> to approve the payment.

=cut

sub get {
    my ($self, $id) = @_;
    croak 'order id required' unless $id;
    my $data = $self->call_operation('orders.get', path => { id => $id });
    return $self->_wrap($data);
}

=method get

    my $order = $pp->orders->get($id);

Fetches an order by ID.

=cut

sub capture {
    my ($self, $id, %args) = @_;
    croak 'order id required' unless $id;

    my $data = $self->call_operation('orders.capture',
        path => { id => $id },
        body => $args{body} || {},
    );
    return $self->_wrap($data);
}

=method capture

    my $order = $pp->orders->capture($id);

Captures an approved order. Returns the updated L<WWW::PayPal::Order> with a
completed capture attached.

=cut

sub authorize {
    my ($self, $id, %args) = @_;
    croak 'order id required' unless $id;
    my $data = $self->call_operation('orders.authorize',
        path => { id => $id },
        body => $args{body} || {},
    );
    return $self->_wrap($data);
}

=method authorize

    my $order = $pp->orders->authorize($id);

Places an authorization on an approved order (alternative to immediate
capture).

=cut

1;
