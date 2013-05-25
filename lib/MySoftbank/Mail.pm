package MySoftbank::Mail;
use 5.12.0;
use utf8;
use Moose;
use Moose::Util::TypeConstraints qw!enum!;
use MooseX::Types::Email qw!EmailAddress!;

with 'MySoftbank::Output::Role::File';

enum OutputType => [qw!json yaml html csv excel!];

use Email::MIME;
use Email::MIME::Creator::ISO_2022_JP;
use Email::Sender::Simple qw!sendmail!;
use Email::Sender::Transport::SMTP;
use Log::Minimal;
use Text::Xslate;
use Try::Tiny;

has mail_username => (is => 'ro', isa => 'Str', required => 1);
has mail_password => (is => 'ro', isa => 'Str', required => 1);
has output_type   => (is => 'ro', isa => 'OutputType', required => 1);
has ssl      => (is => 'ro', isa => 'Bool', default => 1);
has server   => (is => 'ro', isa => 'Str', default => 'smtp.gmail.com');
has port     => (is => 'ro', isa => 'Int', default => 465);
has from     => (is => 'ro', isa => 'Str', required => 1);
has to       => (is => 'ro', isa => 'Str', required => 1);
has username => (is => 'ro', isa => 'Str', required => 1);
has ym       => (is => 'ro', isa => 'Str', default => '000000');
has subject  => (is => 'ro', isa => 'Str',
    default  => '通話履歴 [% year %]年[% month %]月版');
has data     => (is => 'ro', isa => 'Str', default => <<BODY);
電話番号 [% username %] について、最新の通話履歴を送ります。
BODY
has tx       => (is => 'ro', isa => 'Text::Xslate', default => sub {
        return Text::Xslate->new(
            syntax => 'TTerse',
            module => ['Text::Xslate::Bridge::TT2Like'],
        );
    });

__PACKAGE__->meta->make_immutable; no Moose;

sub send { my $self = shift; #{{{
    my ($year, $month) = $self->ym =~ /^(\d{4})(\d\d)$/;
    my %params = (
        year => $year,
        month => $month,
        username => $self->username,
    );

    my ($content_type, $ext, %charset);
    if ($self->output_type  eq 'JSON') {
        $content_type = 'application/json';
        $ext = 'json';
    } elsif ($self->output_type eq 'YAML') {
        $content_type = 'text/yaml';
        $ext = 'yml';
    } elsif ($self->output_type eq 'CSV') {
        $content_type = 'text/csv';
        $ext = 'csv';
        %charset = (charset => 'Shift_JIS');
    } elsif ($self->output_type eq 'Excel') {
        $content_type = 'application/vnd.ms-excel';
        $ext = 'xls';
    } else {
        $content_type = 'text/html';
        $ext = 'html';
        %charset = (charset => 'UTF-8');
    }

    my $attachment = Email::MIME->create(
        attributes => +{
            filename => "test.$ext",
            content_type => $content_type,
            disposition => 'attachment',
            %charset,
        },
        body => scalar $self->file->slurp(iomode
            => "<:encoding($charset{charset})"),
    );

    my $email = Email::MIME->create(
        header_str => [
            From => $self->from,
            To => $self->to,
            Subject => $self->tx->render_string($self->subject, \%params),
        ],
        parts => [
            $self->tx->render_string($self->data, \%params),
            $attachment,
        ],
    );

    my $transport = Email::Sender::Transport::SMTP->new(
        host          => $self->server,
        port          => $self->port,
        ssl           => $self->ssl,
        sasl_username => $self->mail_username,
        sasl_password => $self->mail_password,
    );

    try {
        sendmail($email, +{transport => $transport});
    } catch {
        die "send failed: $_";
    };
} #}}}

1;
