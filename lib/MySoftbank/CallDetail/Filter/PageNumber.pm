package MySoftbank::CallDetail::Filter::PageNumber;
use 5.12.0;
use utf8;
use warnings;
use parent 'MySoftbank::CallDetail::Filter';

# リンクからページ番号を得る
sub filter { ($_) = m!goPaging/(\d+)!; }

1;
