package WWW::PayPal;

# ABSTRACT: Perl client for the PayPal REST API

use Moo;
use Carp qw(croak);
use WWW::PayPal::API::Orders;
use WWW::PayPal::API::Payments;
use WWW::PayPal::API::Products;
use WWW::PayPal::API::Plans;
use WWW::PayPal::API::Subscriptions;
use namespace::clean;

our $VERSION = '0.001';

=head1 SYNOPSIS

    use WWW::PayPal;

    my $pp = WWW::PayPal->new(
        client_id => $ENV{PAYPAL_CLIENT_ID},
        secret    => $ENV{PAYPAL_SECRET},
        sandbox   => 1,                    # default: 0 (live)
    );

    # Create an order (replaces SetExpressCheckout)
    my $order = $pp->orders->create(
        intent         => 'CAPTURE',
        purchase_units => [{
            amount => { currency_code => 'EUR', value => '42.00' },
        }],
        return_url => 'https://example.com/paypal/return',
        cancel_url => 'https://example.com/paypal/cancel',
    );

    # Redirect the buyer here:
    my $approve_url = $order->approve_url;

    # After the buyer approves, capture the payment
    # (replaces GetExpressCheckoutDetails + DoExpressCheckoutPayment)
    my $captured = $pp->orders->capture($order->id);

    print $captured->payer_email, "\n";
    print $captured->fee_in_cent, "\n";

    # Refund a capture
    $pp->payments->refund($captured->capture_id,
        amount => { currency_code => 'EUR', value => '10.00' });

    # --- Recurring subscriptions ---

    # One-time merchant setup: product + plan (do this at deploy time)
    my $product = $pp->products->create(
        name => 'VIP membership', type => 'SERVICE', category => 'SOFTWARE',
    );
    my $plan = $pp->plans->create_monthly(
        product_id => $product->id,
        name       => 'VIP monthly',
        price      => '9.99',
        currency   => 'EUR',
    );

    # Per-user: create a subscription, redirect the buyer
    my $sub = $pp->subscriptions->create(
        plan_id    => $plan->id,
        return_url => 'https://example.com/paypal/sub/return',
        cancel_url => 'https://example.com/paypal/sub/cancel',
    );
    my $approve_url = $sub->approve_url;

    # Later: lifecycle
    $sub->refresh;
    $sub->suspend(reason => 'user paused');
    $sub->activate(reason => 'resumed');
    $sub->cancel(reason   => 'user quit');

=head1 DESCRIPTION

L<WWW::PayPal> wraps PayPal's REST API. The initial release covers the
Checkout / Orders v2 flow (one-off product sales, replacing the legacy NVP
ExpressCheckout dance) and the Billing Subscriptions v1 flow (recurring
monthly/yearly payments).

Operation dispatch uses cached OpenAPI operation tables (see
L<WWW::PayPal::Role::OpenAPI>), so no spec parsing happens at runtime.

=cut

has client_id => (
    is      => 'ro',
    default => sub { $ENV{PAYPAL_CLIENT_ID} },
);

=attr client_id

PayPal REST app client ID. Defaults to the C<PAYPAL_CLIENT_ID> environment
variable.

=cut

has secret => (
    is      => 'ro',
    default => sub { $ENV{PAYPAL_SECRET} },
);

=attr secret

PayPal REST app secret. Defaults to the C<PAYPAL_SECRET> environment variable.

=cut

has sandbox => (
    is      => 'ro',
    default => sub { $ENV{PAYPAL_SANDBOX} ? 1 : 0 },
);

=attr sandbox

When true, all requests go to C<api-m.sandbox.paypal.com>. Defaults to the
C<PAYPAL_SANDBOX> environment variable.

=cut

has base_url => (
    is      => 'lazy',
    builder => sub {
        $_[0]->sandbox
            ? 'https://api-m.sandbox.paypal.com'
            : 'https://api-m.paypal.com';
    },
);

=attr base_url

API base URL. Derived from L</sandbox> by default.

=cut

with 'WWW::PayPal::Role::HTTP';

has orders => (
    is      => 'lazy',
    builder => sub { WWW::PayPal::API::Orders->new(client => $_[0]) },
);

=attr orders

Returns a L<WWW::PayPal::API::Orders> controller for the Checkout / Orders v2
API.

=cut

has payments => (
    is      => 'lazy',
    builder => sub { WWW::PayPal::API::Payments->new(client => $_[0]) },
);

=attr payments

Returns a L<WWW::PayPal::API::Payments> controller for captures, refunds and
authorizations.

=cut

has products => (
    is      => 'lazy',
    builder => sub { WWW::PayPal::API::Products->new(client => $_[0]) },
);

=attr products

Returns a L<WWW::PayPal::API::Products> controller for catalog products (the
abstract "what you're selling", referenced by plans).

=cut

has plans => (
    is      => 'lazy',
    builder => sub { WWW::PayPal::API::Plans->new(client => $_[0]) },
);

=attr plans

Returns a L<WWW::PayPal::API::Plans> controller for billing plans (the
recurring-cycle definitions that subscriptions reference).

=cut

has subscriptions => (
    is      => 'lazy',
    builder => sub { WWW::PayPal::API::Subscriptions->new(client => $_[0]) },
);

=attr subscriptions

Returns a L<WWW::PayPal::API::Subscriptions> controller for creating and
managing per-user recurring subscriptions.

=cut

=seealso

=over 4

=item * L<https://developer.paypal.com/docs/api/orders/v2/>

=item * L<https://github.com/paypal/paypal-rest-api-specifications>

=back

=cut

1;
