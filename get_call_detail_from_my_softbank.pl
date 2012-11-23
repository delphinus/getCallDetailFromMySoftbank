#!/usr/bin/env perl
use 5.12.0;
use utf8;
use Getopt::Long;
use Log::Minimal;
use WWW::Mechanize;

$|++;

my %opt;
GetOptions(
    'username|u=s' => \$opt{username},
    'password|p=s' => \$opt{password},
);

defined $opt{username} and $opt{password} or die;

infof('s1');
my $m = WWW::Mechanize->new;
$m->agent_alias('Windows Mozilla');
infof('s2');
my $res = $m->get('https://my.softbank.jp/msb/d/auth/login?mid=504'); # トップページ
infof(ref $res);
infof('s3');
infof($m->content);
$m->submit_form(
    with_fields => +{
        msn => $opt{username},
        password => $opt{password},
    },
);
infof($m->uri);
$m->follow_link(text => '利用料金を確認する');
