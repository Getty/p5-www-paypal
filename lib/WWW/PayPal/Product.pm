package WWW::PayPal::Product;

# ABSTRACT: PayPal Catalogs Product entity

use Moo;
use namespace::clean;

our $VERSION = '0.002';

=head1 DESCRIPTION

Wrapper around a PayPal catalog product JSON object.

=cut

has _client => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
    init_arg => 'client',
);

has data => ( is => 'rw', required => 1 );

=attr data

Raw decoded JSON for the product.

=cut

sub id          { $_[0]->data->{id} }
sub name        { $_[0]->data->{name} }
sub type        { $_[0]->data->{type} }
sub category    { $_[0]->data->{category} }
sub description { $_[0]->data->{description} }
sub create_time { $_[0]->data->{create_time} }
sub update_time { $_[0]->data->{update_time} }

=attr id

Product ID (e.g. C<PROD-XXX...>). Pass this to
L<WWW::PayPal::API::Plans/create>.

=attr name

=attr type

C<PHYSICAL>, C<DIGITAL>, or C<SERVICE>.

=attr category

PayPal merchant category code, e.g. C<SOFTWARE>.

=attr description

=attr create_time

=attr update_time

=cut

1;
