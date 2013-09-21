#!/usr/bin/env perl

=encoding utf-8

=head1 NAME

get_last_detail.pl - get last call detail from My Softbank always

=head1 SYNOPSIS

    $ perl get_last_detail.pl -u USERNAME -p PASSWORD -m delphinus@remora.cx

=head1 DESCRIPTION

L<My Softbank|https://my.softbank.jp/> にアクセスし、
最新の通話履歴が公開されていたらそれを取得し、
指定したメールアドレスに送付します。

=cut

use 5.12.0;
use utf8;
use warnings;
use Config::Any;
use File::Temp qw!tempfile tempdir!;
use Getopt::Long qw!:config auto_help!;
use JSON;
use Log::Minimal;
use Path::Class;
use Pod::Usage;

use FindBin;
use lib "$FindBin::Bin/lib";
use MySoftbank::CallDetail;
use MySoftbank::Mail;

binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';

$|++;

__FILE__ ne $0 and die "this is not a module.\n";

log_setting();
my %opt = default_option();
main(%opt);

exit;

# デフォルトオプション
sub default_option { #{{{
    my %opt = @_;

    (my $config = file($0)->basename) =~ s/\.pl$/.yml/;

    return (
        agent_alias => 'Windows Mozilla', # Web アクセスに使用する UA
        top_url => 'https://my.softbank.jp/msb/d/top', # トップページの URL
        output_type => 'html', # 標準では結果を HTML で出力
        dir => tempdir(),
        config => dir($FindBin::Bin)->file($config)->stringify,
        verbose => 1,
        %opt,
    );
} #}}}

# メインルーチン
sub main { #{{{
    my %opt = @_;

    %opt = get_options(%opt); # コマンドラインオプションを取得
    debugf(\%opt);

=head1 OPTIONS

=over 4

=item --config,-c

設定を保存するファイルです。標準では、スクリプトのあるディレクトリにある、
C<get_last_detail.yml> を読みます。

=item --test,-t

テストメールを送信します。

=item --ym

年月を YYYYMM の形式で指定して取得します。デフォルトでは未指定です。

=item --help,-h

ヘルプを表示します。

=item --verbose=0,1(default),2

進捗メッセージを表示します。C<0> が指定されると一切のメッセージが表示されません。

=cut

    %opt = load_config(%opt); # 設定ファイルを読む

    if ($opt{test}) {
        my ($fh, $file) = tempfile('tempfileXXXXX', TMPDIR => 1);
        binmode $fh => ':utf8';
        $fh->print(<<HTML);
<html>
    <head><meta charset="UTF-8"></head>
    <body><p>これは添付ファイルのサンプルです。</p></body>
</html>
HTML
        $fh->close;
        MySoftbank::Mail->new(%opt,
            file => $file,
            subject => "$0: これはテストメールです。 [% year %]年[% month %]月",
            data => 'これはテストメールです。',
        )->send;
        infof('テストメールを送信しました。');
        exit;
    }

    my $stats = load_stats(%opt); # 実行状況を読む

    infof('アクセス開始');
    debugf(\%opt);
    my $mc = MySoftbank::CallDetail->new(%opt);

    eval {
        $mc->access_to_detail_top; # 明細書のトップ
        my $results = $mc->scrape_detail_page;

        if ($results->{ym} eq $stats->{last_executed}) {
            infof('既に実行済です');
            exit;
        }

        my ($data, $ym) = $mc->get_detail; # 明細を得る
        my $file = $mc->output($data, $ym); # 出力する
        $stats->{last_executed} = $ym;
        if (defined $opt{stats}) {
            my $fh = file($opt{stats})->openw;
            $fh->print(to_json($stats));
            $fh->close;
        }

        MySoftbank::Mail->new(%opt,
            file => $file,
            ym => $ym,
        )->send;
    };

    if (my $err = $@) {
        my ($err_fh, $err_file) = tempfile('tempfileXXXXX', TMPDIR => 1);
        binmode $err_fh => ':utf8';
        $err_fh->print($mc->m->content);
        $err_fh->close;
        MySoftbank::Mail->new(%opt,
            file => $err_file,
            subject => "$0: エラーが発生しました。",
            data => <<EOM
通信中にエラーが発生しました。添付ファイルも確認してください。

$err
EOM
        )->send;
    }

    infof('メールを送信しました。');
} #}}}

# コマンドラインオプションを解析する
sub get_options { #{{{
    my %opt = @_;

    my @option_definition = qw!config|c=s test|t help|h verbose|v=i ym=s!;
    # オプションの受け取りに失敗するか、-h が指定されたらヘルプを表示
    GetOptions(\%opt, @option_definition) or pod2usage(-verbose => 2);
    $opt{help} and pod2usage(-verbose => 2);
    !-f $opt{config} and pod2usage(-verbose => 2);
    $opt{config} = file($opt{config});

    $Log::Minimal::AUTODUMP = 1;
    $Log::Minimal::LOG_LEVEL = $opt{verbose} == 1 ? 'INFO' :
        $opt{verbose} == 2 ? 'DEBUG' : 'NONE';
    $Log::Minimal::LOG_LEVEL eq 'DEBUG' and $ENV{LM_DEBUG} = 1;

    return %opt;
} #}}}

# 設定ファイルを読む
sub load_config { #{{{
    my %opt = @_;

    my $config_any = Config::Any->load_files(+{
        files => [$opt{config}],
        use_ext => 1,
        flatten_to_hash => 1,
    });
    my ($cfg) = values %$config_any;

    return (%opt, %$cfg);
} #}}}

# 実行状況を読む
sub load_stats { #{{{
    my %opt = @_;

    return defined $opt{stats} && -f $opt{stats}
        ? from_json(file($opt{stats})->slurp) : +{last_executed => 0};
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
