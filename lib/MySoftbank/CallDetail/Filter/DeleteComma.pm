package MySoftbank::CallDetail::Filter::DeleteComma;
use 5.12.0;
use utf8;
use warnings;
use parent 'MySoftbank::CallDetail::Filter';

# コンマを除去する
sub filter { s/,//g; }

1;
