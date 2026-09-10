package WWW::PayPal::Webhook;

# ABSTRACT: PayPal webhook (endpoint subscription) entity

use Moo;
use namespace::clean;

our $VERSION = '0.003';

=head1 SYNOPSIS

    my $webhook = $pp->webhooks->create(
        url         => 'https://example.com/paypal/webhook',
        event_types => [ 'PAYMENT.CAPTURE.COMPLETED', 'CHECKOUT.ORDER.APPROVED' ],
    );

    print $webhook->id;
    print $webhook->url;
    my @names = $webhook->event_names;   # ('PAYMENT.CAPTURE.COMPLETED', ...)

=head1 DESCRIPTION

Wrapper around a PayPal webhook JSON object — the endpoint subscription that
tells PayPal where to deliver events and which event types to send. This is the
merchant-side registration, not the individual event payloads that arrive at
your receiver; verify those with
L<< $pp->webhooks->verify|WWW::PayPal::API::Webhooks/verify >>.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => ( is => 'rw', required => 1 );

=attr data

Raw decoded JSON for the webhook.

=cut

sub id  { $_[0]->data->{id} }
sub url { $_[0]->data->{url} }

=attr id

Webhook ID (e.g. C<1JE4291016473214C>). Pass this to
L<< verify|WWW::PayPal::API::Webhooks/verify >> and store it per environment —
sandbox and live webhook IDs are not interchangeable.

=attr url

The endpoint URL PayPal delivers events to.

=cut

sub event_names {
    my ($self) = @_;
    return map { $_->{name} } @{ $self->data->{event_types} || [] };
}

=method event_names

    my @names = $webhook->event_names;

The subscribed event-type names, flattened out of PayPal's
C<< event_types => [ { name => ... }, ... ] >> shape.

=cut

=seealso

=over 4

=item * L<WWW::PayPal::API::Webhooks>

=item * L<WWW::PayPal::WebhookEvents>

=back

=cut

1;
