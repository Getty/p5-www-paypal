# WWW-PayPal

[![CPAN Version](https://img.shields.io/cpan/v/WWW-PayPal.svg)](https://metacpan.org/pod/WWW::PayPal)
[![License](https://img.shields.io/cpan/l/WWW-PayPal.svg)](https://metacpan.org/pod/WWW::PayPal)

Perl client for PayPal's REST API (Orders v2 + Payments v2). Designed as a
modern replacement for `Business::PayPal::API::ExpressCheckout` when all you
need is "sell a product": create an order, redirect the buyer to PayPal,
capture on return, and optionally refund later.

## Installation

```bash
cpanm WWW::PayPal
```

## Synopsis

```perl
use WWW::PayPal;

my $pp = WWW::PayPal->new(
    client_id => $ENV{PAYPAL_CLIENT_ID},
    secret    => $ENV{PAYPAL_SECRET},
    sandbox   => 1,                      # default: 0 (live)
);

# Create an order — one-liner Express Checkout replacement
my $order = $pp->orders->checkout(
    amount     => '42.00',
    currency   => 'EUR',
    return_url => 'https://example.com/paypal/return',
    cancel_url => 'https://example.com/paypal/cancel',

    # all optional:
    brand_name      => 'My Shop',
    locale          => 'de-DE',
    invoice_id      => 'INV-2026-0042',
    custom_id       => 'user-123',
    soft_descriptor => 'MYSHOP',
    description     => 'Ticket XYZ',
    items => [
        { name => 'Ticket', quantity => 1, unit_amount => '42.00', sku => 'T1' },
    ],
);

# Redirect the buyer here:
my $approve_url = $order->approve_url;

# After the buyer approves, capture the payment
# (replaces GetExpressCheckoutDetails + DoExpressCheckoutPayment)
my $captured = $pp->orders->capture($order->id);

print $captured->payer_name,  "\n";
print $captured->payer_email, "\n";
print $captured->capture_id,  "\n";
print $captured->fee_in_cent, "\n";

# Refund a capture (replaces RefundTransaction)
my $refund = $pp->payments->refund($captured->capture_id,
    amount => { currency_code => 'EUR', value => '10.00' },
);
```

## PayPal JS SDK (client-side Buttons)

For a Buttons-on-the-page flow (instead of a full-page redirect), drop the
official PayPal JS SDK into your template and let `paypal.Buttons` call back
to your server:

```perl
# in your template (Catalyst / Mojolicious / Template::Toolkit / ...)
[% pp.js_sdk_script_tag(currency => 'EUR') %]
<div id="paypal-button"></div>
<script>
paypal.Buttons({
  createOrder: () => fetch('/paypal/create', {method:'POST'})
    .then(r => r.json()).then(d => d.id),
  onApprove:   d => fetch('/paypal/capture/' + d.orderID, {method:'POST'})
    .then(r => r.json()).then(x => location = '/thanks?o=' + x.id),
}).render('#paypal-button');
</script>
```

Server routes call `$pp->orders->checkout(...)` (returns `{id => ...}`) and
`$pp->orders->capture($id)`. For subscription buttons pass
`intent => 'subscription', vault => 1` to `js_sdk_script_tag`.

## Recurring subscriptions

```perl
# One-time merchant setup (create once, reuse the IDs)
my $product = $pp->products->create(
    name => 'VIP membership', type => 'SERVICE', category => 'SOFTWARE',
);
my $plan = $pp->plans->create_monthly(
    product_id => $product->id,
    name       => 'VIP monthly',
    price      => '9.99',
    currency   => 'EUR',
    trial_days => 7,            # optional free trial
);

# Per-user: create a subscription and redirect the buyer
my $sub = $pp->subscriptions->create(
    plan_id    => $plan->id,
    return_url => 'https://example.com/paypal/sub/return',
    cancel_url => 'https://example.com/paypal/sub/cancel',
    custom_id  => 'user-42',    # your internal reference
);
my $approve_url = $sub->approve_url;

# Lifecycle (once active, PayPal auto-bills on the plan's schedule)
$sub->refresh;
print $sub->status;             # ACTIVE
print $sub->next_billing_time;
$sub->suspend(reason => 'holiday');
$sub->activate(reason => 'back');
$sub->cancel(reason  => 'user quit');
```

## End-to-end demos

Two self-contained Mojolicious::Lite daemons live in `examples/`. Create a
sandbox app at <https://developer.paypal.com>, grab the client ID and
secret, then:

```bash
cpanm Mojolicious

# One-off product purchase (Orders v2)
perl examples/buy_demo.pl \
    --client-id $PAYPAL_CLIENT_ID --secret $PAYPAL_SECRET
# Open http://localhost:5555

# Recurring monthly subscription
perl examples/subscribe_demo.pl \
    --client-id $PAYPAL_CLIENT_ID --secret $PAYPAL_SECRET \
    --price 9.99 --currency EUR
# Open http://localhost:5556
# First run auto-creates a product and a monthly plan and prints their IDs.
# Pass them with --product-id / --plan-id on subsequent runs so you don't
# pollute your account with new objects each time.
```

### OAuth / callback FAQ

The OAuth2 `client_credentials` exchange is **pure server-to-server** — PayPal
never calls back to your host to hand you a token. `return_url` and
`cancel_url` are *browser* redirects, not webhooks, so `http://localhost`
works fine for local testing. Webhooks (async events) are a separate optional
feature and are not required for the buy flow.

## Architecture

- `WWW::PayPal` — Moo client (`client_id`, `secret`, `sandbox`, `base_url`)
- `WWW::PayPal::Role::HTTP` — JSON + OAuth2 token caching
- `WWW::PayPal::Role::OpenAPI` — operationId dispatch backed by pre-computed
  operation tables (inspired by `Langertha::Role::OpenAPI`; no runtime
  YAML/OpenAPI parsing)
- `WWW::PayPal::API::Orders` — Orders v2 (one-off product sales)
- `WWW::PayPal::API::Payments` — Payments v2 (captures, refunds,
  authorizations)
- `WWW::PayPal::API::Products` / `Plans` / `Subscriptions` — Catalogs +
  Billing v1 (recurring subscriptions)
- `WWW::PayPal::Order` / `Capture` / `Refund` / `Product` / `Plan` /
  `Subscription` — entity wrappers exposing the fields commonly needed by
  consumers

## See also

- <https://developer.paypal.com/docs/api/orders/v2/>
- <https://github.com/paypal/paypal-rest-api-specifications>
