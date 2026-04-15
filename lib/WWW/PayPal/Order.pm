package WWW::PayPal::Order;

# ABSTRACT: PayPal Orders v2 order entity

use Moo;
use Carp qw(croak);
use namespace::clean;

our $VERSION = '0.002';

=head1 SYNOPSIS

    my $order = $pp->orders->create(...);

    print $order->id, "\n";
    print $order->status, "\n";           # CREATED / APPROVED / COMPLETED / ...
    print $order->approve_url, "\n";      # redirect the buyer here

    # After return from PayPal + capture:
    print $order->payer_email, "\n";
    print $order->payer_name,  "\n";
    print $order->capture_id,  "\n";
    print $order->fee_in_cent, "\n";

=head1 DESCRIPTION

Lightweight wrapper around the JSON returned by the PayPal Orders v2 API.
Exposes the fields relevant to the common "sell a product" flow and keeps
the raw data accessible via L</data>.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => (
    is       => 'rw',
    required => 1,
);

=attr data

Raw decoded JSON from PayPal. Writable so L</refresh>/L</capture> can update
it in place.

=cut

sub id     { $_[0]->data->{id} }
sub status { $_[0]->data->{status} }
sub intent { $_[0]->data->{intent} }

=attr id

PayPal order ID.

=attr status

Order status — one of C<CREATED>, C<SAVED>, C<APPROVED>, C<VOIDED>,
C<COMPLETED>, C<PAYER_ACTION_REQUIRED>.

=attr intent

C<CAPTURE> or C<AUTHORIZE>.

=cut

sub _links {
    my ($self) = @_;
    return $self->data->{links} || [];
}

sub link_for {
    my ($self, $rel) = @_;
    for my $l (@{ $self->_links }) {
        return $l->{href} if $l->{rel} && $l->{rel} eq $rel;
    }
    return;
}

=method link_for

    my $url = $order->link_for('approve');

Looks up a HATEOAS link by C<rel>.

=cut

sub approve_url {
    my ($self) = @_;
    # Modern flows return 'payer-action'; legacy returned 'approve'.
    return $self->link_for('payer-action') // $self->link_for('approve');
}

=attr approve_url

The URL the buyer must visit to approve the payment. Returns C<undef> once
the order is captured.

=cut

sub _capture_node {
    my ($self) = @_;
    my $pu = $self->data->{purchase_units} || [];
    return unless @$pu;
    my $captures = $pu->[0]{payments}{captures} || [];
    return $captures->[0];
}

sub capture_id {
    my ($self) = @_;
    my $c = $self->_capture_node or return;
    return $c->{id};
}

=attr capture_id

ID of the first capture attached to this order (after
L<WWW::PayPal::API::Orders/capture>). Pass this to
L<WWW::PayPal::API::Payments/refund>.

=cut

sub fee_in_cent {
    my ($self) = @_;
    my $c = $self->_capture_node or return;
    my $fee = $c->{seller_receivable_breakdown}{paypal_fee}{value} or return;
    # PayPal returns decimal strings like "1.23"
    return int($fee * 100 + 0.5);
}

=attr fee_in_cent

PayPal's fee for the first capture, in cents (rounded).

=cut

sub total {
    my ($self) = @_;
    my $pu = $self->data->{purchase_units} || [];
    return unless @$pu;
    return $pu->[0]{amount}{value};
}

sub currency {
    my ($self) = @_;
    my $pu = $self->data->{purchase_units} || [];
    return unless @$pu;
    return $pu->[0]{amount}{currency_code};
}

=attr total

String amount from the first purchase unit, e.g. C<"42.00">.

=attr currency

Currency code from the first purchase unit, e.g. C<"EUR">.

=cut

sub payer_email {
    my ($self) = @_;
    return $self->data->{payer}{email_address};
}

sub payer_name {
    my ($self) = @_;
    my $n = $self->data->{payer}{name} or return;
    return join(' ', grep { defined && length } $n->{given_name}, $n->{surname});
}

sub payer_id {
    my ($self) = @_;
    return $self->data->{payer}{payer_id};
}

=attr payer_email

Payer's email address (available once approved).

=attr payer_name

Payer's full name (C<given_name> + C<surname>).

=attr payer_id

PayPal-issued Payer ID.

=cut

sub refresh {
    my ($self) = @_;
    my $fresh = $self->_client->orders->get($self->id);
    $self->data($fresh->data);
    return $self;
}

=method refresh

    $order->refresh;

Re-fetches the order from PayPal and updates L</data> in place.

=cut

sub capture {
    my ($self) = @_;
    my $captured = $self->_client->orders->capture($self->id);
    $self->data($captured->data);
    return $self;
}

=method capture

    $order->capture;

Captures the order (buyer must have approved it first) and updates L</data>.

=cut

1;
