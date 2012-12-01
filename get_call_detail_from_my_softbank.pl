#!/usr/bin/env perl

=encoding utf-8

=head1 NAME

get_call_detail_from_my_softbank.pl - get stats from My Softbank

=head1 SYNOPSIS

    $ perl get_call_detail_from_my_softbank.pl -u USERNAME -p PASSWORD

=head1 DESCRIPTION

L<My Softbank|https://my.softbank.jp/> にアクセスし、通話履歴を CSV/Excel 形式で
取得したり、HTML 形式で統計情報を得ることが出来ます。

=cut

use 5.12.0;
use utf8;
use warnings;
use Data::Util qw!:check!;
use Date::Manip;
use Getopt::Long qw!:config auto_help!;
use Log::Minimal;
use Path::Class;
use Pod::Usage;
use Web::Scraper;
use WWW::Mechanize;

use FindBin;
use lib "$FindBin::Bin/lib";
use MySoftbank::AddressBook;
use MySoftbank::Output;

binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';

$|++;

__FILE__ ne $0 and die "this is not a module.\n";

my %opt = (
    agent_alias => 'Windows Mozilla', # Web アクセスに使用する UA
    top_url => 'https://my.softbank.jp/msb/d/top', # トップページの URL
    type => 'csv', # 標準では結果を CSV で出力
    dir => $FindBin::Bin, # 標準では結果をスクリプトと同じディレクトリに出力
    verbose => 1,
);

log_setting(); # ログ設定
main(%opt);

exit;

# メインルーチン
sub main { #{{{
    my %opt = @_;

    %opt = get_options(%opt); # コマンドラインオプションを取得

=head1 OPTIONS

=over 4

=item --username,-u

My Softbank にログインするためのユーザー名（電話番号）です。（必須）

=item --password,-p

My Softbank にログインするためのパスワードです。（必須）

=item --ym

明細を取得する対象の年月を C<YYYYMM> 形式で指定します。たとえば、2012 年 11 月な
らば C<201211> となります。

=item --type,-t=json,yaml,csv,excel,html

出力をそれぞれの形式で出力します。デフォルトでは CSV です。

JSON, YAML の場合は標準出力に、その他の場合はファイルに出力します。

ファイル名は C<mysoftbank_detail_YYYYMM> となり、拡張子はそれぞれの形式にあった
ものになります。

=item --vcard=sample.vcf

vcard 形式で出力されたアドレス帳を指定します。これを元に相手先電話番号を登録され
た人名に書き換えます。

=item --verbose=0,1(default),2

進捗メッセージを表示します。C<0> が指定されると一切のメッセージが表示されません。

=back

=cut

    infof('アクセス開始');
    my $m = WWW::Mechanize->new;
    access_to_detail_top($m, %opt); # 明細書のトップ
    my ($data, $ym) = get_detail($m, %opt); # 明細を得る
    output($data, $ym, %opt); # 出力する
    infof('終了しました。');
} #}}}

# コマンドラインオプションを解析する
sub get_options { #{{{
    my %opt = @_;

    my @option_definition = qw!
        username|u=s password|p=s type|t=s ym=i vcard=s verbose=i help|h
    !;
    # オプションの受け取りに失敗するか、-h が指定されたらヘルプを表示
    GetOptions(\%opt, @option_definition) or pod2usage(-verbose => 2);
    ($opt{help} or !$opt{username} or !$opt{password}
            or (defined $opt{ym} and $opt{ym} !~ /^\d{6}$/)
            or (defined $opt{vcard} and !-f $opt{vcard})
            or $opt{type} !~ /^(?:json|yaml|csv|excel|html)$/i
            or $opt{verbose} !~ /^(?:0|1|2)$/)
        and pod2usage(-verbose => 2);

    $Log::Minimal::AUTODUMP = 1;
    $Log::Minimal::LOG_LEVEL = $opt{verbose} == 1 ? 'INFO' :
        $opt{verbose} == 2 ? 'DEBUG' : 'NONE';
    $Log::Minimal::LOG_LEVEL eq 'DEBUG' and $ENV{LM_DEBUG} = 1;

    return %opt;
} #}}}

# 明細書のトップまで行く
sub access_to_detail_top { #{{{
    my ($m, %opt) = @_;

    $m->agent_alias($opt{agent_alias});
    $m->get($opt{top_url});
    debugf($m->uri);
    $m->submit_form( # ログイン
        with_fields => +{
            msn => $opt{username},
            password => $opt{password},
        },
    );
    debugf($m->uri);
    $m->follow_link(text => '利用料金を確認する');
    debugf($m->uri);
    $m->submit;
    debugf($m->uri);
    $m->follow_link(text => '通話料明細書');
    debugf($m->uri);
} #}}}

# 明細を得る
sub get_detail { #{{{
    my ($m, %opt) = @_;

    my %phone_number_to_name = defined $opt{vcard}
        ? MySoftbank::AddressBook->new(file => $opt{vcard})
            ->phone_number_to_name
        : ();
    my (@data, $ym);
    my $current_page_number = 0;
    while (1) {
        my $results = scrape_detail_page($m->content);

        $ym = $results->{ym};
        debugf($ym);

        # 年月が指定され、かつ、トップページがそれと異なった場合
        if (defined $opt{ym} and $opt{ym} ne $ym) {
            # 前月へのリンクがあればそっちへ
            if (defined $results->{prev_month_link}) {
                debugf("prev month link found: $results->{prev_month_link}");
                $m->get($results->{prev_month_link});
                next;
            # なければ終了
            } else {
                die "can't find details of the specified YYYYMM: $opt{ym}\n";
            }
        }

        # データを整形
        for my $r (@{$results->{rows}}) {
            $r->{date} or next;
            $r->{call_date} = UnixDate($r->{date} => '%Y/%m/%d')
                . ' ' . $r->{time};
            my ($h, $m, $s, $ss) = split /[.:]/, $r->{call_time};
            $r->{call_time} = defined $h ? 3600 * $h + 60 * $m + $s + $ss / 10
                : 0;
            (my $number = $r->{phone_number}) =~ s/\D//g;
            $r->{call_name} = $phone_number_to_name{$number} // '';
            push @data, $r;
        }

        debugf('data saved');

        # 次のページへのリンクが見つかったらまだ続ける
        my ($next_page_link, $last_page_number) =
            get_page_link($results->{links});
        infof(sprintf "データを取得中 (%3d / %3d)",
            ++$current_page_number, $last_page_number);
        if (defined $next_page_link) {
            debugf("next page link found: $next_page_link");
            $m->get($next_page_link);
        } else {
            debugf('finished');
            last;
        }
    }

    return (\@data, $ym);
} #}}}

# リンクからページ番号を得る
sub get_page_number {
    ($_) = m!goPaging/(\d+)!;
}

# 前後の空白を削除する
sub trim { s/^\s+//; s/\s+$//; }

# &trim + コンマを除去する
sub delete_comma { &trim; s/,//g; }

# HTML を解析する
sub scrape_detail_page { #{{{
    my $html = shift;

    return scraper {
        process
        '//form[@name="detailsCallsActionForm"]//p[@class="prev"]/span[@class=""]/a',
            prev_month_link => '@href';
        process '//input[@name="billYm"]', ym => '@value';
        process '//ul[@class="navi_view_list"]/li',
        'links[]' => +{
            class => '@class',
            page => scraper {
                process '//a'    , number => ['@href' , \&get_page_number];
                process '//span' , text   => 'TEXT';
            },
            link => scraper { process '//a',    url    => '@href'; },
        };
        process '//table[@class="contract-info hasthead"]/tbody/tr',
        'rows[]' => scraper {
            process '//td[1]', date           => ['TEXT', \&trim];
            process '//td[2]', time           => ['TEXT', \&trim];
            process '//td[3]', call_time      => ['TEXT', \&trim];
            process '//td[4]', phone_number   => ['TEXT', \&trim];
            process '//td[5]', option_service => ['TEXT', \&trim];
            process '//td[6]', call_zone      => ['TEXT', \&trim];
            process '//td[7]', charge         => ['TEXT', \&delete_comma];
            process '//td[8]', discount_type  => ['TEXT', \&trim];
            process '//td[9]', cnote          => ['TEXT', \&trim];
        };
    }->scrape($html);
} #}}}

# 次のページへのリンクを見つける
sub get_page_link { #{{{
    my $links = shift;

    my ($next_page_link, $last_page_number) = ('', 0);

    # 最終ページ
    ($last_page_number) = map { $_->{page}{number} }
        grep { defined $_->{class} and $_->{class} eq 'btn_last_page' } @$links;

    {
        # '現在のページ' を探して、見つからなかったら失敗
        my ($current_page) = map { $_->{page}{text} }
            grep { defined $_->{class} and $_->{class} eq 'current' } @$links;
        debugf($current_page);
        $current_page // last;
        # '現在のページ' に +1 したものを探す
        ($next_page_link) = map { $_->{link}{url} }
            grep { is_integer($_->{page}{number})
                and $_->{page}{number} == $current_page + 1 } @$links;
        debugf($next_page_link);
        $next_page_link and last; # 見つかったら戻る
        # '>' 文字のリンクを探す
        ($next_page_link) = map { $_->{link}{url} }
            grep { is_string($_->{page}{number})
                and $_->{page}{number} eq '>' } @$links;
    }
    debugf([$next_page_link, $last_page_number]);

    return ($next_page_link, $last_page_number);
} #}}}

# 出力する
sub output { #{{{
    my ($data, $ym, %opt) = @_;

    # 拡張子作成
    my $ext = lc $opt{type};
    my $type = uc $opt{type};
    if ($type eq 'EXCEL') {
        $ext =  'xls';
        $type = 'Excel';
    }

    # ファイル名設定
    my $file = dir($opt{dir})->file("mysoftbank_detail_$ym.$ext");
    my $count = 0;
    while (1) {
        if (-f $file) {
            $count++;
            $file = dir($opt{dir})->file("mysoftbank_detail_${ym}_$count.$ext");
        } else {
            last;
        }
    }

    my ($year, $month) = $ym =~ /(\d{4})(\d\d)/;

    # 出力開始
    debugf('output');
    infof("出力ファイル : $file");
    MySoftbank::Output->new(
        data  => $data,
        type  => $type,
        file  => $file,
        year  => $year,
        month => $month,
    )->output;
} #}}}

# ログの設定
sub log_setting { #{{{
    $Log::Minimal::PRINT = sub {
        my ($time, $type, $message, $trace, $raw_message) = @_;
        my ($file, $line) = $trace =~ /(.*) line (.*)/;
        warn sprintf "%s [%s][%s: %d] %s\n",
            $time, $type, $file, $line, $message;
    };
} #}}}
