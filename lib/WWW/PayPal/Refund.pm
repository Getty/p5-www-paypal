package WWW::PayPal::Refund;

# ABSTRACT: PayPal Payments v2 refund entity

use Moo;
use namespace::clean;

our $VERSION = '0.003';

=head1 SYNOPSIS

    my $refund = $pp->payments->refund($capture_id,
        amount => { currency_code => 'EUR', value => '5.00' },
    );

    print $refund->id,       "\n";
    print $refund->status,   "\n";
    print $refund->amount,   "\n";
    print $refund->currency, "\n";

=head1 DESCRIPTION

Wrapper around a PayPal refund JSON object, as returned by
L<WWW::PayPal::API::Payments/refund> and L<WWW::PayPal::API::Payments/get_refund>.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => ( is => 'rw', required => 1 );

=attr data

Raw decoded JSON for the refund.

=cut

sub id       { $_[0]->data->{id} }
sub status   { $_[0]->data->{status} }
sub amount   { $_[0]->data->{amount}{value} }
sub currency { $_[0]->data->{amount}{currency_code} }
sub note     { $_[0]->data->{note_to_payer} }

=attr id

Refund ID.

=attr status

Refund status — C<CANCELLED>, C<PENDING>, C<FAILED>, C<COMPLETED>.

=attr amount

String amount, e.g. C<"5.00">.

=attr currency

Currency code, e.g. C<"EUR">.

=attr note

The C<note_to_payer> that was included with the refund, if any.

=cut

=seealso

=over 4

=item * L<WWW::PayPal::API::Payments>

=item * L<WWW::PayPal::Capture>

=back

=cut

1;
