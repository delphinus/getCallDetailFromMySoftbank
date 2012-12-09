package MySoftbank::Output::YAML;
use 5.12.0;
use utf8;
use warnings;
use Moose;

with 'MySoftbank::Output::Role::Base';

use YAML;

sub output { my $self = shift; #{{{
    print Dump $self->data;
} #}}}


__PACKAGE__->meta->make_immutable; no Moose; 1;
