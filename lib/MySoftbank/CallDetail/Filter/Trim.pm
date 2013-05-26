package MySoftbank::CallDetail::Filter::Trim;
use 5.12.0;
use utf8;
use warnings;
use parent 'MySoftbank::CallDetail::Filter';

# 前後の空白を削除する
sub filter { s/^\s+//; s/\s+$//; }

1;
