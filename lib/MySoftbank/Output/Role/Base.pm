package MySoftbank::Output::Role::Base;
use 5.12.0;
use utf8;
use warnings;
use Moose::Role;

# 明細データ
has data => (is => 'ro', isa => 'ArrayRef[HashRef]', required => 1);
# データのカラム
has columns => (is => 'ro', isa => 'ArrayRef', default => sub { [qw!
        call_date call_time phone_number call_name option_service
        call_zone charge discount_type note
    !]; });
# データのカラム（日本語）
has titles => (is => 'ro', isa => 'ArrayRef', default => sub { [qw!
        発信日時 通話時間 相手先電話番号 氏名 オプションサービス
        発信区域 通話料金 割引種別 備考
    !]; });
# データの年
has year => (is => 'ro', isa => 'Int', required => 1);
# データの月
has month => (is => 'ro', isa => 'Int', required => 1);

no Moose::Role; 1;
