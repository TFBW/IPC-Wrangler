package IPC::Wrangler::Client;

use IPC::Wrangler::Policy;
use AnyEvent;
use IO::Socket::UNIX;
use IPC::Wrangler::Message qw(GOOD BAD UGLY decode encode);

# Dev notes: Linux-specific abstract sockets start wtih a NUL and
# don't require deletion.  Real FS sockets need to remain reachable
# while in use: no unlink tricks.

my $SERVER = IO::Socket::sockaddr_un("\0ipc-wrangler"); #'/tmp/wrangler.sock');
my $PATH = "\0ipc-wrangler-client-$$"; #"/tmp/wrangler-client-$$.sock";
END { unlink $PATH if $PATH !~ /^\0/ and -e $PATH }

my $SOCK;

sub new {
    my ($class) = @_;
    $SOCK //= IO::Socket::UNIX->new(
        Type  => IO::Socket::SOCK_DGRAM,
        Local => $PATH,
        ) or die "Can't create socket: $IO::Socket::errstr\n";
    return $class;
}

sub request {
    my $class = shift;
    my $request = encode(@_);
    $SOCK->send($request, 0, $SERVER);
    my $response;
    $SOCK->recv($response, 65535);
    return $response;
}

1;
