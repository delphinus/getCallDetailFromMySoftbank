package MySoftbank::Output::Role::File;
use 5.12.0;
use utf8;
use warnings;
use Moose::Role;
use MooseX::Types::Path::Class qw!File!;

has file => (is => 'ro', isa => File, coerce => 1, required => 1);

no Moose::Role; 1;
