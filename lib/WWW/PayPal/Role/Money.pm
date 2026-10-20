package WWW::PayPal::Role::Money;

# ABSTRACT: Normalisation of money values per currency

use Moo::Role;

our $VERSION = '0.004';

=head1 SYNOPSIS

    package WWW::PayPal::API::Plans;
    use Moo;

    with 'WWW::PayPal::Role::Money';

    my $value = $self->money( $args{price}, $args{currency} );

=head1 DESCRIPTION

Role for the API controllers that send money to PayPal. PayPal takes every
amount as a decimal string whose number of decimals belongs to the currency:
two for most currencies, none for C<HUF>, C<JPY> and C<TWD>. A price sent
unnormalised is rejected (C<DECIMALS_NOT_SUPPORTED>, C<AMOUNT_FORMAT_INVALID>).

=cut

# PayPal rejects decimals for these currencies (DECIMALS_NOT_SUPPORTED).
my %ZERO_DECIMAL = map { $_ => 1 } qw( HUF JPY TWD );

sub money {
    my ( $self, $value, $currency ) = @_;
    return sprintf($ZERO_DECIMAL{ uc($currency // '') } ? '%.0f' : '%.2f', $value);
}

=method money

    my $value = $self->money( '9.99', 'EUR' );    # 9.99
    my $yen   = $self->money( 1000,   'JPY' );    # 1000

Returns the value as a string with the decimals of its currency: two, or none
for C<HUF>, C<JPY> and C<TWD>.

=cut

1;
