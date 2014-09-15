package MySoftbank::AddressBook;
use 5.12.0;
use utf8;
use warnings;
use Moose;
use MooseX::Types::Path::Class qw!File!;

use Encode;
use Text::vCard::Addressbook;

has file => (is => 'ro', isa => File, coerce => 1, required => 1);
has vcards => (is => 'ro', isa => 'ArrayRef', lazy_build => 1);
sub _build_vcards { my $self = shift; #{{{
    my $ab = Text::vCard::Addressbook->new(+{source_file => $self->file});
    return [$ab->vcards];
} #}}}

sub phone_number_to_name { my $self = shift; #{{{
    my %map;
    for my $vcard (@{$self->vcards}) {
        my $fullname = $vcard->fullname;
        my ($moniker) = $vcard->get(+{node_type => 'moniker'});
        my $name = defined $moniker
            ? $moniker->family . ' ' . $moniker->given : $fullname;
        my @phones = $vcard->get(+{node_type => 'phones'});
        for my $p (@phones) {
            defined $p or next;
            (my $number = $p->value) =~ s/\D//g;
            $map{$number} = $name;
        }
    }

    return wantarray ? %map : \%map;
} #}}}

__PACKAGE__->meta->make_immutable; no Moose; 1;
