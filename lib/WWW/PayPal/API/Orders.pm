package WWW::PayPal::API::Orders;

# ABSTRACT: PayPal Checkout / Orders v2 API

use Moo;
use Carp qw(croak);
use WWW::PayPal::Order;
use namespace::clean;

our $VERSION = '0.004';

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

In the redirect flow PayPal sends the buyer back to your C<return_url> with
the order id in the C<token> query parameter. That value can be handed to
L</capture> or L</get> as received: an id is always sent as a single,
percent-encoded path segment (see L<WWW::PayPal::Role::OpenAPI>), so a
manipulated C<token> cannot reach a different endpoint - PayPal just does not
know the order.

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
with 'WWW::PayPal::Role::Money';

sub _wrap {
    my ($self, $data) = @_;
    return WWW::PayPal::Order->new(client => $self->client, data => $data);
}

sub checkout {
    my ($self, %args) = @_;

    croak 'amount required'     unless defined $args{amount};
    croak 'currency required'   unless defined $args{currency};
    croak 'return_url required' unless defined $args{return_url};
    croak 'cancel_url required' unless defined $args{cancel_url};

    my $currency = $args{currency};
    my $amount   = $args{amount};

    my $pu = {
        amount => { currency_code => $currency, value => $self->money($amount, $currency) },
    };
    $pu->{description}     = $args{description}     if defined $args{description};
    $pu->{invoice_id}      = $args{invoice_id}      if defined $args{invoice_id};
    $pu->{custom_id}       = $args{custom_id}       if defined $args{custom_id};
    $pu->{soft_descriptor} = $args{soft_descriptor} if defined $args{soft_descriptor};
    $pu->{reference_id}    = $args{reference_id}    if defined $args{reference_id};

    if ($args{items} && @{ $args{items} }) {
        my @items;
        my $item_total = 0;
        for my $i (@{ $args{items} }) {
            my $unit = $i->{unit_amount} // $i->{price};
            croak 'item unit_amount required' unless defined $unit;
            my $qty  = $i->{quantity} // 1;
            my $item_currency = $i->{currency_code} // $currency;
            # The item amount is rounded on its own, the breakdown is the sum
            # of those rounded amounts - PayPal rejects a breakdown that does
            # not add up.
            my $unit_value = $self->money($unit, $item_currency);
            push @items, {
                name        => $i->{name} // croak('item name required'),
                quantity    => "$qty",
                unit_amount => {
                    currency_code => $item_currency,
                    value         => $unit_value,
                },
                (defined $i->{sku}         ? (sku         => $i->{sku})         : ()),
                (defined $i->{description} ? (description => $i->{description}) : ()),
                (defined $i->{category}    ? (category    => $i->{category})    : ()),
            };
            $item_total += $unit_value * $qty;
        }
        $pu->{items} = \@items;
        # PayPal requires a breakdown when items are present
        $pu->{amount}{breakdown} = {
            item_total => {
                currency_code => $currency,
                value         => $self->money($item_total, $currency),
            },
        };
    }

    $pu->{shipping} = $args{shipping} if $args{shipping};

    my %create = (
        intent         => $args{intent} // 'CAPTURE',
        purchase_units => [$pu],
        return_url     => $args{return_url},
        cancel_url     => $args{cancel_url},
    );
    for my $k (qw(brand_name locale user_action shipping_preference payer)) {
        $create{$k} = $args{$k} if defined $args{$k};
    }
    $create{request_id} = $args{request_id} if defined $args{request_id};

    return $self->create(%create);
}

=method checkout

    my $order = $pp->orders->checkout(
        amount     => '9.99',
        currency   => 'EUR',
        return_url => 'https://example.com/paypal/return',
        cancel_url => 'https://example.com/paypal/cancel',

        # optional
        intent              => 'CAPTURE',       # or 'AUTHORIZE'
        request_id          => 'cart-42-try1',  # idempotency (PayPal-Request-Id)
        brand_name          => 'Amiga Event',
        locale              => 'de-DE',
        user_action         => 'PAY_NOW',       # default
        shipping_preference => 'NO_SHIPPING',   # or GET_FROM_FILE / SET_PROVIDED_ADDRESS
        description         => 'Ticket XYZ',
        invoice_id          => 'INV-2026-0042',
        custom_id           => 'user-123',
        soft_descriptor     => 'AMIGAEVENT',
        reference_id        => 'cart-42',
        items => [
            { name => 'Ticket', quantity => 1, unit_amount => '9.99', sku => 'T1' },
        ],
        shipping => {
            name    => { full_name => 'Jane Doe' },
            address => { country_code => 'DE', postal_code => '10115', ... },
        },
    );

    $c->redirect_to($order->approve_url);

High-level convenience wrapper around L</create> — the modern replacement
for the NVP ExpressCheckout flow. Builds the C<purchase_units> and
C<application_context> structures for the common single-item checkout so
callers don't have to.

When C<items> is given, the amount C<breakdown.item_total> is filled in
automatically (PayPal requires it as soon as items are present). That
breakdown holds only C<item_total>, so with C<items> the C<amount> must equal
the item sum; shipping or tax cannot be expressed here (use L</create>). The
C<item_total> is the sum of the rounded item amounts, so it matches the
C<unit_amount> values that are sent.

Every money value (C<amount>, item C<unit_amount>, C<item_total>) is sent as a
string with the decimals of its currency: two, or none for C<HUF>, C<JPY> and
C<TWD>. A C<unit_amount> of C<0> is valid.

For multi-unit orders, multi-seller orders, or anything else outside this
happy path, use L</create> directly.

=cut

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

    my $data = $self->call_operation('orders.create',
        body => $body,
        (defined $args{request_id} ? (request_id => $args{request_id}) : ()),
    );
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

Pass an optional C<request_id> (a deterministic value you choose) to send a
C<PayPal-Request-Id> header — PayPal then replays the original order on a
retry instead of creating a duplicate.

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
        (defined $args{request_id} ? (request_id => $args{request_id}) : ()),
    );
    return $self->_wrap($data);
}

=method capture

    my $order = $pp->orders->capture($id);

Captures an approved order. Returns the updated L<WWW::PayPal::Order> with a
completed capture attached. Accepts an optional C<request_id> for an
idempotent (retry-safe) capture, sent as the C<PayPal-Request-Id> header.

=cut

sub authorize {
    my ($self, $id, %args) = @_;
    croak 'order id required' unless $id;
    my $data = $self->call_operation('orders.authorize',
        path => { id => $id },
        body => $args{body} || {},
        (defined $args{request_id} ? (request_id => $args{request_id}) : ()),
    );
    return $self->_wrap($data);
}

=method authorize

    my $order = $pp->orders->authorize($id);

Places an authorization on an approved order (alternative to immediate
capture).

=cut

1;
