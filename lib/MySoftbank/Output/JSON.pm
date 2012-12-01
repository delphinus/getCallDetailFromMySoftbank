package MySoftbank::Output::JSON;
use 5.12.0;
use utf8;
use warnings;
use Moose;

with 'MySoftbank::Output::Role::Base';

use JSON;

sub output { my $self = shift; #{{{
    print to_json($self->data);
} #}}}


__PACKAGE__->meta->make_immutable; no Moose; 1;
