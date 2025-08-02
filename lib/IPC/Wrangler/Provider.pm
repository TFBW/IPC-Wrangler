package IPC::Wrangler::Provider;

use IPC::Wrangler::Policy;
use AnyEvent;
use IO::Socket::UNIX;
use IPC::Wrangler::Message qw(GOOD BAD UGLY decode try);

my $PATH = "\0ipc-wrangler"; #'/tmp/wrangler.sock';
END { unlink $PATH if $PATH !~ /^\0/ and -e $PATH }

sub new {
    my ($class, %self) = @_;
    return bless(\%self, ref($class)||$class);
}

sub add {
    my ($self, %op) = @_;
    $self->{$_} = $op{$_} for keys %op;
    return $self;
}

sub run {
    my ($self) = @_;
    my $sock = IO::Socket::UNIX->new(
        Local    => $PATH,
        Type     => IO::Socket::SOCK_DGRAM,
        Blocking => 0,
        ) or die "Can't create socket '$PATH': $IO::Socket::errstr\n";
    #chmod 0660, $PATH;

    my $request_watch = AE::io $sock, 0, sub {
        my $request;
        warn "IO start\n";
        my $client = $sock->recv($request, 65535);
        my ($op, @arg) = decode($request);
        my $response = $self->{$op} ? try($self->{$op}, @arg) : BAD("Unrecognised operation '$op'");
        $sock->send($response, 0, $client);
        warn "IO done\n";
        return;
    };

    my $main_loop = AE::cv;
    my $int_handler = AE::signal INT => sub { $main_loop->send };
    warn "entering loop\n";
    $main_loop->recv;
    $sock->close;
    return $self;
}

1;
