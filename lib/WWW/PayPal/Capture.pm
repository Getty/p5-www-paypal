package WWW::PayPal::Capture;

# ABSTRACT: PayPal Payments v2 capture entity

use Moo;
use namespace::clean;

our $VERSION = '0.001';

=head1 SYNOPSIS

    my $capture = $pp->payments->get_capture($capture_id);

    print $capture->id,          "\n";
    print $capture->status,      "\n";
    print $capture->amount,      "\n";
    print $capture->currency,    "\n";
    print $capture->fee_in_cent, "\n";

    my $refund = $capture->refund(
        amount => { currency_code => 'EUR', value => '5.00' },
    );

=head1 DESCRIPTION

Wrapper around a PayPal capture JSON object. Captures are what you get back
from L<WWW::PayPal::API::Orders/capture> (attached to the order) and from
L<WWW::PayPal::API::Payments/get_capture>.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => ( is => 'rw', required => 1 );

=attr data

Raw decoded JSON for the capture.

=cut

sub id         { $_[0]->data->{id} }
sub status     { $_[0]->data->{status} }
sub amount     { $_[0]->data->{amount}{value} }
sub currency   { $_[0]->data->{amount}{currency_code} }
sub invoice_id { $_[0]->data->{invoice_id} }

=attr id

Capture ID (use this with L<WWW::PayPal::API::Payments/refund>).

=attr status

Capture status — C<COMPLETED>, C<PENDING>, C<DECLINED>, C<REFUNDED>,
C<PARTIALLY_REFUNDED>, C<FAILED>.

=attr amount

String amount of the capture, e.g. C<"42.00">.

=attr currency

Currency code, e.g. C<"EUR">.

=attr invoice_id

Merchant invoice ID, if one was set when creating the order.

=cut

sub fee_in_cent {
    my ($self) = @_;
    my $fee = $self->data->{seller_receivable_breakdown}{paypal_fee}{value} or return;
    return int($fee * 100 + 0.5);
}

=attr fee_in_cent

PayPal's fee for this capture, in cents (rounded from the decimal string
PayPal returns).

=cut

sub refund {
    my ($self, %args) = @_;
    return $self->_client->payments->refund($self->id, %args);
}

=method refund

    my $refund = $capture->refund(
        amount         => { currency_code => 'EUR', value => '5.00' },
        note_to_payer  => 'Partial refund',
    );

Issues a refund against this capture. Omit C<amount> for a full refund.
Returns a L<WWW::PayPal::Refund>.

=cut

=seealso

=over 4

=item * L<WWW::PayPal::API::Payments>

=item * L<WWW::PayPal::Refund>

=item * L<WWW::PayPal::Order>

=back

=cut

1;
