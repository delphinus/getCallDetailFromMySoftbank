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
use Getopt::Long qw!:config auto_help!;
use Log::Minimal;
use Pod::Usage;

use FindBin;
use lib "$FindBin::Bin/lib";
use MySoftbank::CallDetail;

binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';

$|++;

__FILE__ ne $0 and die "this is not a module.\n";

my %opt = (
    agent_alias => 'Windows Mozilla', # Web アクセスに使用する UA
    top_url => 'https://my.softbank.jp/msb/d/top', # トップページの URL
    output_type => 'csv', # 標準では結果を CSV で出力
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

=item --output_type,-t=json,yaml,csv,excel,html

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
    my $mc = MySoftbank::CallDetail->new(%opt);
    $mc->access_to_detail_top; # 明細書のトップ
    my ($data, $ym) = $mc->get_detail; # 明細を得る
    my $file = $mc->output($data, $ym); # 出力する

    infof('メール送信開始');
    MySoftbank::Mail->new(
        %opt,
        ym => $ym,
        file => $file,
    )->send;

    infof('終了しました。');
} #}}}

# コマンドラインオプションを解析する
sub get_options { #{{{
    my %opt = @_;

    my @option_definition = qw!
        username|u=s password|p=s output_type|t=s ym=i vcard=s verbose=i help|h
    !;
    # オプションの受け取りに失敗するか、-h が指定されたらヘルプを表示
    GetOptions(\%opt, @option_definition) or pod2usage(-verbose => 2);
    ($opt{help} or !$opt{username} or !$opt{password}
            or (defined $opt{ym} and $opt{ym} !~ /^\d{6}$/)
            or (defined $opt{vcard} and !-f $opt{vcard})
            or defined $opt{output_type}
                and $opt{output_type} !~ /^(?:json|yaml|csv|excel|html)$/i
            or defined $opt{verbose} and $opt{verbose} !~ /^(?:0|1|2)$/)
        and pod2usage(-verbose => 2);

    $Log::Minimal::AUTODUMP = 1;
    $Log::Minimal::LOG_LEVEL = $opt{verbose} == 1 ? 'INFO' :
        $opt{verbose} == 2 ? 'DEBUG' : 'NONE';
    $Log::Minimal::LOG_LEVEL eq 'DEBUG' and $ENV{LM_DEBUG} = 1;

    return %opt;
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
