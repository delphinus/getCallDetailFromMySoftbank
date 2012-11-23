#!/usr/bin/env perl
use 5.12.0;
use utf8;
use Date::Manip;
use Getopt::Long;
use Log::Minimal;
use Path::Class;
use Text::CSV_XS;
use Web::Scraper;
use WWW::Mechanize;

binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';

$|++;

my %opt;
GetOptions(
    'username|u=s' => \$opt{username},
    'password|p=s' => \$opt{password},
);

defined $opt{username} and $opt{password} or die;

my $m = WWW::Mechanize->new;
$m->agent_alias('Windows Mozilla');
my $res = $m->get('https://my.softbank.jp/msb/d/top'); # トップページ
$m->submit_form(
    with_fields => +{
        msn => $opt{username},
        password => $opt{password},
    },
);
$m->follow_link(text => '利用料金を確認する');
$m->submit;
infof($m->uri);
$m->follow_link(text => '通話料明細書');
infof($m->uri);

my $fh = file("$ENV{HOME}/iClouDrive/test.csv")->openw;
binmode $fh => ':encoding(cp932)';
my $csv = Text::CSV_XS->new(+{binary => 1, eol => "\x0D\x0A"});

my @titles = qw!
    発信日時 通話時間 相手先電話番号 オプションサービス
    発信区域 通話料金 割引種別 備考
!;
$csv->print($fh => \@titles);

infof('file prepared');

sub trim { s/^\s+//; s/\s+$//; }

while (1) {
    my $results = scraper {
        process '//ul[@class="navi_view_list"]/li',
        'links[]' => +{
            class => '@class',
            page => scraper {
                process '//span', number => 'TEXT';
            },
            link => scraper {
                process '//a', url => '@href';
            },
        };
        process '//table[@class="contract-info hasthead"]/tbody/tr',
        'rows[]' => scraper {
            process '//td[1]', 月日               => ['TEXT', \&trim];
            process '//td[2]', 時分秒             => ['TEXT', \&trim];
            process '//td[3]', 通話時間           => ['TEXT', \&trim];
            process '//td[4]', 相手先電話番号     => ['TEXT', \&trim];
            process '//td[5]', オプションサービス => ['TEXT', \&trim];
            process '//td[6]', 発信区域           => ['TEXT', \&trim];
            process '//td[7]', 通話料金           => ['TEXT', \&trim];
            process '//td[8]', 割引種別           => ['TEXT', \&trim];
            process '//td[9]', 備考               => ['TEXT', \&trim];
            };
    }->scrape($m->content);

    for my $r (@{$results->{rows}}) {
        $r->{月日} or next;
        $r->{発信日時} = UnixDate($r->{月日} => '%Y/%m/%d')
            . ' ' . $r->{時分秒};
        my ($h, $m, $s, $ss) = split /[.:]/, $r->{通話時間};
        $r->{通話時間} = 3600 * $h + 60 * $m + $s + $ss / 10;
        $csv->print($fh => [@$r{@titles}]);
    }

    infof('data saved');

    my $next_page_link = _get_next_page_link($results->{links});

    if (defined $next_page_link) {
        infof('next link found');
        infof($next_page_link);
        $m->get($next_page_link);
        infof('next link followed');
    } else {
        infof('finished');
        last;
    }
}

sub _get_next_page_link {
    my $links = shift;

    my ($current_page) = map { $_->{page}{number} }
        grep { defined $_->{class} and $_->{class} eq 'current' } @$links;
    $current_page // return;
    my ($next_page_link) = map { $_->{link}{url} }
        grep { defined $_->{page}{number}
            and $_->{page}{number} == $current_page + 1 } @$links;
    $next_page_link and return $next_page_link;
    ($next_page_link) = map { $_->{link}{url} }
        grep { defined $_->{page}{number}
            and $_->{page}{number} eq '>' } @$links;
    return $next_page_link;
}
