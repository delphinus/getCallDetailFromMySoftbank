package MySoftbank::Output::CSV;
use 5.12.0;
use utf8;
use warnings;
use Moose;

use Text::CSV_XS;

with 'MySoftbank::Output::Role::Base';
with 'MySoftbank::Output::Role::File';

sub output { my $self = shift; #{{{
    my $csv = Text::CSV_XS->new(+{binary => 1, eol => "\x0D\x0A"});
    my $fh = $self->file->openw;
    binmode $fh => ':encoding(cp932)';
    $csv->print($fh => $self->titles);
    $csv->print($fh => [@$_{@{$self->columns}}]) for @{$self->data};
    $fh->close;
} #}}}

__PACKAGE__->meta->make_immutable; no Moose; 1;
