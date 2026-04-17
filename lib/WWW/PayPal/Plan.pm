package WWW::PayPal::Plan;

# ABSTRACT: PayPal Billing Plan entity

use Moo;
use namespace::clean;

our $VERSION = '0.003';

=head1 SYNOPSIS

    print $plan->id;
    print $plan->name;
    print $plan->status;          # CREATED / ACTIVE / INACTIVE

    $plan->deactivate;
    $plan->activate;

=head1 DESCRIPTION

Wrapper around a PayPal Billing Plan JSON object.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => ( is => 'rw', required => 1 );

=attr data

Raw decoded JSON for the plan.

=cut

sub id             { $_[0]->data->{id} }
sub product_id     { $_[0]->data->{product_id} }
sub name           { $_[0]->data->{name} }
sub description    { $_[0]->data->{description} }
sub status         { $_[0]->data->{status} }
sub billing_cycles { $_[0]->data->{billing_cycles} }
sub create_time    { $_[0]->data->{create_time} }
sub update_time    { $_[0]->data->{update_time} }

=attr id

Plan ID (e.g. C<P-XXX...>). Pass this to
L<WWW::PayPal::API::Subscriptions/create>.

=attr product_id

=attr name

=attr description

=attr status

C<CREATED>, C<ACTIVE> or C<INACTIVE>.

=attr billing_cycles

ArrayRef of billing cycle definitions (frequency + pricing).

=attr create_time

=attr update_time

=cut

sub activate {
    my ($self) = @_;
    $self->_client->plans->activate($self->id);
    $self->refresh;
    return $self;
}

sub deactivate {
    my ($self) = @_;
    $self->_client->plans->deactivate($self->id);
    $self->refresh;
    return $self;
}

=method activate

=method deactivate

    $plan->activate;
    $plan->deactivate;

Toggles the plan's C<status> and re-fetches.

=cut

sub refresh {
    my ($self) = @_;
    my $fresh = $self->_client->plans->get($self->id);
    $self->data($fresh->data);
    return $self;
}

=method refresh

    $plan->refresh;

=cut

1;
