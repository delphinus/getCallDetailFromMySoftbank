package MySoftbank::Output;
use 5.12.0;
use utf8;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class qw!File!;

use Module::Load;

extends 'MySoftbank';

enum OutputType => [qw!JSON YAML HTML CSV Excel!];

# 明細データ
has data => (is => 'ro', isa => 'ArrayRef[HashRef]', required => 1);
# 出力形式
has type => (is => 'ro', isa => 'OutputType', required => 1);
# 出力ファイル
has file => (is => 'ro', isa => File, coerce => 1);
# データの年
has year => (is => 'ro', isa => 'Int', required => 1);
# データの月
has month => (is => 'ro', isa => 'Int', required => 1);

__PACKAGE__->meta->make_immutable; no Moose; no Moose::Util::TypeConstraints; 1;

# 出力メソッド
sub output { my $self = shift; #{{{
    my $module_name = 'MySoftbank::Output::' . $self->type;
    load $module_name;
    $module_name->new(
        data  => $self->data,
        file  => $self->file,
        year  => $self->year,
        month => $self->month,
    )->output;
} #}}}
