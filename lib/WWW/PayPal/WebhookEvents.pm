package WWW::PayPal::WebhookEvents;

# ABSTRACT: Curated PayPal webhook event-name constants

use strict;
use warnings;
use Exporter qw( import );

our $VERSION = '0.004';

=head1 SYNOPSIS

    use WWW::PayPal::WebhookEvents qw( :all );

    my $webhook = $pp->webhooks->create(
        url         => 'https://example.com/paypal/webhook',
        event_types => [
            CHECKOUT_ORDER_APPROVED,
            PAYMENT_CAPTURE_COMPLETED,
            BILLING_SUBSCRIPTION_ACTIVATED,
            PAYMENT_SALE_COMPLETED,
        ],
    );

    # ...or import a single name:
    use WWW::PayPal::WebhookEvents qw( PAYMENT_CAPTURE_COMPLETED );

=head1 DESCRIPTION

Plain constant module (no Moo) exporting the PayPal webhook event names that
the two flows this distribution targets actually need: one-off purchases
(Orders v2 / capture) and recurring subscriptions (Billing v1), plus the
dispute event that must always reach a human. Each constant is the exact
event-type string PayPal sends and expects in a webhook subscription's
C<event_types>.

Constant names are the event strings with dots turned into underscores and
uppercased, so C<PAYMENT.CAPTURE.COMPLETED> becomes
L</PAYMENT_CAPTURE_COMPLETED>.

Import individual names, or the whole set with the C<:all> tag.

=func CHECKOUT_ORDER_APPROVED

C<CHECKOUT.ORDER.APPROVED> — buyer approved an order; safe to capture
server-side.

=func PAYMENT_CAPTURE_COMPLETED

C<PAYMENT.CAPTURE.COMPLETED> — money received. Grant the one-off entitlement
here, not in the browser return handler.

=func PAYMENT_CAPTURE_DENIED

C<PAYMENT.CAPTURE.DENIED> — a capture was denied (Payments v1). Revoke / never
grant.

=func PAYMENT_CAPTURE_DECLINED

C<PAYMENT.CAPTURE.DECLINED> — a capture was declined (Payments v2, the version
Orders v2 captures emit). Revoke / never grant.

=func PAYMENT_CAPTURE_REFUNDED

C<PAYMENT.CAPTURE.REFUNDED> — a capture was refunded (possibly from the PayPal
web UI, not your code).

=func PAYMENT_CAPTURE_REVERSED

C<PAYMENT.CAPTURE.REVERSED> — money taken back, e.g. a chargeback outcome.

=func BILLING_SUBSCRIPTION_ACTIVATED

C<BILLING.SUBSCRIPTION.ACTIVATED> — start the subscription entitlement.

=func BILLING_SUBSCRIPTION_UPDATED

C<BILLING.SUBSCRIPTION.UPDATED> — plan/quantity change went through.

=func BILLING_SUBSCRIPTION_SUSPENDED

C<BILLING.SUBSCRIPTION.SUSPENDED> — pause the entitlement. Check
C<failed_payments_count> before assuming the user paused voluntarily.

=func BILLING_SUBSCRIPTION_CANCELLED

C<BILLING.SUBSCRIPTION.CANCELLED> — terminal; end the entitlement.

=func BILLING_SUBSCRIPTION_EXPIRED

C<BILLING.SUBSCRIPTION.EXPIRED> — terminal; end the entitlement.

=func BILLING_SUBSCRIPTION_PAYMENT_FAILED

C<BILLING.SUBSCRIPTION.PAYMENT.FAILED> — dunning: warn the user, count attempts.

=func PAYMENT_SALE_COMPLETED

C<PAYMENT.SALE.COMPLETED> — a recurring payment was collected. This, not a
subscription event, is the renewal trigger.

=func CUSTOMER_DISPUTE_CREATED

C<CUSTOMER.DISPUTE.CREATED> — a human must look; freeze automated refunds for
that transaction.

=cut

use constant {
  CHECKOUT_ORDER_APPROVED             => 'CHECKOUT.ORDER.APPROVED',
  PAYMENT_CAPTURE_COMPLETED           => 'PAYMENT.CAPTURE.COMPLETED',
  PAYMENT_CAPTURE_DENIED              => 'PAYMENT.CAPTURE.DENIED',
  PAYMENT_CAPTURE_DECLINED            => 'PAYMENT.CAPTURE.DECLINED',
  PAYMENT_CAPTURE_REFUNDED            => 'PAYMENT.CAPTURE.REFUNDED',
  PAYMENT_CAPTURE_REVERSED            => 'PAYMENT.CAPTURE.REVERSED',
  BILLING_SUBSCRIPTION_ACTIVATED      => 'BILLING.SUBSCRIPTION.ACTIVATED',
  BILLING_SUBSCRIPTION_UPDATED        => 'BILLING.SUBSCRIPTION.UPDATED',
  BILLING_SUBSCRIPTION_SUSPENDED      => 'BILLING.SUBSCRIPTION.SUSPENDED',
  BILLING_SUBSCRIPTION_CANCELLED      => 'BILLING.SUBSCRIPTION.CANCELLED',
  BILLING_SUBSCRIPTION_EXPIRED        => 'BILLING.SUBSCRIPTION.EXPIRED',
  BILLING_SUBSCRIPTION_PAYMENT_FAILED => 'BILLING.SUBSCRIPTION.PAYMENT.FAILED',
  PAYMENT_SALE_COMPLETED              => 'PAYMENT.SALE.COMPLETED',
  CUSTOMER_DISPUTE_CREATED            => 'CUSTOMER.DISPUTE.CREATED',
};

our @EXPORT_OK = qw(
  CHECKOUT_ORDER_APPROVED
  PAYMENT_CAPTURE_COMPLETED
  PAYMENT_CAPTURE_DENIED
  PAYMENT_CAPTURE_DECLINED
  PAYMENT_CAPTURE_REFUNDED
  PAYMENT_CAPTURE_REVERSED
  BILLING_SUBSCRIPTION_ACTIVATED
  BILLING_SUBSCRIPTION_UPDATED
  BILLING_SUBSCRIPTION_SUSPENDED
  BILLING_SUBSCRIPTION_CANCELLED
  BILLING_SUBSCRIPTION_EXPIRED
  BILLING_SUBSCRIPTION_PAYMENT_FAILED
  PAYMENT_SALE_COMPLETED
  CUSTOMER_DISPUTE_CREATED
);

our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

=seealso

=over 4

=item * L<WWW::PayPal::API::Webhooks>

=item * L<https://developer.paypal.com/api/rest/webhooks/event-names/>

=back

=cut

1;
