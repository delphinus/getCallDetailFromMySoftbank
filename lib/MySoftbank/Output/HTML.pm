package MySoftbank::Output::HTML;
use 5.12.0;
use utf8;
use warnings;
use Moose;

with 'MySoftbank::Output::Role::Base';
with 'MySoftbank::Output::Role::File';

use Date::Manip;
use Log::Minimal;
use Text::Xslate;

no Moose; __PACKAGE__->meta->make_immutable;

sub output { my $self = shift; #{{{
    my ($first_day, $last_day) = map {
        UnixDate $self->data->[$_]{date} => '%Y/%m/%d';
    } (0, -1);

    my (%number_to_total_time, %number_to_total_charge);
    for my $d (@{$self->data}) {
        my $n = $d->{phone_number};

        $number_to_total_time{$n} //= +{
            phone_number => $n,
            call_name => $d->{call_name},
            total_time => 0,
        };
        $number_to_total_time{$n}{total_time} += $d->{call_time};

        $number_to_total_charge{$n} //= +{
            phone_number => $n,
            call_name => $d->{call_name},
            total_charge => 0,
        };
        $number_to_total_charge{$n}{total_charge} += $d->{charge};
    }

    my @total_time_per_number = map { $number_to_total_time{$_} }
        sort { $number_to_total_time{$b}{total_time}
                <=> $number_to_total_time{$a}{total_time} }
            keys %number_to_total_time;
    my @total_charge_per_number = map { $number_to_total_charge{$_} }
        sort { $number_to_total_charge{$b}{total_charge}
                <=> $number_to_total_charge{$a}{total_charge} }
            keys %number_to_total_charge;

    my $tx = Text::Xslate->new(
        syntax => 'TTerse',
        module => ['Text::Xslate::Bridge::TT2Like'],
        function => +{
            commify => sub {
                my $text = reverse $_[0];
                $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
                return scalar reverse $text;
            },
        },
    );
    my $tmpl = do { local $/; <DATA>; };
    my $html = $tx->render_string($tmpl, +{
        first_day               => $first_day,
        last_day                => $last_day,
        data                    => $self->data,
        year                    => $self->year,
        month                   => $self->month,
        titles                  => $self->titles,
        columns                 => $self->columns,
        total_time_per_number   => \@total_time_per_number,
        total_charge_per_number => \@total_charge_per_number,
    });

    my $fh = $self->file->openw;
    $fh->binmode(':utf8');
    $fh->print($html);
} #}}}

__DATA__
<!doctype html>
<html>
    <head>
        <meta charset="UTF-8">
        <style>
            body {
                font-family: "Hiragino Kaku Gothic ProN W3", "Hiragino Kaku Gothic Pro W3", "MS PGothic", sans-serif;
                font-size: 10px;
            }
            h1 {
                border-left: 15px goldenrod solid;
                border-bottom: 3px goldenrod solid;
                padding-left: 20px;
                background-color: wheat;
            }
            h2 {
                padding-left: 20px;
                border-bottom: 3px maroon dotted;
            }
            table {
                border-collapse: collapse;
            }
            thead {
                background-color: darkred;
                color: white;
            }
            thead th {
                padding: 0 5px;
            }
            tbody td {
                padding: 0 5px;
            }
            tbody tr {
                background-color: whitesmoke;
            }
            tbody tr:nth-child(2n) {
                background-color: lightgoldenrodyellow;
            }
            .right {
                text-align: right;
                font-family: Menlo, Consolas, "Lucida Console", "Courier New", monospace;
            }
        </style>
    </head>
    <body>
        <h1>[% year %]年[% month %]月版通話明細集計（[% first_day %] 〜 [% last_day %]</h1>
        <h2>ランキング（長く電話した順）上位10位まで</h2>
        <table>
            <thead><tr><th>順位</th><th>電話番号</th><th>名前</th><th>時間（秒）</th><th>時間</tr></thead>
            <tbody>
[%- FOREACH d IN total_time_per_number %]
    [%- LAST IF loop.count > 10 -%]
                <tr>
                    <th>[% loop.count %]</th>
                    <td>[% d.phone_number %]</td>
                    <td>[% d.call_name %]</td>
                    <td class="right">[% d.total_time | format('%.1f') %]</td>
                    <td class="right">
                        [% IF d.total_time >= 3600 %][% d.total_time / 3600 | format('%d') %]時間[% END -%]
                        [%- (d.total_time % 3600) / 60 | format('%02d') %]分
                        [%- d.total_time % 60 | format('%02d') %]秒
                    </td>
                </tr>
[%- END %]
            </tbody>
        </table>
        <h2>ランキング（電話料金の高い順）上位10位まで</h2>
        <table>
            <thead><tr><th>順位</th><th>電話番号</th><th>名前</th><th>電話料金</th></tr></thead>
            <tbody>
[%- FOREACH d IN total_charge_per_number %]
    [%- LAST IF loop.count > 10 -%]
                <tr>
                    <th>[% loop.count %]</th>
                    <td>[% d.phone_number %]</td>
                    <td>[% d.call_name %]</td>
                    <td class="right">&yen; [% d.total_charge | commify %]</td>
                </tr>
[%- END %]
            </tbody>
        </table>
        <h2>全通話一覧</h2>
        <table>
            <thead><tr>
[% FOREACH c IN titles %]
                <th>[% c %]</th>
[% END %]
            </tr></thead>
            <tbody>
[% FOREACH d IN data -%]
                <tr>
    [%- FOREACH c IN columns -%]
                    <td[% IF c == 'call_time' || c == 'charge' %] class="right"[% END %]>
                    [%- IF c == 'charge' %]&yen; [% d.$c | commify %][% ELSE %][% d.$c %][% END %]</td>
    [% END -%]
                </tr>
[%- END %]
            </tbody>
        </table>
    </body>
</html>
