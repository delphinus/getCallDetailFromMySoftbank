package MySoftbank::CallDetail;
use 5.12.0;
use utf8;
use warnings;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class qw!File Dir!;
use MooseX::Types::URI qw!Uri!;

extends 'MySoftbank';

use MySoftbank::AddressBook;
use MySoftbank::CallDetail::Filter::Trim;
use MySoftbank::CallDetail::Filter::PageNumber;
use MySoftbank::CallDetail::Filter::DeleteComma;
use MySoftbank::Output;

use Data::Util qw!:check!;
use Date::Manip;
use FindBin;
use Log::Minimal;
use Web::Scraper;
use WWW::Mechanize;

subtype YM
    => as Int
    => where { /\d{6}/; };

has m => (is => 'ro', isa => 'WWW::Mechanize', default => sub {
    # user-agent for iPad
    return WWW::Mechanize->new(agent => 'Mozilla/5.0 (iPad; CPU iPhone OS 7_0 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11A465 Safari/9537.53');
} );

has agent_alias => (is => 'ro', isa => 'Str', default => 'Windows Mozilla');
has top_url => (is => 'ro', isa => Uri, coerce => 1,
    default => 'https://my.softbank.jp/msb/d/top');
has output_type => (is => 'ro', isa => enum([qw!json yaml csv excel html!]),
    default => 'csv');
has dir => (is => 'ro', isa => Dir, coerce => 1, default => $FindBin::Bin);
has verbose => (is => 'ro', isa => 'Int', default => 1);

has username => (is => 'ro', isa => 'Str', required => 1);
has password => (is => 'ro', isa => 'Str', required => 1);

has ym => (is => 'ro', isa => 'YM');
has vcard => (is => 'ro', isa => File, coerce => 1);

__PACKAGE__->meta->make_immutable; no Moose;

# 明細書のトップまで行く
sub access_to_detail_top { my $self = shift; #{{{
    $self->m->agent_alias($self->agent_alias);
    $self->m->get($self->top_url);
    debugf($self->m->uri);
    $self->m->submit_form( # ログイン
        form_id => 'authActionForm',
        button => 'doCasisLogin',
    );
    debugf($self->m->uri);
    $self->m->submit_form( # ログイン
        with_fields => +{
            telnum => $self->username,
            password => $self->password,
        },
    );
    debugf($self->m->uri);
    $self->m->follow_link(text => '料金案内');
    debugf($self->m->uri);
    $self->m->follow_link(url_regex => qr,/msb/d/webLink/doSend/WCO010000,);
    debugf($self->m->uri);
    $self->m->submit;
    debugf($self->m->uri);
    $self->m->follow_link(text => '通話料明細書');
    debugf($self->m->uri);
} #}}}

# 明細を得る
sub get_detail { my $self = shift; #{{{
    my %phone_number_to_name = defined $self->vcard
        ? MySoftbank::AddressBook->new(file => $self->vcard)
            ->phone_number_to_name
        : ();
    my (@data, $ym);
    my $current_page_number = 0;
    while (1) {
        my $results = $self->scrape_detail_page;

        $ym = $results->{ym};
        debugf($ym);

        # 年月が指定され、かつ、トップページがそれと異なった場合
        if (defined $self->ym and $self->ym ne $ym) {
            # 前月へのリンクがあればそっちへ
            if (defined $results->{prev_month_link}) {
                debugf("prev month link found: $results->{prev_month_link}");
                $self->m->get($results->{prev_month_link});
                next;
            # なければ終了
            } else {
                die "can't find details of the specified YYYYMM: $self->ym\n";
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
            $self->get_page_link($results->{links});
        infof(sprintf "データを取得中 (%3d / %3d)",
            ++$current_page_number, $last_page_number);
        if (defined $next_page_link) {
            debugf("next page link found: $next_page_link");
            $self->m->get($next_page_link);
        } else {
            debugf('finished');
            last;
        }
    }

    return (\@data, $ym);
} #}}}

# HTML を解析する
sub scrape_detail_page { my $self = shift; #{{{
    my $html = shift // $self->m->content;

    my $filter = '+MySoftbank::CallDetail::Filter::';

    return scraper {
        process
        '//form[@name="detailsCallsActionForm"]//p[@class="prev"]/span[@class=""]/a',
            prev_month_link => '@href';
        process '//input[@name="billYm"]', ym => '@value';
        process '//ul[@class="navi_view_list"]/li',
        'links[]' => +{
            class => '@class',
            page => scraper {
                process '//a'    , number => ['@href' , "${filter}PageNumber"];
                process '//span' , text   => 'TEXT';
            },
            link => scraper { process '//a',    url    => '@href'; },
        };
        process '//table[@class="contract-info hasthead"]/tbody/tr',
        'rows[]' => scraper {
            process '//td[1]', date           => ['TEXT', "${filter}Trim"];
            process '//td[2]', time           => ['TEXT', "${filter}Trim"];
            process '//td[3]', call_time      => ['TEXT', "${filter}Trim"];
            process '//td[4]', phone_number   => ['TEXT', "${filter}Trim"];
            process '//td[5]', option_service => ['TEXT', "${filter}Trim"];
            process '//td[6]', call_zone      => ['TEXT', "${filter}Trim"];
            process '//td[7]', charge         =>
                ['TEXT', "${filter}Trim", "${filter}DeleteComma"];
            process '//td[8]', discount_type  => ['TEXT', "${filter}Trim"];
            process '//td[9]', cnote          => ['TEXT', "${filter}Trim"];
        };
    }->scrape($html);
} #}}}

# 次のページへのリンクを見つける
sub get_page_link { my $self = shift; #{{{
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
sub output { my $self = shift; #{{{
    my ($data, $ym) = @_;

    # 拡張子作成
    my $ext = lc $self->output_type;
    my $type = uc $self->output_type;
    if ($type eq 'EXCEL') {
        $ext =  'xls';
        $type = 'Excel';
    }

    # ファイル名設定
    my $file = $self->dir->file("mysoftbank_detail_$ym.$ext");
    my $count = 0;
    while (1) {
        if (-f $file) {
            $count++;
            $file = $self->dir->file("mysoftbank_detail_${ym}_$count.$ext");
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

    return $file;
} #}}}
