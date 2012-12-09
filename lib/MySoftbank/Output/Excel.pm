package MySoftbank::Output::Excel;
use 5.12.0;
use utf8;
use warnings;
use Moose;

with 'MySoftbank::Output::Role::Base';
with 'MySoftbank::Output::Role::File';

use Log::Minimal;
use Spreadsheet::WriteExcel;

no Moose; __PACKAGE__->meta->make_immutable;

sub output { my $self = shift; #{{{
    my $book = Spreadsheet::WriteExcel->new($self->file->stringify);
    my $sheet = $book->add_worksheet;

    infof('sheet created');

    my %fmt; # セルのフォーマット
    $fmt{default} = $self->add_format($book, undef,
        font => 'MS PGothic',
        size => 12,
        align => 'left',
        valign => 'vcenter',
        num_format => '0',
        text_wrap => 1,
        border => 1,
    );
    $fmt{header} = $self->add_format($book, $fmt{default},
        bold => 1,
        color => 'white',
        bg_color => 'black',
        align => 'center',
    );
    $fmt{date} = $self->add_format($book, $fmt{default},
        num_format => 'yyyy/mm/dd hh:mm:ss',
    );
    $fmt{num} = $self->add_format($book, $fmt{default},
        num_format => '0.0',
        align => 'right',
    );
    $fmt{int} = $self->add_format($book, $fmt{num},
        num_format => '0',
    );
    $fmt{charge} = $self->add_format($book, $fmt{num},
        num_format => chr(0xa5) . ' #,##0;[red]-#,##0;0',
    );

    my @col_formats = (
        date    => 18.17, # 発信日時
        num     => 9.00,  # 通話時間
        default => 14.67, # 相手先電話番号
        default => 9.33,  # 氏名
        default => 10.67, # オプションサービス
        default => 8.67,  # 発信区域
        charge  => 8.67,  # 通話料金
        default => 11.00, # 割引種別
        default => 4.67,  # 備考
    );

    infof('create start');

    # 書き込み開始
    # タイトル
    $sheet->write(0, $_, $self->titles->[$_], $fmt{header})
        for 0 .. @{$self->titles} - 1;

    # データの各行
    for my $r (1 .. @{$self->data}) {
        my $row_data = $self->data->[$r];
        for my $c (0 .. @{$self->titles} - 1) {
            my ($f, $w) = @col_formats[$c * 2, $c * 2 + 1];
            $sheet->set_column($c, $c, $w);
            $sheet->write($r, $c, $row_data->{$self->columns->[$c]}, $fmt{$f});
        }
    }

    $book->close;
} #}}}

sub add_format { my ($self, $book, $base, %params) = @_; #{{{
    my $fmt = $book->add_format;
    defined $base and $fmt->copy($base);
    $fmt->set_format_properties(%params);

    return $fmt;
} #}}}

# セルの大きさ（Excel 単位）
# Excel 単位とピクセル値には次の関係がある
# Wp = int(12We)   if We <  1
# Wp = int(7We +5) if We >= 1
# Hp = int(4/3He)
sub e_height { $_[1] / 4 * 3 }
sub e_width { ($_[1] - 5) /7 }
